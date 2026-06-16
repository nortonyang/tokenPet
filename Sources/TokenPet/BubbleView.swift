import SwiftUI

public struct BubbleView: View {
    @ObservedObject var stateManager = PetStateManager.shared
    @ObservedObject var quotaManager = QuotaManager.shared
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var coordinator = CCDataCoordinator.shared
    @ObservedObject var processMonitor = ProcessMonitor.shared
    
    var onOpenSettings: () -> Void
    var onHidePet: () -> Void
    var onClose: () -> Void
    
    public init(onOpenSettings: @escaping () -> Void, onHidePet: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onHidePet = onHidePet
        self.onClose = onClose
    }
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            
            // ── Header ──
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TokenPet")
                        .font(.system(size: 13, weight: .bold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(stateManager.detailStatus)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Tool logos — 用 AgentLogoView 替代字母圆点
                HStack(spacing: 5) {
                    AgentToolIcon(brand: .gemini, isRunning: processMonitor.isGeminiRunning, isEnabled: settings.geminiMonitorEnabled)
                    AgentToolIcon(brand: .codex,  isRunning: processMonitor.isCodexRunning,  isEnabled: settings.codexMonitorEnabled)
                    AgentToolIcon(brand: .claude, isRunning: processMonitor.isClaudeRunning, isEnabled: settings.claudeMonitorEnabled)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        .font(.system(size: 13))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 6)
            }
            .padding(.bottom, 8)
            
            if settings.codexMonitorEnabled || settings.geminiMonitorEnabled {
                Divider()
            }
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // ── Codex 额度 ──
                    if settings.codexMonitorEnabled {
                        VStack(spacing: 8) {
                    let isStale = quotaManager.dataSource.contains("过期") || quotaManager.dataSource.contains("未检测")
                            BubbleSectionHeader(
                                brand: .codex,
                                title: "Codex",
                                statusText: isStale ? "⚠ 无新数据" : "● 实时",
                                statusColor: isStale ? .orange : .green
                            )
                            
                            // 5h bar
                            CompactQuotaRow(
                                label: "剩余 5h",
                                usedPercent: quotaManager.quota5hUsed,
                                remainingPercent: quotaManager.quota5hRemaining,
                                resetLabel: quotaManager.timeRemaining5h(),
                                color: quotaManager.is5hWarning ? .red : .green
                            )
                            
                            // 7d bar
                            CompactQuotaRow(
                                label: "剩余 7d",
                                usedPercent: quotaManager.quota7dUsed,
                                remainingPercent: quotaManager.quota7dRemaining,
                                resetLabel: quotaManager.timeRemaining7d(),
                                color: quotaManager.is7dWarning ? .red : .green
                            )
                            
                            CodexTokenGrid(tokens: coordinator.usageData.tokenSummary)
                                .padding(.top, 2)
                        }
                        .padding(.horizontal, 2)
                    }
                    
                    if settings.codexMonitorEnabled && settings.geminiMonitorEnabled {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    
                    // ── Gemini 额度 ──
                    if settings.geminiMonitorEnabled {
                        VStack(spacing: 8) {
                            let antigravityStats = coordinator.usageData.antigravityStats
                            let hasAntigravityTokens = antigravityStats.tokenSummary.totalTokens7d > 0
                            let hasAntigravityOfficialQuota = coordinator.usageData.geminiOfficialQuotas.contains { $0.sourceTool == "antigravity-cli" }
                            let antigravityQuotaGroups = AntigravityQuotaDisplayBuilder.groups(from: coordinator.usageData.geminiOfficialQuotas)
                            
                            let geminiStatusText: String = {
                                if quotaManager.geminiMixedOfficialAndLocal {
                                    return "⚠ 混合"
                                } else if quotaManager.geminiIsExhausted || quotaManager.gemini24hIsExhausted {
                                    return "⚠ 已限流"
                                } else if quotaManager.gemini5hUsesOfficialSnapshot || quotaManager.geminiLongUsesOfficialSnapshot {
                                    return "● 官方"
                                } else {
                                    return antigravityStats.calls7d > 0 ? "● 本地" : "⚠ 未采集"
                                }
                            }()
                            
                            let geminiStatusColor: Color = {
                                if quotaManager.geminiMixedOfficialAndLocal {
                                    return .orange
                                } else if quotaManager.geminiIsExhausted || quotaManager.gemini24hIsExhausted {
                                    return .red
                                } else if quotaManager.gemini5hUsesOfficialSnapshot || quotaManager.geminiLongUsesOfficialSnapshot {
                                    return .green
                                } else {
                                    return antigravityStats.calls7d > 0 ? .orange : .gray
                                }
                            }()
                            
                            BubbleSectionHeader(
                                brand: .gemini,
                                title: "反重力",
                                statusText: geminiStatusText,
                                statusColor: geminiStatusColor,
                                refreshCountdown: coordinator.secondsUntilRefresh
                            )
                            
                            if antigravityStats.calls7d == 0 && antigravityStats.errorCount7d == 0 && !hasAntigravityOfficialQuota {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("尚未采集到反重力 /usage 或本地调用")
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange)
                                    Text("启动反重力 CLI 后会自动读取本地 /usage summary。")
                                        .font(.system(size: 8))
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                            } else {
                                VStack(spacing: 6) {
                                    if !antigravityQuotaGroups.isEmpty {
                                        AntigravityQuotaGroupsCompactView(groups: antigravityQuotaGroups)
                                            .padding(.top, 2)
                                    } else {
                                        if !hasAntigravityTokens {
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text("尚未采集到反重力 /usage summary")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.orange)
                                                Text("当前仅显示反重力本地调用和 429。")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.orange)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            .padding(6)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.orange.opacity(0.1))
                                            .cornerRadius(4)
                                        }
                                        
                                        let limit5h = antigravityStats.inferredLimit5h ?? 300
                                        let limit24h = antigravityStats.inferredLimit24h ?? 1000
                                        let resetLabel5h = quotaManager.geminiIsExhausted || quotaManager.gemini5hUsesOfficialSnapshot ? quotaManager.geminiResetsRemaining : "\(antigravityStats.calls5h)/\(limit5h)次"
                                        let resetLabel24h = quotaManager.gemini24hIsExhausted || quotaManager.geminiLongUsesOfficialSnapshot ? quotaManager.gemini24hResetsRemaining : "\(antigravityStats.calls24h)/\(limit24h)次"
                                        
                                        CompactQuotaRow(
                                            label: quotaManager.gemini5hWindowLabel,
                                            usedPercent: quotaManager.gemini5hUsed,
                                            remainingPercent: quotaManager.gemini5hRemaining,
                                            resetLabel: resetLabel5h,
                                            color: quotaManager.geminiIsExhausted ? .red : .blue
                                        )
                                        
                                        CompactQuotaRow(
                                            label: quotaManager.geminiLongWindowLabel,
                                            usedPercent: quotaManager.gemini24hUsed,
                                            remainingPercent: quotaManager.gemini24hRemaining,
                                            resetLabel: resetLabel24h,
                                            color: quotaManager.gemini24hIsExhausted ? .red : .blue
                                        )
                                    }
                                    
                                    if !antigravityQuotaGroups.isEmpty {
                                        HStack {
                                            Text("本地累计调用")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("\(antigravityStats.calls7d) 次")
                                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.top, 2)
                                    }
                                    
                                    if hasAntigravityTokens {
                                        GeminiTokenGrid(tokens: antigravityStats.tokenSummary)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                            
                            Text(geminiDataSourceLabel(hasTelemetryTokens: hasAntigravityTokens, hasSummary: !antigravityQuotaGroups.isEmpty))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 400)
            
            if settings.codexMonitorEnabled || settings.geminiMonitorEnabled {
                Divider()
                    .padding(.bottom, 6)
            }
            
            HStack {
                if let err = quotaManager.parseError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .help(err)
                }
                
                Spacer()
                Button(action: onHidePet) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10))
                        Text("关闭宠物")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onOpenSettings) {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text("设置")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color(NSColor.controlAccentColor))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 270)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var statusColor: Color {
        switch stateManager.currentState {
        case .idle: return .green
        case .working: return .blue
        case .finished: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
    
    private func geminiDataSourceLabel(hasTelemetryTokens: Bool, hasSummary: Bool) -> String {
        let tokenSuffix: String
        if hasTelemetryTokens {
            tokenSuffix = "/usage Token 已采集"
        } else if hasSummary {
            tokenSuffix = "/usage 摘要已采集"
        } else {
            tokenSuffix = "/usage 摘要未采集"
        }
        return "数据源: \(quotaManager.geminiDataSource) | \(tokenSuffix)"
    }
}

// MARK: - Bubble Section Header (with Agent Logo + Status Capsule)

struct BubbleSectionHeader: View {
    let brand: AgentBrand
    let title: String
    let statusText: String
    let statusColor: Color
    var refreshCountdown: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            AgentLogoView(brand: brand, size: 18)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .tracking(0.3)
            Spacer()
            if let refreshCountdown {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(Double(refreshCountdown) * -12.0))
                    Text("\(refreshCountdown)s")
                        .font(.system(size: 8).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
            StatusCapsule(text: statusText, color: statusColor)
        }
    }
}


struct AntigravityQuotaGroupsCompactView: View {
    let groups: [AntigravityQuotaDisplayGroup]
    
    private var accountLabel: String? {
        groups.compactMap(\.accountLabel).first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let accountLabel {
                HStack(spacing: 4) {
                    Text("账号：")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(accountLabel)
                        .font(.system(size: 9, weight: .semibold).monospaced())
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            ForEach(groups) { group in
                AntigravityQuotaCompactGroupView(group: group)
            }
        }
    }
}

struct AntigravityQuotaCompactGroupView: View {
    let group: AntigravityQuotaDisplayGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title.uppercased())
                .font(.system(size: 9, weight: .semibold).monospaced())
                .foregroundColor(.secondary)
            if !group.description.isEmpty {
                Text(group.description)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            ForEach(group.buckets) { bucket in
                AntigravityQuotaCompactBucketRow(bucket: bucket)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AntigravityQuotaCompactBucketRow: View {
    let bucket: AntigravityQuotaDisplayBucket
    
    private var color: Color {
        if bucket.remainingFraction <= 0.1 { return .red }
        if bucket.remainingFraction <= 0.25 { return .yellow }
        return .green
    }
    
    var body: some View {
        CompactQuotaRow(
            label: bucket.title,
            usedPercent: max(0, min(100, 100 - bucket.remainingWholePercent)),
            remainingPercent: bucket.remainingWholePercent,
            resetLabel: "\(formatRemaining(until: bucket.resetTime))后刷新",
            color: color,
            labelWidth: 52,
            remainingWidth: 42,
            resetWidth: 66
        )
    }
    
    private func formatRemaining(until date: Date?) -> String {
        guard let date else { return "未知" }
        let remaining = max(0, Int(date.timeIntervalSince(Date())))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        }
        return "\(max(1, minutes))分"
    }
}


struct GeminiTokenUnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("反重力 /usage Token 未采集")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
            Text("当前本地日志没有 token 字段；需要导入或采集 /usage 后才能对齐官方显示。")
                .font(.system(size: 8))
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(4)
    }
}

struct GeminiModelUsageList: View {
    let modelUsages: [GeminiModelUsage]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("模型统计")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("5h / 24h / 7d")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            
            ForEach(Array(modelUsages.prefix(5))) { usage in
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(usage.modelName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        HStack(spacing: 4) {
                            Text("\(usage.calls5h) / \(usage.calls24h) / \(usage.calls7d) 次")
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundColor(.secondary)
                            
                            if !usage.officialQuotas.isEmpty {
                                Text("•")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                Text(officialSummary(for: usage))
                                    .font(.system(size: 8).monospacedDigit())
                                    .foregroundColor(.blue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        
                        if usage.totalTokens5h > 0 {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 8) {
                                    Text("In: \(formatTokens(usage.inputTokens5h))")
                                    Text("Out: \(formatTokens(usage.outputTokens5h))")
                                    if usage.cachedTokens5h > 0 {
                                        let hitRate = Double(usage.inputTokens5h) > 0 ? (Double(usage.cachedTokens5h) / Double(usage.inputTokens5h) * 100.0) : 0.0
                                        Text("Hit: \(String(format: "%.1f", hitRate))%")
                                    }
                                }
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundColor(.secondary)
                                
                                HStack(spacing: 8) {
                                    if usage.thoughtsTokens5h > 0 {
                                        Text("Thought: \(formatTokens(usage.thoughtsTokens5h))")
                                    }
                                    if usage.toolTokens5h > 0 {
                                        Text("Tool: \(formatTokens(usage.toolTokens5h))")
                                    }
                                    if usage.avgDurationMs5h > 0 {
                                        Text("Avg: \(String(format: "%.2f", usage.avgDurationMs5h / 1000.0))s")
                                    }
                                }
                                .font(.system(size: 8).monospacedDigit())
                                .foregroundColor(.secondary)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(statusText(for: usage))
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundColor(statusColor(for: usage))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: 76, alignment: .trailing)
                }
            }
        }
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
        .cornerRadius(4)
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
    
    private func statusText(for usage: GeminiModelUsage) -> String {
        if !usage.officialQuotas.isEmpty {
            return "\(usage.officialQuotas.count)窗口"
        }
        if let resetAt = usage.activeResetAt, resetAt > Date() {
            return "限 \(formatRemaining(until: resetAt))"
        }
        if usage.errorCount7d > 0 {
            return "\(usage.errorCount7d)次429"
        }
        return "正常"
    }
    
    private func statusColor(for usage: GeminiModelUsage) -> Color {
        if !usage.officialQuotas.isEmpty {
            return .blue
        }
        if let resetAt = usage.activeResetAt, resetAt > Date() {
            return .red
        }
        if usage.errorCount7d > 0 {
            return .orange
        }
        return .green
    }
    
    private func officialSummary(for usage: GeminiModelUsage) -> String {
        usage.officialQuotas.prefix(2).map { quota in
            let remaining = Int(quota.remainingFraction * 100)
            let reset = quota.resetTime.map { " \(formatRemaining(until: $0))" } ?? ""
            return "\(quota.windowType) \(remaining)%剩\(reset)"
        }.joined(separator: " · ")
    }
    
    private func formatRemaining(until date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(Date())))
        let days = remaining / 86400
        let hours = (remaining % 86400) / 3600
        let minutes = (remaining % 3600) / 60
        
        if days > 0 {
            return "\(days)天\(hours)时"
        }
        if hours > 0 {
            return "\(hours)时\(minutes)分"
        }
        return "\(max(1, minutes))分"
    }
}

// MARK: - Compact Quota Row

struct CompactQuotaRow: View {
    let label: String
    let usedPercent: Int
    let remainingPercent: Int
    let resetLabel: String
    let color: Color
    var labelWidth: CGFloat = 45
    var remainingWidth: CGFloat = 42
    var resetWidth: CGFloat = 60
    
    private var usedFraction: Double { max(0, min(1, Double(usedPercent) / 100.0)) }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: labelWidth, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Color.red.opacity(0.7), Color.red],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * CGFloat(usedFraction))
                        .animation(.easeInOut(duration: 0.4), value: usedFraction)
                }
            }
            .frame(height: 6)
            
            Text("\(remainingPercent)% 剩")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: remainingWidth, alignment: .trailing)
            
            Text(resetLabel)
                .font(.system(size: 9).monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: resetWidth, alignment: .trailing)
        }
    }
}

// MARK: - Stat Cell

struct StatCell: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Status Capsule — 统一状态转载胶囊

struct StatusCapsule: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(Capsule())
    }
}

// MARK: - Agent Tool Icon — 头部 Logo 圆点（含运行中脉冲动画）

struct AgentToolIcon: View {
    let brand: AgentBrand
    let isRunning: Bool
    let isEnabled: Bool

    @State private var pulse = false

    private var iconSize: CGFloat { 20 }

    var body: some View {
        ZStack {
            if isEnabled && isRunning {
                Circle()
                    .strokeBorder(brandColor.opacity(pulse ? 0.0 : 0.45), lineWidth: 1.5)
                    .frame(width: iconSize + 6, height: iconSize + 6)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }
            AgentLogoView(brand: brand, size: iconSize)
                .opacity(isEnabled ? 1.0 : 0.28)
        }
        .help(toolName + (isRunning ? ": 运行中" : ": 未运行"))
    }

    private var brandColor: Color {
        switch brand {
        case .gemini: return Color(hex: "#4285F4")
        case .codex:  return Color(NSColor.labelColor)
        case .claude: return Color(hex: "#DA7756")
        }
    }

    private var toolName: String {
        switch brand {
        case .gemini: return "反重力"
        case .codex:  return "Codex"
        case .claude: return "Claude"
        }
    }
}

// MARK: - Tool Dot (历史兼容)
struct ToolDot: View {
    let label: String
    let isRunning: Bool
    let isEnabled: Bool
    let color: Color
    var body: some View { EmptyView() }
}

// MARK: - ToolIndicator (kept for backward compat)
struct ToolIndicator: View {
    let label: String
    let isRunning: Bool
    let isEnabled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isEnabled ? (isRunning ? Color.green : Color.gray.opacity(0.4)) : Color.gray.opacity(0.2))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9, weight: isRunning ? .bold : .regular))
                .foregroundColor(isEnabled ? (isRunning ? .green : .secondary) : .secondary.opacity(0.5))
        }
        .opacity(isEnabled ? 1.0 : 0.4)
    }
}

// MARK: - QuotaBarView (kept for backward compat if needed)
struct QuotaBarView: View {
    let title: String
    let used: Int
    let remaining: Int
    let limit: Int
    let percent: Double
    let resetText: String
    let accentColor: Color
    var isPercentage: Bool = false
    
    private var usedFraction: Double { max(0.0, min(1.0, 1.0 - percent)) }
    
    var body: some View {
        CompactQuotaRow(
            label: title,
            usedPercent: used,
            remainingPercent: remaining,
            resetLabel: resetText,
            color: accentColor
        )
    }
}

// MARK: - Gemini Token Grid Helpers

struct GeminiTokenGrid: View {
    let tokens: GeminiTokenUsageSummary
    
    var body: some View {
        VStack(spacing: 4) {
            Text("5小时 Token 消耗")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                
            HStack(spacing: 6) {
                TokenMiniCell(label: "输入", value: formatTokens(tokens.inputTokens5h))
                TokenMiniCell(label: "输出", value: formatTokens(tokens.outputTokens5h))
                TokenMiniCell(label: "缓存", value: formatTokens(tokens.cachedTokens5h))
            }
            HStack(spacing: 6) {
                TokenMiniCell(label: "思考", value: formatTokens(tokens.thoughtsTokens5h))
                TokenMiniCell(label: "工具", value: formatTokens(tokens.toolTokens5h))
                TokenMiniCell(label: "总计", value: formatTokens(tokens.totalTokens5h))
            }
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

struct TokenMiniCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            Text(value)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5))
        )
    }
}

struct CodexTokenGrid: View {
    let tokens: TokenUsageSummary
    
    var body: some View {
        VStack(spacing: 4) {
            Text("5小时 Token 消耗")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                
            HStack(spacing: 6) {
                TokenMiniCell(label: "输入", value: formatTokens(tokens.inputTokens5h))
                TokenMiniCell(label: "输出", value: formatTokens(tokens.outputTokens5h))
                TokenMiniCell(label: "缓存", value: formatTokens(tokens.cachedInputTokens5h))
            }
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}
