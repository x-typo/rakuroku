import Foundation
import Testing
@testable import Rakuroku

@Suite("AniList client")
@MainActor
struct AniListClientTests {
    @Test("Scores use a fixed raw scale and decode normalized values", arguments: [0.0, 8.0, 8.5, 10.0])
    func writesRawScore(score: Double) async throws {
        let transport = StubAniListTransport(responses: [
            (200, entryResponse(field: "SaveMediaListEntry", score: score)),
        ])
        let client = AniListClient(transport: transport.send)

        let entry = try await client.updateScore(mediaId: 101, score: score, accessToken: "test-token")

        #expect(entry.score == score)
        let requests = await transport.requests
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let payload = try decodePayload(request)
        #expect(payload.variables["mediaId"] as? Int == 101)
        #expect(payload.variables["scoreRaw"] as? Int == Int(score * 10))
        #expect(payload.variables["score"] == nil)
        #expect(payload.query.contains("scoreRaw: $scoreRaw"))
        #expect(payload.query.contains("score(format: POINT_10_DECIMAL)"))
    }

    @Test("Invalid scores fail before sending a request", arguments: [-0.1, 10.1, .nan, .infinity, -.infinity])
    func rejectsInvalidScore(score: Double) async {
        let transport = StubAniListTransport(responses: [])
        let client = AniListClient(transport: transport.send)

        do {
            _ = try await client.updateScore(mediaId: 101, score: score, accessToken: "test-token")
            Issue.record("Invalid score was accepted")
        } catch AniListError.invalidScore {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Every entry read and other save operation requests ten-point decimal scores")
    func normalizesAllEntrySelections() async throws {
        let transport = StubAniListTransport(responses: [
            (200, entryResponse(field: "SaveMediaListEntry")),
            (200, entryResponse(field: "SaveMediaListEntry")),
            (200, entryResponse(field: "SaveMediaListEntry")),
            (200, entryResponse(field: "MediaList")),
            (200, #"{"data":{"MediaListCollection":{"lists":[{"entries":[{"id":1,"status":"CURRENT","progress":4,"score":8.5,"media":{"id":101,"title":{"english":"Example"}}}]}]}}}"#),
        ])
        let client = AniListClient(transport: transport.send)

        let progress = try await client.updateProgress(mediaId: 101, progress: 4, accessToken: "test-token")
        let status = try await client.updateStatus(mediaId: 101, status: .current, accessToken: "test-token")
        let addition = try await client.addToList(mediaId: 101, status: .current, accessToken: "test-token")
        let entry = try await client.fetchUserMediaEntry(mediaId: 101, username: "tester")
        let list = try await client.fetchMediaList(type: .anime, username: "tester")

        #expect(progress.score == 8.5)
        #expect(status.score == 8.5)
        #expect(addition.score == 8.5)
        #expect(entry?.score == 8.5)
        #expect(list.first?.score == 8.5)
        let requests = await transport.requests
        #expect(requests.count == 5)
        for request in requests {
            #expect(try decodePayload(request).query.contains("score(format: POINT_10_DECIMAL)"))
        }
    }

    @Test("Authentication failures fall back to the same public read", arguments: [200, 401, 403], [false, true])
    func publicReadFallback(statusCode: Int, collection: Bool) async throws {
        let errorBody = statusCode == 200
            ? #"{"errors":[{"message":"Unauthorized","status":401}]}"#
            : #"{"errors":[{"message":"Unauthorized"}]}"#
        let publicBody = collection
            ? #"{"data":{"MediaListCollection":{"lists":[]}}}"#
            : #"{"data":{"MediaList":null}}"#
        let transport = StubAniListTransport(responses: [(statusCode, errorBody), (200, publicBody)])
        let client = AniListClient(transport: transport.send)

        if collection {
            let entries = try await client.fetchMediaList(type: .anime, username: "tester", accessToken: "expired-token")
            #expect(entries.isEmpty)
        } else {
            let entry = try await client.fetchUserMediaEntry(mediaId: 101, username: "tester", accessToken: "expired-token")
            #expect(entry == nil)
        }

        let requests = await transport.requests
        #expect(requests.count == 2)
        let authenticated = try #require(requests.first)
        let publicRequest = try #require(requests.last)
        #expect(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer expired-token")
        #expect(publicRequest.value(forHTTPHeaderField: "Authorization") == nil)
        let authenticatedPayload = try decodePayload(authenticated)
        let publicPayload = try decodePayload(publicRequest)
        #expect(authenticatedPayload.query == publicPayload.query)
        #expect(NSDictionary(dictionary: authenticatedPayload.variables).isEqual(to: publicPayload.variables))
    }

    private enum OutageRequest: CaseIterable {
        case publicSeason, viewer, authenticatedCollection, authenticatedEntry
    }

    @Test("AniList's observed API shutdown is not an authentication failure", arguments: [200, 403], OutageRequest.allCases)
    private func surfacesServiceOutage(statusCode: Int, requestKind: OutageRequest) async throws {
        let body = #"{"errors":[{"message":"The AniList API has been temporarily disabled due to severe stability issues.","status":403,"locations":[{"line":1,"column":1}]}],"data":null}"#
        let transport = StubAniListTransport(responses: [(statusCode, body)])
        let client = AniListClient(transport: transport.send)

        do {
            switch requestKind {
            case .publicSeason:
                _ = try await client.fetchSeasonalAnime(season: .summer, year: 2026)
            case .viewer:
                _ = try await client.fetchAuthenticatedUser(accessToken: "test-token")
            case .authenticatedCollection:
                _ = try await client.fetchMediaList(type: .anime, username: "tester", accessToken: "test-token")
            case .authenticatedEntry:
                _ = try await client.fetchUserMediaEntry(mediaId: 101, username: "tester", accessToken: "test-token")
            }
            Issue.record("Service outage was not surfaced")
        } catch let error as AniListError {
            guard case .serviceUnavailable = error else {
                Issue.record("Unexpected AniList error: \(error)")
                return
            }
            #expect(!error.isAuthenticationFailure)
            #expect(error.localizedDescription == "AniList has temporarily disabled its API due to stability issues. Please try again later.")
        }

        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == (requestKind == .publicSeason ? nil : "Bearer test-token"))
    }

    @Test("HTTP and GraphQL rate limits surface without retrying", arguments: [200, 429])
    func surfacesRateLimit(statusCode: Int) async {
        let body = statusCode == 429
            ? "Too many requests"
            : #"{"errors":[{"message":"Too many requests","status":429}]}"#
        let transport = StubAniListTransport(responses: [(statusCode, body)])
        let client = AniListClient(transport: transport.send)

        do {
            _ = try await client.fetchMediaList(type: .anime, username: "tester", accessToken: "test-token")
            Issue.record("Rate limit was not surfaced")
        } catch AniListError.rateLimited {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await transport.requests.count == 1)
    }

    private func entryResponse(field: String, score: Double = 8.5) -> String {
        """
        {"data":{"\(field)":{"id":1,"status":"CURRENT","score":\(score),"progress":4,"updatedAt":100}}}
        """
    }

    private func decodePayload(_ request: URLRequest) throws -> (query: String, variables: [String: Any]) {
        let data = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (
            try #require(object["query"] as? String),
            try #require(object["variables"] as? [String: Any])
        )
    }
}

private actor StubAniListTransport {
    private var responses: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let stub = try #require(responses.first, "Unexpected request")
        responses.removeFirst()
        let requestURL = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: requestURL,
            statusCode: stub.0,
            httpVersion: nil,
            headerFields: nil
        ))
        return (Data(stub.1.utf8), response)
    }
}
