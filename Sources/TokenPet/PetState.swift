import Foundation
import Combine

public enum PetVisualState: String {
    case idle = "idle"
    case working = "working"
    case finished = "finished"
    case warning = "warning"
    case error = "error"
}

@MainActor public class PetStateManager: ObservableObject {
    public static let shared = PetStateManager()
    
    @Published public var currentState: PetVisualState = .idle
    @Published public var detailStatus: String = "空闲"
    
    private var processMonitor = ProcessMonitor.shared
    private var quotaManager = QuotaManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private var recentlyFinishedTimer: Timer?
    private var recentlyFinished = false
    
    private init() {
        // Observe all input sources to compute the overall pet state
        Publishers.CombineLatest3(
            processMonitor.$isGeminiRunning
                .combineLatest(processMonitor.$isCodexRunning)
                .combineLatest(processMonitor.$isClaudeRunning),
            processMonitor.$hasMonitoringError,
            quotaManager.$is5hWarning.combineLatest(quotaManager.$is7dWarning)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] processStates, hasError, quotaWarnings in
            let ((geminiCodex, claude), _) = (processStates, ())
            self?.updateState(
                isGeminiRunning: geminiCodex.0,
                isCodexRunning: geminiCodex.1,
                isClaudeRunning: claude,
                hasError: hasError,
                is5hWarning: quotaWarnings.0,
                is7dWarning: quotaWarnings.1
            )
        }
        .store(in: &cancellables)
    }
    
    private func updateState(
        isGeminiRunning: Bool,
        isCodexRunning: Bool,
        isClaudeRunning: Bool,
        hasError: Bool,
        is5hWarning: Bool,
        is7dWarning: Bool
    ) {
        let isRunning = isGeminiRunning || isCodexRunning || isClaudeRunning
        
        // Handle "Recently Finished" Transition
        if !isRunning && (currentState == .working) {
            triggerRecentlyFinished()
        }
        
        if hasError {
            currentState = .error
            detailStatus = "监控异常"
        } else if isRunning {
            // Cancel recently finished state if a new task starts
            cancelRecentlyFinished()
            currentState = .working
            
            var runningTools: [String] = []
            if isGeminiRunning { runningTools.append("反重力") }
            if isCodexRunning { runningTools.append("Codex") }
            if isClaudeRunning { runningTools.append("Claude") }
            
            if runningTools.count > 1 {
                detailStatus = runningTools.joined(separator: " & ") + " 工作中"
            } else {
                detailStatus = (runningTools.first ?? "AI") + " CLI 工作中"
            }
        } else if recentlyFinished {
            currentState = .finished
            detailStatus = "任务已完成"
        } else if is5hWarning || is7dWarning {
            currentState = .warning
            if is5hWarning && is7dWarning {
                detailStatus = "额度双重警告 (5H & 7D 低)"
            } else if is5hWarning {
                detailStatus = "5小时额度临近超限"
            } else {
                detailStatus = "7天额度临近超限"
            }
        } else {
            currentState = .idle
            detailStatus = "守护中"
        }
    }
    
    private func triggerRecentlyFinished() {
        recentlyFinished = true
        recentlyFinishedTimer?.invalidate()
        recentlyFinishedTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.recentlyFinished = false
                self.updateState(
                    isGeminiRunning: self.processMonitor.isGeminiRunning,
                    isCodexRunning: self.processMonitor.isCodexRunning,
                    isClaudeRunning: self.processMonitor.isClaudeRunning,
                    hasError: self.processMonitor.hasMonitoringError,
                    is5hWarning: self.quotaManager.is5hWarning,
                    is7dWarning: self.quotaManager.is7dWarning
                )
            }
        }
    }
    
    private func cancelRecentlyFinished() {
        recentlyFinished = false
        recentlyFinishedTimer?.invalidate()
        recentlyFinishedTimer = nil
    }
}
