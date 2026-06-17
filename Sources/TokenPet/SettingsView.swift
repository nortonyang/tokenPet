import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var quotaManager = QuotaManager.shared
    @ObservedObject var coordinator = CCDataCoordinator.shared
    @ObservedObject var processMonitor = ProcessMonitor.shared
    
    @State private var activeTab = 0
    @State private var selectedAgentTab = 0
    
    public init() {}
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
    
    private func calculateCacheHitRate(input: Int, cached: Int) -> String {
        guard input > 0 else { return "0%" }
        let rate = Double(cached) / Double(input) * 100.0
        return String(format: "%.0f%%", rate)
    }
    
    // Custom hex color loader
    public struct Theme {
        public static let background = Color.clear
        public static let card = Color(NSColor.controlBackgroundColor).opacity(0.4)
        public static let separator = Color(NSColor.separatorColor).opacity(0.3)
        public static let textMain = Color(NSColor.labelColor)
        public static let textSecondary = Color(NSColor.secondaryLabelColor)
        public static let accent = Color(NSColor.controlAccentColor)
        public static let green = Color(hex: "#30D158")
        public static let yellow = Color(hex: "#FFD60A")
        public static let red = Color(hex: "#FF453A")
    }
    
    private var pageTitle: String {
        switch activeTab {
        case 0: return "常规设置"
        case 1: return "运行监控"
        default: return "额度与用量"
        }
    }
    
    private var pageSubtitle: String {
        switch activeTab {
        case 0: return "配置桌面宠物外观、始终置顶等参数"
        case 1: return "监控命令行工具在后台的运行状态"
        default: return "监控 Codex / 反重力 (Gemini) / Claude 的 Token、调用次数和限流状态"
        }
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            VStack(alignment: .leading, spacing: 4) {
                // Header of sidebar
                HStack(spacing: 6) {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.accent)
                    Text("TokenPet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textMain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
                
                SidebarItem(title: "常规设置", icon: "gearshape", tag: 0, activeTab: $activeTab)
                SidebarItem(title: "运行监控", icon: "waveform.path.ecg", tag: 1, activeTab: $activeTab)
                SidebarItem(title: "额度与用量", icon: "chart.bar.xaxis", tag: 2, activeTab: $activeTab)
                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .frame(width: 145)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
            
            Divider()
                .background(Theme.separator)
            
            // Right Content Area
            VStack(spacing: 0) {
                // Top Header with Title and Action buttons
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pageTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(Theme.textMain)
                        Text(pageSubtitle)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textSecondary)
                    }
                    
                    Spacer()
                    
                    if activeTab == 2 {
                        HStack(spacing: 12) {
                            Button(action: { quotaManager.forceRefresh() }) {
                                Label("刷新数据", systemImage: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(LinkButtonStyle(color: Theme.accent))
                            
                            Button(action: { openDataDirectory() }) {
                                Label("打开数据目录", systemImage: "folder")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(LinkButtonStyle(color: Theme.accent))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 12)
                
                Divider()
                    .background(Theme.separator)
                
                // Content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if activeTab == 0 {
                            generalTab
                        } else if activeTab == 1 {
                            monitoringTab
                        } else {
                            quotaTab
                        }
                    }
                    .padding(24)
                }
                .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 680, height: 500)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Actions
    
    private func openDataDirectory() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/antigravity-cli")
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Tab Views
    
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomCard(title: "桌面宠物外观") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("宠物大小:")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textMain)
                        Slider(value: $settings.petSize, in: 0.5...2.0, step: 0.1)
                            .accentColor(Theme.accent)
                        Text(String(format: "%.1fx", settings.petSize))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.accent)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Toggle("始终置顶 (悬浮在所有窗口上方)", isOn: $settings.alwaysOnTop)
                        .toggleStyle(CustomCheckboxToggleStyle())
                }
            }
            
            CustomCard(title: "系统集成") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("开机自动启动 TokenPet", isOn: $settings.launchAtLogin)
                        .toggleStyle(CustomCheckboxToggleStyle())
                    Toggle("允许系统通知 (当额度临近超限或任务完成时)", isOn: $settings.showNotifications)
                        .toggleStyle(CustomCheckboxToggleStyle())
                }
            }
        }
    }
    
    private var monitoringTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            CustomCard(title: "Gemini CLI 监控") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用 Gemini CLI 运行监控", isOn: $settings.geminiMonitorEnabled)
                        .toggleStyle(CustomCheckboxToggleStyle())
                    if settings.geminiMonitorEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("进程过滤关键字 (用英文逗号隔开):")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            TextField("例如: gemini,antigravity-cli", text: $settings.geminiKeywords)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .background(Theme.background)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.separator, lineWidth: 1))
                                .foregroundColor(Theme.textMain)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            
            CustomCard(title: "Codex 监控") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用 Codex 运行监控", isOn: $settings.codexMonitorEnabled)
                        .toggleStyle(CustomCheckboxToggleStyle())
                    if settings.codexMonitorEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("进程过滤关键字 (用英文逗号隔开):")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            TextField("例如: codex", text: $settings.codexKeywords)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .background(Theme.background)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.separator, lineWidth: 1))
                                .foregroundColor(Theme.textMain)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            
            CustomCard(title: "Claude Code 监控") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用 Claude Code 运行监控", isOn: $settings.claudeMonitorEnabled)
                        .toggleStyle(CustomCheckboxToggleStyle())
                    if settings.claudeMonitorEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("进程过滤关键字 (用英文逗号隔开):")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                            TextField("例如: claude,claude-code", text: $settings.claudeKeywords)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .background(Theme.background)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.separator, lineWidth: 1))
                                .foregroundColor(Theme.textMain)
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }
    
    private var quotaTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Custom Agent Tab Bar with Company Logos ──
            HStack(spacing: 8) {
                AgentTabButton(title: "反重力", brand: .antigravity, isSelected: selectedAgentTab == 0) {
                    selectedAgentTab = 0
                }
                AgentTabButton(title: "Codex", brand: .codex, isSelected: selectedAgentTab == 1) {
                    selectedAgentTab = 1
                }
                AgentTabButton(title: "Claude Code", brand: .claude, isSelected: selectedAgentTab == 2) {
                    selectedAgentTab = 2
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.card.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.separator, lineWidth: 1))
            )

            if selectedAgentTab == 0 {
                geminiQuotaTabContent
            } else if selectedAgentTab == 1 {
                codexQuotaTabContent
            } else {
                claudeQuotaTabContent
            }
        }
    }

    
    // MARK: - Agent Sub-Tab: 反重力 (Gemini)
    
    private var geminiQuotaTabContent: some View {
        CustomCard(title: "") {
            VStack(alignment: .leading, spacing: 0) {
                
                // ── 标题行 ──
                AgentQuotaHeader(
                    brand: .antigravity,
                    title: "反重力 额度",
                    statusText: geminiStatusText,
                    statusColor: geminiStatusColor,
                    primaryMeta: "数据源: \(quotaManager.geminiDataSource)",
                    secondaryMeta: "更新于 \(timeFormatter.string(from: quotaManager.lastUpdated))",
                    refreshAction: { coordinator.refresh() }
                )
                .padding(.bottom, 12)
                
                // ── /usage 模型组额度 ──
                let antigravityQuotaGroups = AntigravityQuotaDisplayBuilder.groups(from: coordinator.usageData.geminiOfficialQuotas)
                if !antigravityQuotaGroups.isEmpty {
                    AntigravityQuotaGroupsSettingsView(groups: antigravityQuotaGroups)
                        .padding(.bottom, 12)
                } else {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Theme.textSecondary)
                            .font(.system(size: 11))
                        Text("尚未获取到反重力 /usage 摘要。启动反重力 CLI 后会自动同步模型与额度。")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(12)
                    .background(Theme.background.opacity(0.4))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
                    .padding(.bottom, 12)
                }
                
                // ── 调用量统计（4格网格）──
                HStack(spacing: 8) {
                    AgentMetricCell(title: "5h 调用", value: "\(coordinator.usageData.antigravityStats.calls5h)", subtitle: "最近 5 小时")
                    AgentMetricCell(title: "24h 调用", value: "\(coordinator.usageData.antigravityStats.calls24h)", subtitle: "最近 24 小时")
                    AgentMetricCell(title: "7天 调用", value: "\(coordinator.usageData.antigravityStats.calls7d)", subtitle: "最近 7 天")
                    AgentMetricCell(
                        title: "7天 429",
                        value: "\(coordinator.usageData.antigravityStats.errorCount7d)",
                        subtitle: "限流累计",
                        valueColor: coordinator.usageData.antigravityStats.errorCount7d > 0 ? Theme.red : Theme.textSecondary
                    )
                }
                .padding(.bottom, 12)
                
                // ── Token 消耗（若有数据）──
                if geminiTokenDataAvailable {
                    let tok = coordinator.usageData.antigravityStats.tokenSummary
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Token 消耗")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.textSecondary)
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("最近 5 小时")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.textSecondary)
                                TokenDetailRow(label: "输入", value: formatTokens(tok.inputTokens5h))
                                TokenDetailRow(label: "输出", value: formatTokens(tok.outputTokens5h))
                                TokenDetailRow(label: "缓存", value: formatTokens(tok.cachedTokens5h))
                                if tok.thoughtsTokens5h > 0 {
                                    TokenDetailRow(label: "思考", value: formatTokens(tok.thoughtsTokens5h))
                                }
                                Divider().background(Theme.separator)
                                TokenDetailRow(label: "合计", value: formatTokens(tok.totalTokens5h), isTotal: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.background.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator, lineWidth: 1))
                            
                            VStack(alignment: .leading, spacing: 5) {
                                Text("最近 7 天")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.textSecondary)
                                TokenDetailRow(label: "输入", value: formatTokens(tok.inputTokens7d))
                                TokenDetailRow(label: "输出", value: formatTokens(tok.outputTokens7d))
                                TokenDetailRow(label: "缓存", value: formatTokens(tok.cachedTokens7d))
                                if tok.thoughtsTokens7d > 0 {
                                    TokenDetailRow(label: "思考", value: formatTokens(tok.thoughtsTokens7d))
                                }
                                Divider().background(Theme.separator)
                                TokenDetailRow(label: "合计", value: formatTokens(tok.totalTokens7d), isTotal: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Theme.background.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator, lineWidth: 1))
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 2)
        }
    }
    
    // MARK: - Agent Sub-Tab: Codex
    
    private var codexQuotaTabContent: some View {
        CustomCard(title: "") {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                AgentQuotaHeader(
                    brand: .codex,
                    title: "Codex 额度",
                    statusText: codexStatusText,
                    statusColor: codexStatusColor,
                    primaryMeta: "数据源: \(quotaManager.dataSource)",
                    secondaryMeta: "更新于 \(timeFormatter.string(from: quotaManager.lastUpdated))",
                    refreshAction: { coordinator.refresh() }
                )
                
                // Progress bars
                VStack(spacing: 12) {
                    QuotaRowView(
                        label: "5小时",
                        used: quotaManager.quota5hUsed,
                        remaining: quotaManager.quota5hRemaining,
                        resetText: quotaManager.timeRemaining5h(),
                        isWarning: quotaManager.is5hWarning
                    )
                    
                    QuotaRowView(
                        label: "7天",
                        used: quotaManager.quota7dUsed,
                        remaining: quotaManager.quota7dRemaining,
                        resetText: quotaManager.timeRemaining7d(),
                        isWarning: quotaManager.is7dWarning
                    )
                }
                .padding(.vertical, 4)
                
                Divider().background(Theme.separator)
                
                // Token Stats Grid
                let summary = coordinator.usageData.tokenSummary
                HStack(spacing: 12) {
                    AgentMetricCell(
                        title: "5小时 Token",
                        value: formatTokens(summary.inputTokens5h + summary.outputTokens5h),
                        subtitle: "输: \(formatTokens(summary.inputTokens5h)) | 出: \(formatTokens(summary.outputTokens5h))"
                    )
                    AgentMetricCell(
                        title: "7天 Token",
                        value: formatTokens(summary.inputTokens7d + summary.outputTokens7d),
                        subtitle: "输: \(formatTokens(summary.inputTokens7d)) | 出: \(formatTokens(summary.outputTokens7d))"
                    )
                    AgentMetricCell(
                        title: "缓存命中 (5h / 7d)",
                        value: "\(calculateCacheHitRate(input: summary.inputTokens5h, cached: summary.cachedInputTokens5h)) / \(calculateCacheHitRate(input: summary.inputTokens7d, cached: summary.cachedInputTokens7d))",
                        subtitle: "会话数: \(summary.sessionCount5h) / \(summary.sessionCount7d)"
                    )
                }
                
                Divider().background(Theme.separator)
                
                // Threshold steppers
                HStack(spacing: 24) {
                    Text("告警阈值配置:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textMain)
                    
                    Stepper(value: $settings.quota5hThreshold, in: 0...100) {
                        Text("5h 剩余 ≤ \(settings.quota5hThreshold)%")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textMain)
                    }
                    
                    Stepper(value: $settings.quota7dThreshold, in: 0...100) {
                        Text("7d 剩余 ≤ \(settings.quota7dThreshold)%")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textMain)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Agent Sub-Tab: Claude Code
    
    private var claudeQuotaTabContent: some View {
        CustomCard(title: "") {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                AgentQuotaHeader(
                    brand: .claude,
                    title: "Claude Code 状态",
                    statusText: processMonitor.isClaudeRunning ? "● 运行中" : "● 已停止",
                    statusColor: processMonitor.isClaudeRunning ? Theme.green : Theme.textSecondary,
                    primaryMeta: settings.claudeMonitorEnabled ? "监控已启用" : "监控已关闭",
                    secondaryMeta: "进程监控"
                )
                
                HStack(spacing: 12) {
                    AgentMetricCell(
                        title: "监控",
                        value: settings.claudeMonitorEnabled ? "开启" : "关闭",
                        subtitle: "运行监控",
                        valueColor: settings.claudeMonitorEnabled ? Theme.green : Theme.textSecondary
                    )
                    AgentMetricCell(
                        title: "进程",
                        value: processMonitor.isClaudeRunning ? "运行中" : "未运行",
                        subtitle: "实时检测",
                        valueColor: processMonitor.isClaudeRunning ? Theme.green : Theme.textSecondary
                    )
                    AgentMetricCell(
                        title: "Token",
                        value: "未开放",
                        subtitle: "无本地明细",
                        valueColor: Theme.textSecondary
                    )
                }
                
                Divider().background(Theme.separator)
                
                // Process status details
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: processMonitor.isClaudeRunning ? "circle.fill" : "circle.dotted")
                            .font(.system(size: 28))
                            .foregroundColor(processMonitor.isClaudeRunning ? Theme.green : Theme.textSecondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(processMonitor.isClaudeRunning ? "Claude Code 正在运行" : "未检测到 Claude Code 进程")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(processMonitor.isClaudeRunning ? Theme.textMain : Theme.textSecondary)
                            Text(processMonitor.isClaudeRunning
                                 ? "TokenPet 正监控此进程，宠物将显示对应工作动画"
                                 : "启动 Claude Code 后此处将实时更新进程状态")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((processMonitor.isClaudeRunning ? Theme.green : Theme.textSecondary).opacity(0.07))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke((processMonitor.isClaudeRunning ? Theme.green : Theme.separator), lineWidth: 1))
                }
                
                Divider().background(Theme.separator)
                
                // Info: no local log files
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                        Text("关于 Claude Code 数据采集")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.textMain)
                    }
                    
                    VStack(alignment: .leading, spacing: 5) {
                        InfoBullet(text: "Claude Code 不提供本地 Token 级日志文件，因此无法自动统计 Token 消耗")
                        InfoBullet(text: "TokenPet 通过进程监控感知 Claude Code 的启动与停止，并驱动宠物动画")
                        InfoBullet(text: "如需查看 Token 用量，请访问 Anthropic 控制台官网")
                    }
                }
                .padding(12)
                .background(Theme.accent.opacity(0.05))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
                
                // Monitor config reminder
                if !settings.claudeMonitorEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.yellow)
                        Text("Claude Code 监控已关闭 — 请前往「运行监控」标签启用")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Theme.yellow.opacity(0.08))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.yellow.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }
    
    private func formatTimeRemaining(from targetDate: Date) -> String {
        let now = Date()
        let remaining = targetDate.timeIntervalSince(now)
        guard remaining > 0 else { return "已重置" }
        
        let h = Int(remaining) / 3600
        let m = (Int(remaining) % 3600) / 60
        if h > 0 {
            return "\(h)小时\(m)分钟后"
        } else {
            return "\(m)分钟后"
        }
    }
}

// MARK: - Info Bullet Helper

struct AgentQuotaHeader: View {
    let brand: AgentBrand
    let title: String
    let statusText: String
    let statusColor: Color
    let primaryMeta: String
    var secondaryMeta: String? = nil
    var refreshAction: (() -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AgentLogoView(brand: brand, size: 28)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(SettingsView.Theme.textMain)
                    StatusCapsule(text: statusText, color: statusColor)
                }
                
                Text(primaryMeta)
                    .font(.system(size: 9))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if let secondaryMeta {
                HStack(spacing: 5) {
                    if let refreshAction {
                        Button(action: refreshAction) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(SettingsView.Theme.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Text(secondaryMeta)
                        .font(.system(size: 9))
                        .foregroundColor(SettingsView.Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct AgentMetricCell: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var valueColor: Color = SettingsView.Theme.textMain
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(SettingsView.Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(SettingsView.Theme.background.opacity(0.3))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(SettingsView.Theme.separator, lineWidth: 1)
        )
    }
}

struct InfoBullet: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text("•")
                .font(.system(size: 11))
                .foregroundColor(SettingsView.Theme.textSecondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(SettingsView.Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - SettingsView Quota Status Helpers

extension SettingsView {
    var codexStatusText: String {
        if quotaManager.quota7dRemaining <= 10 {
            return "即将耗尽"
        } else if quotaManager.is5hWarning || quotaManager.is7dWarning {
            return "告警"
        } else {
            return "正常"
        }
    }
    
    var codexStatusColor: Color {
        if quotaManager.quota7dRemaining <= 10 {
            return Theme.red
        } else if quotaManager.is5hWarning || quotaManager.is7dWarning {
            return Theme.yellow
        } else {
            return Theme.green
        }
    }
    
    var geminiStatusText: String {
        if quotaManager.geminiMixedOfficialAndLocal {
            return "混合"
        } else if quotaManager.geminiIsExhausted || quotaManager.gemini24hIsExhausted {
            return "已限流"
        } else if quotaManager.gemini5hUsesOfficialSnapshot || quotaManager.geminiLongUsesOfficialSnapshot {
            return "官方"
        } else if coordinator.usageData.antigravityStats.calls7d == 0 {
            return "未采集"
        } else {
            return "本地"
        }
    }
    
    var geminiStatusColor: Color {
        if quotaManager.geminiMixedOfficialAndLocal {
            return Theme.yellow
        } else if quotaManager.geminiIsExhausted || quotaManager.gemini24hIsExhausted {
            return Theme.red
        } else if quotaManager.gemini5hUsesOfficialSnapshot || quotaManager.geminiLongUsesOfficialSnapshot {
            return Theme.green
        } else if coordinator.usageData.antigravityStats.calls7d == 0 {
            return Theme.textSecondary
        } else {
            return Theme.yellow
        }
    }
    
    var geminiTokenDataAvailable: Bool {
        coordinator.usageData.antigravityStats.tokenSummary.totalTokens7d > 0
    }
    
    var geminiDataSourceText: String {
        let hasSummary = !AntigravityQuotaDisplayBuilder.groups(from: coordinator.usageData.geminiOfficialQuotas).isEmpty
        let tokenSuffix: String
        if geminiTokenDataAvailable {
            tokenSuffix = "/usage Token 已采集"
        } else if hasSummary {
            tokenSuffix = "/usage 摘要已采集"
        } else {
            tokenSuffix = "/usage 摘要未采集"
        }
        return "数据源: \(quotaManager.geminiDataSource) | \(tokenSuffix)"
    }
    
    var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }
}


struct SidebarItem: View {
    let title: String
    let icon: String
    let tag: Int
    @Binding var activeTab: Int
    
    var body: some View {
        Button(action: { activeTab = tag }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: 12, weight: activeTab == tag ? .bold : .regular))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .foregroundColor(activeTab == tag ? SettingsView.Theme.textMain : SettingsView.Theme.textSecondary)
            .background(activeTab == tag ? SettingsView.Theme.card : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Link Button Style

struct LinkButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .background(Color.clear)
    }
}

// MARK: - Quota Row View (Row with ProgressBar)

struct QuotaRowView: View {
    let label: String
    let used: Int
    let remaining: Int
    let resetText: String
    let isWarning: Bool
    var labelWidth: CGFloat = 42
    var infoWidth: CGFloat = 105
    var resetWidth: CGFloat = 80
    
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SettingsView.Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: labelWidth, alignment: .leading)
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SettingsView.Theme.green.opacity(0.25))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [SettingsView.Theme.red.opacity(0.7), SettingsView.Theme.red],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, Double(used) / 100.0))))
                }
            }
            .frame(height: 6)
            
            // Info text
            Text("已用 \(used)% | 剩 \(remaining)%")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundColor(isWarning ? SettingsView.Theme.red : SettingsView.Theme.green)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: infoWidth, alignment: .trailing)
            
            Text(resetText)
                .font(.system(size: 10).monospacedDigit())
                .foregroundColor(SettingsView.Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: resetWidth, alignment: .trailing)
        }
    }
}

// MARK: - Quota Indicator Cell

struct QuotaIndicatorCell: View {
    let title: String
    let value: String
    let subvalue: String
    
    var body: some View {
        AgentMetricCell(title: title, value: value, subtitle: subvalue)
    }
}

// MARK: - Stat Mini Cell (compact 4-grid for call counts)
struct StatMiniCell: View {
    let label: String
    let value: String
    var valueColor: Color = SettingsView.Theme.textMain
    
    var body: some View {
        AgentMetricCell(title: label, value: value, valueColor: valueColor)
    }
}

// MARK: - Antigravity /usage Group View

struct AntigravityQuotaGroupsSettingsView: View {
    let groups: [AntigravityQuotaDisplayGroup]
    
    private var accountLabel: String? {
        groups.compactMap(\.accountLabel).first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                Text("模型与额度")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(SettingsView.Theme.textMain)
                Spacer()
            }
            
            if let accountLabel {
                HStack(spacing: 6) {
                    Text("账号：")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(SettingsView.Theme.textMain)
                    Text(accountLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SettingsView.Theme.accent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            ForEach(groups) { group in
                AntigravityQuotaSettingsGroupCard(group: group)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("同一组内的模型共享每周额度和 5 小时额度。")
                Text("额度按 Token 成本比例消耗，成本更低的模型可用时间更长。")
            }
            .font(.system(size: 11))
            .foregroundColor(SettingsView.Theme.textSecondary)
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(SettingsView.Theme.separator)
                    .frame(width: 2)
            }
        }
        .padding(14)
        .background(SettingsView.Theme.background.opacity(0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsView.Theme.separator, lineWidth: 1))
    }
}

struct AntigravityQuotaSettingsGroupCard: View {
    let group: AntigravityQuotaDisplayGroup
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title.uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(SettingsView.Theme.textMain)
            
            if !group.description.isEmpty {
                Text(group.description)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8FBFC1"))
                    .lineLimit(2)
            }
            
            ForEach(group.buckets) { bucket in
                AntigravityQuotaSettingsBucketRow(bucket: bucket)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AntigravityQuotaSettingsBucketRow: View {
    let bucket: AntigravityQuotaDisplayBucket
    
    var body: some View {
        QuotaRowView(
            label: bucket.title,
            used: max(0, min(100, 100 - bucket.remainingWholePercent)),
            remaining: bucket.remainingWholePercent,
            resetText: "\(formatRemaining(until: bucket.resetTime))后",
            isWarning: bucket.remainingWholePercent <= 25,
            labelWidth: 68,
            infoWidth: 105,
            resetWidth: 92
        )
        .padding(.leading, 26)
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

// MARK: - Custom Card Helper

struct CustomCard<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                    .padding(.leading, 2)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsView.Theme.card)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SettingsView.Theme.separator, lineWidth: 1)
            )
        }
    }
}

// MARK: - Custom Checkbox Toggle Style

struct CustomCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: { configuration.isOn.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(configuration.isOn ? SettingsView.Theme.accent : SettingsView.Theme.textSecondary)
                configuration.label
                    .font(.system(size: 12))
                    .foregroundColor(SettingsView.Theme.textMain)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Token Detail Helpers

struct TokenTelemetryEmptyState: View {
    let message: String
    
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 20))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(SettingsView.Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}

struct TokenDetailRow: View {
    let label: String
    let value: String
    var isTotal: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(isTotal ? SettingsView.Theme.textMain : SettingsView.Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: isTotal ? .bold : .medium).monospacedDigit())
                .foregroundColor(isTotal ? SettingsView.Theme.accent : SettingsView.Theme.textMain)
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
