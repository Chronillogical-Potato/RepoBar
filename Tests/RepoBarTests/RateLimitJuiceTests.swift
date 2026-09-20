import Foundation
@testable import RepoBarCore
import Testing

struct RateLimitJuiceTests {
    @Test
    func `uses live diagnostics before cached responses`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 2500,
                used: 2500,
                reset: now.addingTimeInterval(60),
                fetchedAt: now
            ),
            graphQLRateLimit: RateLimitSnapshot(
                resource: "graphql",
                limit: 5000,
                remaining: 1250,
                used: 3750,
                reset: now.addingTimeInterval(60),
                fetchedAt: now
            ),
            rateLimitResources: nil
        )

        let juice = RateLimitJuice(diagnostics: diagnostics, now: now)

        #expect(juice.restPercent == 50)
        #expect(juice.graphQLPercent == 25)
        #expect(juice.compactRestText == "2.5K")
        #expect(juice.hasData)
    }

    @Test
    func `uses cached REST limits when live diagnostics are empty`() {
        let now = Date(timeIntervalSinceReferenceDate: 200)
        let summary = RepoBarCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            graphQLResponseCount: 0,
            rateLimitCount: 0,
            latestResponses: [
                RepoBarCachedResponseSummary(
                    method: "GET",
                    url: "https://api.github.com/user/repos",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 4000,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )

        let juice = RateLimitJuice(diagnostics: .empty, cacheSummary: summary, now: now)

        #expect(juice.restPercent == 80)
        #expect(juice.graphQLPercent == nil)
        #expect(juice.compactRestText == "4K")
        #expect(juice.hasData)
    }

    @Test
    func `display state uses same cached value for menu bar and menu summary`() {
        let now = Date(timeIntervalSinceReferenceDate: 250)
        let summary = RepoBarCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 1,
            graphQLResponseCount: 0,
            rateLimitCount: 0,
            latestResponses: [
                RepoBarCachedResponseSummary(
                    method: "GET",
                    url: "https://api.github.com/user/repos",
                    hasETag: true,
                    statusCode: 200,
                    fetchedAt: now,
                    rateLimitResource: "core",
                    rateLimitLimit: 5000,
                    rateLimitRemaining: 4948,
                    rateLimitReset: now.addingTimeInterval(600)
                )
            ],
            rateLimits: []
        )
        let state = RateLimitDisplayState(diagnostics: .empty, cacheSummary: summary)

        #expect(state.juice.compactRestText == "4.9K")
        #expect(state.compactSummary(now: now).contains("4.9K requests"))
        #expect(state.sections(now: now).flatMap(\.rows).contains { $0.contains("4948/5000") })
    }

    @Test
    func `display state reports freshest shared sample time`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 275)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 4000,
                used: 1000,
                reset: nil,
                fetchedAt: now
            ),
            graphQLRateLimit: nil,
            rateLimitResources: RateLimitResourcesSnapshot(
                fetchedAt: now.addingTimeInterval(10),
                resources: [:]
            )
        )

        let state = RateLimitDisplayState(diagnostics: diagnostics)

        #expect(state.lastUpdatedAt == now.addingTimeInterval(10))
    }

    @Test
    func `active limit renders as empty lane`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 300)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")),
            rateLimitReset: now.addingTimeInterval(60),
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: nil,
            graphQLRateLimit: nil,
            rateLimitResources: nil
        )

        let juice = RateLimitJuice(diagnostics: diagnostics, now: now)

        #expect(juice.isRestLimited)
        #expect(juice.displayRestPercent == 0)
        #expect(juice.compactRestText == "0")
        #expect(juice.hasData)
    }

    @Test
    func `uses response headers before rate limit endpoint within the same window`() throws {
        let now = Date(timeIntervalSinceReferenceDate: 350)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")),
            rateLimitReset: nil,
            lastRateLimitError: nil,
            etagEntries: 0,
            backoffEntries: 0,
            restRateLimit: RateLimitSnapshot(
                resource: "core",
                limit: 5000,
                remaining: 100,
                used: 4900,
                reset: now.addingTimeInterval(60),
                fetchedAt: now
            ),
            graphQLRateLimit: nil,
            rateLimitResources: RateLimitResourcesSnapshot(
                fetchedAt: now,
                resources: [
                    "core": RateLimitSnapshot(
                        resource: "core",
                        limit: 5000,
                        remaining: 4000,
                        used: 1000,
                        reset: now.addingTimeInterval(60),
                        fetchedAt: now
                    ),
                    "graphql": RateLimitSnapshot(
                        resource: "graphql",
                        limit: 5000,
                        remaining: 2500,
                        used: 2500,
                        reset: now.addingTimeInterval(60),
                        fetchedAt: now
                    )
                ]
            )
        )

        let juice = RateLimitJuice(diagnostics: diagnostics, now: now)

        #expect(juice.restPercent == 2)
        #expect(juice.graphQLPercent == 50)
        #expect(juice.compactRestText == "100")
    }

    @Test
    func `display state ignores expired active limits`() {
        let now = Date(timeIntervalSinceReferenceDate: 400)
        let summary = RepoBarCacheSummary(
            databasePath: "/tmp/cache.sqlite",
            exists: true,
            apiResponseCount: 0,
            graphQLResponseCount: 0,
            rateLimitCount: 1,
            latestResponses: [],
            rateLimits: [
                RepoBarRateLimitSummary(
                    resource: "core",
                    remaining: 0,
                    resetAt: now.addingTimeInterval(-1),
                    lastError: "old limit"
                )
            ]
        )

        #expect(RateLimitDisplayState(diagnostics: .empty, cacheSummary: summary).isLimited(now: now) == false)
    }

    @Test
    func `newer synthetic full budgets cannot hide REST or GraphQL usage`() throws {
        let now = Date()
        let observed = now.addingTimeInterval(-30)
        let realReset = now.addingTimeInterval(600)
        let summaryReset = now.addingTimeInterval(3600)
        let rest = RateLimitSnapshot(resource: "core", limit: 5000, remaining: 2120, used: 2880, reset: realReset, fetchedAt: observed)
        let graph = RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 842, used: 4158, reset: realReset, fetchedAt: observed)
        let reported = RateLimitResourcesSnapshot(fetchedAt: now, resources: [
            "core": RateLimitSnapshot(resource: "core", limit: 5000, remaining: 5000, used: 0, reset: summaryReset, fetchedAt: now),
            "graphql": RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 5000, used: 0, reset: summaryReset, fetchedAt: now)
        ])
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")), rateLimitReset: nil, lastRateLimitError: nil,
            etagEntries: 0, backoffEntries: 0, restRateLimit: rest, graphQLRateLimit: graph, rateLimitResources: reported
        )
        let state = RateLimitDisplayState(diagnostics: diagnostics)
        #expect(state.juice.compactRestText == "2.1K")
        #expect(state.juice.compactGraphQLText == "842")
        #expect(state.juice.menuBarTooltip.contains("2120/5000"))
        #expect(state.juice.menuBarTooltip.contains("842/5000"))
        let rows = state.sections(now: now).flatMap(\.rows)
        #expect(rows.contains { $0.contains("2120/5000") })
        #expect(rows.contains { $0.contains("842/5000") })
        #expect(diagnostics.restRateLimit?.reset == realReset)
        #expect(diagnostics.graphQLRateLimit?.reset == realReset)
    }

    @Test(arguments: [false, true])
    func `summary can replace response after its known window expires`(expired: Bool) {
        let now = Date()
        let response = RateLimitSnapshot(
            resource: "core",
            limit: 5000,
            remaining: 0,
            used: 5000,
            reset: now.addingTimeInterval(expired ? -1 : 1),
            fetchedAt: now.addingTimeInterval(-30)
        )
        let reported = RateLimitSnapshot(
            resource: "core",
            limit: 5000,
            remaining: 5000,
            used: 0,
            reset: now.addingTimeInterval(3600),
            fetchedAt: now
        )
        #expect(RateLimitSnapshot.preferred(reported: reported, response: response)?.remaining == (expired ? 5000 : 0))
        #expect(RateLimitSnapshot.preferred(reported: reported, response: nil)?.remaining == 5000)
        #expect(RateLimitSnapshot.preferred(reported: nil, response: response)?.remaining == 0)
    }

    @Test
    func `newer headers win across all quota displays`() throws {
        let now = Date()
        let old = RateLimitSnapshot(resource: "core", limit: 5000, remaining: 5000, used: 0, reset: now.addingTimeInterval(3600), fetchedAt: now)
        let rest = RateLimitSnapshot(resource: "core", limit: 5000, remaining: 4200, used: 800, reset: old.reset, fetchedAt: now.addingTimeInterval(10))
        let graphQL = RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 2500, used: 2500, reset: old.reset, fetchedAt: now.addingTimeInterval(10))
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")), rateLimitReset: nil, lastRateLimitError: nil,
            etagEntries: 0, backoffEntries: 0, restRateLimit: rest, graphQLRateLimit: graphQL,
            rateLimitResources: RateLimitResourcesSnapshot(fetchedAt: now, resources: ["core": old, "graphql": old])
        )
        let state = RateLimitDisplayState(diagnostics: diagnostics)
        #expect(state.juice.compactMenuBarText == "R 4.2K · G 2.5K")
        #expect(state.compactSummary().contains("REST 4.2K requests · GraphQL 2.5K points"))
        #expect(diagnostics.rateLimitResources?["core"]?.remaining == 4200)
        #expect(diagnostics.rateLimitResources?["graphql"]?.remaining == 2500)
        #expect(state.juice.menuBarTooltip.contains("4200/5000 requests"))
        #expect(state.juice.menuBarTooltip.contains("2500/5000 points"))
    }

    @Test
    func `graph QL only quota and secondary block are visible`() throws {
        let now = Date()
        let graphQL = RateLimitSnapshot(resource: "graphql", limit: 5000, remaining: 4000, used: 1000, reset: now.addingTimeInterval(3600), fetchedAt: now)
        let diagnostics = try DiagnosticsSummary(
            apiHost: #require(URL(string: "https://api.github.com")), rateLimitReset: nil, lastRateLimitError: nil,
            etagEntries: 0, backoffEntries: 0, restRateLimit: nil, graphQLRateLimit: graphQL,
            rateLimitResources: nil, graphQLRateLimitReset: now.addingTimeInterval(60)
        )
        let state = RateLimitDisplayState(diagnostics: diagnostics)
        #expect(state.isLimited())
        #expect(state.juice.hasData)
        #expect(state.juice.isRestLimited == false)
        #expect(state.juice.compactMenuBarText == "R ? · G !")
        #expect(state.juice.menuBarTooltip.contains("4000/5000 points left (blocked)"))
        #expect(state.compactSummary().contains("GraphQL blocked"))
        #expect(state.sections().flatMap(\.rows).contains { $0.contains("GraphQL") })
    }
}
