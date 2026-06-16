import Foundation
import Combine
import ServiceManagement

@MainActor public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()
    
    // Keys
    private let keyPetSize = "TokenPet.size"
    private let keyAlwaysOnTop = "TokenPet.alwaysOnTop"
    private let keyWindowPositionX = "TokenPet.windowPositionX"
    private let keyWindowPositionY = "TokenPet.windowPositionY"
    private let keyShowNotifications = "TokenPet.showNotifications"
    private let keyLaunchAtLogin = "TokenPet.launchAtLogin"
    
    private let keyGeminiMonitorEnabled = "TokenPet.geminiMonitorEnabled"
    private let keyCodexMonitorEnabled = "TokenPet.codexMonitorEnabled"
    private let keyClaudeMonitorEnabled = "TokenPet.claudeMonitorEnabled"
    private let keyGeminiKeywords = "TokenPet.geminiKeywords"
    private let keyCodexKeywords = "TokenPet.codexKeywords"
    private let keyClaudeKeywords = "TokenPet.claudeKeywords"
    
    private let keyQuota5hLimit = "TokenPet.quota5hLimit"
    private let keyQuota7dLimit = "TokenPet.quota7dLimit"
    private let keyQuota5hThreshold = "TokenPet.quota5hThreshold"
    private let keyQuota7dThreshold = "TokenPet.quota7dThreshold"
    
    @Published public var petSize: Double {
        didSet { UserDefaults.standard.set(petSize, forKey: keyPetSize) }
    }
    
    @Published public var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: keyAlwaysOnTop) }
    }
    
    @Published public var windowPositionX: Double? {
        didSet { UserDefaults.standard.set(windowPositionX, forKey: keyWindowPositionX) }
    }
    
    @Published public var windowPositionY: Double? {
        didSet { UserDefaults.standard.set(windowPositionY, forKey: keyWindowPositionY) }
    }
    
    @Published public var showNotifications: Bool {
        didSet { UserDefaults.standard.set(showNotifications, forKey: keyShowNotifications) }
    }
    
    @Published public var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: keyLaunchAtLogin)
            #if !targetEnvironment(simulator)
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                    print("TokenPet: 已注册开机启动")
                } else {
                    try SMAppService.mainApp.unregister()
                    print("TokenPet: 已注销开机启动")
                }
            } catch {
                print("TokenPet: 更新开机启动状态失败 - \(error.localizedDescription)")
            }
            #endif
        }
    }
    
    @Published public var geminiMonitorEnabled: Bool {
        didSet { UserDefaults.standard.set(geminiMonitorEnabled, forKey: keyGeminiMonitorEnabled) }
    }
    
    @Published public var codexMonitorEnabled: Bool {
        didSet { UserDefaults.standard.set(codexMonitorEnabled, forKey: keyCodexMonitorEnabled) }
    }
    
    @Published public var claudeMonitorEnabled: Bool {
        didSet { UserDefaults.standard.set(claudeMonitorEnabled, forKey: keyClaudeMonitorEnabled) }
    }
    
    @Published public var geminiKeywords: String {
        didSet { UserDefaults.standard.set(geminiKeywords, forKey: keyGeminiKeywords) }
    }
    
    @Published public var codexKeywords: String {
        didSet { UserDefaults.standard.set(codexKeywords, forKey: keyCodexKeywords) }
    }
    
    @Published public var claudeKeywords: String {
        didSet { UserDefaults.standard.set(claudeKeywords, forKey: keyClaudeKeywords) }
    }
    
    @Published public var quota5hLimit: Int {
        didSet { UserDefaults.standard.set(quota5hLimit, forKey: keyQuota5hLimit) }
    }
    
    @Published public var quota7dLimit: Int {
        didSet { UserDefaults.standard.set(quota7dLimit, forKey: keyQuota7dLimit) }
    }
    
    @Published public var quota5hThreshold: Int {
        didSet { UserDefaults.standard.set(quota5hThreshold, forKey: keyQuota5hThreshold) }
    }
    
    @Published public var quota7dThreshold: Int {
        didSet { UserDefaults.standard.set(quota7dThreshold, forKey: keyQuota7dThreshold) }
    }
    
    private init() {
        UserDefaults.standard.register(defaults: [
            keyPetSize: 1.0,
            keyAlwaysOnTop: true,
            keyShowNotifications: true,
            keyLaunchAtLogin: false,
            keyGeminiMonitorEnabled: true,
            keyCodexMonitorEnabled: true,
            keyClaudeMonitorEnabled: true,
            keyGeminiKeywords: "gemini,antigravity",
            keyCodexKeywords: "codex",
            keyClaudeKeywords: "claude,claude-code",
            keyQuota5hLimit: 50,
            keyQuota7dLimit: 200,
            keyQuota5hThreshold: 10,
            keyQuota7dThreshold: 40,
        ])
        
        self.petSize = UserDefaults.standard.double(forKey: keyPetSize)
        self.alwaysOnTop = UserDefaults.standard.bool(forKey: keyAlwaysOnTop)
        self.windowPositionX = UserDefaults.standard.object(forKey: keyWindowPositionX) as? Double
        self.windowPositionY = UserDefaults.standard.object(forKey: keyWindowPositionY) as? Double
        self.showNotifications = UserDefaults.standard.bool(forKey: keyShowNotifications)
        
        #if !targetEnvironment(simulator)
        let status = SMAppService.mainApp.status
        self.launchAtLogin = (status == .enabled)
        #else
        self.launchAtLogin = UserDefaults.standard.bool(forKey: keyLaunchAtLogin)
        #endif
        
        self.geminiMonitorEnabled = UserDefaults.standard.bool(forKey: keyGeminiMonitorEnabled)
        self.codexMonitorEnabled = UserDefaults.standard.bool(forKey: keyCodexMonitorEnabled)
        self.claudeMonitorEnabled = UserDefaults.standard.bool(forKey: keyClaudeMonitorEnabled)
        self.geminiKeywords = UserDefaults.standard.string(forKey: keyGeminiKeywords) ?? "gemini,antigravity"
        self.codexKeywords = UserDefaults.standard.string(forKey: keyCodexKeywords) ?? "codex"
        self.claudeKeywords = UserDefaults.standard.string(forKey: keyClaudeKeywords) ?? "claude,claude-code"
        
        self.quota5hLimit = UserDefaults.standard.integer(forKey: keyQuota5hLimit)
        self.quota7dLimit = UserDefaults.standard.integer(forKey: keyQuota7dLimit)
        self.quota5hThreshold = UserDefaults.standard.integer(forKey: keyQuota5hThreshold)
        self.quota7dThreshold = UserDefaults.standard.integer(forKey: keyQuota7dThreshold)
        
        checkGeminiTelemetryStatus()
    }
    
    @Published public var isGeminiTelemetryEnabled: Bool = false
    
    private var geminiSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/settings.json")
    }
    
    private var antigravitySettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/antigravity-cli/settings.json")
    }
    
    private var geminiTelemetryOutputURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/telemetry.log")
    }
    
    public func checkGeminiTelemetryStatus() {
        let geminiEnabled = geminiCLISettingsTelemetryEnabled()
        let antigravityEnabled = antigravityCLISettingsTelemetryEnabled()
        self.isGeminiTelemetryEnabled = geminiEnabled && antigravityEnabled
    }
    
    public func enableGeminiTelemetry() {
        let fm = FileManager.default
        let telemetryBlock: [String: Any] = [
            "enabled": true,
            "target": "local",
            "outfile": geminiTelemetryOutputURL.path
        ]
        
        var geminiJSON = loadJSON(from: geminiSettingsURL)
        geminiJSON["telemetry"] = telemetryBlock
        
        var antigravityJSON = loadJSON(from: antigravitySettingsURL)
        antigravityJSON["enableTelemetry"] = true
        antigravityJSON["telemetry"] = telemetryBlock
        
        do {
            try writeJSON(geminiJSON, to: geminiSettingsURL, fileManager: fm)
            try writeJSON(antigravityJSON, to: antigravitySettingsURL, fileManager: fm)
            self.isGeminiTelemetryEnabled = true
            print("TokenPet: 已成功写入 Gemini/Antigravity telemetry 配置")
        } catch {
            checkGeminiTelemetryStatus()
            print("TokenPet: 写入 telemetry 配置失败 - \(error.localizedDescription)")
        }
    }
    
    private func geminiCLISettingsTelemetryEnabled() -> Bool {
        let json = loadJSON(from: geminiSettingsURL)
        guard let telemetry = json["telemetry"] as? [String: Any],
              let enabled = telemetry["enabled"] as? Bool else {
            return false
        }
        
        return enabled
    }
    
    private func antigravityCLISettingsTelemetryEnabled() -> Bool {
        let json = loadJSON(from: antigravitySettingsURL)
        if let enabled = json["enableTelemetry"] as? Bool {
            return enabled
        }
        
        if let telemetry = json["telemetry"] as? [String: Any],
           let enabled = telemetry["enabled"] as? Bool {
            return enabled
        }
        
        return false
    }
    
    private func loadJSON(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [:]
        }
        return parsed
    }
    
    private func writeJSON(_ json: [String: Any], to url: URL, fileManager: FileManager) throws {
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
