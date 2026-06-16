import Foundation

public struct TokenEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var input: Int
    public var output: Int
    public var cached: Int
    
    public init(timestamp: Date, input: Int, output: Int, cached: Int) {
        self.timestamp = timestamp
        self.input = input
        self.output = output
        self.cached = cached
    }
}

public struct CodexRateLimits: Codable, Equatable, Sendable {
    public var primary5hUsedPercent: Double    // 5h 已用 %（0-100）
    public var primary5hResetsAt: Date         // 精确重置时间
    public var secondary7dUsedPercent: Double  // 7d 已用 %
    public var secondary7dResetsAt: Date
    public var planType: String                // "plus" / "free"
    public var sessionTimestamp: Date          // 该数据对应的 session 时间
    public var accountLabel: String?
    
    public init(primary5hUsedPercent: Double, primary5hResetsAt: Date, secondary7dUsedPercent: Double, secondary7dResetsAt: Date, planType: String, sessionTimestamp: Date, accountLabel: String? = nil) {
        self.primary5hUsedPercent = primary5hUsedPercent
        self.primary5hResetsAt = primary5hResetsAt
        self.secondary7dUsedPercent = secondary7dUsedPercent
        self.secondary7dResetsAt = secondary7dResetsAt
        self.planType = planType
        self.sessionTimestamp = sessionTimestamp
        self.accountLabel = accountLabel
    }
}

public struct TokenUsageSummary: Codable, Equatable, Sendable {
    public var inputTokens5h: Int
    public var outputTokens5h: Int
    public var cachedInputTokens5h: Int
    public var inputTokens7d: Int
    public var outputTokens7d: Int
    public var cachedInputTokens7d: Int
    public var sessionCount5h: Int
    public var sessionCount7d: Int
    
    public init(inputTokens5h: Int, outputTokens5h: Int, cachedInputTokens5h: Int, inputTokens7d: Int, outputTokens7d: Int, cachedInputTokens7d: Int, sessionCount5h: Int, sessionCount7d: Int) {
        self.inputTokens5h = inputTokens5h
        self.outputTokens5h = outputTokens5h
        self.cachedInputTokens5h = cachedInputTokens5h
        self.inputTokens7d = inputTokens7d
        self.outputTokens7d = outputTokens7d
        self.cachedInputTokens7d = cachedInputTokens7d
        self.sessionCount5h = sessionCount5h
        self.sessionCount7d = sessionCount7d
    }
}

public struct GeminiTokenUsageSummary: Codable, Equatable, Sendable {
    public var inputTokens5h: Int
    public var outputTokens5h: Int
    public var cachedTokens5h: Int
    public var thoughtsTokens5h: Int
    public var toolTokens5h: Int
    public var totalTokens5h: Int
    
    public var inputTokens7d: Int
    public var outputTokens7d: Int
    public var cachedTokens7d: Int
    public var thoughtsTokens7d: Int
    public var toolTokens7d: Int
    public var totalTokens7d: Int
    
    public init(
        inputTokens5h: Int = 0,
        outputTokens5h: Int = 0,
        cachedTokens5h: Int = 0,
        thoughtsTokens5h: Int = 0,
        toolTokens5h: Int = 0,
        totalTokens5h: Int = 0,
        inputTokens7d: Int = 0,
        outputTokens7d: Int = 0,
        cachedTokens7d: Int = 0,
        thoughtsTokens7d: Int = 0,
        toolTokens7d: Int = 0,
        totalTokens7d: Int = 0
    ) {
        self.inputTokens5h = inputTokens5h
        self.outputTokens5h = outputTokens5h
        self.cachedTokens5h = cachedTokens5h
        self.thoughtsTokens5h = thoughtsTokens5h
        self.toolTokens5h = toolTokens5h
        self.totalTokens5h = totalTokens5h
        self.inputTokens7d = inputTokens7d
        self.outputTokens7d = outputTokens7d
        self.cachedTokens7d = cachedTokens7d
        self.thoughtsTokens7d = thoughtsTokens7d
        self.toolTokens7d = toolTokens7d
        self.totalTokens7d = totalTokens7d
    }
}

public struct GeminiModelUsage: Codable, Equatable, Identifiable, Sendable {
    public var id: String { modelName }
    public var modelName: String
    public var calls5h: Int
    public var calls24h: Int
    public var calls7d: Int
    public var errorCount7d: Int
    public var activeResetAt: Date?
    public var activeErrorMessage: String?
    public var officialQuotas: [GeminiOfficialQuotaBucket]
    
    // Telemetry tokens (last 5h)
    public var inputTokens5h: Int
    public var outputTokens5h: Int
    public var cachedTokens5h: Int
    public var thoughtsTokens5h: Int
    public var toolTokens5h: Int
    public var totalTokens5h: Int
    public var avgDurationMs5h: Double
    
    public init(
        modelName: String,
        calls5h: Int = 0,
        calls24h: Int = 0,
        calls7d: Int = 0,
        errorCount7d: Int = 0,
        activeResetAt: Date? = nil,
        activeErrorMessage: String? = nil,
        officialQuotas: [GeminiOfficialQuotaBucket] = [],
        inputTokens5h: Int = 0,
        outputTokens5h: Int = 0,
        cachedTokens5h: Int = 0,
        thoughtsTokens5h: Int = 0,
        toolTokens5h: Int = 0,
        totalTokens5h: Int = 0,
        avgDurationMs5h: Double = 0.0
    ) {
        self.modelName = modelName
        self.calls5h = calls5h
        self.calls24h = calls24h
        self.calls7d = calls7d
        self.errorCount7d = errorCount7d
        self.activeResetAt = activeResetAt
        self.activeErrorMessage = activeErrorMessage
        self.officialQuotas = officialQuotas
        self.inputTokens5h = inputTokens5h
        self.outputTokens5h = outputTokens5h
        self.cachedTokens5h = cachedTokens5h
        self.thoughtsTokens5h = thoughtsTokens5h
        self.toolTokens5h = toolTokens5h
        self.totalTokens5h = totalTokens5h
        self.avgDurationMs5h = avgDurationMs5h
    }
}

public struct GeminiToolUsageBreakdown: Codable, Equatable, Sendable {
    public var geminiCliCalls24h: Int
    public var antigravityCalls24h: Int
    public var legacyGeminiCalls24h: Int
    public var latestToolName: String?
    
    public init(
        geminiCliCalls24h: Int = 0,
        antigravityCalls24h: Int = 0,
        legacyGeminiCalls24h: Int = 0,
        latestToolName: String? = nil
    ) {
        self.geminiCliCalls24h = geminiCliCalls24h
        self.antigravityCalls24h = antigravityCalls24h
        self.legacyGeminiCalls24h = legacyGeminiCalls24h
        self.latestToolName = latestToolName
    }
}

public struct GoogleToolUsageStats: Codable, Equatable, Sendable {
    public var calls5h: Int
    public var calls24h: Int
    public var calls7d: Int
    public var activeError5hResetsAt: Date?
    public var activeError24hResetsAt: Date?
    public var activeErrorResetsAt: Date?
    public var activeErrorMessage: String?
    public var inferredLimit5h: Int?
    public var inferredLimit24h: Int?
    public var errorCount7d: Int
    public var tokenSummary: GeminiTokenUsageSummary
    public var modelUsages: [GeminiModelUsage]
    
    public init(
        calls5h: Int = 0,
        calls24h: Int = 0,
        calls7d: Int = 0,
        activeError5hResetsAt: Date? = nil,
        activeError24hResetsAt: Date? = nil,
        activeErrorResetsAt: Date? = nil,
        activeErrorMessage: String? = nil,
        inferredLimit5h: Int? = nil,
        inferredLimit24h: Int? = nil,
        errorCount7d: Int = 0,
        tokenSummary: GeminiTokenUsageSummary = GeminiTokenUsageSummary(),
        modelUsages: [GeminiModelUsage] = []
    ) {
        self.calls5h = calls5h
        self.calls24h = calls24h
        self.calls7d = calls7d
        self.activeError5hResetsAt = activeError5hResetsAt
        self.activeError24hResetsAt = activeError24hResetsAt
        self.activeErrorResetsAt = activeErrorResetsAt
        self.activeErrorMessage = activeErrorMessage
        self.inferredLimit5h = inferredLimit5h
        self.inferredLimit24h = inferredLimit24h
        self.errorCount7d = errorCount7d
        self.tokenSummary = tokenSummary
        self.modelUsages = modelUsages
    }
}

public struct GeminiOfficialQuotaBucket: Codable, Equatable, Sendable {
    public var modelId: String
    public var remainingFraction: Double
    public var resetTime: Date?
    public var tokenType: String
    public var windowType: String
    public var sourceTool: String
    public var accountLabel: String?
    public var bucketId: String?
    public var bucketDisplayName: String?
    public var groupDescription: String?
    
    public init(
        modelId: String,
        remainingFraction: Double,
        resetTime: Date? = nil,
        tokenType: String,
        windowType: String = "unknown",
        sourceTool: String = "gemini-cli",
        accountLabel: String? = nil,
        bucketId: String? = nil,
        bucketDisplayName: String? = nil,
        groupDescription: String? = nil
    ) {
        self.modelId = modelId
        self.remainingFraction = remainingFraction
        self.resetTime = resetTime
        self.tokenType = tokenType
        self.windowType = windowType
        self.sourceTool = sourceTool
        self.accountLabel = accountLabel
        self.bucketId = bucketId
        self.bucketDisplayName = bucketDisplayName
        self.groupDescription = groupDescription
    }
}

// 聚合输出
public struct CCUsageData: Codable, Equatable, Sendable {
    public var rateLimits: CodexRateLimits?
    public var tokenSummary: TokenUsageSummary
    
    // Gemini 统计
    public var geminiCalls5h: Int
    public var geminiCalls24h: Int
    public var geminiCalls7d: Int
    public var geminiActiveError5hResetsAt: Date?
    public var geminiActiveError24hResetsAt: Date?
    public var geminiActiveErrorResetsAt: Date?
    public var geminiActiveErrorMessage: String?
    public var geminiInferredLimit5h: Int?
    public var geminiInferredLimit24h: Int?
    public var geminiErrorCount7d: Int
    public var geminiTokenSummary: GeminiTokenUsageSummary
    public var geminiModelUsages: [GeminiModelUsage]
    public var geminiOfficialQuotas: [GeminiOfficialQuotaBucket]
    public var geminiQuotaFetchError: String?
    public var geminiToolUsageBreakdown: GeminiToolUsageBreakdown
    public var antigravityStats: GoogleToolUsageStats
    
    public var lastUpdated: Date
    public var dataSource: String
    
    public init(
        rateLimits: CodexRateLimits? = nil,
        tokenSummary: TokenUsageSummary,
        geminiCalls5h: Int,
        geminiCalls24h: Int = 0,
        geminiCalls7d: Int,
        geminiActiveError5hResetsAt: Date? = nil,
        geminiActiveError24hResetsAt: Date? = nil,
        geminiActiveErrorResetsAt: Date? = nil,
        geminiActiveErrorMessage: String? = nil,
        geminiInferredLimit5h: Int? = nil,
        geminiInferredLimit24h: Int? = nil,
        geminiErrorCount7d: Int = 0,
        geminiTokenSummary: GeminiTokenUsageSummary = GeminiTokenUsageSummary(),
        geminiModelUsages: [GeminiModelUsage] = [],
        geminiOfficialQuotas: [GeminiOfficialQuotaBucket] = [],
        geminiQuotaFetchError: String? = nil,
        geminiToolUsageBreakdown: GeminiToolUsageBreakdown = GeminiToolUsageBreakdown(),
        antigravityStats: GoogleToolUsageStats = GoogleToolUsageStats(),
        lastUpdated: Date,
        dataSource: String
    ) {
        self.rateLimits = rateLimits
        self.tokenSummary = tokenSummary
        self.geminiCalls5h = geminiCalls5h
        self.geminiCalls24h = geminiCalls24h
        self.geminiCalls7d = geminiCalls7d
        self.geminiActiveError5hResetsAt = geminiActiveError5hResetsAt
        self.geminiActiveError24hResetsAt = geminiActiveError24hResetsAt
        self.geminiActiveErrorResetsAt = geminiActiveErrorResetsAt
        self.geminiActiveErrorMessage = geminiActiveErrorMessage
        self.geminiInferredLimit5h = geminiInferredLimit5h
        self.geminiInferredLimit24h = geminiInferredLimit24h
        self.geminiErrorCount7d = geminiErrorCount7d
        self.geminiTokenSummary = geminiTokenSummary
        self.geminiModelUsages = geminiModelUsages
        self.geminiOfficialQuotas = geminiOfficialQuotas
        self.geminiQuotaFetchError = geminiQuotaFetchError
        self.geminiToolUsageBreakdown = geminiToolUsageBreakdown
        self.antigravityStats = antigravityStats
        self.lastUpdated = lastUpdated
        self.dataSource = dataSource
    }
}
