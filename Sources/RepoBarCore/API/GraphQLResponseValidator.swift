import Foundation

/// GraphQL can return HTTP 200 with errors and no data (or incomplete data).
enum GraphQLResponseValidator {
    static func validate(_ data: Data) throws {
        let envelope = try JSONDecoder().decode(GitHubErrorResponse.self, from: data)
        let errors = envelope.errors ?? []
        if errors.isEmpty == false || envelope.message != nil {
            let detail = errors.compactMap(\.message).first ?? envelope.message ?? "The query failed."
            throw GraphQLResponseError(message: "GitHub GraphQL: \(detail)")
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["data"] is [String: Any] else {
            throw GraphQLResponseError(message: "GitHub GraphQL returned no data. Try refreshing again.")
        }
    }
}

struct GraphQLResponseError: LocalizedError {
    let message: String

    var errorDescription: String? {
        self.message
    }
}
