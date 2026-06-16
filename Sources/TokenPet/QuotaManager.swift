import Foundation
import Combine

@MainActor public class QuotaManager: ObservableObject {
    public static let shared = QuotaManager()
    
    private var settings = SettingsManager.shared
    private var logParser = UsageLogParser.shared
    private var cancellables = Set<AnyCancellable>()
    
    // Codex Derived display values
    @Published public var quota5hUsed: Int = 0
    @Published public var quota7dUsed: Int = 0
    @Published public var quota5hRemaining: Int = 0
    @Published public var quota7dRemaining: Int = 0
    @Published public var quota5hPercent: Double = 1.0
    @Published public var quota7dPercent: Double = 1.0
    @Published public var is5hWarning: Bool = false
    @Published public var is7dWarning: Bool = false
    @Published public var lastUpdated: Date = Date()
    @Published public var dataSource: String = "日志自动解析"
    
    // Gemini Derived display values (computed via SQLite in CCDataCoordinator)
    @Published public var gemini5hUsed: Int = 0
    @Published public var gemini5hRemaining: Int = 0
    @Published public var gemini5hPercent: Double = 1.0
    @Published public var geminiIsExhausted: Bool = false
    @Published public var geminiResetsRemaining: String = "良好"
    
    @Published public var gemini24hUsed: Int = 0
    @Published public var gemini24hRemaining: Int = 0
    @Published public var gemini24hPercent: Double = 1.0
    @Published public var gemini24hIsExhausted: Bool = false
    @Published public var gemini24hResetsRemaining: String = "良好"
    @Published public var gemini5hWindowLabel: String = "剩余 5h"
    @Published public var geminiLongWindowLabel: String = "剩余 24h"
    @Published public var gemini5hUsesOfficialSnapshot: Bool = false
    @Published public var geminiLongUsesOfficialSnapshot: Bool = false
    @Published public var geminiMixedOfficialAndLocal: Bool = false
    
    @Published public var geminiDataSource: String = "Gemini 自动解析 (SQLite)"
    
    @Published public var parseError: String? = nil
    
    private init() {
        // Wire CCDataCoordinator output into quota calculations
        CCDataCoordinator.shared.$usageData
            .sink { [weak self] usage in
                guard let self = self else { return }
                
                // --- Codex Quota ---
                if let rateLimits = usage.rateLimits {
                    let now = Date()
                    let is5hExpired = rateLimits.primary5hResetsAt <= now
                    let is7dExpired = rateLimits.secondary7dResetsAt <= now
                    
                    self.quota5hUsed = is5hExpired ? 0 : Int(rateLimits.primary5hUsedPercent)
                    self.quota7dUsed = is7dExpired ? 0 : Int(rateLimits.secondary7dUsedPercent)
                    
                    let planLabel = rateLimits.planType.uppercased()
                    let accountPart = rateLimits.accountLabel.map { " · \($0)" } ?? ""
                    if is5hExpired {
                        self.dataSource = "Codex \(planLabel)\(accountPart) · 5h 已重置"
                    } else {
                        self.dataSource = "Codex 官方实时额度 (\(planLabel)\(accountPart))"
                    }
                } else {
                    self.quota5hUsed = 0
                    self.quota7dUsed = 0
                    self.dataSource = "未检测到 Codex 会话数据"
                }
                
                // --- Antigravity quota (/usage is the primary target) ---
                let now = Date()
                let antigravity = usage.antigravityStats
                let activeModelName: String = {
                    if let best = antigravity.modelUsages.max(by: { $0.calls24h < $1.calls24h }), best.calls24h > 0 {
                        return best.modelName
                    }
                    return antigravity.modelUsages.first?.modelName ?? "Gemini 3.5"
                }()
                
                let normModel = self.normalizedModel(activeModelName)
                let hasAntigravityLocalUsage = antigravity.calls7d > 0 || antigravity.errorCount7d > 0
                
                self.geminiMixedOfficialAndLocal = false
                
                let local5hUsed = min(100, Int(Double(antigravity.calls5h) / Double(antigravity.inferredLimit5h ?? 300) * 100.0))
                let local24hUsed = min(100, Int(Double(antigravity.calls24h) / Double(antigravity.inferredLimit24h ?? 1000) * 100.0))
                
                // 5h limit
                if let official5h = self.officialBucket(from: usage.geminiOfficialQuotas, normalizedModel: normModel, preferredWindows: ["5h", "model", "unknown"], requiredTool: "antigravity-cli") {
                    self.gemini5hUsesOfficialSnapshot = true
                    self.gemini5hWindowLabel = self.displayWindowLabel(for: official5h, fallback: "剩余 5h")
                    self.geminiIsExhausted = (official5h.remainingFraction <= 0.0)
                    
                    let official5hUsed = Int((1.0 - official5h.remainingFraction) * 100.0)
                    self.gemini5hUsed = max(official5hUsed, local5hUsed)
                    self.geminiResetsRemaining = self.formatTimeRemaining(from: official5h.resetTime)
                } else if let errorResetsAt = antigravity.activeError5hResetsAt, errorResetsAt > now {
                    self.gemini5hUsesOfficialSnapshot = false
                    self.gemini5hWindowLabel = "剩余 5h"
                    self.gemini5hUsed = 100
                    self.geminiIsExhausted = true
                    self.geminiResetsRemaining = self.formatTimeRemaining(from: errorResetsAt)
                } else {
                    self.gemini5hUsesOfficialSnapshot = false
                    self.gemini5hWindowLabel = "剩余 5h"
                    self.geminiIsExhausted = false
                    self.geminiResetsRemaining = hasAntigravityLocalUsage ? "/usage 未采集" : "无反重力数据"
                    self.gemini5hUsed = local5hUsed
                }
                self.gemini5hRemaining = max(0, 100 - self.gemini5hUsed)
                self.gemini5hPercent = max(0, min(1.0, Double(self.gemini5hRemaining) / 100.0))
                
                // Long limit (24h/7d/monthly)
                if let official24h = self.officialBucket(from: usage.geminiOfficialQuotas, normalizedModel: normModel, preferredWindows: ["24h", "1d", "7d", "weekly", "monthly"], requiredTool: "antigravity-cli") {
                    self.geminiLongUsesOfficialSnapshot = true
                    self.geminiLongWindowLabel = self.displayWindowLabel(for: official24h, fallback: "剩余 24h")
                    self.gemini24hIsExhausted = (official24h.remainingFraction <= 0.0)
                    
                    let official24hUsed = Int((1.0 - official24h.remainingFraction) * 100.0)
                    self.gemini24hUsed = max(official24hUsed, local24hUsed)
                    self.gemini24hResetsRemaining = self.formatTimeRemaining(from: official24h.resetTime)
                } else if let errorResetsAt = antigravity.activeError24hResetsAt, errorResetsAt > now {
                    self.geminiLongUsesOfficialSnapshot = false
                    self.geminiLongWindowLabel = "剩余 24h"
                    self.gemini24hUsed = 100
                    self.gemini24hIsExhausted = true
                    self.gemini24hResetsRemaining = self.formatTimeRemaining(from: errorResetsAt)
                } else {
                    self.geminiLongUsesOfficialSnapshot = false
                    self.geminiLongWindowLabel = "剩余 24h"
                    self.gemini24hIsExhausted = false
                    self.gemini24hResetsRemaining = hasAntigravityLocalUsage ? "/usage 未采集" : "无反重力数据"
                    self.gemini24hUsed = local24hUsed
                }
                self.gemini24hRemaining = max(0, 100 - self.gemini24hUsed)
                self.gemini24hPercent = max(0, min(1.0, Double(self.gemini24hRemaining) / 100.0))
                
                // Data Source Label
                let hasOfficial5h = self.gemini5hUsesOfficialSnapshot
                let hasOfficial24h = self.geminiLongUsesOfficialSnapshot
                
                if hasOfficial5h && hasOfficial24h {
                    let accountLabel = usage.geminiOfficialQuotas.first?.accountLabel ?? "云端"
                    self.geminiDataSource = "反重力官方 /usage 实时同步 (\(accountLabel))"
                } else if hasOfficial5h || hasOfficial24h {
                    self.geminiMixedOfficialAndLocal = true
                    let accountLabel = usage.geminiOfficialQuotas.first?.accountLabel ?? "云端"
                    self.geminiDataSource = "反重力官方 /usage 与本地混合 (\(accountLabel))"
                } else {
                    if hasAntigravityLocalUsage {
                        self.geminiDataSource = "反重力 /usage 未采集；当前为本地调用/429"
                    } else {
                        self.geminiDataSource = "未检测到反重力 /usage 或本地调用"
                    }
                }
                
                self.lastUpdated = usage.lastUpdated
                self.recalculate()
            }
            .store(in: &cancellables)
        
        logParser.$parseError
            .sink { [weak self] error in
                self?.parseError = error
            }
            .store(in: &cancellables)
        
        // Recalculate when thresholds change
        settings.$quota5hThreshold
            .combineLatest(settings.$quota7dThreshold)
            .sink { [weak self] _, _ in self?.recalculate() }
            .store(in: &cancellables)
        
        // Start auto-refresh every 30 seconds via coordinator
        CCDataCoordinator.shared.startAutoRefresh(interval: 30)
    }
    
    private func normalizedModel(_ modelName: String) -> String {
        let lower = modelName.lowercased()
        if lower.contains("flash") {
            return lower.contains("lite") ? "lite" : "flash"
        }
        if lower.contains("pro") {
            return "pro"
        }
        if lower.contains("3.5") || lower.contains("3.1") || lower.contains("gemini-3") {
            return "gemini-3"
        }
        if lower.contains("2.5") {
            return "gemini-2.5"
        }
        return lower
    }
    
    private func officialBucket(
        from buckets: [GeminiOfficialQuotaBucket],
        normalizedModel: String,
        preferredWindows: [String],
        requiredTool: String? = nil
    ) -> GeminiOfficialQuotaBucket? {
        // If a specific tool is required (e.g. "antigravity-cli"), filter to only
        // those buckets. This prevents gemini-cli's 100%-remaining quota from
        // being mistakenly applied to the Antigravity progress bar.
        let toolFiltered = requiredTool.map { tool in
            buckets.filter { $0.sourceTool == tool }
        } ?? buckets
        
        // If no tool-matched buckets exist, return nil immediately rather than
        // falling back to other tools' data.
        guard !toolFiltered.isEmpty else { return nil }
        
        let matchingModel = toolFiltered.filter { bucket in
            let model = bucket.modelId.lowercased()
            if normalizedModel == "gemini-3" {
                return model.contains("gemini") || model.contains("flash") || model.contains("pro")
            }
            if normalizedModel == "gemini-2.5" {
                return model.contains("gemini-2.5") || model.contains("gemini")
            }
            if normalizedModel == "flash" {
                return (model.contains("flash") && !model.contains("lite")) || model.contains("gemini")
            }
            if normalizedModel == "lite" {
                return model.contains("lite") || model.contains("gemini")
            }
            if normalizedModel == "pro" {
                return model.contains("pro") || model.contains("gemini")
            }
            return model.contains(normalizedModel) || normalizedModel.contains(model)
        }
        let candidates = matchingModel.isEmpty ? toolFiltered : matchingModel
        for window in preferredWindows {
            let windowCandidates = candidates.filter { $0.windowType == window }
            if let bucket = tightestBucket(windowCandidates) {
                return bucket
            }
        }
        return tightestBucket(candidates)
    }
    
    private func tightestBucket(_ buckets: [GeminiOfficialQuotaBucket]) -> GeminiOfficialQuotaBucket? {
        let now = Date()
        return buckets.min { lhs, rhs in
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
    }
    
    private func displayWindowLabel(for bucket: GeminiOfficialQuotaBucket, fallback: String) -> String {
        switch bucket.windowType {
        case "5h": return "剩余 5h"
        case "24h", "1d": return "剩余 24h"
        case "7d", "weekly": return "剩余 7d"
        case "monthly": return "剩余 30d"
        case "model", "unknown": return "剩余 5h"
        default: return fallback
        }
    }
    
    private func recalculate() {
        quota5hRemaining = max(0, 100 - quota5hUsed)
        quota7dRemaining = max(0, 100 - quota7dUsed)
        quota5hPercent = max(0, min(1.0, Double(quota5hRemaining) / 100.0))
        quota7dPercent = max(0, min(1.0, Double(quota7dRemaining) / 100.0))
        is5hWarning = quota5hRemaining <= settings.quota5hThreshold
        is7dWarning = quota7dRemaining <= settings.quota7dThreshold
    }
    
    public func forceRefresh() {
        CCDataCoordinator.shared.refresh()
    }
    
    // MARK: - Countdown helpers
    
    public func timeRemaining5h() -> String {
        guard let rateLimits = CCDataCoordinator.shared.usageData.rateLimits else {
            return "约 \(timeUntilNextReset(hours: 5))"
        }
        let now = Date()
        if rateLimits.primary5hResetsAt > now {
            return formatTimeRemaining(from: rateLimits.primary5hResetsAt)
        } else {
            return "已重置"
        }
    }
    
    public func timeRemaining7d() -> String {
        guard let rateLimits = CCDataCoordinator.shared.usageData.rateLimits else {
            return "约 \(timeUntilNextReset(days: 7))"
        }
        let now = Date()
        if rateLimits.secondary7dResetsAt > now {
            return formatTimeRemaining(from: rateLimits.secondary7dResetsAt)
        } else {
            return "已重置"
        }
    }
    
    private func formatUpdateDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "今天 " + f.string(from: date)
        } else if cal.isDateInYesterday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "昨日 " + f.string(from: date)
        } else {
            let f = DateFormatter()
            f.dateFormat = "MM-dd HH:mm"
            return f.string(from: date)
        }
    }
    
    public func formatTimeRemaining(from targetDate: Date?) -> String {
        guard let targetDate else { return "重置未返回" }
        let remaining = targetDate.timeIntervalSince(Date())
        if remaining <= 0 { return "即将重置" }
        
        let d = Int(remaining) / 86400
        let h = (Int(remaining) % 86400) / 3600
        let m = (Int(remaining) % 3600) / 60
        
        if d > 0 {
            return "\(d)天\(h)小时"
        } else if h > 0 {
            return "\(h)小时\(m)分钟"
        } else {
            return "\(m)分钟"
        }
    }
    
    private func timeUntilNextReset(hours: Int) -> String {
        let secondsPerWindow = TimeInterval(hours) * 3600
        let resetTime = Date().addingTimeInterval(secondsPerWindow).addingTimeInterval(-Date().timeIntervalSince1970.truncatingRemainder(dividingBy: secondsPerWindow))
        let remaining = resetTime.timeIntervalSince(Date())
        if remaining <= 0 { return "即将重置" }
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        return h > 0 ? "\(h)小时\(m)分钟" : "\(m)分钟"
    }
    
    private func timeUntilNextReset(days: Int) -> String {
        let secondsPerWindow = TimeInterval(days) * 24 * 3600
        let remaining = secondsPerWindow - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: secondsPerWindow)
        let d = Int(remaining) / 86400
        let h = (Int(remaining) % 86400) / 3600
        return d > 0 ? "\(d)天\(h)小时" : "\(h)小时"
    }
}
