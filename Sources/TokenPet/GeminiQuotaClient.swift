import Foundation
import Combine

@MainActor
public final class GeminiQuotaClient: ObservableObject {
    public static let shared = GeminiQuotaClient()
    
    // Credentials are stored in GeminiCredentials.swift (gitignored).
    // Copy GeminiCredentials.swift.example → GeminiCredentials.swift and fill in your values.
    private let clientId     = GeminiCredentials.clientId
    private let clientSecret = GeminiCredentials.clientSecret
    private let cloudcodeQuotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    private let dailyCloudcodeQuotaURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    
    @Published public var officialQuotas: [GeminiOfficialQuotaBucket] = []
    @Published public var lastFetchError: String? = nil
    
    private init() {}
    
    public func fetchQuota() async {
        var allBuckets: [GeminiOfficialQuotaBucket] = []
        var errors: [String] = []
        
        let localUsage = await AntigravityLocalUsageClient.fetchUserStatus()
        let sources = loadCredentialSources(localUsage: localUsage)
        guard !sources.isEmpty else {
            self.officialQuotas = []
            self.lastFetchError = "未找到 Gemini 或反重力 OAuth 凭据"
            return
        }
        
        for source in sources {
            do {
                let result: QuotaFetchResult
                switch source.credential {
                case .antigravityLocal(let localUsage):
                    result = try retrieveAntigravityLocalUsage(source: source, localUsage: localUsage)
                default:
                    let credential = try await refreshedCredentialIfNeeded(source)
                    result = try await retrieveUserQuota(source: source, accessToken: credential.accessToken)
                }
                allBuckets.append(contentsOf: result.buckets)
                
                let capturedAt = result.capturedAt
                for bucket in result.buckets {
                    let uniqueKey = [
                        "gemini-quota",
                        source.identity.fingerprint,
                        bucket.sourceTool,
                        bucket.modelId,
                        bucket.windowType,
                        bucket.tokenType,
                        bucket.resetTime.map { String(Int($0.timeIntervalSince1970)) } ?? "no-reset",
                        String(Int(capturedAt.timeIntervalSince1970))
                    ].joined(separator: ":")
                    
                    SQLiteManager.shared.insertLimitSnapshot(
                        provider: "google",
                        toolName: bucket.sourceTool,
                        modelName: bucket.modelId,
                        accountFingerprint: source.identity.fingerprint,
                        accountLabel: source.identity.label,
                        authType: source.authType,
                        planName: nil,
                        windowType: bucket.windowType,
                        metricType: bucket.tokenType,
                        limitValue: 1,
                        remainingValue: bucket.remainingFraction,
                        usedValue: 1.0 - bucket.remainingFraction,
                        resetAt: bucket.resetTime,
                        resetAfterSeconds: bucket.resetTime.map { max(0, Int($0.timeIntervalSince(capturedAt))) },
                        retryAfterSeconds: nil,
                        source: "google_quota_snapshot",
                        sourceDetail: result.sourceDetail,
                        sourceURL: result.sourceURL.absoluteString,
                        confidenceLevel: "L4",
                        isOfficial: true,
                        isEstimated: false,
                        capturedAt: capturedAt,
                        expiresAt: bucket.resetTime,
                        rawSnapshot: result.rawSnapshot,
                        dedupeKey: uniqueKey
                    )
                }
            } catch {
                errors.append("\(source.toolName): \(error.localizedDescription)")
            }
        }
        
        self.officialQuotas = dedupeBuckets(allBuckets)
        self.lastFetchError = allBuckets.isEmpty && !errors.isEmpty ? errors.joined(separator: "；") : nil
    }
    
    private func loadCredentialSources(localUsage: AntigravityLocalUsageResult?) -> [CredentialSource] {
        let home = NSHomeDirectory()
        var sources: [CredentialSource] = []
        
        if let localUsage {
            sources.append(CredentialSource(
                toolName: "antigravity-cli",
                authType: "local-usage",
                identity: AccountIdentityManager.currentAntigravityIdentity(),
                fileURL: AntigravityStateStore.stateDBURL,
                credential: .antigravityLocal(localUsage)
            ))
        }
        
        let geminiURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/oauth_creds.json")
        if let data = try? Data(contentsOf: geminiURL),
           let creds = try? JSONDecoder().decode(GeminiOAuthCreds.self, from: data) {
            sources.append(CredentialSource(
                toolName: "gemini-cli",
                authType: "oauth-personal",
                identity: AccountIdentityManager.currentGeminiIdentity(),
                fileURL: geminiURL,
                credential: .gemini(creds)
            ))
        }
        
        let antigravityURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
        if let data = try? Data(contentsOf: antigravityURL),
           let creds = try? JSONDecoder().decode(AntigravityOAuthFile.self, from: data) {
            sources.append(CredentialSource(
                toolName: "antigravity-cli",
                authType: creds.auth_method,
                identity: AccountIdentityManager.currentAntigravityIdentity(),
                fileURL: antigravityURL,
                credential: .antigravity(creds)
            ))
        } else if localUsage == nil, let accessToken = AntigravityStateStore.oauthAccessToken() {
            sources.append(CredentialSource(
                toolName: "antigravity-cli",
                authType: "vscode-state-bearer",
                identity: AccountIdentityManager.currentAntigravityIdentity(),
                fileURL: AntigravityStateStore.stateDBURL,
                credential: .antigravityBearer(accessToken)
            ))
        }
        
        return sources
    }
    
    private func refreshedCredentialIfNeeded(_ source: CredentialSource) async throws -> RuntimeCredential {
        let nowMs = Date().timeIntervalSince1970 * 1000
        switch source.credential {
        case .gemini(let creds):
            if creds.expiry_date - nowMs < 300_000 {
                let refreshed = try await refreshGeminiAccessToken(creds: creds, fileURL: source.fileURL)
                return RuntimeCredential(accessToken: refreshed.access_token)
            }
            return RuntimeCredential(accessToken: creds.access_token)
            
        case .antigravity(let creds):
            let expiryMs = creds.token.expiryMilliseconds
            if let expiryMs, expiryMs - nowMs < 300_000 {
                let refreshed = try await refreshAntigravityAccessToken(creds: creds, fileURL: source.fileURL)
                return RuntimeCredential(accessToken: refreshed.token.access_token)
            }
            return RuntimeCredential(accessToken: creds.token.access_token)
            
        case .antigravityBearer(let accessToken):
            return RuntimeCredential(accessToken: accessToken)
            
        case .antigravityLocal:
            throw NSError(domain: "GeminiQuotaClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "反重力本地 /usage 不需要 OAuth token"])
        }
    }
    
    private func refreshGeminiAccessToken(creds: GeminiOAuthCreds, fileURL: URL) async throws -> GeminiOAuthCreds {
        let response = try await refreshAccessToken(refreshToken: creds.refresh_token)
        var updatedCreds = creds
        updatedCreds.access_token = response.access_token
        updatedCreds.expiry_date = (Date().timeIntervalSince1970 + Double(response.expires_in)) * 1000
        if let idToken = response.id_token {
            updatedCreds.id_token = idToken
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updatedCreds).write(to: fileURL, options: .atomic)
        return updatedCreds
    }
    
    private func refreshAntigravityAccessToken(creds: AntigravityOAuthFile, fileURL: URL) async throws -> AntigravityOAuthFile {
        let response = try await refreshAccessToken(refreshToken: creds.token.refresh_token)
        var updatedCreds = creds
        updatedCreds.token.access_token = response.access_token
        updatedCreds.token.expiry = FlexibleDouble((Date().timeIntervalSince1970 + Double(response.expires_in)) * 1000)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updatedCreds).write(to: fileURL, options: .atomic)
        return updatedCreds
    }
    
    private func refreshAccessToken(refreshToken: String) async throws -> TokenRefreshResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GeminiQuotaClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "刷新 OAuth token 失败: \(errorText)"])
        }
        return try JSONDecoder().decode(TokenRefreshResponse.self, from: data)
    }
    
    private func retrieveAntigravityLocalUsage(source: CredentialSource, localUsage: AntigravityLocalUsageResult) throws -> QuotaFetchResult {
        let capturedAt = Date()
        var buckets: [GeminiOfficialQuotaBucket] = []
        if let quotaSummary = localUsage.quotaSummary {
            buckets.append(contentsOf: parseQuotaSummaryBuckets(
                quotaSummary,
                sourceTool: source.toolName,
                accountLabel: source.identity.label
            ))
        }
        buckets.append(contentsOf: parseQuotaBuckets(
            localUsage.object,
            context: QuotaContext(),
            sourceTool: source.toolName,
            accountLabel: source.identity.label,
            capturedAt: capturedAt
        ))
        buckets.append(contentsOf: parseCreditBuckets(
            localUsage.object,
            sourceTool: source.toolName,
            accountLabel: source.identity.label
        ))
        buckets = dedupeBuckets(buckets)
        
        guard !buckets.isEmpty else {
            throw NSError(domain: "GeminiQuotaClient", code: 6, userInfo: [NSLocalizedDescriptionKey: "反重力本地 /usage 返回成功，但没有识别到 quotaInfo"])
        }
        
        return QuotaFetchResult(
            buckets: buckets,
            capturedAt: capturedAt,
            rawSnapshot: nil,
            sourceURL: localUsage.quotaSummaryURL ?? localUsage.endpointURL,
            sourceDetail: localUsage.quotaSummary == nil ? "antigravity local GetUserStatus" : "antigravity local RetrieveUserQuotaSummary"
        )
    }
    
    private func retrieveUserQuota(source: CredentialSource, accessToken: String) async throws -> QuotaFetchResult {
        var failures: [String] = []
        for quotaURL in quotaURLs(for: source) {
            do {
                return try await retrieveUserQuotaOnce(source: source, accessToken: accessToken, quotaURL: quotaURL)
            } catch {
                failures.append("\(quotaURL.host ?? quotaURL.absoluteString): \(error.localizedDescription)")
            }
        }
        
        throw NSError(
            domain: "GeminiQuotaClient",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: failures.joined(separator: "；")]
        )
    }
    
    private func quotaURLs(for source: CredentialSource) -> [URL] {
        if source.toolName == "antigravity-cli" {
            return [dailyCloudcodeQuotaURL, cloudcodeQuotaURL]
        }
        return [cloudcodeQuotaURL, dailyCloudcodeQuotaURL]
    }
    
    private func retrieveUserQuotaOnce(source: CredentialSource, accessToken: String, quotaURL: URL) async throws -> QuotaFetchResult {
        var request = URLRequest(url: quotaURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenPet", forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "GeminiQuotaClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "读取额度失败 HTTP \(status): \(errorText)"])
        }
        
        let capturedAt = Date()
        let object = try JSONSerialization.jsonObject(with: data)
        let rawSnapshot = String(data: data, encoding: .utf8)
        let buckets = parseQuotaBuckets(
            object,
            context: QuotaContext(),
            sourceTool: source.toolName,
            accountLabel: source.identity.label,
            capturedAt: capturedAt
        )
        
        guard !buckets.isEmpty else {
            throw NSError(domain: "GeminiQuotaClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "额度接口返回成功，但没有识别到可展示的 bucket"])
        }
        
        return QuotaFetchResult(
            buckets: buckets,
            capturedAt: capturedAt,
            rawSnapshot: rawSnapshot,
            sourceURL: quotaURL,
            sourceDetail: "cloudcode retrieveUserQuota"
        )
    }
    
    private func parseQuotaBuckets(
        _ node: Any,
        context: QuotaContext,
        sourceTool: String,
        accountLabel: String,
        capturedAt: Date
    ) -> [GeminiOfficialQuotaBucket] {
        if let array = node as? [Any] {
            return array.flatMap {
                parseQuotaBuckets($0, context: context, sourceTool: sourceTool, accountLabel: accountLabel, capturedAt: capturedAt)
            }
        }
        
        guard let dict = node as? [String: Any] else {
            return []
        }
        
        var updated = context
        updated.modelId = firstString(["modelId", "model_id", "model", "modelName", "model_name", "tier", "name", "label", "displayName"], in: dict)
            ?? updated.modelId
        updated.windowType = normalizeWindow(firstString(["windowType", "window_type", "quotaWindow", "quota_window", "primary_window"], in: dict))
            ?? updated.windowType
        updated.tokenType = firstString(["tokenType", "token_type", "metricType", "metric_type", "quotaType", "quota_type"], in: dict)
            ?? updated.tokenType
        
        var buckets: [GeminiOfficialQuotaBucket] = []
        if let remaining = remainingFraction(in: dict) {
            let reset = resetDate(in: dict, capturedAt: capturedAt)
            let windowType = updated.windowType ?? reset.flatMap { inferWindowType(resetTime: $0, capturedAt: capturedAt) } ?? "model"
            buckets.append(GeminiOfficialQuotaBucket(
                modelId: updated.modelId ?? "gemini",
                remainingFraction: max(0, min(1, remaining)),
                resetTime: reset,
                tokenType: updated.tokenType ?? "requests",
                windowType: windowType,
                sourceTool: sourceTool,
                accountLabel: accountLabel
            ))
        }
        
        for (key, value) in dict {
            guard value is [String: Any] || value is [Any] else { continue }
            var child = updated
            if let model = modelFromKey(key) {
                child.modelId = model
            }
            if let window = normalizeWindow(key) {
                child.windowType = window
            }
            if tokenTypeFromKey(key) != nil {
                child.tokenType = tokenTypeFromKey(key)
            }
            buckets.append(contentsOf: parseQuotaBuckets(value, context: child, sourceTool: sourceTool, accountLabel: accountLabel, capturedAt: capturedAt))
        }
        
        return dedupeBuckets(buckets)
    }
    
    private func parseQuotaSummaryBuckets(_ object: [String: Any], sourceTool: String, accountLabel: String?) -> [GeminiOfficialQuotaBucket] {
        guard let response = object["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else {
            return []
        }
        
        var buckets: [GeminiOfficialQuotaBucket] = []
        for group in groups {
            let groupName = firstString(["displayName", "display_name", "name"], in: group) ?? "Antigravity Models"
            let groupDescription = firstString(["description"], in: group)
            guard let rawBuckets = group["buckets"] as? [[String: Any]] else { continue }
            
            for rawBucket in rawBuckets {
                guard let remaining = remainingFraction(in: rawBucket) else { continue }
                let bucketDisplayName = firstString(["displayName", "display_name", "name"], in: rawBucket)
                let rawWindow = firstString(["window", "windowType", "window_type"], in: rawBucket)
                    ?? bucketDisplayName
                    ?? firstString(["bucketId", "bucket_id"], in: rawBucket)
                let windowType = normalizeWindow(rawWindow) ?? "unknown"
                
                buckets.append(GeminiOfficialQuotaBucket(
                    modelId: groupName,
                    remainingFraction: max(0, min(1, remaining)),
                    resetTime: resetDate(in: rawBucket, capturedAt: Date()),
                    tokenType: "requests",
                    windowType: windowType,
                    sourceTool: sourceTool,
                    accountLabel: accountLabel,
                    bucketId: firstString(["bucketId", "bucket_id"], in: rawBucket),
                    bucketDisplayName: bucketDisplayName,
                    groupDescription: groupDescription
                ))
            }
        }
        
        return buckets
    }
    
    private func parseCreditBuckets(_ object: [String: Any], sourceTool: String, accountLabel: String?) -> [GeminiOfficialQuotaBucket] {
        guard let userStatus = object["userStatus"] as? [String: Any],
              let planStatus = userStatus["planStatus"] as? [String: Any],
              let planInfo = planStatus["planInfo"] as? [String: Any] else {
            return []
        }
        
        var buckets: [GeminiOfficialQuotaBucket] = []
        if let rawAvailable = planStatus["availablePromptCredits"],
           let rawMonthly = planInfo["monthlyPromptCredits"],
           let available = doubleValue(rawAvailable),
           let monthly = doubleValue(rawMonthly),
           monthly > 0 {
            buckets.append(GeminiOfficialQuotaBucket(
                modelId: "Prompt Credits",
                remainingFraction: max(0, min(1, available / monthly)),
                resetTime: nil,
                tokenType: "credits",
                windowType: "monthly",
                sourceTool: sourceTool,
                accountLabel: accountLabel
            ))
        }
        
        if let rawAvailable = planStatus["availableFlowCredits"],
           let rawMonthly = planInfo["monthlyFlowCredits"],
           let available = doubleValue(rawAvailable),
           let monthly = doubleValue(rawMonthly),
           monthly > 0 {
            buckets.append(GeminiOfficialQuotaBucket(
                modelId: "Flow Credits",
                remainingFraction: max(0, min(1, available / monthly)),
                resetTime: nil,
                tokenType: "credits",
                windowType: "monthly",
                sourceTool: sourceTool,
                accountLabel: accountLabel
            ))
        }
        
        return buckets
    }
    
    private func remainingFraction(in dict: [String: Any]) -> Double? {
        if let value = firstDouble(["remainingFraction", "remaining_fraction"], in: dict) {
            return value
        }
        if let value = firstDouble(["remainingPercent", "remaining_percent", "current_interval_remaining_percent", "current_weekly_remaining_percent"], in: dict) {
            return value > 1 ? value / 100.0 : value
        }
        if let value = firstDouble(["used_percent", "usedPercent"], in: dict) {
            return 1.0 - (value > 1 ? value / 100.0 : value)
        }
        if let value = firstDouble(["utilization"], in: dict) {
            return 1.0 - (value > 1 ? value / 100.0 : value)
        }
        if let used = firstDouble(["usedCredits", "used_credits", "used_value_usd"], in: dict),
           let limit = firstDouble(["monthly_limit", "max_value_usd", "limit"], in: dict),
           limit > 0 {
            return max(0, (limit - used) / limit)
        }
        return nil
    }
    
    private func resetDate(in dict: [String: Any], capturedAt: Date) -> Date? {
        let dateKeys = [
            "resetTime", "reset_time", "resetAt", "reset_at", "resets_at",
            "expiresAt", "expires_at", "expiry_date", "weekly_end_time", "resetTimeMillis"
        ]
        for key in dateKeys {
            if let raw = value(for: key, in: dict), let date = parseDate(raw) {
                return date
            }
        }
        
        if let seconds = firstDouble(["limit_window_seconds", "reset_after_seconds"], in: dict), seconds > 0 {
            return capturedAt.addingTimeInterval(seconds)
        }
        return nil
    }
    
    private func inferWindowType(resetTime: Date, capturedAt: Date) -> String? {
        let seconds = resetTime.timeIntervalSince(capturedAt)
        if seconds <= 0 {
            return nil
        }
        if seconds <= 5 * 3600 + 600 {
            return "5h"
        }
        if seconds <= 24 * 3600 + 600 {
            return "24h"
        }
        if seconds <= 7 * 24 * 3600 + 3600 {
            return "7d"
        }
        if seconds <= 31 * 24 * 3600 + 3600 {
            return "monthly"
        }
        return nil
    }
    
    private func normalizeWindow(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lower = raw.lowercased()
        if lower.contains("quota_5_hour") || lower.contains("5h") || (lower.contains("5") && lower.contains("hour")) || lower.contains("primary") || lower.contains("interval") {
            return "5h"
        }
        if lower.contains("quota_7_day") || lower.contains("7d") || lower.contains("weekly") || lower.contains("week") || (lower.contains("7") && lower.contains("day")) || lower.contains("secondary") {
            return "weekly"
        }
        if lower.contains("24h") || lower.contains("daily") || lower.contains("day") {
            return "24h"
        }
        if lower.contains("month") {
            return "monthly"
        }
        if lower.contains("rate_limit") {
            return "rate_limit"
        }
        return nil
    }
    
    private func modelFromKey(_ key: String) -> String? {
        let lower = key.lowercased()
        if lower.contains("flash-lite") || lower.contains("flash_lite") || lower == "lite" {
            return "flash-lite"
        }
        if lower == "flash" || lower.contains("flash") {
            return "flash"
        }
        if lower == "pro" || lower.contains("pro") {
            return "pro"
        }
        if lower.contains("gemini") {
            return key
        }
        return nil
    }
    
    private func tokenTypeFromKey(_ key: String) -> String? {
        let lower = key.lowercased()
        if lower.contains("token") {
            return "tokens"
        }
        if lower.contains("request") || lower.contains("rate") {
            return "requests"
        }
        return nil
    }
    
    private func value(for target: String, in dict: [String: Any]) -> Any? {
        dict.first { $0.key.caseInsensitiveCompare(target) == .orderedSame }?.value
    }
    
    private func firstString(_ keys: [String], in dict: [String: Any]) -> String? {
        for key in keys {
            guard let raw = value(for: key, in: dict) else { continue }
            if let string = raw as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
            if let number = raw as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }
    
    private func firstDouble(_ keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            guard let raw = value(for: key, in: dict), let number = doubleValue(raw) else { continue }
            return number
        }
        return nil
    }
    
    private func doubleValue(_ raw: Any) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
    
    private func parseDate(_ raw: Any) -> Date? {
        if let number = doubleValue(raw) {
            if number > 10_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000.0)
            }
            if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }
        
        guard let string = raw as? String else { return nil }
        if let numeric = Double(string) {
            return parseDate(numeric)
        }
        
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: string) {
            return date
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
    
    private func dedupeBuckets(_ buckets: [GeminiOfficialQuotaBucket]) -> [GeminiOfficialQuotaBucket] {
        var seen = Set<String>()
        return buckets.filter { bucket in
            let key = [
                bucket.accountLabel ?? "",
                bucket.modelId,
                bucket.windowType,
                bucket.tokenType,
                bucket.resetTime.map { String(Int($0.timeIntervalSince1970)) } ?? "no-reset",
                String(format: "%.5f", bucket.remainingFraction)
            ].joined(separator: "|")
            return seen.insert(key).inserted
        }
    }
    
    private func formEncoded(_ params: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

private struct CredentialSource {
    let toolName: String
    let authType: String
    let identity: AIAccountIdentity
    let fileURL: URL
    let credential: CredentialKind
}

private enum CredentialKind {
    case gemini(GeminiOAuthCreds)
    case antigravity(AntigravityOAuthFile)
    case antigravityBearer(String)
    case antigravityLocal(AntigravityLocalUsageResult)
}

private struct RuntimeCredential {
    let accessToken: String
}

private struct QuotaFetchResult {
    let buckets: [GeminiOfficialQuotaBucket]
    let capturedAt: Date
    let rawSnapshot: String?
    let sourceURL: URL
    let sourceDetail: String
}

private struct QuotaContext {
    var modelId: String?
    var windowType: String?
    var tokenType: String?
}

private struct GeminiOAuthCreds: Codable {
    var access_token: String
    var scope: String?
    var token_type: String
    var id_token: String?
    var expiry_date: Double
    var refresh_token: String
}

private struct AntigravityOAuthFile: Codable {
    var auth_method: String
    var token: AntigravityOAuthToken
}

private struct AntigravityOAuthToken: Codable {
    var access_token: String
    var refresh_token: String
    var token_type: String?
    var expiry: FlexibleDouble?
    
    var expiryMilliseconds: Double? {
        guard let value = expiry?.value else { return nil }
        return value > 10_000_000_000 ? value : value * 1000.0
    }
}

private struct TokenRefreshResponse: Codable {
    let access_token: String
    let expires_in: Int
    let scope: String?
    let token_type: String?
    let id_token: String?
}

private struct FlexibleDouble: Codable {
    var value: Double
    
    init(_ value: Double) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self), let double = Double(string) {
            value = double
        } else {
            value = 0
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
