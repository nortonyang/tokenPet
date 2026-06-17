# TokenPet

TokenPet 是一个原生 macOS 桌面宠物应用，用来陪伴和监控本机 AI CLI 工具的运行状态与额度余量。

当前重点支持：

- Codex：运行状态、5 小时额度、7 天额度、本地会话用量统计。
- 反重力 Antigravity CLI：运行状态、官方 `/usage` 模型组额度、5 小时与 7 天/weekly 剩余额度。
- Claude Code：运行状态监控。Claude Code 当前不提供稳定的本地 Token/额度明细，因此 TokenPet 只展示进程状态。

TokenPet 的主气泡面板现在聚焦展示 5h 和 7d 剩余流量，不再在小面板里塞 Token 消耗明细。

## 当前状态

这是一个开发中的个人效率工具，适合本机使用和继续二次开发。

已完成的核心能力：

- macOS 原生透明悬浮宠物窗口。
- 菜单栏常驻入口。
- 宠物可拖拽、可隐藏、可打开设置。
- Codex / 反重力 / Claude Code 进程监控。
- Codex 5h / 7d 额度概览。
- 反重力 `/usage` 模型组额度展示。
- 反重力 Gemini 模型组、Claude 与 GPT 模型组分别展示 5h 和 7d/weekly 剩余量。
- 设置页内按 Agent 分页展示：反重力、Codex、Claude Code。
- SQLite 本地持久化，用于记录调用、额度快照和账号隔离信息。
- 多账号切换检测：账号指纹变化后，当前账号视图不沿用旧账号数据。

## 界面说明

### 桌面宠物

宠物会根据运行状态切换表现：

- 空闲：待机、呼吸、轻微动态。
- 工作中：检测到 Codex、反重力或 Claude Code 运行时进入工作状态。
- 警告：额度低、限流或数据异常时进入警告状态。
- 完成或恢复：任务结束后回到普通状态。

### 气泡面板

点击宠物或菜单栏入口可以打开状态气泡。

气泡面板当前只展示关键额度：

- Codex：剩余 5h、剩余 7d。
- 反重力：按官方 `/usage` 模型组展示剩余 5h、剩余 7d/weekly。
- 每条额度展示剩余百分比和重置倒计时。
- 数据源状态会标注为实时、官方、混合、本地或未采集。

### 设置页

设置页包含三个主要区域：

- 常规设置：宠物大小、始终置顶、开机启动、通知。
- 运行监控：配置 Codex、反重力、Claude Code 的监控开关和进程关键字。
- 额度与用量：按 Agent 查看额度、状态和本地统计。

## 数据来源

TokenPet 尽量优先读取官方或 CLI 自身暴露的信息；没有稳定数据时，会明确降级为本地统计或未采集状态。

| Agent | 当前展示 | 数据来源 |
| --- | --- | --- |
| Codex | 5h / 7d 剩余额度、本地 Token 统计 | `~/.codex/sessions/`、`~/.codex/auth.json`、本地 SQLite |
| 反重力 Antigravity | `/usage` 模型组额度、5h 和 7d/weekly 剩余量、重置时间 | 反重力本地 LanguageServer、`~/.gemini/antigravity-cli/`、Google OAuth 凭据、本地 SQLite |
| Gemini CLI | 兼容性读取路径 | `~/.gemini/oauth_creds.json`、`~/.gemini/settings.json`、`~/.gemini/telemetry.log` |
| Claude Code | 进程运行状态 | 本机进程扫描 |

反重力 `/usage` 是当前重点支持的数据源。Gemini CLI 相关路径主要作为兼容来源保留。

## 准确性说明

不同 CLI 对额度信息的开放程度不同，TokenPet 会按数据可信度展示：

- 官方：来自反重力 `/usage` 或可识别的官方额度快照。
- 实时：本地扫描刚刚刷新。
- 混合：官方额度与本地统计同时存在，但来源不完全一致。
- 本地：仅来自本机日志或会话统计。
- 未采集：当前账号或当前工具还没有可用数据。

注意：

- 反重力不同模型组可能有不同的 5h 和 weekly 重置时间。
- Claude Code 当前不展示 Token 或额度余量。
- Codex 的官方额度精度取决于本地会话、账号状态和可读数据；TokenPet 会避免把纯估算伪装成官方额度。

## 隐私与本地数据

TokenPet 面向本机使用：

- 不上传本地日志、命令内容或额度数据。
- OAuth token、refresh token、邮箱等敏感信息不会写入仓库。
- 账号隔离使用脱敏指纹。
- 本地数据库默认位于：

```text
~/.gemini/antigravity-cli/tokenpet.db
```

会读取的常见本地路径：

```text
~/.codex/auth.json
~/.codex/sessions/
~/.gemini/oauth_creds.json
~/.gemini/google_accounts.json
~/.gemini/settings.json
~/.gemini/telemetry.log
~/.gemini/antigravity-cli/
```

## 技术栈

- Swift 6
- SwiftUI
- AppKit
- SQLite3
- Swift Package Manager
- macOS background agent app bundle

最低系统要求：

- macOS 14.0+
- Xcode 16 或带 Swift 6 的命令行工具

## 构建前准备

公开仓库不会提交真实 OAuth Client 凭据。首次构建前需要创建本地凭据文件：

```bash
cp Sources/TokenPet/GeminiCredentials.swift.example Sources/TokenPet/GeminiCredentials.swift
```

然后编辑：

```swift
struct GeminiCredentials {
    static let clientId     = "YOUR_GOOGLE_OAUTH_CLIENT_ID"
    static let clientSecret = "YOUR_GOOGLE_OAUTH_CLIENT_SECRET"
}
```

`Sources/TokenPet/GeminiCredentials.swift` 已被 `.gitignore` 忽略，不要提交。

如果你只想先跑 UI，也仍然需要这个文件存在，否则 `GeminiQuotaClient.swift` 无法编译。

## 构建与运行

开发构建：

```bash
swift build --disable-sandbox
```

生成 macOS app：

```bash
./build_app.sh
```

运行：

```bash
open TokenPet.app
```

应用以后台 Agent 形式运行，不显示 Dock 图标。启动后请在桌面宠物或菜单栏入口中操作。

## ⚓️ 命令行动作钩子 (Shell Hooks)

为了消除进程轮询产生的秒级延迟，并避免短命令执行时间太短而被轮询漏掉，TokenPet 提供了**动作钩子文件**支持：

应用启动后会自动在 `~/.tokenpet/status` 创建监控文件。你可以通过向此文件写入状态来**毫秒级地**控制宠物的动作：

- 触发打字（以反重力为例）：`echo "working:antigravity" > ~/.tokenpet/status`
- 触发打字（以 Codex 为例）：`echo "working:codex" > ~/.tokenpet/status`
- 触发打字（以 Claude 为例）：`echo "working:claude" > ~/.tokenpet/status`
- 触发结束（旋转跳跃并回到空闲）：`echo "idle" > ~/.tokenpet/status`

### 🐚 终端 Shell 完美集成联动 (zsh 示例)

你可以将以下逻辑添加到你的 `~/.zshrc` 配置文件中。这样只要在终端执行 AI 相关的命令行工具，桌面宠物就会**立刻开始敲键盘**；命令执行结束后**立刻庆祝并停下**，体验极其丝滑：

```zsh
# ~/.zshrc 中添加 TokenPet 动作钩子联动
function tokenpet_preexec() {
    local cmd="$1"
    # 匹配以 antigravity, gemini, claude, codex 开头的命令
    if [[ "$cmd" =~ "^(antigravity|gemini|claude|codex)" ]]; then
        # 提取命令的主名作为参数写入钩子文件
        local tool="${cmd%% *}"
        if [[ "$tool" == "gemini" ]]; then tool="antigravity"; fi
        echo "working:$tool" > ~/.tokenpet/status
    fi
}

function tokenpet_precmd() {
    # 命令执行完毕回到 prompt 时，向钩子文件发送 idle 状态
    echo "idle" > ~/.tokenpet/status
}

# 挂载到 zsh 的钩子函数列表中
autoload -Uz add-zsh-hook
add-zsh-hook preexec tokenpet_preexec
add-zsh-hook precmd tokenpet_precmd
```

*(注：钩子包含 30 秒超时防卡死机制。如果因为意外 shell 没能发送 idle 指令，宠物在持续敲键盘 30 秒后会自动恢复空闲状态。)*

## 项目结构

```text
TokenPet/
├── Package.swift
├── build_app.sh
├── README.md
├── Sources/TokenPet/
│   ├── TokenPet.swift
│   ├── AppDelegate.swift
│   ├── PetView.swift
│   ├── PetState.swift
│   ├── BubbleView.swift
│   ├── SettingsView.swift
│   ├── AgentLogoView.swift
│   ├── ProcessMonitor.swift
│   ├── QuotaManager.swift
│   ├── CCDataCoordinator.swift
│   ├── SessionScanner.swift
│   ├── UsageLogParser.swift
│   ├── GeminiQuotaClient.swift
│   ├── AntigravityLocalUsageClient.swift
│   ├── AntigravityQuotaDisplay.swift
│   ├── AccountIdentityManager.swift
│   ├── SQLiteManager.swift
│   └── GeminiCredentials.swift.example
└── Tests/
```

## 开发注意事项

- `TokenPet.app/` 是构建产物，不应提交。
- `.build/`、`.swiftpm/`、`.idea/` 不应提交。
- `Sources/TokenPet/GeminiCredentials.swift` 是本地凭据文件，不应提交。
- 如果上传 GitHub，建议补充截图到 `docs/assets/` 后再在 README 中引用。
- 公开前建议补充 `LICENSE` 文件。

## 路线计划

后续可以继续完善：

- 添加真实截图和演示 GIF。
- 给 Codex 官方额度来源做更强校验。
- 将反重力 `/usage` 原始快照导出为调试视图。
- 增加可选的历史趋势图。
- 增加导入/导出本地 SQLite 数据的工具。
- 完善测试覆盖。

## License

当前仓库尚未添加许可证文件。公开发布前请根据你的使用方式选择并添加 `LICENSE`。
