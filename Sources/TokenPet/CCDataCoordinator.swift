import Foundation
import Combine

@MainActor public class CCDataCoordinator: ObservableObject {
    public static let shared = CCDataCoordinator()
    
    @Published public var usageData: CCUsageData
    @Published public var secondsUntilRefresh: Int = 30
    private var refreshInterval: TimeInterval = 30
    
    private var timer: AnyCancellable?
    private var logParser = UsageLogParser.shared
    private var scanner = SessionScanner.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Initialize with default empty usage data
        self.usageData = CCUsageData(
            rateLimits: nil,
            tokenSummary: TokenUsageSummary(
                inputTokens5h: 0, outputTokens5h: 0, cachedInputTokens5h: 0,
                inputTokens7d: 0, outputTokens7d: 0, cachedInputTokens7d: 0,
                sessionCount5h: 0, sessionCount7d: 0
            ),
            geminiCalls5h: 0,
            geminiCalls24h: 0,
            geminiCalls7d: 0,
            geminiActiveError5hResetsAt: nil,
            geminiActiveError24hResetsAt: nil,
            geminiActiveErrorResetsAt: nil,
            geminiActiveErrorMessage: nil,
            geminiInferredLimit5h: nil,
            geminiInferredLimit24h: nil,
            geminiErrorCount7d: 0,
            lastUpdated: Date(),
            dataSource: "Codex & Gemini 自动解析 (SQLite)"
        )
        
        // Listen to UsageLogParser changes to merge Gemini stats
        logParser.$lastParsed
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.usageData.geminiCalls5h = self.logParser.calls5h
                self.usageData.geminiCalls24h = self.logParser.calls24h
                self.usageData.geminiCalls7d = self.logParser.calls7d
                self.usageData.geminiActiveError5hResetsAt = self.logParser.activeError5hResetsAt
                self.usageData.geminiActiveError24hResetsAt = self.logParser.activeError24hResetsAt
                self.usageData.geminiActiveErrorResetsAt = self.logParser.activeErrorResetsAt
                self.usageData.geminiActiveErrorMessage = self.logParser.activeErrorMessage
                self.usageData.geminiInferredLimit5h = self.logParser.inferredLimit5h
                self.usageData.geminiInferredLimit24h = self.logParser.inferredLimit24h
                self.usageData.geminiErrorCount7d = self.logParser.errorCount7d
                self.usageData.geminiTokenSummary = self.logParser.geminiTokenSummary
                self.usageData.geminiToolUsageBreakdown = SQLiteManager.shared.getGeminiToolUsageBreakdown(now: Date())
                self.usageData.antigravityStats = SQLiteManager.shared.getAntigravityStats(now: Date())
                self.usageData.antigravityStats.modelUsages = self.mergeGeminiModelUsages(
                    self.usageData.antigravityStats.modelUsages,
                    quotas: self.antigravityQuotas(self.usageData.geminiOfficialQuotas)
                )
                self.usageData.geminiModelUsages = self.mergeGeminiModelUsages(
                    self.logParser.modelUsages,
                    quotas: self.usageData.geminiOfficialQuotas
                )
            }
            .store(in: &cancellables)
    }
    
    public func startAutoRefresh(interval: TimeInterval = 30) {
        refreshInterval = interval
        secondsUntilRefresh = Int(interval)
        logParser.startAutoRefresh(interval: interval)
        
        refresh()
        
        timer?.cancel()
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.secondsUntilRefresh > 1 {
                    self.secondsUntilRefresh -= 1
                } else {
                    self.secondsUntilRefresh = Int(self.refreshInterval)
                    self.refresh()
                }
            }
    }
    
    public func stopAutoRefresh() {
        timer?.cancel()
        timer = nil
        logParser.stopAutoRefresh()
    }
    
    public func refresh() {
        AntigravityLocalUsageClient.clearCache()
        secondsUntilRefresh = Int(refreshInterval)
        // 1. Refresh Gemini logs first (inserts new records into SQLite)
        logParser.refresh()
        
        // 2. Scan Codex session files (inserts new records into SQLite)
        let now = Date()
        DispatchQueue.global(qos: .utility).async {
            let (rateLimits, summary) = SessionScanner.shared.scan(now: now)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.usageData.rateLimits = rateLimits
                self.usageData.tokenSummary = summary
                self.usageData.geminiToolUsageBreakdown = SQLiteManager.shared.getGeminiToolUsageBreakdown(now: now)
                self.usageData.antigravityStats = SQLiteManager.shared.getAntigravityStats(now: now)
                self.usageData.antigravityStats.modelUsages = self.mergeGeminiModelUsages(
                    self.usageData.antigravityStats.modelUsages,
                    quotas: self.antigravityQuotas(self.usageData.geminiOfficialQuotas)
                )
                self.usageData.lastUpdated = now
            }
        }
        
        // 3. Fetch official Gemini quota via API
        Task {
            await GeminiQuotaClient.shared.fetchQuota()
            self.usageData.geminiOfficialQuotas = GeminiQuotaClient.shared.officialQuotas
            self.usageData.geminiQuotaFetchError = GeminiQuotaClient.shared.lastFetchError
            self.usageData.geminiModelUsages = self.mergeGeminiModelUsages(
                self.usageData.geminiModelUsages,
                quotas: GeminiQuotaClient.shared.officialQuotas
            )
            self.usageData.antigravityStats.modelUsages = self.mergeGeminiModelUsages(
                self.usageData.antigravityStats.modelUsages,
                quotas: self.antigravityQuotas(GeminiQuotaClient.shared.officialQuotas)
            )
        }
    }
    
    private func antigravityQuotas(_ quotas: [GeminiOfficialQuotaBucket]) -> [GeminiOfficialQuotaBucket] {
        quotas.filter { $0.sourceTool == "antigravity-cli" }
    }
    
    private func mergeGeminiModelUsages(_ usages: [GeminiModelUsage], quotas: [GeminiOfficialQuotaBucket]) -> [GeminiModelUsage] {
        var byModel = Dictionary(uniqueKeysWithValues: usages.map { ($0.modelName, $0) })
        
        for quota in quotas {
            let key = displayModelName(for: quota.modelId)
            var usage = byModel[key] ?? GeminiModelUsage(modelName: key)
            if !usage.officialQuotas.contains(quota) {
                usage.officialQuotas.append(quota)
                usage.officialQuotas.sort { lhs, rhs in
                    if lhs.windowType != rhs.windowType {
                        return windowSortValue(lhs.windowType) < windowSortValue(rhs.windowType)
                    }
                    return (lhs.resetTime ?? .distantFuture) < (rhs.resetTime ?? .distantFuture)
                }
            }
            byModel[key] = usage
        }
        
        return Array(byModel.values.sorted { lhs, rhs in
            let lhsHasQuota = !lhs.officialQuotas.isEmpty
            let rhsHasQuota = !rhs.officialQuotas.isEmpty
            if lhsHasQuota != rhsHasQuota {
                return lhsHasQuota && !rhsHasQuota
            }
            if lhs.calls5h != rhs.calls5h {
                return lhs.calls5h > rhs.calls5h
            }
            if lhs.calls24h != rhs.calls24h {
                return lhs.calls24h > rhs.calls24h
            }
            return lhs.modelName < rhs.modelName
        }.prefix(12))
    }
    
    private func displayModelName(for modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower == "pro" {
            return "Gemini 3.1 Pro (High)"
        }
        if lower == "flash" || lower == "flash-lite" || lower == "lite" {
            return SQLiteManager.mapToAntigravityModelName(lower)
        }
        let mapped = SQLiteManager.mapToAntigravityModelName(modelId)
        if mapped != modelId {
            return mapped
        }
        if lower.contains("flash-lite") || lower.contains("flash_lite") || lower == "lite" {
            return "flash-lite"
        }
        if lower.contains("flash") {
            return "flash"
        }
        if lower.contains("pro") {
            return "pro"
        }
        return modelId
    }
    
    private func windowSortValue(_ window: String) -> Int {
        switch window {
        case "5h": return 0
        case "24h": return 1
        case "7d": return 2
        case "monthly": return 3
        default: return 9
        }
    }
}
