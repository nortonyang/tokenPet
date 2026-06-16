import Foundation
import SQLite3

public final class SQLiteManager: @unchecked Sendable {
    public static let shared = SQLiteManager()
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.tokenpet.sqlite")
    
    private init() {
        let homeDir = NSHomeDirectory()
        let appDir = homeDir + "/.gemini/antigravity-cli"
        
        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: appDir) {
            try? fm.createDirectory(atPath: appDir, withIntermediateDirectories: true)
        }
        
        self.dbPath = appDir + "/tokenpet.db"
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("TokenPet SQLite: Failed to open database at \(dbPath)")
        } else {
            // Enable WAL mode for concurrent reading/writing
            var errorMsg: UnsafeMutablePointer<Int8>?
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, &errorMsg)
            if errorMsg != nil {
                sqlite3_free(errorMsg)
            }
        }
        
        createTables()
    }
    
    deinit {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
            }
        }
    }
    
    private func createTables() {
        queue.sync {
            let sqlGemini = """
            CREATE TABLE IF NOT EXISTS gemini_calls (
                timestamp REAL PRIMARY KEY,
                url TEXT,
                trace_id TEXT,
                is_error INTEGER,
                error_message TEXT,
                resets_at REAL,
                account_fingerprint TEXT,
                account_label TEXT
            );
            """
            exec(sql: sqlGemini)
            
            // Schema Migrations for Gemini Telemetry (v1.md)
            let columns = [
                ("model_name", "TEXT"),
                ("input_tokens", "INTEGER DEFAULT 0"),
                ("output_tokens", "INTEGER DEFAULT 0"),
                ("cached_tokens", "INTEGER DEFAULT 0"),
                ("thoughts_tokens", "INTEGER DEFAULT 0"),
                ("tool_tokens", "INTEGER DEFAULT 0"),
                ("total_tokens", "INTEGER DEFAULT 0"),
                ("duration_ms", "INTEGER DEFAULT 0"),
                ("status_code", "TEXT"),
                ("data_source", "TEXT DEFAULT 'local_log'"),
                ("is_estimated", "INTEGER DEFAULT 0"),
                ("account_fingerprint", "TEXT"),
                ("account_label", "TEXT")
            ]
            for (colName, colType) in columns {
                let sqlAddCol = "ALTER TABLE gemini_calls ADD COLUMN \(colName) \(colType);"
                exec(sql: sqlAddCol)
            }
            
            let sqlCodex = """
            CREATE TABLE IF NOT EXISTS codex_events (
                timestamp REAL PRIMARY KEY,
                session_id TEXT,
                account_fingerprint TEXT,
                account_label TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                cached_tokens INTEGER,
                used_percent_5h REAL,
                resets_at_5h REAL,
                used_percent_7d REAL,
                resets_at_7d REAL,
                plan_type TEXT
            );
            """
            exec(sql: sqlCodex)
            
            let sqlAIUsage = """
            CREATE TABLE IF NOT EXISTS ai_usage_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dedupe_key TEXT NOT NULL UNIQUE,
                provider TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                model_name TEXT,
                account_fingerprint TEXT,
                account_label TEXT,
                session_id TEXT,
                prompt_id TEXT,
                project_path TEXT,
                worktree_name TEXT,
                input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0,
                cached_tokens INTEGER DEFAULT 0,
                thoughts_tokens INTEGER DEFAULT 0,
                tool_tokens INTEGER DEFAULT 0,
                total_tokens INTEGER DEFAULT 0,
                duration_ms INTEGER,
                status TEXT,
                status_code TEXT,
                error_message TEXT,
                data_source TEXT,
                is_estimated INTEGER DEFAULT 0,
                confidence_level TEXT DEFAULT 'L0',
                limit_snapshot_id INTEGER,
                started_at REAL NOT NULL,
                ended_at REAL,
                raw_log TEXT,
                created_at REAL DEFAULT (strftime('%s','now'))
            );
            """
            exec(sql: sqlAIUsage)
            
            let sqlLimitSnapshot = """
            CREATE TABLE IF NOT EXISTS ai_limit_snapshot (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                dedupe_key TEXT NOT NULL UNIQUE,
                provider TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                model_name TEXT,
                account_fingerprint TEXT,
                account_label TEXT,
                auth_type TEXT,
                plan_name TEXT,
                window_type TEXT NOT NULL,
                metric_type TEXT NOT NULL,
                limit_value REAL,
                remaining_value REAL,
                used_value REAL,
                reset_at REAL,
                reset_after_seconds INTEGER,
                retry_after_seconds INTEGER,
                source TEXT NOT NULL,
                source_detail TEXT,
                source_url TEXT,
                confidence_level TEXT NOT NULL,
                is_official INTEGER DEFAULT 0,
                is_estimated INTEGER DEFAULT 0,
                captured_at REAL NOT NULL,
                expires_at REAL,
                raw_snapshot TEXT,
                created_at REAL DEFAULT (strftime('%s','now'))
            );
            """
            exec(sql: sqlLimitSnapshot)
            
            let tableColumns = [
                "codex_events": [("account_fingerprint", "TEXT"), ("account_label", "TEXT")],
                "ai_usage_log": [("account_fingerprint", "TEXT"), ("account_label", "TEXT")],
                "ai_limit_snapshot": [("account_fingerprint", "TEXT"), ("account_label", "TEXT")]
            ]
            for (table, columns) in tableColumns {
                for (colName, colType) in columns {
                    exec(sql: "ALTER TABLE \(table) ADD COLUMN \(colName) \(colType);")
                }
            }
            
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_ai_usage_tool_time ON ai_usage_log(tool_name, started_at);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_ai_usage_provider_time ON ai_usage_log(provider, started_at);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_ai_limit_snapshot_lookup ON ai_limit_snapshot(provider, tool_name, window_type, metric_type, captured_at);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_gemini_calls_model_time ON gemini_calls(model_name, timestamp);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_codex_events_account_time ON codex_events(account_fingerprint, timestamp);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_gemini_calls_account_time ON gemini_calls(account_fingerprint, timestamp);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_ai_usage_account_time ON ai_usage_log(account_fingerprint, started_at);")
            exec(sql: "CREATE INDEX IF NOT EXISTS idx_ai_limit_account_time ON ai_limit_snapshot(account_fingerprint, captured_at);")
        }
    }
    
    private func exec(sql: String) {
        var errorMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMsg) != SQLITE_OK {
            if let error = errorMsg {
                let msg = String(cString: error)
                if !msg.contains("duplicate column name") {
                    print("TokenPet SQLite Exec Error: \(msg) (SQL: \(sql))")
                }
                sqlite3_free(errorMsg)
            }
        }
    }
    
    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value = value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, Self.sqliteTransient)
    }
    
    private func bindInt(_ stmt: OpaquePointer?, _ index: Int32, _ value: Int?) {
        guard let value = value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_int(stmt, index, Int32(value))
    }
    
    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        guard let value = value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_double(stmt, index, value)
    }
    
    private func bindDate(_ stmt: OpaquePointer?, _ index: Int32, _ value: Date?) {
        bindDouble(stmt, index, value?.timeIntervalSince1970)
    }
    
    private func stringColumn(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, column) else {
            return nil
        }
        let value = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    
    private func timestampKey(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }
    
    private func accountPredicate(column: String, identities: [AIAccountIdentity]) -> String {
        let fingerprints = identities.map(\.fingerprint).filter { !$0.isEmpty }
        guard !fingerprints.isEmpty else {
            return "1 = 0"
        }
        
        let quoted = fingerprints
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ", ")
        let includeLegacyRows = identities.allSatisfy { $0.validAfter == nil }
        
        if includeLegacyRows {
            return "(\(column) IN (\(quoted)) OR \(column) IS NULL OR \(column) = '')"
        }
        return "\(column) IN (\(quoted))"
    }
    
    private func latestValidAfterTimestamp(_ identities: [AIAccountIdentity]) -> Double? {
        AccountIdentityManager.latestValidAfter(identities)?.timeIntervalSince1970
    }
    
    private func upsertAIUsageLogLocked(
        dedupeKey: String,
        provider: String,
        toolName: String,
        modelName: String?,
        accountFingerprint: String?,
        accountLabel: String?,
        sessionId: String?,
        promptId: String?,
        projectPath: String? = nil,
        worktreeName: String? = nil,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        thoughtsTokens: Int = 0,
        toolTokens: Int = 0,
        totalTokens: Int,
        durationMs: Int?,
        status: String,
        statusCode: String?,
        errorMessage: String?,
        dataSource: String,
        isEstimated: Bool,
        confidenceLevel: String,
        limitSnapshotId: Int? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        rawLog: String? = nil
    ) {
        let sql = """
        INSERT INTO ai_usage_log (
            dedupe_key, provider, tool_name, model_name, account_fingerprint, account_label, session_id, prompt_id,
            project_path, worktree_name, input_tokens, output_tokens, cached_tokens,
            thoughts_tokens, tool_tokens, total_tokens, duration_ms, status,
            status_code, error_message, data_source, is_estimated, confidence_level,
            limit_snapshot_id, started_at, ended_at, raw_log
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(dedupe_key) DO UPDATE SET
            model_name = excluded.model_name,
            account_fingerprint = COALESCE(account_fingerprint, excluded.account_fingerprint),
            account_label = COALESCE(account_label, excluded.account_label),
            session_id = excluded.session_id,
            prompt_id = excluded.prompt_id,
            project_path = excluded.project_path,
            worktree_name = excluded.worktree_name,
            input_tokens = excluded.input_tokens,
            output_tokens = excluded.output_tokens,
            cached_tokens = excluded.cached_tokens,
            thoughts_tokens = excluded.thoughts_tokens,
            tool_tokens = excluded.tool_tokens,
            total_tokens = excluded.total_tokens,
            duration_ms = excluded.duration_ms,
            status = excluded.status,
            status_code = excluded.status_code,
            error_message = excluded.error_message,
            data_source = excluded.data_source,
            is_estimated = excluded.is_estimated,
            confidence_level = excluded.confidence_level,
            limit_snapshot_id = excluded.limit_snapshot_id,
            ended_at = excluded.ended_at,
            raw_log = excluded.raw_log;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("TokenPet SQLite: Prepare failed for upsertAIUsageLog")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        bindText(stmt, 1, dedupeKey)
        bindText(stmt, 2, provider)
        bindText(stmt, 3, toolName)
        bindText(stmt, 4, modelName)
        bindText(stmt, 5, accountFingerprint)
        bindText(stmt, 6, accountLabel)
        bindText(stmt, 7, sessionId)
        bindText(stmt, 8, promptId)
        bindText(stmt, 9, projectPath)
        bindText(stmt, 10, worktreeName)
        bindInt(stmt, 11, inputTokens)
        bindInt(stmt, 12, outputTokens)
        bindInt(stmt, 13, cachedTokens)
        bindInt(stmt, 14, thoughtsTokens)
        bindInt(stmt, 15, toolTokens)
        bindInt(stmt, 16, totalTokens)
        bindInt(stmt, 17, durationMs)
        bindText(stmt, 18, status)
        bindText(stmt, 19, statusCode)
        bindText(stmt, 20, errorMessage)
        bindText(stmt, 21, dataSource)
        bindInt(stmt, 22, isEstimated ? 1 : 0)
        bindText(stmt, 23, confidenceLevel)
        bindInt(stmt, 24, limitSnapshotId)
        bindDate(stmt, 25, startedAt)
        bindDate(stmt, 26, endedAt)
        bindText(stmt, 27, rawLog)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("TokenPet SQLite: Failed to upsert ai_usage_log")
        }
    }
    
    private func upsertLimitSnapshotLocked(
        dedupeKey: String,
        provider: String,
        toolName: String,
        modelName: String? = nil,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil,
        authType: String? = nil,
        planName: String? = nil,
        windowType: String,
        metricType: String,
        limitValue: Double?,
        remainingValue: Double?,
        usedValue: Double?,
        resetAt: Date?,
        resetAfterSeconds: Int? = nil,
        retryAfterSeconds: Int? = nil,
        source: String,
        sourceDetail: String? = nil,
        sourceURL: String? = nil,
        confidenceLevel: String,
        isOfficial: Bool,
        isEstimated: Bool,
        capturedAt: Date,
        expiresAt: Date? = nil,
        rawSnapshot: String? = nil
    ) {
        let sql = """
        INSERT INTO ai_limit_snapshot (
            dedupe_key, provider, tool_name, model_name, account_fingerprint, account_label, auth_type, plan_name,
            window_type, metric_type, limit_value, remaining_value, used_value,
            reset_at, reset_after_seconds, retry_after_seconds, source, source_detail,
            source_url, confidence_level, is_official, is_estimated, captured_at,
            expires_at, raw_snapshot
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(dedupe_key) DO UPDATE SET
            model_name = excluded.model_name,
            account_fingerprint = COALESCE(account_fingerprint, excluded.account_fingerprint),
            account_label = COALESCE(account_label, excluded.account_label),
            auth_type = excluded.auth_type,
            plan_name = excluded.plan_name,
            limit_value = excluded.limit_value,
            remaining_value = excluded.remaining_value,
            used_value = excluded.used_value,
            reset_at = excluded.reset_at,
            reset_after_seconds = excluded.reset_after_seconds,
            retry_after_seconds = excluded.retry_after_seconds,
            source = excluded.source,
            source_detail = excluded.source_detail,
            source_url = excluded.source_url,
            confidence_level = excluded.confidence_level,
            is_official = excluded.is_official,
            is_estimated = excluded.is_estimated,
            captured_at = excluded.captured_at,
            expires_at = excluded.expires_at,
            raw_snapshot = excluded.raw_snapshot;
        """
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            print("TokenPet SQLite: Prepare failed for upsertLimitSnapshot")
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        bindText(stmt, 1, dedupeKey)
        bindText(stmt, 2, provider)
        bindText(stmt, 3, toolName)
        bindText(stmt, 4, modelName)
        bindText(stmt, 5, accountFingerprint)
        bindText(stmt, 6, accountLabel)
        bindText(stmt, 7, authType)
        bindText(stmt, 8, planName)
        bindText(stmt, 9, windowType)
        bindText(stmt, 10, metricType)
        bindDouble(stmt, 11, limitValue)
        bindDouble(stmt, 12, remainingValue)
        bindDouble(stmt, 13, usedValue)
        bindDate(stmt, 14, resetAt)
        bindInt(stmt, 15, resetAfterSeconds)
        bindInt(stmt, 16, retryAfterSeconds)
        bindText(stmt, 17, source)
        bindText(stmt, 18, sourceDetail)
        bindText(stmt, 19, sourceURL)
        bindText(stmt, 20, confidenceLevel)
        bindInt(stmt, 21, isOfficial ? 1 : 0)
        bindInt(stmt, 22, isEstimated ? 1 : 0)
        bindDate(stmt, 23, capturedAt)
        bindDate(stmt, 24, expiresAt)
        bindText(stmt, 25, rawSnapshot)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("TokenPet SQLite: Failed to upsert ai_limit_snapshot")
        }
    }
    
    // MARK: - Insert Operations
    
    public func insertUsageLog(
        provider: String,
        toolName: String,
        modelName: String? = nil,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil,
        sessionId: String? = nil,
        promptId: String? = nil,
        projectPath: String? = nil,
        worktreeName: String? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        thoughtsTokens: Int = 0,
        toolTokens: Int = 0,
        totalTokens: Int? = nil,
        durationMs: Int? = nil,
        status: String = "success",
        statusCode: String? = nil,
        errorMessage: String? = nil,
        dataSource: String,
        isEstimated: Bool = false,
        confidenceLevel: String,
        startedAt: Date,
        endedAt: Date? = nil,
        rawLog: String? = nil,
        dedupeKey: String? = nil
    ) {
        queue.sync {
            let accountPart = accountFingerprint ?? "legacy"
            let key = dedupeKey ?? "\(provider):\(toolName):\(accountPart):\(dataSource):\(timestampKey(startedAt)):\(sessionId ?? ""):\(promptId ?? "")"
            upsertAIUsageLogLocked(
                dedupeKey: key,
                provider: provider,
                toolName: toolName,
                modelName: modelName,
                accountFingerprint: accountFingerprint,
                accountLabel: accountLabel,
                sessionId: sessionId,
                promptId: promptId,
                projectPath: projectPath,
                worktreeName: worktreeName,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedTokens: cachedTokens,
                thoughtsTokens: thoughtsTokens,
                toolTokens: toolTokens,
                totalTokens: totalTokens ?? (inputTokens + outputTokens + cachedTokens + thoughtsTokens + toolTokens),
                durationMs: durationMs,
                status: status,
                statusCode: statusCode,
                errorMessage: errorMessage,
                dataSource: dataSource,
                isEstimated: isEstimated,
                confidenceLevel: confidenceLevel,
                startedAt: startedAt,
                endedAt: endedAt,
                rawLog: rawLog
            )
        }
    }
    
    public func insertLimitSnapshot(
        provider: String,
        toolName: String,
        modelName: String? = nil,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil,
        authType: String? = nil,
        planName: String? = nil,
        windowType: String,
        metricType: String,
        limitValue: Double?,
        remainingValue: Double?,
        usedValue: Double?,
        resetAt: Date?,
        resetAfterSeconds: Int? = nil,
        retryAfterSeconds: Int? = nil,
        source: String,
        sourceDetail: String? = nil,
        sourceURL: String? = nil,
        confidenceLevel: String,
        isOfficial: Bool,
        isEstimated: Bool = false,
        capturedAt: Date,
        expiresAt: Date? = nil,
        rawSnapshot: String? = nil,
        dedupeKey: String? = nil
    ) {
        queue.sync {
            let accountPart = accountFingerprint ?? "legacy"
            let key = dedupeKey ?? "\(provider):\(toolName):\(accountPart):\(windowType):\(metricType):\(timestampKey(capturedAt))"
            upsertLimitSnapshotLocked(
                dedupeKey: key,
                provider: provider,
                toolName: toolName,
                modelName: modelName,
                accountFingerprint: accountFingerprint,
                accountLabel: accountLabel,
                authType: authType,
                planName: planName,
                windowType: windowType,
                metricType: metricType,
                limitValue: limitValue,
                remainingValue: remainingValue,
                usedValue: usedValue,
                resetAt: resetAt,
                resetAfterSeconds: resetAfterSeconds,
                retryAfterSeconds: retryAfterSeconds,
                source: source,
                sourceDetail: sourceDetail,
                sourceURL: sourceURL,
                confidenceLevel: confidenceLevel,
                isOfficial: isOfficial,
                isEstimated: isEstimated,
                capturedAt: capturedAt,
                expiresAt: expiresAt,
                rawSnapshot: rawSnapshot
            )
        }
    }
    
    public func insertGeminiCall(
        timestamp: Date,
        url: String,
        traceId: String,
        isError: Int,
        errorMessage: String?,
        resetsAt: Date?,
        modelName: String? = nil,
        toolName: String = "gemini",
        accountFingerprint: String? = nil,
        accountLabel: String? = nil
    ) {
        queue.sync {
            let normalizedModel = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedModel = (normalizedModel?.isEmpty == false) ? normalizedModel : nil
            
            let sql = """
            INSERT INTO gemini_calls (
                timestamp, url, trace_id, is_error, error_message, resets_at,
                model_name, data_source, is_estimated, account_fingerprint, account_label
            ) VALUES (?, ?, ?, ?, ?, ?, ?, 'local_log', 1, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                url = CASE WHEN data_source = 'telemetry' THEN url ELSE excluded.url END,
                trace_id = CASE WHEN data_source = 'telemetry' THEN trace_id ELSE excluded.trace_id END,
                is_error = CASE WHEN data_source = 'telemetry' THEN is_error ELSE excluded.is_error END,
                error_message = COALESCE(excluded.error_message, error_message),
                resets_at = COALESCE(excluded.resets_at, resets_at),
                model_name = COALESCE(NULLIF(excluded.model_name, ''), model_name),
                account_fingerprint = COALESCE(account_fingerprint, excluded.account_fingerprint),
                account_label = COALESCE(account_label, excluded.account_label),
                data_source = CASE WHEN data_source = 'telemetry' THEN data_source ELSE 'local_log' END,
                is_estimated = CASE WHEN data_source = 'telemetry' THEN is_estimated ELSE 1 END;
            """
            var stmt: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("TokenPet SQLite: Prepare failed for insertGeminiCall")
                return
            }
            sqlite3_bind_double(stmt, 1, timestamp.timeIntervalSince1970)
            bindText(stmt, 2, url)
            bindText(stmt, 3, traceId)
            sqlite3_bind_int(stmt, 4, Int32(isError))
            
            if let err = errorMessage {
                bindText(stmt, 5, err)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            
            if let reset = resetsAt {
                sqlite3_bind_double(stmt, 6, reset.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            bindText(stmt, 7, storedModel)
            bindText(stmt, 8, accountFingerprint)
            bindText(stmt, 9, accountLabel)
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("TokenPet SQLite: Failed to upsert Gemini local call")
            }
            
            sqlite3_finalize(stmt)
            
            let status = isError == 1 ? "rate_limited" : "success"
            let statusCode = isError == 1 ? "429" : nil
            upsertAIUsageLogLocked(
                dedupeKey: "gemini:local:\(accountFingerprint ?? "legacy"):\(timestampKey(timestamp)):\(traceId):\(url)",
                provider: "google",
                toolName: toolName,
                modelName: storedModel,
                accountFingerprint: accountFingerprint,
                accountLabel: accountLabel,
                sessionId: nil,
                promptId: traceId.isEmpty ? nil : traceId,
                inputTokens: 0,
                outputTokens: 0,
                cachedTokens: 0,
                totalTokens: 0,
                durationMs: nil,
                status: status,
                statusCode: statusCode,
                errorMessage: errorMessage,
                dataSource: "local_log",
                isEstimated: false,
                confidenceLevel: isError == 1 ? "L2" : "L3",
                startedAt: timestamp,
                rawLog: errorMessage
            )
            
            if isError == 1 {
                let resetAfterSeconds = resetsAt.map { max(0, Int($0.timeIntervalSince(timestamp))) }
                let windowType: String
                if let resetAfterSeconds {
                    windowType = resetAfterSeconds <= 18060 ? "gemini_5h" : "gemini_24h"
                } else {
                    windowType = "gemini_rate_limit"
                }
                
                upsertLimitSnapshotLocked(
                    dedupeKey: "gemini:local:limit:\(accountFingerprint ?? "legacy"):\(storedModel ?? "unknown"):\(windowType):\(timestampKey(timestamp))",
                    provider: "google",
                    toolName: toolName,
                    modelName: storedModel,
                    accountFingerprint: accountFingerprint,
                    accountLabel: accountLabel,
                    windowType: windowType,
                    metricType: "requests",
                    limitValue: nil,
                    remainingValue: 0,
                    usedValue: nil,
                    resetAt: resetsAt,
                    resetAfterSeconds: resetAfterSeconds,
                    source: "local_log_429",
                    sourceDetail: "Antigravity/Gemini CLI 429 reset message",
                    confidenceLevel: "L3",
                    isOfficial: false,
                    isEstimated: false,
                    capturedAt: timestamp,
                    rawSnapshot: errorMessage
                )
            }
        }
    }
    
    public func insertGeminiTelemetryCall(
        timestamp: Date,
        event: String,
        model: String,
        promptId: String,
        authType: String,
        statusCode: String,
        durationMs: Int,
        inputTokens: Int,
        outputTokens: Int,
        cachedTokens: Int,
        thoughtsTokens: Int,
        toolTokens: Int,
        totalTokens: Int,
        isError: Int,
        errorMessage: String?,
        resetsAt: Date?,
        toolName: String = "gemini-cli",
        accountFingerprint: String? = nil,
        accountLabel: String? = nil
    ) {
        queue.sync {
            let t = timestamp.timeIntervalSince1970
            let r = resetsAt?.timeIntervalSince1970
            
            let sql = """
            INSERT INTO gemini_calls (
                timestamp, url, trace_id, is_error, error_message, resets_at,
                model_name, input_tokens, output_tokens, cached_tokens, thoughts_tokens,
                tool_tokens, total_tokens, duration_ms, status_code, data_source, is_estimated,
                account_fingerprint, account_label
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'telemetry', 0, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                is_error = excluded.is_error,
                error_message = excluded.error_message,
                resets_at = COALESCE(excluded.resets_at, resets_at),
                model_name = COALESCE(excluded.model_name, model_name),
                account_fingerprint = COALESCE(account_fingerprint, excluded.account_fingerprint),
                account_label = COALESCE(account_label, excluded.account_label),
                input_tokens = COALESCE(excluded.input_tokens, input_tokens),
                output_tokens = COALESCE(excluded.output_tokens, output_tokens),
                cached_tokens = COALESCE(excluded.cached_tokens, cached_tokens),
                thoughts_tokens = COALESCE(excluded.thoughts_tokens, thoughts_tokens),
                tool_tokens = COALESCE(excluded.tool_tokens, tool_tokens),
                total_tokens = COALESCE(excluded.total_tokens, total_tokens),
                duration_ms = COALESCE(excluded.duration_ms, duration_ms),
                status_code = COALESCE(excluded.status_code, status_code),
                data_source = 'telemetry';
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, t)
                sqlite3_bind_text(stmt, 2, "", -1, nil)
                sqlite3_bind_text(stmt, 3, (promptId as NSString).utf8String, -1, nil) // use prompt_id as trace_id
                sqlite3_bind_int(stmt, 4, Int32(isError))
                
                if let msg = errorMessage {
                    sqlite3_bind_text(stmt, 5, (msg as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }
                
                if let resets = r {
                    sqlite3_bind_double(stmt, 6, resets)
                } else {
                    sqlite3_bind_null(stmt, 6)
                }
                
                sqlite3_bind_text(stmt, 7, (model as NSString).utf8String, -1, nil)
                sqlite3_bind_int(stmt, 8, Int32(inputTokens))
                sqlite3_bind_int(stmt, 9, Int32(outputTokens))
                sqlite3_bind_int(stmt, 10, Int32(cachedTokens))
                sqlite3_bind_int(stmt, 11, Int32(thoughtsTokens))
                sqlite3_bind_int(stmt, 12, Int32(toolTokens))
                sqlite3_bind_int(stmt, 13, Int32(totalTokens))
                sqlite3_bind_int(stmt, 14, Int32(durationMs))
                sqlite3_bind_text(stmt, 15, (statusCode as NSString).utf8String, -1, nil)
                bindText(stmt, 16, accountFingerprint)
                bindText(stmt, 17, accountLabel)
                
                if sqlite3_step(stmt) != SQLITE_DONE {
                    print("TokenPet: Failed to insert Gemini Telemetry event to SQLite")
                }
            }
            sqlite3_finalize(stmt)
            
            upsertAIUsageLogLocked(
                dedupeKey: "gemini:telemetry:\(accountFingerprint ?? "legacy"):\(timestampKey(timestamp)):\(promptId):\(event)",
                provider: "google",
                toolName: toolName,
                modelName: model,
                accountFingerprint: accountFingerprint,
                accountLabel: accountLabel,
                sessionId: nil,
                promptId: promptId.isEmpty ? nil : promptId,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cachedTokens: cachedTokens,
                thoughtsTokens: thoughtsTokens,
                toolTokens: toolTokens,
                totalTokens: totalTokens,
                durationMs: durationMs,
                status: isError == 1 ? "rate_limited" : "success",
                statusCode: statusCode,
                errorMessage: errorMessage,
                dataSource: "telemetry",
                isEstimated: false,
                confidenceLevel: "L5",
                startedAt: timestamp,
                rawLog: errorMessage
            )
        }
    }
    
    public func insertCodexEvent(
        timestamp: Date,
        sessionId: String,
        input: Int,
        output: Int,
        cached: Int,
        used5h: Double?,
        resetsAt5h: Date?,
        used7d: Double?,
        resetsAt7d: Date?,
        plan: String?,
        accountFingerprint: String? = nil,
        accountLabel: String? = nil
    ) {
        queue.sync {
            let sql = """
            INSERT INTO codex_events (
                timestamp, session_id, account_fingerprint, account_label, input_tokens, output_tokens, cached_tokens,
                used_percent_5h, resets_at_5h, used_percent_7d, resets_at_7d, plan_type
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(timestamp) DO UPDATE SET
                session_id = COALESCE(excluded.session_id, session_id),
                account_fingerprint = COALESCE(account_fingerprint, excluded.account_fingerprint),
                account_label = COALESCE(account_label, excluded.account_label),
                input_tokens = CASE WHEN excluded.input_tokens > 0 THEN excluded.input_tokens ELSE input_tokens END,
                output_tokens = CASE WHEN excluded.output_tokens > 0 THEN excluded.output_tokens ELSE output_tokens END,
                cached_tokens = CASE WHEN excluded.cached_tokens > 0 THEN excluded.cached_tokens ELSE cached_tokens END,
                used_percent_5h = COALESCE(excluded.used_percent_5h, used_percent_5h),
                resets_at_5h = COALESCE(excluded.resets_at_5h, resets_at_5h),
                used_percent_7d = COALESCE(excluded.used_percent_7d, used_percent_7d),
                resets_at_7d = COALESCE(excluded.resets_at_7d, resets_at_7d),
                plan_type = COALESCE(excluded.plan_type, plan_type);
            """
            var stmt: OpaquePointer?
            
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                print("TokenPet SQLite: Prepare failed for insertCodexEvent")
                return
            }
            
            sqlite3_bind_double(stmt, 1, timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, (sessionId as NSString).utf8String, -1, nil)
            bindText(stmt, 3, accountFingerprint)
            bindText(stmt, 4, accountLabel)
            sqlite3_bind_int(stmt, 5, Int32(input))
            sqlite3_bind_int(stmt, 6, Int32(output))
            sqlite3_bind_int(stmt, 7, Int32(cached))
            
            if let u5h = used5h {
                sqlite3_bind_double(stmt, 8, u5h)
            } else {
                sqlite3_bind_null(stmt, 8)
            }
            
            if let r5h = resetsAt5h {
                sqlite3_bind_double(stmt, 9, r5h.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            
            if let u7d = used7d {
                sqlite3_bind_double(stmt, 10, u7d)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            
            if let r7d = resetsAt7d {
                sqlite3_bind_double(stmt, 11, r7d.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 11)
            }
            
            if let p = plan {
                sqlite3_bind_text(stmt, 12, (p as NSString).utf8String, -1, nil)
            } else {
                sqlite3_bind_null(stmt, 12)
            }
            
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("TokenPet SQLite: Failed to execute insertCodexEvent")
            }
            
            sqlite3_finalize(stmt)
            
            if input > 0 || output > 0 || cached > 0 {
                upsertAIUsageLogLocked(
                    dedupeKey: "codex:local:\(accountFingerprint ?? "legacy"):\(sessionId):\(timestampKey(timestamp)):\(input):\(output):\(cached)",
                    provider: "openai",
                    toolName: "codex",
                    modelName: nil,
                    accountFingerprint: accountFingerprint,
                    accountLabel: accountLabel,
                    sessionId: sessionId,
                    promptId: nil,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: cached,
                    totalTokens: input + output + cached,
                    durationMs: nil,
                    status: "success",
                    statusCode: nil,
                    errorMessage: nil,
                    dataSource: "local_log",
                    isEstimated: false,
                    confidenceLevel: "L3",
                    startedAt: timestamp
                )
            }
            
            if let used5h = used5h {
                let remaining = max(0, 100 - used5h)
                upsertLimitSnapshotLocked(
                    dedupeKey: "codex:limit:\(accountFingerprint ?? "legacy"):5h:\(timestampKey(timestamp))",
                    provider: "openai",
                    toolName: "codex",
                    accountFingerprint: accountFingerprint,
                    accountLabel: accountLabel,
                    planName: plan,
                    windowType: "codex_5h",
                    metricType: "percent",
                    limitValue: 100,
                    remainingValue: remaining,
                    usedValue: used5h,
                    resetAt: resetsAt5h,
                    source: "codex_local_log",
                    sourceDetail: "Codex local rate limit event",
                    confidenceLevel: "L4",
                    isOfficial: true,
                    isEstimated: false,
                    capturedAt: timestamp
                )
            }
            
            if let used7d = used7d {
                let remaining = max(0, 100 - used7d)
                upsertLimitSnapshotLocked(
                    dedupeKey: "codex:limit:\(accountFingerprint ?? "legacy"):weekly:\(timestampKey(timestamp))",
                    provider: "openai",
                    toolName: "codex",
                    accountFingerprint: accountFingerprint,
                    accountLabel: accountLabel,
                    planName: plan,
                    windowType: "codex_weekly",
                    metricType: "percent",
                    limitValue: 100,
                    remainingValue: remaining,
                    usedValue: used7d,
                    resetAt: resetsAt7d,
                    source: "codex_local_log",
                    sourceDetail: "Codex local rate limit event",
                    confidenceLevel: "L4",
                    isOfficial: true,
                    isEstimated: false,
                    capturedAt: timestamp
                )
            }
        }
    }
    
    // MARK: - Query Operations
    
    public func getGeminiStats(now: Date) -> (
        calls5h: Int,
        calls24h: Int,
        calls7d: Int,
        activeError5hResetsAt: Date?,
        activeError24hResetsAt: Date?,
        activeErrorResetsAt: Date?,
        activeErrorMessage: String?,
        inferredLimit5h: Int?,
        inferredLimit24h: Int?,
        errorCount7d: Int,
        tokenSummary: GeminiTokenUsageSummary,
        modelUsages: [GeminiModelUsage]
    ) {
        return queue.sync {
            let geminiIdentities = AccountIdentityManager.currentGeminiToolIdentities()
            let accountSQL = accountPredicate(column: "account_fingerprint", identities: geminiIdentities)
            let validAfter = latestValidAfterTimestamp(geminiIdentities)
            let tNow = now.timeIntervalSince1970
            let tAccount = validAfter ?? 0
            let t5h = max(tNow - (5 * 60 * 60), tAccount)
            let t24h = max(tNow - (24 * 60 * 60), tAccount)
            let t7d = max(tNow - (7 * 24 * 60 * 60), tAccount)
            
            var calls5h = 0
            var calls24h = 0
            var calls7d = 0
            var activeError5hResetsAt: Date? = nil
            var activeError24hResetsAt: Date? = nil
            var activeErrorResetsAt: Date? = nil
            var activeErrorMessage: String? = nil
            var inferredLimit5h: Int? = nil
            var inferredLimit24h: Int? = nil
            var errorCount7d = 0
            var modelUsages: [GeminiModelUsage] = []
            
            func stringColumn(_ stmt: OpaquePointer?, _ column: Int32) -> String? {
                guard let cStr = sqlite3_column_text(stmt, column) else {
                    return nil
                }
                let value = String(cString: cStr).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            
            func countGeminiCalls(since timestamp: Double) -> Int {
                let sql = """
                SELECT
                    (SELECT COUNT(*) FROM gemini_calls
                     WHERE timestamp >= ?
                       AND \(accountSQL)
                       AND is_error = 0
                       AND data_source = 'telemetry'
                       AND (
                           total_tokens > 0
                           OR duration_ms > 0
                           OR (status_code IS NOT NULL AND status_code NOT IN ('', '200'))
                       )),
                    (SELECT COUNT(*) FROM gemini_calls
                     WHERE timestamp >= ?
                       AND \(accountSQL)
                       AND is_error = 0
                       AND (data_source IS NULL OR data_source != 'telemetry'));
                """
                var stmt: OpaquePointer?
                var telemetryCount = 0
                var localCount = 0
                
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_double(stmt, 1, timestamp)
                    sqlite3_bind_double(stmt, 2, timestamp)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        telemetryCount = Int(sqlite3_column_int(stmt, 0))
                        localCount = Int(sqlite3_column_int(stmt, 1))
                    }
                }
                sqlite3_finalize(stmt)
                
                return telemetryCount > 0 ? telemetryCount : localCount
            }
            
            func hasValidTelemetry(since timestamp: Double) -> Bool {
                let sql = """
                SELECT COUNT(*) FROM gemini_calls
                WHERE timestamp >= ?
                  AND \(accountSQL)
                  AND data_source = 'telemetry'
                  AND (
                      total_tokens > 0
                      OR duration_ms > 0
                      OR (status_code IS NOT NULL AND status_code NOT IN ('', '200'))
                  );
                """
                var stmt: OpaquePointer?
                var count = 0
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_double(stmt, 1, timestamp)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        count = Int(sqlite3_column_int(stmt, 0))
                    }
                }
                sqlite3_finalize(stmt)
                return count > 0
            }
            
            func hasSuccessAfter(timestamp: Double, modelName: String?) -> Bool {
                let sql: String
                if modelName == nil {
                    sql = """
                    SELECT MAX(timestamp) FROM gemini_calls
                    WHERE is_error = 0
                      AND \(accountSQL)
                      AND (model_name IS NULL OR model_name = '')
                      AND timestamp > ?;
                    """
                } else {
                    sql = """
                    SELECT MAX(timestamp) FROM gemini_calls
                    WHERE is_error = 0
                      AND \(accountSQL)
                      AND model_name = ?
                      AND timestamp > ?;
                    """
                }
                
                var stmt: OpaquePointer?
                var cleared = false
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    if let modelName {
                        bindText(stmt, 1, modelName)
                        sqlite3_bind_double(stmt, 2, timestamp)
                    } else {
                        sqlite3_bind_double(stmt, 1, timestamp)
                    }
                    
                    if sqlite3_step(stmt) == SQLITE_ROW,
                       sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                        cleared = sqlite3_column_double(stmt, 0) > timestamp
                    }
                }
                sqlite3_finalize(stmt)
                return cleared
            }
            
            calls5h = countGeminiCalls(since: t5h)
            calls24h = countGeminiCalls(since: t24h)
            calls7d = countGeminiCalls(since: t7d)
            
            // Get 7d 429 error count
            let sqlErrCount = "SELECT COUNT(*) FROM gemini_calls WHERE timestamp >= ? AND \(accountSQL) AND is_error = 1;"
            var stmtErrCount: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlErrCount, -1, &stmtErrCount, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtErrCount, 1, t7d)
                if sqlite3_step(stmtErrCount) == SQLITE_ROW {
                    errorCount7d = Int(sqlite3_column_int(stmtErrCount, 0))
                }
            }
            sqlite3_finalize(stmtErrCount)
            
            // 3. Get active errors that reset in the future
            let sqlErr = "SELECT resets_at, error_message, timestamp, model_name FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at > ? ORDER BY timestamp DESC LIMIT 5;"
            var stmtErr: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlErr, -1, &stmtErr, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtErr, 1, tNow)
                while sqlite3_step(stmtErr) == SQLITE_ROW {
                    let rAt = sqlite3_column_double(stmtErr, 0)
                    let errTs = sqlite3_column_double(stmtErr, 2)
                    let duration = rAt - errTs
                    
                    var msg: String? = nil
                    if let cStr = sqlite3_column_text(stmtErr, 1) {
                        msg = String(cString: cStr)
                    }
                    
                    let modelName = stringColumn(stmtErr, 3)
                    let errorCleared = hasSuccessAfter(timestamp: errTs, modelName: modelName)
                    
                    if !errorCleared {
                        let resetDate = Date(timeIntervalSince1970: rAt)
                        if duration <= 18060 { // 5 hours + 60s
                            if activeError5hResetsAt == nil {
                                activeError5hResetsAt = resetDate
                            }
                        } else {
                            if activeError24hResetsAt == nil {
                                activeError24hResetsAt = resetDate
                            }
                        }
                        if activeErrorResetsAt == nil {
                            activeErrorResetsAt = resetDate
                        }
                        if activeErrorMessage == nil {
                            activeErrorMessage = msg
                        }
                    }
                }
            }
            sqlite3_finalize(stmtErr)
            
            // 4. Infer 5h limit from latest 5h error
            let sqlInfer5h = """
            SELECT COUNT(*) FROM gemini_calls
            WHERE is_error = 0
              AND \(accountSQL)
              AND timestamp >= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp <= 18060 ORDER BY timestamp DESC LIMIT 1) - 18000
              AND timestamp <= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp <= 18060 ORDER BY timestamp DESC LIMIT 1);
            """
            var stmtInfer5h: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlInfer5h, -1, &stmtInfer5h, nil) == SQLITE_OK {
                if sqlite3_step(stmtInfer5h) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmtInfer5h, 0))
                    if count > 0 {
                        inferredLimit5h = count
                    }
                }
            }
            sqlite3_finalize(stmtInfer5h)
            
            // Infer 24h limit from latest 24h error
            let sqlInfer24h = """
            SELECT COUNT(*) FROM gemini_calls
            WHERE is_error = 0
              AND \(accountSQL)
              AND timestamp >= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp > 18060 ORDER BY timestamp DESC LIMIT 1) - 86400
              AND timestamp <= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp > 18060 ORDER BY timestamp DESC LIMIT 1);
            """
            var stmtInfer24h: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlInfer24h, -1, &stmtInfer24h, nil) == SQLITE_OK {
                if sqlite3_step(stmtInfer24h) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmtInfer24h, 0))
                    if count > 0 {
                        inferredLimit24h = count
                    }
                }
            }
            sqlite3_finalize(stmtInfer24h)
            
            // 5. Aggregate 5h Tokens
            var in5h = 0, out5h = 0, cache5h = 0, thought5h = 0, tool5h = 0, tot5h = 0
            let sqlTok5h = """
            SELECT SUM(input_tokens), SUM(output_tokens), SUM(cached_tokens),
                   SUM(thoughts_tokens), SUM(tool_tokens), SUM(total_tokens)
            FROM gemini_calls WHERE timestamp >= ? AND \(accountSQL);
            """
            var stmtTok5h: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlTok5h, -1, &stmtTok5h, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtTok5h, 1, t5h)
                if sqlite3_step(stmtTok5h) == SQLITE_ROW {
                    in5h = Int(sqlite3_column_int(stmtTok5h, 0))
                    out5h = Int(sqlite3_column_int(stmtTok5h, 1))
                    cache5h = Int(sqlite3_column_int(stmtTok5h, 2))
                    thought5h = Int(sqlite3_column_int(stmtTok5h, 3))
                    tool5h = Int(sqlite3_column_int(stmtTok5h, 4))
                    tot5h = Int(sqlite3_column_int(stmtTok5h, 5))
                }
            }
            sqlite3_finalize(stmtTok5h)
            
            // 6. Aggregate 7d Tokens
            var in7d = 0, out7d = 0, cache7d = 0, thought7d = 0, tool7d = 0, tot7d = 0
            let sqlTok7d = """
            SELECT SUM(input_tokens), SUM(output_tokens), SUM(cached_tokens),
                   SUM(thoughts_tokens), SUM(tool_tokens), SUM(total_tokens)
            FROM gemini_calls WHERE timestamp >= ? AND \(accountSQL);
            """
            var stmtTok7d: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlTok7d, -1, &stmtTok7d, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtTok7d, 1, t7d)
                if sqlite3_step(stmtTok7d) == SQLITE_ROW {
                    in7d = Int(sqlite3_column_int(stmtTok7d, 0))
                    out7d = Int(sqlite3_column_int(stmtTok7d, 1))
                    cache7d = Int(sqlite3_column_int(stmtTok7d, 2))
                    thought7d = Int(sqlite3_column_int(stmtTok7d, 3))
                    tool7d = Int(sqlite3_column_int(stmtTok7d, 4))
                    tot7d = Int(sqlite3_column_int(stmtTok7d, 5))
                }
            }
            sqlite3_finalize(stmtTok7d)
            
            let tokSummary = GeminiTokenUsageSummary(
                inputTokens5h: in5h,
                outputTokens5h: out5h,
                cachedTokens5h: cache5h,
                thoughtsTokens5h: thought5h,
                toolTokens5h: tool5h,
                totalTokens5h: tot5h,
                inputTokens7d: in7d,
                outputTokens7d: out7d,
                cachedTokens7d: cache7d,
                thoughtsTokens7d: thought7d,
                toolTokens7d: tool7d,
                totalTokens7d: tot7d
            )
            
            let useTelemetryForModels = hasValidTelemetry(since: t7d)
            let modelSourcePredicate: String
            if useTelemetryForModels {
                modelSourcePredicate = """
                data_source = 'telemetry'
                AND (
                    total_tokens > 0
                    OR duration_ms > 0
                    OR (status_code IS NOT NULL AND status_code NOT IN ('', '200'))
                )
                """
            } else {
                modelSourcePredicate = "(data_source IS NULL OR data_source != 'telemetry')"
            }
            
            func unifyModelName(_ name: String?) -> String {
                guard let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "未知模型" }
                return SQLiteManager.mapToAntigravityModelName(name)
            }

            var modelUsageByName: [String: GeminiModelUsage] = [:]
            let sqlModelUsage = """
            SELECT
                model_name,
                SUM(CASE WHEN timestamp >= ? AND is_error = 0 THEN 1 ELSE 0 END) AS calls_5h,
                SUM(CASE WHEN timestamp >= ? AND is_error = 0 THEN 1 ELSE 0 END) AS calls_24h,
                SUM(CASE WHEN timestamp >= ? AND is_error = 0 THEN 1 ELSE 0 END) AS calls_7d,
                SUM(CASE WHEN timestamp >= ? AND is_error = 1 THEN 1 ELSE 0 END) AS errors_7d,
                
                SUM(CASE WHEN timestamp >= ? THEN input_tokens ELSE 0 END) AS input_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN output_tokens ELSE 0 END) AS output_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN cached_tokens ELSE 0 END) AS cached_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN thoughts_tokens ELSE 0 END) AS thoughts_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN tool_tokens ELSE 0 END) AS tool_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN total_tokens ELSE 0 END) AS total_tokens_5h,
                SUM(CASE WHEN timestamp >= ? THEN duration_ms ELSE 0 END) AS duration_ms_5h
            FROM gemini_calls
            WHERE timestamp >= ?
              AND \(accountSQL)
              AND \(modelSourcePredicate)
            GROUP BY model_name;
            """
            var stmtModel: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlModelUsage, -1, &stmtModel, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtModel, 1, t5h)
                sqlite3_bind_double(stmtModel, 2, t24h)
                sqlite3_bind_double(stmtModel, 3, t7d)
                sqlite3_bind_double(stmtModel, 4, t7d)
                sqlite3_bind_double(stmtModel, 5, t5h)
                sqlite3_bind_double(stmtModel, 6, t5h)
                sqlite3_bind_double(stmtModel, 7, t5h)
                sqlite3_bind_double(stmtModel, 8, t5h)
                sqlite3_bind_double(stmtModel, 9, t5h)
                sqlite3_bind_double(stmtModel, 10, t5h)
                sqlite3_bind_double(stmtModel, 11, t5h)
                sqlite3_bind_double(stmtModel, 12, t7d)
                
                while sqlite3_step(stmtModel) == SQLITE_ROW {
                    let rawName = stringColumn(stmtModel, 0)
                    let modelName = unifyModelName(rawName)
                    
                    let c5h = Int(sqlite3_column_int(stmtModel, 1))
                    let c24h = Int(sqlite3_column_int(stmtModel, 2))
                    let c7d = Int(sqlite3_column_int(stmtModel, 3))
                    let err7d = Int(sqlite3_column_int(stmtModel, 4))
                    
                    let in5h = Int(sqlite3_column_int(stmtModel, 5))
                    let out5h = Int(sqlite3_column_int(stmtModel, 6))
                    let cache5h = Int(sqlite3_column_int(stmtModel, 7))
                    let thoughts5h = Int(sqlite3_column_int(stmtModel, 8))
                    let tool5h = Int(sqlite3_column_int(stmtModel, 9))
                    let tot5h = Int(sqlite3_column_int(stmtModel, 10))
                    let dur5h = Double(sqlite3_column_double(stmtModel, 11))
                    
                    var usage = modelUsageByName[modelName] ?? GeminiModelUsage(modelName: modelName)
                    usage.calls5h += c5h
                    usage.calls24h += c24h
                    usage.calls7d += c7d
                    usage.errorCount7d += err7d
                    
                    usage.inputTokens5h += in5h
                    usage.outputTokens5h += out5h
                    usage.cachedTokens5h += cache5h
                    usage.thoughtsTokens5h += thoughts5h
                    usage.toolTokens5h += tool5h
                    usage.totalTokens5h += tot5h
                    usage.avgDurationMs5h += dur5h
                    
                    modelUsageByName[modelName] = usage
                }
            }
            sqlite3_finalize(stmtModel)
            
            // Divide total duration by calls5h to get average
            for name in modelUsageByName.keys {
                if var usage = modelUsageByName[name] {
                    let totalCalls = usage.calls5h
                    if totalCalls > 0 {
                        usage.avgDurationMs5h = usage.avgDurationMs5h / Double(totalCalls)
                    } else {
                        usage.avgDurationMs5h = 0.0
                    }
                    modelUsageByName[name] = usage
                }
            }
            
            let sqlModelReset = """
            SELECT model_name, resets_at, error_message, timestamp
            FROM gemini_calls
            WHERE is_error = 1
              AND \(accountSQL)
              AND resets_at > ?
            ORDER BY timestamp DESC;
            """
            var stmtModelReset: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlModelReset, -1, &stmtModelReset, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtModelReset, 1, tNow)
                
                while sqlite3_step(stmtModelReset) == SQLITE_ROW {
                    let rawModelName = stringColumn(stmtModelReset, 0)
                    let modelName = unifyModelName(rawModelName)
                    let resetAt = Date(timeIntervalSince1970: sqlite3_column_double(stmtModelReset, 1))
                    let message = stringColumn(stmtModelReset, 2)
                    let errorTimestamp = sqlite3_column_double(stmtModelReset, 3)
                    
                    guard !hasSuccessAfter(timestamp: errorTimestamp, modelName: rawModelName) else {
                        continue
                    }
                    
                    var usage = modelUsageByName[modelName] ?? GeminiModelUsage(modelName: modelName)
                    if usage.activeResetAt == nil {
                        usage.activeResetAt = resetAt
                        usage.activeErrorMessage = message
                    }
                    modelUsageByName[modelName] = usage
                }
            }
            sqlite3_finalize(stmtModelReset)
            
            modelUsages = Array(modelUsageByName.values.sorted { lhs, rhs in
                let lhsActive = lhs.activeResetAt.map { $0 > now } ?? false
                let rhsActive = rhs.activeResetAt.map { $0 > now } ?? false
                
                if lhsActive != rhsActive {
                    return lhsActive && !rhsActive
                }
                if lhs.modelName == "未知模型", rhs.modelName != "未知模型" {
                    return false
                }
                if rhs.modelName == "未知模型", lhs.modelName != "未知模型" {
                    return true
                }
                if lhs.calls5h != rhs.calls5h {
                    return lhs.calls5h > rhs.calls5h
                }
                if lhs.calls24h != rhs.calls24h {
                    return lhs.calls24h > rhs.calls24h
                }
                if lhs.calls7d != rhs.calls7d {
                    return lhs.calls7d > rhs.calls7d
                }
                return lhs.modelName < rhs.modelName
            }.prefix(8))
            
            return (
                calls5h: calls5h,
                calls24h: calls24h,
                calls7d: calls7d,
                activeError5hResetsAt: activeError5hResetsAt,
                activeError24hResetsAt: activeError24hResetsAt,
                activeErrorResetsAt: activeErrorResetsAt,
                activeErrorMessage: activeErrorMessage,
                inferredLimit5h: inferredLimit5h,
                inferredLimit24h: inferredLimit24h,
                errorCount7d: errorCount7d,
                tokenSummary: tokSummary,
                modelUsages: modelUsages
            )
        }
    }
    
    public func getGeminiToolUsageBreakdown(now: Date) -> GeminiToolUsageBreakdown {
        return queue.sync {
            let identities = AccountIdentityManager.currentGeminiToolIdentities()
            let accountSQL = accountPredicate(column: "account_fingerprint", identities: identities)
            let validAfter = latestValidAfterTimestamp(identities)
            let t24h = max(now.timeIntervalSince1970 - (24 * 60 * 60), validAfter ?? 0)
            
            var geminiCliCalls = 0
            var antigravityCalls = 0
            var legacyGeminiCalls = 0
            var latestTool: String? = nil
            
            let sql = """
            SELECT tool_name, account_label, COUNT(*), MAX(started_at)
            FROM ai_usage_log
            WHERE provider = 'google'
              AND started_at >= ?
              AND \(accountSQL)
            GROUP BY tool_name, account_label
            ORDER BY MAX(started_at) DESC;
            """
            
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_double(stmt, 1, t24h)
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let tool = stringColumn(stmt, 0) ?? "unknown"
                    let label = stringColumn(stmt, 1) ?? ""
                    let count = Int(sqlite3_column_int(stmt, 2))
                    
                    if latestTool == nil {
                        latestTool = tool
                    }
                    
                    if tool == "gemini-cli" {
                        geminiCliCalls += count
                    } else if tool == "antigravity-cli" || label.contains("反重力") {
                        antigravityCalls += count
                    } else if tool == "gemini" {
                        legacyGeminiCalls += count
                    }
                }
            }
            sqlite3_finalize(stmt)
            
            return GeminiToolUsageBreakdown(
                geminiCliCalls24h: geminiCliCalls,
                antigravityCalls24h: antigravityCalls,
                legacyGeminiCalls24h: legacyGeminiCalls,
                latestToolName: latestTool
            )
        }
    }
    
    public func getCodexStats(now: Date) -> (
        rateLimits: CodexRateLimits?,
        tokenSummary: TokenUsageSummary
    ) {
        return queue.sync {
            let codexIdentity = AccountIdentityManager.currentCodexIdentity()
            let codexIdentities = [codexIdentity]
            let accountSQL = accountPredicate(column: "account_fingerprint", identities: codexIdentities)
            let validAfter = latestValidAfterTimestamp(codexIdentities)
            let tNow = now.timeIntervalSince1970
            let tAccount = validAfter ?? 0
            let t5h = max(tNow - (5 * 60 * 60), tAccount)
            let t7d = max(tNow - (7 * 24 * 60 * 60), tAccount)
            
            // 1. Get latest rate limits
            var rateLimits: CodexRateLimits? = nil
            let sqlRL = """
            SELECT used_percent_5h, resets_at_5h, used_percent_7d, resets_at_7d, plan_type, timestamp, account_label
            FROM codex_events
            WHERE used_percent_5h IS NOT NULL
              AND timestamp >= ?
              AND \(accountSQL)
            ORDER BY timestamp DESC LIMIT 1;
            """
            var stmtRL: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlRL, -1, &stmtRL, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtRL, 1, tAccount)
                if sqlite3_step(stmtRL) == SQLITE_ROW {
                    let u5h = sqlite3_column_double(stmtRL, 0)
                    let r5h = sqlite3_column_double(stmtRL, 1)
                    let u7d = sqlite3_column_double(stmtRL, 2)
                    let r7d = sqlite3_column_double(stmtRL, 3)
                    
                    var plan = "plus"
                    if let pStr = sqlite3_column_text(stmtRL, 4) {
                        plan = String(cString: pStr)
                    }
                    
                    let ts = sqlite3_column_double(stmtRL, 5)
                    let accountLabel = stringColumn(stmtRL, 6) ?? codexIdentity.label
                    
                    // Expiry checks
                    let resetsAt5h = Date(timeIntervalSince1970: r5h)
                    let resetsAt7d = Date(timeIntervalSince1970: r7d)
                    
                    let used5h = u5h
                    let used7d = u7d
                    
                    rateLimits = CodexRateLimits(
                        primary5hUsedPercent: used5h,
                        primary5hResetsAt: resetsAt5h,
                        secondary7dUsedPercent: used7d,
                        secondary7dResetsAt: resetsAt7d,
                        planType: plan,
                        sessionTimestamp: Date(timeIntervalSince1970: ts),
                        accountLabel: accountLabel
                    )
                }
            }
            sqlite3_finalize(stmtRL)
            
            // 2. Aggregate token counts
            var in5h = 0, out5h = 0, cached5h = 0
            var in7d = 0, out7d = 0, cached7d = 0
            var sCount5h = 0, sCount7d = 0
            
            let sqlSum = """
            SELECT
                SUM(CASE WHEN timestamp >= ? THEN input_tokens ELSE 0 END),
                SUM(CASE WHEN timestamp >= ? THEN output_tokens ELSE 0 END),
                SUM(CASE WHEN timestamp >= ? THEN cached_tokens ELSE 0 END),
                SUM(CASE WHEN timestamp >= ? THEN input_tokens ELSE 0 END),
                SUM(CASE WHEN timestamp >= ? THEN output_tokens ELSE 0 END),
                SUM(CASE WHEN timestamp >= ? THEN cached_tokens ELSE 0 END),
                COUNT(DISTINCT CASE WHEN timestamp >= ? THEN session_id ELSE NULL END),
                COUNT(DISTINCT CASE WHEN timestamp >= ? THEN session_id ELSE NULL END)
            FROM codex_events
            WHERE \(accountSQL);
            """
            
            var stmtSum: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlSum, -1, &stmtSum, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtSum, 1, t5h)
                sqlite3_bind_double(stmtSum, 2, t5h)
                sqlite3_bind_double(stmtSum, 3, t5h)
                sqlite3_bind_double(stmtSum, 4, t7d)
                sqlite3_bind_double(stmtSum, 5, t7d)
                sqlite3_bind_double(stmtSum, 6, t7d)
                sqlite3_bind_double(stmtSum, 7, t5h)
                sqlite3_bind_double(stmtSum, 8, t7d)
                
                if sqlite3_step(stmtSum) == SQLITE_ROW {
                    in5h = Int(sqlite3_column_int(stmtSum, 0))
                    out5h = Int(sqlite3_column_int(stmtSum, 1))
                    cached5h = Int(sqlite3_column_int(stmtSum, 2))
                    in7d = Int(sqlite3_column_int(stmtSum, 3))
                    out7d = Int(sqlite3_column_int(stmtSum, 4))
                    cached7d = Int(sqlite3_column_int(stmtSum, 5))
                    sCount5h = Int(sqlite3_column_int(stmtSum, 6))
                    sCount7d = Int(sqlite3_column_int(stmtSum, 7))
                }
            }
            sqlite3_finalize(stmtSum)
            
            let summary = TokenUsageSummary(
                inputTokens5h: in5h,
                outputTokens5h: out5h,
                cachedInputTokens5h: cached5h,
                inputTokens7d: in7d,
                outputTokens7d: out7d,
                cachedInputTokens7d: cached7d,
                sessionCount5h: sCount5h,
                sessionCount7d: sCount7d
            )
            
            return (rateLimits, summary)
        }
    }
    
    public func getAntigravityStats(now: Date) -> GoogleToolUsageStats {
        return queue.sync {
            let identities = AccountIdentityManager.currentGeminiToolIdentities()
            // antigravity-cli's credential file is unstable: the file may not exist, appear,
            // or rotate, generating a new fingerprint each time. This splits records across
            // 2-3+ different fingerprints all representing the same account. Skip fingerprint
            // filtering for antigravity-cli so ALL historical records are counted.
            // Only use gemini-cli identity for validAfter (its credential file is stable).
            let geminiOnlyIdentities = identities.filter { $0.toolName != "antigravity-cli" }
            let geminiAccountSQL = accountPredicate(column: "account_fingerprint", identities: identities)
            // Alias used by gemini_calls queries (error detection, infer limits, model usage)
            // which are all gemini-cli telemetry and can stay fingerprint-filtered.
            let accountSQL = geminiAccountSQL
            let validAfter = latestValidAfterTimestamp(geminiOnlyIdentities)
            let tNow = now.timeIntervalSince1970
            let tAccount = validAfter ?? 0
            let t5h = max(tNow - (5 * 60 * 60), tAccount)
            let t24h = max(tNow - (24 * 60 * 60), tAccount)
            let t7d = max(tNow - (7 * 24 * 60 * 60), tAccount)
            // For antigravity-cli: no fingerprint filter (all historical records included)
            // For gemini/gemini-cli: fingerprint-filtered as usual
            let baseToolSQL = "(tool_name = 'antigravity-cli' OR (tool_name = 'gemini' AND \(geminiAccountSQL)) OR (tool_name = 'gemini-cli' AND \(geminiAccountSQL)))"
            let chatToolSQL = "(tool_name = 'antigravity-cli' AND data_source = 'antigravity_chat_jsonl')"
            let successSQL = "(COALESCE(status, 'success') != 'rate_limited' AND COALESCE(status_code, '') != '429')"
            let errorSQL = "(COALESCE(status, '') = 'rate_limited' OR COALESCE(status_code, '') = '429')"
            
            var hasChatUsage = false
            let sqlHasChat = """
            SELECT 1
            FROM ai_usage_log
            WHERE provider = 'google'
              AND \(chatToolSQL)
              AND started_at >= ?
            LIMIT 1;
            """
            var stmtHasChat: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlHasChat, -1, &stmtHasChat, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtHasChat, 1, t7d)
                hasChatUsage = sqlite3_step(stmtHasChat) == SQLITE_ROW
            }
            sqlite3_finalize(stmtHasChat)
            
            let usageToolSQL = hasChatUsage ? chatToolSQL : baseToolSQL
            
            var calls5h = 0
            var calls24h = 0
            var calls7d = 0
            var errorCount7d = 0
            
            let sqlCounts = """
            SELECT
                SUM(CASE WHEN started_at >= ? AND \(usageToolSQL) AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(usageToolSQL) AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(usageToolSQL) AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(baseToolSQL) AND \(errorSQL) THEN 1 ELSE 0 END)
            FROM ai_usage_log
            WHERE provider = 'google'
              AND \(accountSQL);
            """
            
            var stmtCounts: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlCounts, -1, &stmtCounts, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtCounts, 1, t5h)
                sqlite3_bind_double(stmtCounts, 2, t24h)
                sqlite3_bind_double(stmtCounts, 3, t7d)
                sqlite3_bind_double(stmtCounts, 4, t7d)
                if sqlite3_step(stmtCounts) == SQLITE_ROW {
                    calls5h = Int(sqlite3_column_int(stmtCounts, 0))
                    calls24h = Int(sqlite3_column_int(stmtCounts, 1))
                    calls7d = Int(sqlite3_column_int(stmtCounts, 2))
                    errorCount7d = Int(sqlite3_column_int(stmtCounts, 3))
                }
            }
            sqlite3_finalize(stmtCounts)
            
            var in5h = 0, out5h = 0, cache5h = 0, thought5h = 0, tool5h = 0, total5h = 0
            var in7d = 0, out7d = 0, cache7d = 0, thought7d = 0, tool7d = 0, total7d = 0
            
            let sqlTokens = """
            SELECT
                SUM(CASE WHEN started_at >= ? THEN input_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN output_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN cached_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN thoughts_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN tool_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN total_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN input_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN output_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN cached_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN thoughts_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN tool_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN total_tokens ELSE 0 END)
            FROM ai_usage_log
            WHERE provider = 'google'
              AND \(usageToolSQL)
              AND \(accountSQL);
            """
            
            var stmtTokens: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlTokens, -1, &stmtTokens, nil) == SQLITE_OK {
                for index in 1...6 {
                    sqlite3_bind_double(stmtTokens, Int32(index), t5h)
                }
                for index in 7...12 {
                    sqlite3_bind_double(stmtTokens, Int32(index), t7d)
                }
                if sqlite3_step(stmtTokens) == SQLITE_ROW {
                    in5h = Int(sqlite3_column_int(stmtTokens, 0))
                    out5h = Int(sqlite3_column_int(stmtTokens, 1))
                    cache5h = Int(sqlite3_column_int(stmtTokens, 2))
                    thought5h = Int(sqlite3_column_int(stmtTokens, 3))
                    tool5h = Int(sqlite3_column_int(stmtTokens, 4))
                    total5h = Int(sqlite3_column_int(stmtTokens, 5))
                    in7d = Int(sqlite3_column_int(stmtTokens, 6))
                    out7d = Int(sqlite3_column_int(stmtTokens, 7))
                    cache7d = Int(sqlite3_column_int(stmtTokens, 8))
                    thought7d = Int(sqlite3_column_int(stmtTokens, 9))
                    tool7d = Int(sqlite3_column_int(stmtTokens, 10))
                    total7d = Int(sqlite3_column_int(stmtTokens, 11))
                }
            }
            sqlite3_finalize(stmtTokens)
            
            let tokenSummary = GeminiTokenUsageSummary(
                inputTokens5h: in5h,
                outputTokens5h: out5h,
                cachedTokens5h: cache5h,
                thoughtsTokens5h: thought5h,
                toolTokens5h: tool5h,
                totalTokens5h: total5h,
                inputTokens7d: in7d,
                outputTokens7d: out7d,
                cachedTokens7d: cache7d,
                thoughtsTokens7d: thought7d,
                toolTokens7d: tool7d,
                totalTokens7d: total7d
            )
            
            var activeError5hResetsAt: Date? = nil
            var activeError24hResetsAt: Date? = nil
            var activeErrorResetsAt: Date? = nil
            var activeErrorMessage: String? = nil
            
            let sqlReset = """
            SELECT reset_at, reset_after_seconds, raw_snapshot
            FROM ai_limit_snapshot
            WHERE provider = 'google'
              AND \(baseToolSQL)
              AND \(accountSQL)
              AND reset_at > ?
              AND source = 'local_log_429'
            ORDER BY captured_at DESC
            LIMIT 5;
            """
            
            var stmtReset: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlReset, -1, &stmtReset, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtReset, 1, tNow)
                while sqlite3_step(stmtReset) == SQLITE_ROW {
                    let resetAt = Date(timeIntervalSince1970: sqlite3_column_double(stmtReset, 0))
                    let resetAfter = Int(sqlite3_column_int(stmtReset, 1))
                    let raw = stringColumn(stmtReset, 2)
                    
                    if activeErrorResetsAt == nil {
                        activeErrorResetsAt = resetAt
                        activeErrorMessage = raw
                    }
                    if resetAfter > 0 && resetAfter <= 18060 {
                        if activeError5hResetsAt == nil {
                            activeError5hResetsAt = resetAt
                        }
                    } else if activeError24hResetsAt == nil {
                        activeError24hResetsAt = resetAt
                    }
                }
            }
            sqlite3_finalize(stmtReset)
            
            var modelUsageByName: [String: GeminiModelUsage] = [:]
            let sqlModels = """
            SELECT
                COALESCE(NULLIF(model_name, ''), '未知模型'),
                SUM(CASE WHEN started_at >= ? AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(successSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? AND \(errorSQL) THEN 1 ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN input_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN output_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN cached_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN thoughts_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN tool_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN total_tokens ELSE 0 END),
                SUM(CASE WHEN started_at >= ? THEN COALESCE(duration_ms, 0) ELSE 0 END)
            FROM ai_usage_log
            WHERE provider = 'google'
              AND started_at >= ?
              AND \(usageToolSQL)
              AND \(accountSQL)
            GROUP BY COALESCE(NULLIF(model_name, ''), '未知模型');
            """
            
            var stmtModels: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlModels, -1, &stmtModels, nil) == SQLITE_OK {
                sqlite3_bind_double(stmtModels, 1, t5h)
                sqlite3_bind_double(stmtModels, 2, t24h)
                sqlite3_bind_double(stmtModels, 3, t7d)
                sqlite3_bind_double(stmtModels, 4, t7d)
                for index in 5...11 {
                    sqlite3_bind_double(stmtModels, Int32(index), t5h)
                }
                sqlite3_bind_double(stmtModels, 12, t7d)
                
                while sqlite3_step(stmtModels) == SQLITE_ROW {
                    let rawModelName = stringColumn(stmtModels, 0) ?? "未知模型"
                    let modelName = SQLiteManager.mapToAntigravityModelName(rawModelName)
                    let calls5h = Int(sqlite3_column_int(stmtModels, 1))
                    let calls24h = Int(sqlite3_column_int(stmtModels, 2))
                    let calls7d = Int(sqlite3_column_int(stmtModels, 3))
                    let errorCount7d = Int(sqlite3_column_int(stmtModels, 4))
                    let inputTokens5h = Int(sqlite3_column_int(stmtModels, 5))
                    let outputTokens5h = Int(sqlite3_column_int(stmtModels, 6))
                    let cachedTokens5h = Int(sqlite3_column_int(stmtModels, 7))
                    let thoughtsTokens5h = Int(sqlite3_column_int(stmtModels, 8))
                    let toolTokens5h = Int(sqlite3_column_int(stmtModels, 9))
                    let totalTokens5h = Int(sqlite3_column_int(stmtModels, 10))
                    let durationTotal = Double(sqlite3_column_double(stmtModels, 11))
                    
                    var existing = modelUsageByName[modelName] ?? GeminiModelUsage(
                        modelName: modelName,
                        calls5h: 0,
                        calls24h: 0,
                        calls7d: 0,
                        errorCount7d: 0,
                        inputTokens5h: 0,
                        outputTokens5h: 0,
                        cachedTokens5h: 0,
                        thoughtsTokens5h: 0,
                        toolTokens5h: 0,
                        totalTokens5h: 0,
                        avgDurationMs5h: 0.0
                    )
                    
                    existing.calls5h += calls5h
                    existing.calls24h += calls24h
                    existing.calls7d += calls7d
                    existing.errorCount7d += errorCount7d
                    existing.inputTokens5h += inputTokens5h
                    existing.outputTokens5h += outputTokens5h
                    existing.cachedTokens5h += cachedTokens5h
                    existing.thoughtsTokens5h += thoughtsTokens5h
                    existing.toolTokens5h += toolTokens5h
                    existing.totalTokens5h += totalTokens5h
                    existing.avgDurationMs5h += durationTotal
                    
                    modelUsageByName[modelName] = existing
                }
                
                for (name, var usage) in modelUsageByName {
                    if usage.calls5h > 0 {
                        usage.avgDurationMs5h = usage.avgDurationMs5h / Double(usage.calls5h)
                    } else {
                        usage.avgDurationMs5h = 0.0
                    }
                    modelUsageByName[name] = usage
                }
            }
            sqlite3_finalize(stmtModels)
            
            let modelUsages = Array(modelUsageByName.values.sorted { lhs, rhs in
                if lhs.calls24h != rhs.calls24h {
                    return lhs.calls24h > rhs.calls24h
                }
                if lhs.calls7d != rhs.calls7d {
                    return lhs.calls7d > rhs.calls7d
                }
                return lhs.modelName < rhs.modelName
            }.prefix(8))
            
            var inferredLimit5h: Int? = nil
            var inferredLimit24h: Int? = nil
            
            let sqlInfer5h = """
            SELECT COUNT(*) FROM gemini_calls
            WHERE is_error = 0
              AND \(accountSQL)
              AND timestamp >= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp <= 18060 ORDER BY timestamp DESC LIMIT 1) - 18000
              AND timestamp <= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp <= 18060 ORDER BY timestamp DESC LIMIT 1);
            """
            var stmtInfer5h: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlInfer5h, -1, &stmtInfer5h, nil) == SQLITE_OK {
                if sqlite3_step(stmtInfer5h) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmtInfer5h, 0))
                    if count > 0 {
                        inferredLimit5h = count
                    }
                }
            }
            sqlite3_finalize(stmtInfer5h)
            
            let sqlInfer24h = """
            SELECT COUNT(*) FROM gemini_calls
            WHERE is_error = 0
              AND \(accountSQL)
              AND timestamp >= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp > 18060 ORDER BY timestamp DESC LIMIT 1) - 86400
              AND timestamp <= (SELECT timestamp FROM gemini_calls WHERE is_error = 1 AND \(accountSQL) AND resets_at - timestamp > 18060 ORDER BY timestamp DESC LIMIT 1);
            """
            var stmtInfer24h: OpaquePointer?
            if sqlite3_prepare_v2(db, sqlInfer24h, -1, &stmtInfer24h, nil) == SQLITE_OK {
                if sqlite3_step(stmtInfer24h) == SQLITE_ROW {
                    let count = Int(sqlite3_column_int(stmtInfer24h, 0))
                    if count > 0 {
                        inferredLimit24h = count
                    }
                }
            }
            sqlite3_finalize(stmtInfer24h)
            
            return GoogleToolUsageStats(
                calls5h: calls5h,
                calls24h: calls24h,
                calls7d: calls7d,
                activeError5hResetsAt: activeError5hResetsAt,
                activeError24hResetsAt: activeError24hResetsAt,
                activeErrorResetsAt: activeErrorResetsAt,
                activeErrorMessage: activeErrorMessage,
                inferredLimit5h: inferredLimit5h,
                inferredLimit24h: inferredLimit24h,
                errorCount7d: errorCount7d,
                tokenSummary: tokenSummary,
                modelUsages: modelUsages
            )
        }
    }
    
    public static func mapToAntigravityModelName(_ model: String) -> String {
        let lower = model.lowercased()
        
        // Match Claude
        if lower.contains("sonnet") || lower.contains("claude-3-5") || lower.contains("claude-3.5") {
            return "Claude Sonnet 4.6 (Thinking)"
        }
        if lower.contains("opus") {
            return "Claude Opus 4.6 (Thinking)"
        }
        if lower.contains("claude") {
            return "Claude Sonnet 4.6 (Thinking)"
        }
        
        // Match Gemini Pro
        if lower.contains("pro") && (lower.contains("gemini-3") || lower.contains("3.1") || lower.contains("3.5")) {
            return "Gemini 3.1 Pro (High)"
        }
        
        // Match Gemini Flash
        if lower.contains("flash-lite") || lower.contains("flash_lite") || lower == "lite" || lower.contains("3.1-flash-lite") {
            return "Gemini 3.5 Flash (High)"
        }
        if lower.contains("flash") || lower.contains("gemini-3-flash") {
            return "Gemini 3.5 Flash (High)"
        }
        
        return model
    }
}
