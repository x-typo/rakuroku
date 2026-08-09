import Foundation
import Testing
@testable import Rakuroku

@Suite("AniList model filtering")
@MainActor
struct AniListModelFilteringTests {
    @Test("Adult relation nodes are removed while safe nodes remain")
    func filtersAdultRelationsDuringDecoding() throws {
        let json = """
        {
          "edges": [
            {
              "relationType": "SEQUEL",
              "node": {
                "id": 1,
                "isAdult": true,
                "title": { "romaji": "Hidden" },
                "format": "TV",
                "type": "ANIME",
                "status": "FINISHED"
              }
            },
            {
              "relationType": "PREQUEL",
              "node": {
                "id": 2,
                "isAdult": false,
                "title": { "english": "Visible" },
                "format": "MOVIE",
                "type": "ANIME",
                "status": "FINISHED"
              }
            }
          ]
        }
        """

        let data = try #require(json.data(using: .utf8))
        let connection = try JSONDecoder().decode(MediaRelationConnection.self, from: data)
        #expect(connection.edges?.map(\.node.id) == [2])
    }
}
