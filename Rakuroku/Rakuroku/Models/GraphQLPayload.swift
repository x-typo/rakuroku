import Foundation

struct GraphQLRequest: Encodable, Sendable {
    let query: String
    let variables: [String: AnyCodable]
}

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable, Sendable {
    let message: String
}

// Type-erased Codable for GraphQL variables
struct AnyCodable: Encodable, Sendable {
    private let _encode: @Sendable (Encoder) throws -> Void

    init(_ value: some Sendable & Encodable) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }

    static let null = AnyCodable(_isNull: true)

    private init(_isNull: Bool) {
        self._encode = { encoder in
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

extension AnyCodable: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self.init(value) }
}

extension AnyCodable: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) { self.init(value) }
}

extension AnyCodable: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) { self.init(value) }
}
