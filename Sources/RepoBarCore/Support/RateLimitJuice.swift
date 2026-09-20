import Foundation

public struct RateLimitJuice: Equatable, Sendable {
    public let restPercent: Double?
    public let graphQLPercent: Double?
    public let restRemaining: Int?
    public let restLimit: Int?
    public let graphQLRemaining: Int?
    public let graphQLLimit: Int?
    public let isRestLimited: Bool
    public let isGraphQLLimited: Bool

    public init(
        diagnostics: DiagnosticsSummary,
        cacheSummary: RepoBarCacheSummary? = nil,
        now: Date = Date()
    ) {
        let resourceCore = diagnostics.rateLimitResources?["core"] ?? diagnostics.rateLimitResources?["rate"]
        let resourceGraphQL = diagnostics.rateLimitResources?["graphql"]
        let cachedCore = cacheSummary.flatMap { Self.cachedInfo(resource: "core", in: $0) }
        let cachedGraphQL = cacheSummary.flatMap { Self.cachedInfo(resource: "graphql", in: $0) }
        let activeLimits = cacheSummary?.rateLimits.filter { $0.resetAt > now } ?? []

        self.restRemaining = resourceCore?.remaining ?? diagnostics.restRateLimit?.remaining ?? cachedCore?.remaining
        self.restLimit = resourceCore?.limit ?? diagnostics.restRateLimit?.limit ?? cachedCore?.limit
        self.graphQLRemaining = resourceGraphQL?.remaining ?? diagnostics.graphQLRateLimit?.remaining ?? cachedGraphQL?.remaining
        self.graphQLLimit = resourceGraphQL?.limit ?? diagnostics.graphQLRateLimit?.limit ?? cachedGraphQL?.limit
        self.restPercent = Self.percent(remaining: self.restRemaining, limit: self.restLimit)
        self.graphQLPercent = Self.percent(remaining: self.graphQLRemaining, limit: self.graphQLLimit)
        self.isRestLimited = diagnostics.rateLimitReset.map { $0 > now } ?? false
            || activeLimits.contains { $0.resource == "core" }
        self.isGraphQLLimited = diagnostics.graphQLRateLimitReset.map { $0 > now } ?? false
            || activeLimits.contains { $0.resource == "graphql" }
            || ((resourceGraphQL ?? diagnostics.graphQLRateLimit).map { $0.remaining == 0 && ($0.reset.map { $0 > now } ?? false) } ?? false)
    }

    public var hasData: Bool {
        self.restPercent != nil || self.graphQLPercent != nil || self.isRestLimited || self.isGraphQLLimited
    }

    public var displayRestPercent: Double? {
        self.isRestLimited ? 0 : self.restPercent
    }

    public var displayGraphQLPercent: Double? {
        self.isGraphQLLimited ? 0 : self.graphQLPercent
    }

    public var compactRestText: String? {
        if self.isRestLimited {
            return (self.restRemaining ?? 0) > 0 ? "!" : "0"
        }
        if let restRemaining {
            return Self.shortCount(restRemaining)
        }
        if let restPercent {
            return "\(Int(restPercent.rounded()))%"
        }
        return nil
    }

    public var compactGraphQLText: String? {
        if self.isGraphQLLimited {
            return self.graphQLRemaining == 0 ? "0" : "!"
        }
        return self.graphQLRemaining.map(Self.shortCount)
    }

    public var compactMenuBarText: String {
        let rest = self.compactRestText ?? "?"
        let graphQL = self.compactGraphQLText ?? "?"
        return "R \(rest) · G \(graphQL)"
    }

    public var menuBarTooltip: String {
        let rest = Self.quotaText(remaining: self.restRemaining, limit: self.restLimit, unit: "requests")
        let graphQL = Self.quotaText(remaining: self.graphQLRemaining, limit: self.graphQLLimit, unit: "points")
        return [
            "RepoBar GitHub API quota (last observed)",
            "R — REST core: \(rest)\(self.isRestLimited ? " (blocked)" : "")",
            "G — GraphQL: \(graphQL)\(self.isGraphQLLimited ? " (blocked)" : "")",
            "Top row: REST · Bottom row: GraphQL",
            "Separate budgets; search limits are in GitHub API Status."
        ].joined(separator: "\n")
    }

    private static func quotaText(remaining: Int?, limit: Int?, unit: String) -> String {
        guard let remaining else { return "unknown" }

        let total = limit.map { "/\($0)" } ?? ""
        return "\(remaining)\(total) \(unit) left"
    }

    private static func cachedInfo(resource: String, in summary: RepoBarCacheSummary) -> CachedRateLimitInfo? {
        guard let row = summary.latestResponses.filter({ $0.rateLimitResource == resource }).max(by: { $0.fetchedAt < $1.fetchedAt }) else { return nil }

        return CachedRateLimitInfo(remaining: row.rateLimitRemaining, limit: row.rateLimitLimit)
    }

    static func percent(remaining: Int?, limit: Int?) -> Double? {
        guard let remaining, let limit, limit > 0 else { return nil }

        let raw = (Double(remaining) / Double(limit)) * 100
        return min(100, max(0, raw))
    }

    private static func shortCount(_ value: Int) -> String {
        if value >= 1000 {
            let rounded = Double(value) / 1000
            return rounded.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(rounded))K"
                : String(format: "%.1fK", rounded)
        }
        return "\(value)"
    }

    private struct CachedRateLimitInfo {
        let remaining: Int?
        let limit: Int?
    }
}
