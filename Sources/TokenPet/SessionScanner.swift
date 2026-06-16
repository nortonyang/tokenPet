import Foundation
import SQLite3

public struct CachedSessionData: Sendable {
    public var modificationDate: Date
    public var events: [TokenEvent]
    public var lastRateLimits: CodexRateLimits?
}

public final class SessionScanner: @unchecked Sendable {
    public static let shared = SessionScanner()
    
    private let sessionsDir = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".codex/sessions")
    
    private let cacheLock = NSLock()
    private var memoryCache = [String: CachedSessionData]()
    private var lastScanIdentityFingerprint: String?
    
    private static func parseDate(_ str: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let backupFormatter = ISO8601DateFormatter()
        backupFormatter.formatOptions = [.withInternetDateTime]
        
        return isoFormatter.date(from: str) ?? backupFormatter.date(from: str)
    }
    
    private init() {}
    
    private static func shouldInclude(_ date: Date, for identity: AIAccountIdentity) -> Bool {
        guard let validAfter = identity.validAfter else { return true }
        return date >= validAfter
    }
    
    /// Extract session creation date from rollout filename, e.g.
    /// "rollout-2026-06-09T10-25-22-xxxx.jsonl" -> Date(2026-06-09 10:25:22)
    private static func sessionTimestamp(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent // e.g. rollout-2026-06-09T10-25-22-...
        let pattern = #"rollout-(\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range(at: 1), in: name)
        else { return nil }
        let raw = String(name[range]).replacingOccurrences(of: "T(\\d{2})-(\\d{2})-(\\d{2})", with: "T$1:$2:$3", options: .regularExpression)
        return parseDate(raw + "Z") ?? parseDate(raw)
    }
    
    public func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        memoryCache.removeAll()
    }
    
    public func scan(now: Date = Date()) -> (rateLimits: CodexRateLimits?, tokenSummary: TokenUsageSummary) {
        let identity = AccountIdentityManager.currentCodexIdentity()
        cacheLock.lock()
        if lastScanIdentityFingerprint != identity.fingerprint {
            memoryCache.removeAll()
            lastScanIdentityFingerprint = identity.fingerprint
        }
        cacheLock.unlock()
        
        parseCodexSQLite(now: now, identity: identity)
        
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sessionsDir.path) else {
            return SQLiteManager.shared.getCodexStats(now: now)
        }
        
        // 1. Enumerate all .jsonl files in the last 7 days
        var sessionFiles: [(url: URL, modDate: Date)] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        
        if let enumerator = fileManager.enumerator(at: sessionsDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                if let resourceValues = try? url.resourceValues(forKeys: Set(keys)),
                   let isFile = resourceValues.isRegularFile, isFile,
                   let modDate = resourceValues.contentModificationDate {
                    if modDate >= sevenDaysAgo {
                        sessionFiles.append((url: url, modDate: modDate))
                    }
                }
            }
        }
        
        // Sort by session creation time extracted from filename
        sessionFiles.sort {
            let t0 = SessionScanner.sessionTimestamp(from: $0.url) ?? $0.modDate
            let t1 = SessionScanner.sessionTimestamp(from: $1.url) ?? $1.modDate
            return t0 > t1
        }
        
        cacheLock.lock()
        let cacheCopy = self.memoryCache
        cacheLock.unlock()
        
        var newCache = [String: CachedSessionData]()
        
        // Parse files and insert/replace into SQLite
        for fileInfo in sessionFiles {
            let cacheKey = fileInfo.url.lastPathComponent
            
            var cached: CachedSessionData? = cacheCopy[cacheKey]
            if let c = cached, c.modificationDate == fileInfo.modDate {
                newCache[cacheKey] = c
            } else {
                cached = parseSessionFile(fileInfo.url, modificationDate: fileInfo.modDate, identity: identity)
                newCache[cacheKey] = cached
            }
        }
        
        // Update memory cache
        cacheLock.lock()
        self.memoryCache = newCache
        cacheLock.unlock()
        
        // 2. Query SQLite for the aggregated statistics
        return SQLiteManager.shared.getCodexStats(now: now)
    }
    
    private func parseSessionFile(_ url: URL, modificationDate: Date, identity: AIAccountIdentity) -> CachedSessionData {
        var events: [TokenEvent] = []
        var lastRateLimits: CodexRateLimits? = nil
        
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return CachedSessionData(modificationDate: modificationDate, events: [], lastRateLimits: nil)
        }
        
        let lines = content.components(separatedBy: "\n")
        let sessionId = url.lastPathComponent.replacingOccurrences(of: ".jsonl", with: "")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            guard trimmed.contains("\"token_count\"") else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            
            do {
                let decoder = JSONDecoder()
                let logEvent = try decoder.decode(CodexLogEvent.self, from: data)
                
                if logEvent.payload.type == "token_count",
                   let info = logEvent.payload.info,
                   let ltu = info.last_token_usage,
                   let callDate = SessionScanner.parseDate(logEvent.timestamp) {
                    guard SessionScanner.shouldInclude(callDate, for: identity) else { continue }
                    
                    let event = TokenEvent(
                        timestamp: callDate,
                        input: ltu.input_tokens ?? 0,
                        output: ltu.output_tokens ?? 0,
                        cached: ltu.cached_input_tokens ?? 0
                    )
                    events.append(event)
                    
                    var u5h: Double? = nil
                    var r5h: Date? = nil
                    var u7d: Double? = nil
                    var r7d: Date? = nil
                    var plan: String? = nil
                    
                    // Parse rate limits if present
                    if let rl = logEvent.payload.rate_limits,
                       let primary = rl.primary,
                       let secondary = rl.secondary {
                        
                        let resetsAt5h = Date(timeIntervalSince1970: primary.resets_at ?? 0)
                        let resetsAt7d = Date(timeIntervalSince1970: secondary.resets_at ?? 0)
                        let now = Date()
                        
                        let used5h = resetsAt5h > now ? (primary.used_percent ?? 0.0) : 0.0
                        let used7d = resetsAt7d > now ? (secondary.used_percent ?? 0.0) : (secondary.used_percent ?? 0.0)
                        
                        lastRateLimits = CodexRateLimits(
                            primary5hUsedPercent: used5h,
                            primary5hResetsAt: resetsAt5h,
                            secondary7dUsedPercent: used7d,
                            secondary7dResetsAt: resetsAt7d,
                            planType: rl.plan_type ?? "plus",
                            sessionTimestamp: callDate,
                            accountLabel: identity.label
                        )
                        
                        u5h = primary.used_percent
                        r5h = resetsAt5h
                        u7d = secondary.used_percent
                        r7d = resetsAt7d
                        plan = rl.plan_type
                    }
                    
                    SQLiteManager.shared.insertCodexEvent(
                        timestamp: callDate,
                        sessionId: sessionId,
                        input: ltu.input_tokens ?? 0,
                        output: ltu.output_tokens ?? 0,
                        cached: ltu.cached_input_tokens ?? 0,
                        used5h: u5h,
                        resetsAt5h: r5h,
                        used7d: u7d,
                        resetsAt7d: r7d,
                        plan: plan,
                        accountFingerprint: identity.fingerprint,
                        accountLabel: identity.label
                    )
                }
            } catch {
                continue
            }
        }
        
        return CachedSessionData(
            modificationDate: modificationDate,
            events: events,
            lastRateLimits: lastRateLimits
        )
    }
    
    private func regexFirstMatch(regex: NSRegularExpression?, in text: String) -> String? {
        guard let regex = regex else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
            if match.numberOfRanges > 1 {
                return nsString.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private func parseCodexSQLite(now: Date, identity: AIAccountIdentity) {
        let codexDbPath = NSHomeDirectory() + "/.codex/logs_2.sqlite"
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: codexDbPath) else { return }
        
        var db: OpaquePointer? = nil
        guard sqlite3_open_v2(codexDbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }
        
        let lastId = UserDefaults.standard.integer(forKey: "lastParsedCodexLogId")
        let sevenDaysAgo = Int64(now.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970)
        
        let sql = """
        SELECT id, ts, feedback_log_body FROM logs
        WHERE ts >= ? AND id > ? AND (
            feedback_log_body LIKE '%"type":"codex.rate_limits"%'
            OR feedback_log_body LIKE '%"type":"error"%'
            OR feedback_log_body LIKE '%codex.turn.token_usage%'
        )
        ORDER BY id ASC;
        """
        
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_int64(stmt, 1, sevenDaysAgo)
        sqlite3_bind_int64(stmt, 2, Int64(lastId))
        
        var maxId = lastId
        
        let threadIdRegex = try? NSRegularExpression(pattern: #"(?:thread_id|thread\\.id)=([0-9a-fA-F\-]+)"#)
        let inputRegex = try? NSRegularExpression(pattern: #"codex\.turn\.token_usage\.input_tokens=(\d+)"#)
        let outputRegex = try? NSRegularExpression(pattern: #"codex\.turn\.token_usage\.output_tokens=(\d+)"#)
        let cachedRegex = try? NSRegularExpression(pattern: #"codex\.turn\.token_usage\.cached_input_tokens=(\d+)"#)
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let tsVal = sqlite3_column_double(stmt, 1)
            let timestamp = Date(timeIntervalSince1970: tsVal)
            guard SessionScanner.shouldInclude(timestamp, for: identity) else { continue }
            
            if id > maxId {
                maxId = Int(id)
            }
            
            guard let bodyCStr = sqlite3_column_text(stmt, 2) else { continue }
            let body = String(cString: bodyCStr)
            
            if body.contains("codex.turn.token_usage") {
                let sessionId = regexFirstMatch(regex: threadIdRegex, in: body) ?? "unknown_session"
                let input = Int(regexFirstMatch(regex: inputRegex, in: body) ?? "") ?? 0
                let output = Int(regexFirstMatch(regex: outputRegex, in: body) ?? "") ?? 0
                let cached = Int(regexFirstMatch(regex: cachedRegex, in: body) ?? "") ?? 0
                
                SQLiteManager.shared.insertCodexEvent(
                    timestamp: timestamp,
                    sessionId: sessionId,
                    input: input,
                    output: output,
                    cached: cached,
                    used5h: nil,
                    resetsAt5h: nil,
                    used7d: nil,
                    resetsAt7d: nil,
                    plan: nil,
                    accountFingerprint: identity.fingerprint,
                    accountLabel: identity.label
                )
            } else if let wsEventRange = body.range(of: "websocket event:") {
                let subBody = body[wsEventRange.upperBound...]
                if let braceIndex = subBody.firstIndex(of: "{") {
                    let jsonString = String(subBody[braceIndex...])
                    if let jsonData = jsonString.data(using: .utf8) {
                        do {
                            let decoder = JSONDecoder()
                            let wsEvent = try decoder.decode(CodexWebsocketEvent.self, from: jsonData)
                            
                            if wsEvent.type == "codex.rate_limits", let rl = wsEvent.rate_limits {
                                let plan = wsEvent.plan_type ?? "plus"
                                let resetsAt5h = Date(timeIntervalSince1970: rl.primary?.reset_at ?? 0)
                                let resetsAt7d = Date(timeIntervalSince1970: rl.secondary?.reset_at ?? 0)
                                
                                SQLiteManager.shared.insertCodexEvent(
                                    timestamp: timestamp,
                                    sessionId: "rate_limit_update",
                                    input: 0,
                                    output: 0,
                                    cached: 0,
                                    used5h: rl.primary?.used_percent,
                                    resetsAt5h: resetsAt5h,
                                    used7d: rl.secondary?.used_percent,
                                    resetsAt7d: resetsAt7d,
                                    plan: plan,
                                    accountFingerprint: identity.fingerprint,
                                    accountLabel: identity.label
                                )
                            } else if wsEvent.type == "error", wsEvent.status_code == 429 {
                                var resetsAt7d = Date(timeIntervalSince1970: wsEvent.error?.resets_at ?? 0)
                                var used7dVal = 100.0
                                var used5hVal = 100.0
                                var resetsAt5h = Date().addingTimeInterval(5 * 3600)
                                
                                if let headers = wsEvent.headers {
                                    if let primaryResetStr = headers.primaryResetAt, let primaryResetVal = Double(primaryResetStr) {
                                        resetsAt5h = Date(timeIntervalSince1970: primaryResetVal)
                                    }
                                    if let primaryUsedStr = headers.primaryUsedPercent, let primaryUsedVal = Double(primaryUsedStr) {
                                        used5hVal = primaryUsedVal
                                    }
                                    if let secondaryResetStr = headers.secondaryResetAt, let secondaryResetVal = Double(secondaryResetStr) {
                                        resetsAt7d = Date(timeIntervalSince1970: secondaryResetVal)
                                    }
                                    if let secondaryUsedStr = headers.secondaryUsedPercent, let secondaryUsedVal = Double(secondaryUsedStr) {
                                        used7dVal = secondaryUsedVal
                                    }
                                }
                                
                                SQLiteManager.shared.insertCodexEvent(
                                    timestamp: timestamp,
                                    sessionId: "rate_limit_error",
                                    input: 0,
                                    output: 0,
                                    cached: 0,
                                    used5h: used5hVal,
                                    resetsAt5h: resetsAt5h,
                                    used7d: used7dVal,
                                    resetsAt7d: resetsAt7d,
                                    plan: "plus",
                                    accountFingerprint: identity.fingerprint,
                                    accountLabel: identity.label
                                )
                            }
                        } catch {
                            // ignore decoding errors
                        }
                    }
                }
            }
        }
        
        if maxId > lastId {
            UserDefaults.standard.set(maxId, forKey: "lastParsedCodexLogId")
        }
    }
}

private struct CodexWebsocketEvent: Decodable {
    let type: String
    let plan_type: String?
    let rate_limits: RateLimits?
    let error: ErrorDetails?
    let status_code: Int?
    let headers: Headers?
    
    struct RateLimits: Decodable {
        let primary: LimitDetails?
        let secondary: LimitDetails?
    }
    
    struct LimitDetails: Decodable {
        let reset_at: Double?
        let used_percent: Double?
    }
    
    struct ErrorDetails: Decodable {
        let type: String?
        let resets_at: Double?
    }
    
    struct Headers: Decodable {
        let primaryResetAt: String?
        let primaryUsedPercent: String?
        let secondaryResetAt: String?
        let secondaryUsedPercent: String?
        
        private enum CodingKeys: String, CodingKey {
            case primaryResetAt = "X-Codex-Primary-Reset-At"
            case primaryUsedPercent = "X-Codex-Primary-Used-Percent"
            case secondaryResetAt = "X-Codex-Secondary-Reset-At"
            case secondaryUsedPercent = "X-Codex-Secondary-Used-Percent"
        }
    }
}

// MARK: - Decodable models for session log parsing

private struct CodexLogEvent: Decodable {
    var timestamp: String
    var type: String
    var payload: Payload
    
    struct Payload: Decodable {
        var type: String
        var info: Info?
        var rate_limits: RateLimits?
    }
    
    struct Info: Decodable {
        var last_token_usage: TokenUsage?
        var total_token_usage: TokenUsage?
    }
    
    struct RateLimits: Decodable {
        var plan_type: String?
        var primary: LimitDetails?
        var secondary: LimitDetails?
    }
    
    struct LimitDetails: Decodable {
        var resets_at: Double?
        var used_percent: Double?
        var window_minutes: Double?
    }
    
    struct TokenUsage: Decodable {
        var input_tokens: Int?
        var output_tokens: Int?
        var cached_input_tokens: Int?
    }
}
