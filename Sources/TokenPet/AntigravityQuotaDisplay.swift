import Foundation

public struct AntigravityQuotaDisplayGroup: Identifiable, Equatable, Sendable {
    public var id: String { title.lowercased() }
    public let title: String
    public let description: String
    public let accountLabel: String?
    public let buckets: [AntigravityQuotaDisplayBucket]
}

public struct AntigravityQuotaDisplayBucket: Identifiable, Equatable, Sendable {
    public var id: String {
        [
            title,
            windowType,
            resetTime.map { String(Int($0.timeIntervalSince1970)) } ?? "no-reset",
            String(format: "%.5f", remainingFraction)
        ].joined(separator: "|")
    }
    
    public let title: String
    public let windowType: String
    public let remainingFraction: Double
    public let resetTime: Date?
    
    public var remainingPercent: Double {
        max(0, min(100, remainingFraction * 100.0))
    }
    
    public var remainingWholePercent: Int {
        max(0, min(100, Int(remainingPercent)))
    }
}

public enum AntigravityQuotaDisplayBuilder {
    public static func groups(from buckets: [GeminiOfficialQuotaBucket]) -> [AntigravityQuotaDisplayGroup] {
        let antigravityBuckets = buckets.filter {
            $0.sourceTool == "antigravity-cli" && $0.tokenType.lowercased() != "credits"
        }
        
        struct Accumulator {
            var title: String
            var description: String
            var accountLabel: String?
            var bucketsByWindow: [String: AntigravityQuotaDisplayBucket] = [:]
        }
        
        var grouped: [String: Accumulator] = [:]
        for bucket in antigravityBuckets {
            guard let window = normalizedDisplayWindow(bucket.windowType) else { continue }
            let groupTitle = canonicalGroupTitle(for: bucket)
            let key = groupTitle.lowercased()
            let description = localizedDescription(for: groupTitle, raw: bucket.groupDescription)
            var accumulator = grouped[key] ?? Accumulator(
                title: groupTitle,
                description: description,
                accountLabel: bucket.accountLabel
            )
            if accumulator.accountLabel == nil {
                accumulator.accountLabel = bucket.accountLabel
            }
            if accumulator.description.isEmpty {
                accumulator.description = description
            }
            
            let displayBucket = AntigravityQuotaDisplayBucket(
                title: localizedBucketTitle(bucket.bucketDisplayName, window: window),
                windowType: window,
                remainingFraction: bucket.remainingFraction,
                resetTime: bucket.resetTime
            )
            
            if let existing = accumulator.bucketsByWindow[window] {
                if isTighter(displayBucket, than: existing) {
                    accumulator.bucketsByWindow[window] = displayBucket
                }
            } else {
                accumulator.bucketsByWindow[window] = displayBucket
            }
            grouped[key] = accumulator
        }
        
        return grouped.values
            .map { accumulator in
                AntigravityQuotaDisplayGroup(
                    title: accumulator.title,
                    description: accumulator.description,
                    accountLabel: accumulator.accountLabel,
                    buckets: accumulator.bucketsByWindow.values.sorted { lhs, rhs in
                        windowOrder(lhs.windowType) < windowOrder(rhs.windowType)
                    }
                )
            }
            .filter { !$0.buckets.isEmpty }
            .sorted { lhs, rhs in
                groupOrder(lhs.title) < groupOrder(rhs.title)
            }
    }
    
    private static func normalizedDisplayWindow(_ window: String) -> String? {
        let lower = window.lowercased()
        if lower == "weekly" || lower == "7d" || lower.contains("week") {
            return "weekly"
        }
        if lower == "5h" || lower.contains("5") && lower.contains("hour") || lower == "model" || lower == "unknown" {
            return "5h"
        }
        return nil
    }
    
    private static func canonicalGroupTitle(for bucket: GeminiOfficialQuotaBucket) -> String {
        let haystack = [
            bucket.modelId,
            bucket.groupDescription ?? "",
            bucket.bucketId ?? "",
            bucket.bucketDisplayName ?? ""
        ].joined(separator: " ").lowercased()
        
        if haystack.contains("claude") || haystack.contains("gpt") || haystack.contains("oss") || haystack.contains("3p") {
            return "Claude 与 GPT 模型"
        }
        if haystack.contains("gemini") || haystack.contains("flash") || haystack.contains("pro") {
            return "Gemini 模型"
        }
        return bucket.modelId
    }
    
    private static func fallbackDescription(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("claude") || lower.contains("gpt") {
            return "该组模型：Claude Opus、Claude Sonnet、GPT-OSS"
        }
        if lower.contains("gemini") {
            return "该组模型：Gemini Flash、Gemini Pro"
        }
        return ""
    }
    
    private static func localizedDescription(for title: String, raw: String?) -> String {
        let fallback = fallbackDescription(for: title)
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        
        let lower = raw.lowercased()
        if lower.contains("models within this group") {
            return fallback
        }
        return raw
    }
    
    private static func title(for window: String) -> String {
        switch window {
        case "weekly": return "剩余 7d"
        case "5h": return "剩余 5h"
        case "24h", "1d": return "剩余 24h"
        default: return "剩余 \(window)"
        }
    }
    
    private static func localizedBucketTitle(_ raw: String?, window: String) -> String {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return title(for: window)
        }
        
        let lower = raw.lowercased()
        if lower.contains("weekly") || lower.contains("week") {
            return title(for: "weekly")
        }
        if lower.contains("five") || lower.contains("5") && lower.contains("hour") {
            return title(for: "5h")
        }
        return raw
    }
    
    private static func isTighter(_ lhs: AntigravityQuotaDisplayBucket, than rhs: AntigravityQuotaDisplayBucket) -> Bool {
        let now = Date()
        let lhsExpired = lhs.resetTime.map { $0 <= now } ?? false
        let rhsExpired = rhs.resetTime.map { $0 <= now } ?? false
        if lhsExpired != rhsExpired {
            return !lhsExpired
        }
        if lhs.remainingFraction != rhs.remainingFraction {
            return lhs.remainingFraction < rhs.remainingFraction
        }
        return (lhs.resetTime ?? .distantFuture) < (rhs.resetTime ?? .distantFuture)
    }
    
    private static func windowOrder(_ window: String) -> Int {
        switch window {
        case "5h": return 0
        case "weekly": return 1
        default: return 9
        }
    }
    
    private static func groupOrder(_ title: String) -> Int {
        let lower = title.lowercased()
        if lower.contains("gemini") { return 0 }
        if lower.contains("claude") || lower.contains("gpt") { return 1 }
        return 9
    }
}
