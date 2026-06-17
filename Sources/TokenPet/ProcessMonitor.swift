import Foundation
import Combine

@MainActor public class ProcessMonitor: ObservableObject {
    public static let shared = ProcessMonitor()
    
    @Published public var isGeminiRunning: Bool = false
    @Published public var isCodexRunning: Bool = false
    @Published public var isClaudeRunning: Bool = false
    @Published public var hasMonitoringError: Bool = false
    
    // Hook-triggered states
    @Published public var isGeminiRunningFromHook: Bool = false {
        didSet { updatePublishedStates() }
    }
    @Published public var isCodexRunningFromHook: Bool = false {
        didSet { updatePublishedStates() }
    }
    @Published public var isClaudeRunningFromHook: Bool = false {
        didSet { updatePublishedStates() }
    }
    
    // PS-detected states
    private var isGeminiRunningFromPS: Bool = false
    private var isCodexRunningFromPS: Bool = false
    private var isClaudeRunningFromPS: Bool = false
    
    private func updatePublishedStates() {
        self.isGeminiRunning = isGeminiRunningFromPS || isGeminiRunningFromHook
        self.isCodexRunning = isCodexRunningFromPS || isCodexRunningFromHook
        self.isClaudeRunning = isClaudeRunningFromPS || isClaudeRunningFromHook
    }
    
    private var settings = SettingsManager.shared
    private var timer: AnyCancellable?
    private var isScanning = false
    
    private init() {
        startMonitoring()
    }
    
    public func startMonitoring() {
        timer?.cancel()
        timer = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.scanProcesses()
            }
    }
    
    public func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }
    
    private func scanProcesses() {
        guard !isScanning else { return }
        isScanning = true
        
        // Run in background thread to avoid blocking main UI thread
        DispatchQueue.global(qos: .background).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-ax", "-o", "command"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Silence stderr
            
            var resultOutput: String? = nil
            var didError = false
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                resultOutput = String(data: data, encoding: .utf8)
            } catch {
                didError = true
            }
            
            // Dispatch back to main thread to parse and update state
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isScanning = false
                
                if didError || resultOutput == nil {
                    self.hasMonitoringError = true
                } else if let output = resultOutput {
                    self.parseProcessOutput(output)
                }
            }
        }
    }
    
    private func parseProcessOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        
        let geminiEnabled = settings.geminiMonitorEnabled
        let codexEnabled = settings.codexMonitorEnabled
        let claudeEnabled = settings.claudeMonitorEnabled
        
        let geminiKeywords = settings.geminiKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            
        let codexKeywords = settings.codexKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        
        let claudeKeywords = settings.claudeKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            
        var geminiDetected = false
        var codexDetected = false
        var claudeDetected = false
        
        for line in lines {
            let lowerLine = line.lowercased()
            
            // Skip the ps command itself to avoid self-detection
            if lowerLine.contains("ps -ax") || lowerLine.contains("tokenpet") {
                continue
            }
            
            // Skip known persistent background/daemon processes to avoid false positives
            if lowerLine.contains("/applications/codex.app") ||
               lowerLine.contains("gemini_bridge_server.py") ||
               lowerLine.contains("bare-modifier-monitor") ||
               lowerLine.contains("skycomputeruseservice") ||
               lowerLine.contains("node_repl") ||
               lowerLine.contains("crashpad_handler") {
                continue
            }
            
            if geminiEnabled {
                for kw in geminiKeywords {
                    if lowerLine.contains(kw) {
                        geminiDetected = true
                        break
                    }
                }
            }
            
            if codexEnabled {
                for kw in codexKeywords {
                    if lowerLine.contains(kw) {
                        codexDetected = true
                        break
                    }
                }
            }
            
            if claudeEnabled {
                for kw in claudeKeywords {
                    if lowerLine.contains(kw) {
                        claudeDetected = true
                        break
                    }
                }
            }
        }
        
        self.isGeminiRunningFromPS = geminiDetected
        self.isCodexRunningFromPS = codexDetected
        self.isClaudeRunningFromPS = claudeDetected
        self.hasMonitoringError = false
        updatePublishedStates()
        
        // Note: quota is now tracked automatically by UsageLogParser via log file scanning
    }
}
