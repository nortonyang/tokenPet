import Foundation
import Combine
import CryptoKit

/// 从 Gemini CLI 日志文件中解析真实 API 调用次数并存入 SQLite 数据库中计算
/// 日志格式：I0609 10:47:40.455524   975 http_helpers.go:183] URL: https://daily-cloudcode-pa.googleapis.com/...
@MainActor public class UsageLogParser: ObservableObject {
    public static let shared = UsageLogParser()
    
    private let logDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".gemini/antigravity-cli/log")
    private let cliLogFile = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".gemini/antigravity-cli/cli.log")
    
    @Published public var calls5h: Int = 0
    @Published public var calls24h: Int = 0
    @Published public var calls7d: Int = 0
    @Published public var activeError5hResetsAt: Date? = nil
    @Published public var activeError24hResetsAt: Date? = nil
    @Published public var activeErrorResetsAt: Date? = nil
    @Published public var activeErrorMessage: String? = nil
    @Published public var inferredLimit5h: Int? = nil
    @Published public var inferredLimit24h: Int? = nil
    @Published public var errorCount7d: Int = 0
    @Published public var geminiTokenSummary: GeminiTokenUsageSummary = GeminiTokenUsageSummary()
    @Published public var modelUsages: [GeminiModelUsage] = []
    @Published public var lastParsed: Date = Date()
    @Published public var parseError: String? = nil
    
    private var timer: AnyCancellable?
    
    private init() {}
    
    public func startAutoRefresh(interval: TimeInterval = 60) {
        refresh()
        timer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
    }
    
    public func stopAutoRefresh() {
        timer?.cancel()
        timer = nil
    }
    
    public func refresh() {
        let logDir = self.logDir
        let cliLogFile = self.cliLogFile
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let error = UsageLogParser.parseAndLoadAllLogs(logDir: logDir, cliLogFile: cliLogFile)
            let stats = SQLiteManager.shared.getGeminiStats(now: Date())
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.calls5h = stats.calls5h
                self.calls24h = stats.calls24h
                self.calls7d = stats.calls7d
                self.activeError5hResetsAt = stats.activeError5hResetsAt
                self.activeError24hResetsAt = stats.activeError24hResetsAt
                self.activeErrorResetsAt = stats.activeErrorResetsAt
                self.activeErrorMessage = stats.activeErrorMessage
                self.inferredLimit5h = stats.inferredLimit5h
                self.inferredLimit24h = stats.inferredLimit24h
                self.errorCount7d = stats.errorCount7d
                self.geminiTokenSummary = stats.tokenSummary
                self.modelUsages = stats.modelUsages
                self.lastParsed = Date()
                self.parseError = error
            }
        }
    }
    
    // MARK: - Log Parsing and Loading (runs on background thread)
    
    nonisolated private static func parseAndLoadAllLogs(logDir: URL, cliLogFile: URL) -> String? {
        let geminiIdentity = AccountIdentityManager.currentGeminiIdentity()
        let antigravityIdentity = AccountIdentityManager.currentAntigravityIdentity()
        let errCli = parseAndLoadCliLogs(logDir: logDir, cliLogFile: cliLogFile, identity: antigravityIdentity)
        let errChat = parseAndLoadAntigravityChatLogs(identity: antigravityIdentity)
        let errTel = parseAndLoadTelemetryLog(identity: geminiIdentity)
        return errCli ?? errChat ?? errTel
    }
    
    nonisolated(unsafe) private static let telemetryOffsetLock = NSLock()
    nonisolated(unsafe) private static var lastTelemetryOffset: UInt64 = 0
    
    nonisolated private static func parseAndLoadTelemetryLog(identity: AIAccountIdentity) -> String? {
        let fm = FileManager.default
        let telemetryLogFile = configuredTelemetryLogURL()
            
        guard fm.fileExists(atPath: telemetryLogFile.path) else {
            return nil
        }
        
        guard let attributes = try? fm.attributesOfItem(atPath: telemetryLogFile.path),
              let fileSize = attributes[.size] as? UInt64 else {
            return nil
        }
        
        var offset: UInt64 = 0
        telemetryOffsetLock.lock()
        if fileSize < lastTelemetryOffset {
            lastTelemetryOffset = 0
        }
        offset = lastTelemetryOffset
        telemetryOffsetLock.unlock()
        
        guard fileSize > offset else {
            return nil
        }
        
        guard let fileHandle = try? FileHandle(forReadingFrom: telemetryLogFile) else {
            return "无法读取 Gemini Telemetry 日志文件"
        }
        
        defer {
            try? fileHandle.close()
        }
        
        let content: String
        do {
            try fileHandle.seek(toOffset: offset)
            let data = fileHandle.readDataToEndOfFile()
            
            telemetryOffsetLock.lock()
            lastTelemetryOffset = fileSize
            telemetryOffsetLock.unlock()
            
            guard let utf8String = String(data: data, encoding: .utf8) else {
                return "无法解析 Telemetry 新增内容为 UTF8 字符串"
            }
            content = utf8String
        } catch {
            return "读取 Telemetry 日志时寻址或读取失败"
        }
        
        struct FlexibleInt: Decodable {
            var value: Int
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let intVal = try? container.decode(Int.self) {
                    value = intVal
                } else if let stringVal = try? container.decode(String.self), let intVal = Int(stringVal) {
                    value = intVal
                } else {
                    value = 0
                }
            }
        }

        struct TelemetryRecord: Decodable {
            var time: String?
            var timestamp: String?
            var event: String?
            var name: String?
            
            var attributes: Attributes?
            
            struct Attributes: Decodable {
                var eventName: String?
                var model: String?
                var modelName: String?
                var promptId: String?
                var authType: String?
                var statusCode: FlexibleInt?
                var durationMs: Int?
                var duration: Int?
                var inputTokenCount: Int?
                var inputTokens: Int?
                var outputTokenCount: Int?
                var outputTokens: Int?
                var cachedContentTokenCount: Int?
                var cachedTokens: Int?
                var thoughtsTokenCount: Int?
                var thoughtsTokens: Int?
                var toolTokenCount: Int?
                var toolTokens: Int?
                var totalTokenCount: Int?
                var totalTokens: Int?
                var errorMessage: String?
                var error: String?
                var resetsAt: Double?
                
                private enum CodingKeys: String, CodingKey {
                    case eventName = "event.name"
                    case model
                    case modelName = "model_name"
                    case promptId = "prompt_id"
                    case authType = "auth_type"
                    case statusCode = "status_code"
                    case durationMs = "duration_ms"
                    case duration
                    case inputTokenCount = "input_token_count"
                    case inputTokens = "input_tokens"
                    case outputTokenCount = "output_token_count"
                    case outputTokens = "output_tokens"
                    case cachedContentTokenCount = "cached_content_token_count"
                    case cachedTokens = "cached_tokens"
                    case thoughtsTokenCount = "thoughts_token_count"
                    case thoughtsTokens = "thoughts_tokens"
                    case toolTokenCount = "tool_token_count"
                    case toolTokens = "tool_tokens"
                    case totalTokenCount = "total_token_count"
                    case totalTokens = "total_tokens"
                    case errorMessage = "error_message"
                    case error = "error"
                    case resetsAt = "resets_at"
                }
            }
        }
        
        func parseTelemetryTime(_ str: String) -> Date? {
            if let date = ISO8601DateFormatter().date(from: str) {
                return date
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ",
                "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
                "yyyy-MM-dd HH:mm:ss"
            ]
            for format in formats {
                formatter.dateFormat = format
                if let date = formatter.date(from: str) {
                    return date
                }
            }
            if let doubleVal = Double(str) {
                return Date(timeIntervalSince1970: doubleVal)
            }
            return nil
        }
        
        var blocks: [String] = []
        var currentBlock: [String] = []
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            let stripped = line.trimmingCharacters(in: CharacterSet.newlines)
            if stripped == "{" {
                currentBlock = ["{"]
            } else if stripped == "}" {
                currentBlock.append("}")
                blocks.append(currentBlock.joined(separator: "\n"))
                currentBlock = []
            } else {
                if !currentBlock.isEmpty {
                    currentBlock.append(line)
                }
            }
        }
        
        let decoder = JSONDecoder()
        for block in blocks {
            guard let data = block.data(using: .utf8),
                  let record = try? decoder.decode(TelemetryRecord.self, from: data) else {
                continue
            }
            
            let eventName = record.event ?? record.name ?? record.attributes?.eventName ?? ""
            let isAPIResponseEvent = eventName == "gemini_cli.api_response" || eventName.hasSuffix(".api_response")
            let isAPIErrorEvent = eventName == "gemini_cli.api_error" || eventName.hasSuffix(".api_error")
            guard isAPIResponseEvent || isAPIErrorEvent else {
                continue
            }
            
            let model = record.attributes?.model ?? record.attributes?.modelName ?? "gemini"
            let promptId = record.attributes?.promptId ?? ""
            let authType = record.attributes?.authType ?? ""
            let statusCode = record.attributes?.statusCode.map { "\($0.value)" } ?? "200"
            let durationMs = record.attributes?.durationMs ?? record.attributes?.duration ?? 0
            
            let inputTokens = record.attributes?.inputTokens ?? record.attributes?.inputTokenCount ?? 0
            let outputTokens = record.attributes?.outputTokens ?? record.attributes?.outputTokenCount ?? 0
            let cachedTokens = record.attributes?.cachedTokens ?? record.attributes?.cachedContentTokenCount ?? 0
            let thoughtsTokens = record.attributes?.thoughtsTokens ?? record.attributes?.thoughtsTokenCount ?? 0
            let toolTokens = record.attributes?.toolTokens ?? record.attributes?.toolTokenCount ?? 0
            let totalTokens = record.attributes?.totalTokens ?? record.attributes?.totalTokenCount ?? (inputTokens + outputTokens)
            
            let timeStr = record.time ?? record.timestamp ?? ""
            let callDate = parseTelemetryTime(timeStr) ?? Date()
            if let validAfter = identity.validAfter, callDate < validAfter {
                continue
            }
            
            let isError = (isAPIErrorEvent || statusCode != "200") ? 1 : 0
            let errorMsg = record.attributes?.errorMessage ?? record.attributes?.error
            
            var resetDate: Date? = nil
            if let resetsEpoch = record.attributes?.resetsAt {
                resetDate = Date(timeIntervalSince1970: resetsEpoch)
            }
            
            let finalIsError = (isError == 1 || statusCode == "429" || (errorMsg?.contains("RESOURCE_EXHAUSTED") ?? false)) ? 1 : 0
            
            SQLiteManager.shared.insertGeminiTelemetryCall(
                timestamp: callDate,
                event: eventName,
                model: model,
                promptId: promptId,
                authType: authType,
                statusCode: statusCode,
                durationMs: durationMs,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedTokens: cachedTokens,
                thoughtsTokens: thoughtsTokens,
                toolTokens: toolTokens,
                totalTokens: totalTokens,
                isError: finalIsError,
                errorMessage: errorMsg,
                resetsAt: resetDate,
                toolName: "gemini-cli",
                accountFingerprint: identity.fingerprint,
                accountLabel: identity.label
            )
        }
        
        return nil
    }
    
    nonisolated private static func configuredTelemetryLogURL() -> URL {
        let home = NSHomeDirectory()
        let defaultURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/telemetry.log")
        let settingsURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/settings.json")
        
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let telemetry = json["telemetry"] as? [String: Any],
              let outfile = telemetry["outfile"] as? String,
              !outfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultURL
        }
        
        let expanded = outfile.replacingOccurrences(of: "~", with: home, options: [.anchored])
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        
        return URL(fileURLWithPath: home).appendingPathComponent(expanded)
    }
    
    nonisolated private static func parseAndLoadAntigravityChatLogs(identity: AIAccountIdentity) -> String? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/tmp")
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return nil }
        
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl",
                  fileURL.pathComponents.contains("chats") else {
                continue
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt >= sevenDaysAgo else {
                continue
            }
            
            parseAntigravityChatFile(fileURL, identity: identity, sevenDaysAgo: sevenDaysAgo)
        }
        
        return nil
    }
    
    nonisolated private static func parseAntigravityChatFile(_ fileURL: URL, identity: AIAccountIdentity, sevenDaysAgo: Date) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        let sessionId = chatSessionId(from: fileURL)
        
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let record = try? decoder.decode(AntigravityChatRecord.self, from: data),
                  record.type == nil || record.type == "gemini",
                  let tokens = record.tokens else {
                continue
            }
            
            let total = tokens.total ?? (tokens.input + tokens.output + tokens.thoughts + tokens.tool)
            guard total > 0 else { continue }
            
            let timestamp = parseISODate(record.timestamp) ?? fileModificationDate(fileURL) ?? Date()
            if timestamp < sevenDaysAgo { continue }
            if let validAfter = identity.validAfter, timestamp < validAfter { continue }
            
            let recordKey = record.id?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dedupeSuffix = (recordKey?.isEmpty == false) ? recordKey! : sha256(line)
            let model = record.model?.trimmingCharacters(in: .whitespacesAndNewlines)
            SQLiteManager.shared.insertUsageLog(
                provider: "google",
                toolName: "antigravity-cli",
                modelName: model?.isEmpty == false ? model : "gemini",
                accountFingerprint: identity.fingerprint,
                accountLabel: identity.label,
                sessionId: sessionId,
                promptId: recordKey,
                inputTokens: tokens.input,
                outputTokens: tokens.output,
                cachedTokens: tokens.cached,
                thoughtsTokens: tokens.thoughts,
                toolTokens: tokens.tool,
                totalTokens: total,
                durationMs: nil,
                status: "success",
                statusCode: nil,
                errorMessage: nil,
                dataSource: "antigravity_chat_jsonl",
                isEstimated: false,
                confidenceLevel: "L5",
                startedAt: timestamp,
                rawLog: nil,
                dedupeKey: "antigravity:chat-jsonl:\(identity.fingerprint):\(dedupeSuffix)"
            )
        }
    }
    
    nonisolated private static func chatSessionId(from fileURL: URL) -> String {
        let filename = fileURL.deletingPathExtension().lastPathComponent
        if filename.hasPrefix("session-") {
            return filename
        }
        let parent = fileURL.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? filename : parent
    }
    
    nonisolated private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
    
    nonisolated private static func fileModificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
    
    nonisolated private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    nonisolated private static func parseAndLoadCliLogs(logDir: URL, cliLogFile: URL, identity: AIAccountIdentity) -> String? {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        
        // Collect log files, resolving symlinks to avoid double-counting
        var seenRealPaths = Set<String>()
        var logFiles: [URL] = []
        let fm = FileManager.default
        
        func addIfNew(_ url: URL) {
            let resolvedPath: String
            if let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                if dest.hasPrefix("/") {
                    resolvedPath = dest
                } else {
                    resolvedPath = url.deletingLastPathComponent().appendingPathComponent(dest).standardizedFileURL.path
                }
            } else {
                resolvedPath = url.standardizedFileURL.path
            }
            if seenRealPaths.insert(resolvedPath).inserted {
                logFiles.append(URL(fileURLWithPath: resolvedPath))
            }
        }
        
        if fm.fileExists(atPath: cliLogFile.path) {
            addIfNew(cliLogFile)
        }
        
        if let contents = try? fm.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) {
            let archived = contents
                .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("cli-") }
                .filter { url in
                    if let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                       let modDate = attrs.contentModificationDate {
                        return modDate >= sevenDaysAgo
                    }
                    return false
                }
            for url in archived { addIfNew(url) }
        }
        
        if logFiles.isEmpty {
            return "未找到 Gemini CLI 日志文件，请确认 ~/.gemini/antigravity-cli/ 路径存在"
        }
        
        // Parse each log file and load into SQLite
        for fileURL in logFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            
            let lines = content.components(separatedBy: "\n")
            var currentModelName: String? = nil
            for line in lines {
                if let modelLabel = UsageLogParser.extractModelLabel(from: line) {
                    currentModelName = modelLabel
                }
                
                if line.contains("URL:") && (line.contains("generateContent") || line.contains("streamGenerateContent")) {
                    guard let callDate = UsageLogParser.extractDate(from: line) else { continue }
                    if let validAfter = identity.validAfter, callDate < validAfter {
                        continue
                    }
                    
                    var urlStr = ""
                    if let urlRange = line.range(of: "URL: ") {
                        let afterURL = line[urlRange.upperBound...]
                        if let spaceIdx = afterURL.firstIndex(of: " ") {
                            urlStr = String(afterURL[..<spaceIdx])
                        } else {
                            urlStr = String(afterURL)
                        }
                    }
                    
                    var traceStr = ""
                    if let traceRange = line.range(of: "Trace: ") {
                        traceStr = String(line[traceRange.upperBound...])
                    }
                    
                    SQLiteManager.shared.insertGeminiCall(
                        timestamp: callDate,
                        url: urlStr,
                        traceId: traceStr,
                        isError: 0,
                        errorMessage: nil,
                        resetsAt: nil,
                        modelName: currentModelName,
                        toolName: "antigravity-cli",
                        accountFingerprint: identity.fingerprint,
                        accountLabel: identity.label
                    )
                } else if line.contains("RESOURCE_EXHAUSTED") && line.contains("code 429") {
                    guard let callDate = UsageLogParser.extractDate(from: line) else { continue }
                    if let validAfter = identity.validAfter, callDate < validAfter {
                        continue
                    }
                    
                    var resetsAt: Date? = nil
                    if let resetRange = line.range(of: "Resets in ") {
                        let afterReset = line[resetRange.upperBound...]
                        let durationToken: String
                        if let colonIdx = afterReset.firstIndex(of: ":") {
                            durationToken = String(afterReset[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if let spaceIdx = afterReset.firstIndex(of: " ") {
                            durationToken = String(afterReset[..<spaceIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            durationToken = String(afterReset).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        
                        if let seconds = UsageLogParser.parseDuration(durationToken) {
                            resetsAt = callDate.addingTimeInterval(seconds)
                        }
                    }
                    
                    SQLiteManager.shared.insertGeminiCall(
                        timestamp: callDate,
                        url: "",
                        traceId: "",
                        isError: 1,
                        errorMessage: line,
                        resetsAt: resetsAt,
                        modelName: currentModelName,
                        toolName: "antigravity-cli",
                        accountFingerprint: identity.fingerprint,
                        accountLabel: identity.label
                    )
                }
            }
        }
        
        return nil
    }
    
    nonisolated private static func extractModelLabel(from line: String) -> String? {
        guard line.contains("model_config_manager"),
              let labelRange = line.range(of: "label=\"") else {
            return nil
        }
        
        let afterLabel = line[labelRange.upperBound...]
        guard let endQuote = afterLabel.firstIndex(of: "\"") else {
            return nil
        }
        
        let label = String(afterLabel[..<endQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
    
    /// Parse the log timestamp from a log line with microsecond precision
    /// Format: I0609 10:47:40.455524 or I0602 15:00:23.572982
    nonisolated private static func extractDate(from line: String) -> Date? {
        guard line.count > 15 else { return nil }
        let start = line.startIndex
        
        let monthDayStart = line.index(start, offsetBy: 1)
        
        guard line.index(monthDayStart, offsetBy: 4, limitedBy: line.endIndex) != nil,
              let spaceIdx = line[monthDayStart...].firstIndex(of: " ") else { return nil }
        
        let monthDay = String(line[monthDayStart..<spaceIdx]) // e.g. "0609"
        guard monthDay.count == 4,
              let month = Int(monthDay.prefix(2)),
              let day = Int(monthDay.suffix(2)) else { return nil }
        
        let afterSpace = line.index(spaceIdx, offsetBy: 1)
        guard afterSpace < line.endIndex else { return nil }
        
        let spaceAfterTime = line[afterSpace...].firstIndex(of: " ") ?? line.endIndex
        let timeString = String(line[afterSpace..<spaceAfterTime]) // "10:47:40.455524"
        
        let parts = timeString.components(separatedBy: ".")
        let hms = parts[0]
        guard hms.count == 8,
              let hour = Int(hms.prefix(2)),
              let minute = Int(hms.dropFirst(3).prefix(2)),
              let second = Int(hms.dropFirst(6).prefix(2)) else { return nil }
        
        var microseconds = 0
        if parts.count > 1, let micros = Int(parts[1]) {
            microseconds = micros
        }
        
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        var comps = DateComponents()
        comps.year = currentYear
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        
        guard var date = cal.date(from: comps) else { return nil }
        
        // Add microseconds
        date = date.addingTimeInterval(Double(microseconds) / 1_000_000.0)
        
        // Handle year boundary
        if date > Date().addingTimeInterval(3600) {
            comps.year = currentYear - 1
            if var d2 = cal.date(from: comps) {
                d2 = d2.addingTimeInterval(Double(microseconds) / 1_000_000.0)
                return d2
            }
        }
        return date
    }
    
    /// Parses duration strings like "3m40s", "15s", "1h5m" into seconds
    nonisolated private static func parseDuration(_ str: String) -> TimeInterval? {
        var seconds: TimeInterval = 0
        var currentNum = ""
        
        for char in str {
            if char.isNumber {
                currentNum.append(char)
            } else if char == "h" {
                if let val = Double(currentNum) {
                    seconds += val * 3600
                }
                currentNum = ""
            } else if char == "m" {
                if let val = Double(currentNum) {
                    seconds += val * 60
                }
                currentNum = ""
            } else if char == "s" {
                if let val = Double(currentNum) {
                    seconds += val
                }
                currentNum = ""
            }
        }
        
        // Fallback: if no unit, treat as seconds
        if !currentNum.isEmpty && seconds == 0 {
            if let val = Double(currentNum) {
                seconds = val
            }
        }
        
        return seconds > 0 ? seconds : nil
    }
}

private struct AntigravityChatRecord: Decodable {
    var id: String?
    var timestamp: String?
    var type: String?
    var model: String?
    var tokens: AntigravityChatTokens?
}

private struct AntigravityChatTokens: Decodable {
    var input: Int
    var output: Int
    var cached: Int
    var thoughts: Int
    var tool: Int
    var total: Int?
    
    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cached
        case thoughts
        case tool
        case total
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = (try? container.decode(Int.self, forKey: .input)) ?? 0
        output = (try? container.decode(Int.self, forKey: .output)) ?? 0
        cached = (try? container.decode(Int.self, forKey: .cached)) ?? 0
        thoughts = (try? container.decode(Int.self, forKey: .thoughts)) ?? 0
        tool = (try? container.decode(Int.self, forKey: .tool)) ?? 0
        total = try? container.decode(Int.self, forKey: .total)
    }
}
