import Foundation
@testable import RepoBarCore
import Testing

struct GraphQLResponseTests {
    @Test(arguments: [
        #"{"errors":[{"message":"Something went wrong while executing your query"}]}"#,
        #"{"data":null,"errors":[{"message":"Something went wrong while executing your query"}]}"#,
        #"{"data":{"repository":null},"errors":[{"message":"Something went wrong while executing your query"}]}"#
    ])
    func `error envelope preserves git hub message`(body: String) throws {
        #expect(throws: GraphQLResponseError.self) {
            try GraphQLClient.decodeRepoSummary(from: Data(body.utf8), owner: "owner", name: "repo")
        }
        do {
            try GraphQLResponseValidator.validate(Data(body.utf8))
        } catch {
            #expect(error.localizedDescription == "GitHub GraphQL: Something went wrong while executing your query")
        }
    }

    @Test
    func `missing data is not A decoding error`() {
        #expect(throws: GraphQLResponseError.self) {
            try GraphQLClient.decodeRepoSummary(from: Data("{}".utf8), owner: "owner", name: "repo")
        }
    }

    @Test(arguments: [false, true])
    func `failed responses are not cached`(contributions: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLResponseTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let cache = try GraphQLResponseDiskCache(path: path)
        let transport = GraphQLTestTransport(bodies: [
            #"{"errors":[{"message":"Temporary query failure"}]}"#,
            contributions ? #"{"data":{"user":null}}"# : Self.summary
        ])
        let client = GraphQLClient(responseCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "test-token" }
        do {
            if contributions {
                _ = try await client.userContributionHeatmap(login: "owner")
            } else {
                _ = try await client.repoSummary(owner: "owner", name: "repo")
            }
            Issue.record("Expected the GraphQL error")
        } catch let error as GraphQLResponseError {
            #expect(error.message.contains("Temporary query failure"))
        }
        if contributions {
            _ = try await client.userContributionHeatmap(login: "owner")
        } else {
            #expect(try await client.repoSummary(owner: "owner", name: "repo").openIssues == 4)
        }
        #expect(await transport.requests.count == 2)
    }

    @Test
    func `invalid legacy cache is bypassed`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GraphQLResponseTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appending(path: "Cache.sqlite").path
        let cache = try GraphQLResponseDiskCache(path: path)
        let transport = GraphQLTestTransport(bodies: [Self.summary, Self.summary])
        let client = GraphQLClient(responseCache: cache, dataLoader: HTTPDataLoader { try await transport.data(for: $0) })
        await client.setTokenProvider { "test-token" }
        _ = try await client.repoSummary(owner: "owner", name: "repo")
        let request = try #require(await transport.requests.first)
        let endpoint = try #require(request.url)
        let body = try #require(request.httpBody)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        let key = "\(endpoint.absoluteString)\tRepoSummary\t\(bodyString)"
        let legacyCache = try GraphQLResponseDiskCache(path: path)
        legacyCache.save(key: key, endpoint: endpoint, operation: "RepoSummary", body: body, responseBody: Data("{}".utf8))

        #expect(try await client.repoSummary(owner: "owner", name: "repo").openIssues == 4)
        #expect(await transport.requests.count == 2)
        _ = try await client.repoSummary(owner: "owner", name: "repo")
        #expect(await transport.requests.count == 2)
    }

    private static let summary = #"{"data":{"repository":{"latestRelease":null,"issues":{"totalCount":4},"pullRequests":{"totalCount":2}}}}"#
}

private actor GraphQLTestTransport {
    private var bodies: [String]
    private(set) var requests: [URLRequest] = []

    init(bodies: [String]) {
        self.bodies = bodies
    }

    func data(for request: URLRequest) throws -> (Data, URLResponse) {
        self.requests.append(request)
        guard self.bodies.isEmpty == false else { throw URLError(.badServerResponse) }

        let body = self.bodies.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
