import Foundation
import CryptoKit

public struct AIAccountIdentity: Equatable, Sendable {
    public let provider: String
    public let toolName: String
    public let fingerprint: String
    public let label: String
    public let validAfter: Date?
}

public enum AccountIdentityManager {
    public static func currentCodexIdentity() -> AIAccountIdentity {
        let home = NSHomeDirectory()
        let url = URL(fileURLWithPath: home).appendingPathComponent(".codex/auth.json")
        let json = loadJSON(url)
        let authMode = string(at: ["auth_mode"], in: json) ?? "unknown"
        let accountId = string(at: ["tokens", "account_id"], in: json)
        let jwtIdentity = jwtClaimIdentity(from: string(at: ["tokens", "id_token"], in: json))
        let apiKey = string(at: ["OPENAI_API_KEY"], in: json)
        
        let rawIdentity = accountId
            ?? jwtIdentity
            ?? apiKey.map { "api-key:\(sha256($0))" }
            ?? "missing"
        let fingerprint = sha256("openai:codex:\(authMode):\(rawIdentity)")
        let validAfter = trackSwitch(storageKey: "codex", fingerprint: fingerprint, credentialURL: url)
        
        return AIAccountIdentity(
            provider: "openai",
            toolName: "codex",
            fingerprint: fingerprint,
            label: "Codex \(authMode) \(short(fingerprint))",
            validAfter: validAfter
        )
    }
    
    public static func currentGeminiIdentity() -> AIAccountIdentity {
        let home = NSHomeDirectory()
        let accountsURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/google_accounts.json")
        let oauthURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/oauth_creds.json")
        let accountsJSON = loadJSON(accountsURL)
        let oauthJSON = loadJSON(oauthURL)
        
        let activeAccount = string(at: ["active"], in: accountsJSON)
        let jwtIdentity = jwtClaimIdentity(from: string(at: ["id_token"], in: oauthJSON))
        let refreshHash = string(at: ["refresh_token"], in: oauthJSON).map { "refresh:\(sha256($0))" }
        let rawIdentity = activeAccount ?? jwtIdentity ?? refreshHash ?? "missing"
        let fingerprint = sha256("google:gemini-cli:\(rawIdentity)")
        let validAfter = trackSwitch(storageKey: "gemini", fingerprint: fingerprint, credentialURL: newestExistingURL([accountsURL, oauthURL]))
        
        return AIAccountIdentity(
            provider: "google",
            toolName: "gemini-cli",
            fingerprint: fingerprint,
            label: activeAccount ?? jwtIdentity ?? "Gemini \(short(fingerprint))",
            validAfter: validAfter
        )
    }
    
    public static func currentAntigravityIdentity() -> AIAccountIdentity {
        let home = NSHomeDirectory()
        let tokenURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/antigravity-cli/antigravity-oauth-token")
        let fileExists = FileManager.default.fileExists(atPath: tokenURL.path)
        let json = fileExists ? loadJSON(tokenURL) : [:]
        let localStatus = AntigravityLocalUsageClient.cachedUserStatus()
        let authMethod = string(at: ["auth_method"], in: json)
            ?? (localStatus != nil ? "local-usage" : nil)
            ?? (AntigravityStateStore.oauthAccessToken() != nil ? "vscode-state" : "unknown")
        let refreshHash = string(at: ["token", "refresh_token"], in: json).map { "refresh:\(sha256($0))" }
        let accessHash = string(at: ["token", "access_token"], in: json).map { "access:\(sha256($0))" }
        let localEmail = localStatus.flatMap { string(at: ["userStatus", "email"], in: $0) }
        
        // Fallback to active google account since antigravity CLI shares the same OAuth account
        let accountsURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/google_accounts.json")
        let oauthURL = URL(fileURLWithPath: home).appendingPathComponent(".gemini/oauth_creds.json")
        let accountsJSON = FileManager.default.fileExists(atPath: accountsURL.path) ? loadJSON(accountsURL) : [:]
        let oauthJSON = FileManager.default.fileExists(atPath: oauthURL.path) ? loadJSON(oauthURL) : [:]
        let activeAccount = string(at: ["active"], in: accountsJSON)
        let jwtIdentity = jwtClaimIdentity(from: string(at: ["id_token"], in: oauthJSON))
        let fallbackEmail = activeAccount ?? jwtIdentity
        
        let localIdentity = localStatus.flatMap { status -> String? in
            if let email = localEmail {
                return "email:\(email)"
            }
            if let name = string(at: ["userStatus", "name"], in: status) {
                return "name:\(sha256(name))"
            }
            return nil
        }
        let stateIdentity = AntigravityStateStore.userStatusIdentity().map { "state:\(sha256($0))" }
        let stateAccessHash = AntigravityStateStore.oauthAccessToken().map { "state-access:\(sha256($0))" }
        let rawIdentity = refreshHash ?? localIdentity ?? stateIdentity ?? accessHash ?? stateAccessHash ?? "missing"
        let fingerprint = sha256("google:antigravity-cli:\(authMethod):\(rawIdentity)")
        
        // If the credential file doesn't exist, proactively clear any stale validAfter
        // that may have been written as Date() in a previous app run, which would
        // incorrectly truncate all historical telemetry data.
        let fallbackCredentialURL = localStatus != nil ? AntigravityStateStore.stateDBURL : nil
        if !fileExists && fallbackCredentialURL == nil {
            let validAfterKey = "TokenPet.account.antigravity.validAfter"
            UserDefaults.standard.removeObject(forKey: validAfterKey)
        }
        
        let validAfter = trackSwitch(storageKey: "antigravity", fingerprint: fingerprint, credentialURL: fileExists ? tokenURL : fallbackCredentialURL)
        
        return AIAccountIdentity(
            provider: "google",
            toolName: "antigravity-cli",
            fingerprint: fingerprint,
            label: localEmail ?? fallbackEmail ?? "反重力 \(authMethod) \(short(fingerprint))",
            validAfter: validAfter
        )
    }
    
    public static func currentGeminiToolIdentities() -> [AIAccountIdentity] {
        let identities = [currentGeminiIdentity(), currentAntigravityIdentity()]
        var seen = Set<String>()
        return identities.filter { seen.insert($0.fingerprint).inserted }
    }
    
    public static func latestValidAfter(_ identities: [AIAccountIdentity]) -> Date? {
        identities.compactMap(\.validAfter).max()
    }
    
    public static func short(_ fingerprint: String) -> String {
        String(fingerprint.prefix(8))
    }
    
    private static func trackSwitch(storageKey: String, fingerprint: String, credentialURL: URL?) -> Date? {
        let defaults = UserDefaults.standard
        let fingerprintKey = "TokenPet.account.\(storageKey).fingerprint"
        let validAfterKey = "TokenPet.account.\(storageKey).validAfter"
        let previous = defaults.string(forKey: fingerprintKey)
        
        if previous == nil {
            defaults.set(fingerprint, forKey: fingerprintKey)
            return defaults.object(forKey: validAfterKey).map { _ in
                Date(timeIntervalSince1970: defaults.double(forKey: validAfterKey))
            }
        }
        
        if previous != fingerprint {
            // Only record a validAfter if we can reliably determine when the switch
            // happened from the file's modification date. If the credential file
            // doesn't exist (modificationDate returns nil), fall back gracefully:
            // don't write validAfter (treat as "no switch recorded") so that all
            // historical data remains visible instead of being truncated to Date().
            if let credURL = credentialURL, let switchedAt = modificationDate(credURL) {
                defaults.set(fingerprint, forKey: fingerprintKey)
                defaults.set(switchedAt.timeIntervalSince1970, forKey: validAfterKey)
                return switchedAt
            } else {
                // Credential file absent — update fingerprint but don't set validAfter
                defaults.set(fingerprint, forKey: fingerprintKey)
                defaults.removeObject(forKey: validAfterKey)
                return nil
            }
        }
        
        guard defaults.object(forKey: validAfterKey) != nil else {
            return nil
        }
        return Date(timeIntervalSince1970: defaults.double(forKey: validAfterKey))
    }
    
    private static func newestExistingURL(_ urls: [URL]) -> URL? {
        urls
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { lhs, rhs in
                (modificationDate(lhs) ?? .distantPast) < (modificationDate(rhs) ?? .distantPast)
            }
    }
    
    private static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }
    
    private static func loadJSON(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return [:]
        }
        return json
    }
    
    private static func string(at path: [String], in json: [String: Any]) -> String? {
        var current: Any = json
        for key in path {
            guard let dict = current as? [String: Any],
                  let next = dict[key] else {
                return nil
            }
            current = next
        }
        guard let value = current as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    private static func jwtClaimIdentity(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: payloadData),
              let payload = object as? [String: Any] else {
            return nil
        }
        
        if let email = payload["email"] as? String, !email.isEmpty {
            return "email:\(email)"
        }
        if let subject = payload["sub"] as? String, !subject.isEmpty {
            return "sub:\(subject)"
        }
        return nil
    }
    
    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }
    
    private static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
