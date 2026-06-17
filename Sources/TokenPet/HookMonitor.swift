import Foundation
import Combine

/// 监听本地文件 `~/.tokenpet/status` 发生的变化，实现毫秒级“动作钩子”联动
@MainActor public class HookMonitor {
    public static let shared = HookMonitor()
    
    private let hookDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".tokenpet")
    private let hookFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".tokenpet/status")
    
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var timeoutTimer: Timer?
    
    private init() {
        setupHookFile()
        startWatching()
    }
    
    private func setupHookFile() {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: hookDir.path) {
                try fm.createDirectory(at: hookDir, withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: hookFile.path) {
                try "idle".write(to: hookFile, atomically: true, encoding: .utf8)
            }
        } catch {
            print("TokenPet: 创建动作钩子文件失败 - \(error.localizedDescription)")
        }
    }
    
    public func startWatching() {
        // Cancel existing watcher if any
        dispatchSource?.cancel()
        if fileDescriptor >= 0 {
            close(fileDescriptor)
        }
        
        let fd = open(hookFile.path, O_EVTONLY)
        guard fd >= 0 else {
            print("TokenPet: 打开动作钩子文件描述符失败")
            return
        }
        self.fileDescriptor = fd
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        
        source.setEventHandler { [weak self] in
            self?.handleFileWrite()
        }
        
        source.setCancelHandler {
            close(fd)
        }
        
        self.dispatchSource = source
        source.resume()
        
        // Initial check
        handleFileWrite()
    }
    
    private func handleFileWrite() {
        do {
            let content = try String(contentsOf: hookFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            
            parseHookContent(content)
        } catch {
            // Read failure due to rapid writing can be safely ignored
        }
    }
    
    private func parseHookContent(_ content: String) {
        // Reset timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        let processMonitor = ProcessMonitor.shared
        
        if content.hasPrefix("working:") {
            let parts = content.split(separator: ":")
            guard parts.count >= 2 else { return }
            let tool = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if tool == "gemini" || tool == "antigravity" {
                processMonitor.isGeminiRunningFromHook = true
            } else if tool == "codex" {
                processMonitor.isCodexRunningFromHook = true
            } else if tool == "claude" {
                processMonitor.isClaudeRunningFromHook = true
            }
            
            // Set 30s safety timeout to prevent getting stuck if shell hook fails to report completion
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.resetHookStates()
                }
            }
        } else if content == "idle" || content == "finished" || content == "done" {
            resetHookStates()
        }
    }
    
    private func resetHookStates() {
        let pm = ProcessMonitor.shared
        pm.isGeminiRunningFromHook = false
        pm.isCodexRunningFromHook = false
        pm.isClaudeRunningFromHook = false
    }
    
    deinit {
        dispatchSource?.cancel()
    }
}
