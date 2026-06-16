import AppKit
import SwiftUI
@preconcurrency import UserNotifications
import Combine

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    var petPanel: PetPanel!
    var settingsPopover: NSPopover?
    var settingsWindow: NSWindow?
    
    private var settings = SettingsManager.shared
    private var stateManager = PetStateManager.shared
    private var quotaManager = QuotaManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification authorization
        setupNotifications()
        
        // Setup Status Bar Menu
        setupStatusItem()
        
        // Setup Transparent Pet Window
        setupPetPanel()
        
        // Listen to settings changes
        setupBindings()
        
        // Observe quota warnings for system notification dispatch
        setupNotificationObservers()
        
        // Start process monitoring
        ProcessMonitor.shared.startMonitoring()
        
        // Trigger initial log parse to populate quota values
        quotaManager.forceRefresh()
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        ProcessMonitor.shared.stopMonitoring()
        CCDataCoordinator.shared.stopAutoRefresh()
    }
    
    // MARK: - Status Item
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            // Use system icon for menu bar (cute pet-like or workflow symbol)
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "TokenPet")
            button.action = #selector(statusBarClicked(_:))
            button.target = self
        }
        
        // Create context menu
        let menu = NSMenu()
        
        let statusMenuItem = NSMenuItem(title: "TokenPet: 守护中", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let togglePetItem = NSMenuItem(title: "隐藏宠物", action: #selector(togglePetVisibility), keyEquivalent: "h")
        togglePetItem.target = self
        menu.addItem(togglePetItem)
        
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 TokenPet", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = nil // Only open menu on right click, left click opens bubble
        
        // We'll handle left click -> Popover, right click -> Menu
    }
    
    @objc func statusBarClicked(_ sender: AnyObject?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Show menu on right click
            showMenuBarMenu()
        } else {
            // Show status bubble on left click
            togglePopover()
        }
    }
    
    private func showMenuBarMenu() {
        let menu = NSMenu()
        
        let statusTitle = "TokenPet: \(stateManager.detailStatus)"
        let statusTitleItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        menu.addItem(statusTitleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let isVisible = petPanel.isVisible
        let toggleTitle = isVisible ? "隐藏宠物" : "显示宠物"
        let togglePetItem = NSMenuItem(title: toggleTitle, action: #selector(togglePetVisibility), keyEquivalent: "h")
        togglePetItem.target = self
        menu.addItem(togglePetItem)
        
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 TokenPet", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        self.statusItem.menu = menu
        self.statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func togglePetVisibility() {
        if petPanel.isVisible {
            petPanel.orderOut(nil)
        } else {
            petPanel.makeKeyAndOrderFront(nil)
        }
    }
    
    // MARK: - Pet Panel Setup
    
    private func setupPetPanel() {
        let size: CGFloat = 200
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        
        // Restore window position
        if let x = settings.windowPositionX, let y = settings.windowPositionY {
            rect.origin = CGPoint(x: x, y: y)
        } else {
            // Default position: Bottom Right of screen
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                rect.origin = CGPoint(
                    x: screenRect.maxX - size - 40,
                    y: screenRect.minY + 40
                )
            }
        }
        
        petPanel = PetPanel(contentRect: rect)
        
        // Initialize window position settings if not already set
        if settings.windowPositionX == nil || settings.windowPositionY == nil {
            settings.windowPositionX = rect.origin.x
            settings.windowPositionY = rect.origin.y
        }
        
        // Host the SwiftUI view
        let petView = PetView()
        let hostingView = NSHostingView(rootView: petView)
        hostingView.frame = NSRect(x: 0, y: 0, width: size, height: size)
        petPanel.contentView = hostingView
        
        // Show panel
        petPanel.makeKeyAndOrderFront(nil)
        
        // Observe window movement to save position
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: petPanel)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let origin = self.petPanel.frame.origin
                self.settings.windowPositionX = origin.x
                self.settings.windowPositionY = origin.y
            }
            .store(in: &cancellables)
            
        // Left click → show status popover
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(petWindowClicked(_:)))
        clickGesture.buttonMask = 0x1 // left button only
        hostingView.addGestureRecognizer(clickGesture)
        
        // Right click → show context menu directly on pet
        let rightClickGesture = NSClickGestureRecognizer(target: self, action: #selector(petWindowRightClicked(_:)))
        rightClickGesture.buttonMask = 0x2 // right button only
        hostingView.addGestureRecognizer(rightClickGesture)
    }
    
    @objc func petWindowClicked(_ sender: NSClickGestureRecognizer) {
        togglePopover()
    }
    
    @objc func petWindowRightClicked(_ sender: NSClickGestureRecognizer) {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "TokenPet · \(stateManager.detailStatus)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hideItem = NSMenuItem(title: "隐藏宠物", action: #selector(togglePetVisibility), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
        
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "退出 TokenPet", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Show menu at cursor location
        let location = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: location, in: nil)
    }
    
    // MARK: - Popover
    
    private func togglePopover() {
        if settingsPopover == nil {
            settingsPopover = NSPopover()
            settingsPopover?.contentSize = NSSize(width: 270, height: 510)
            settingsPopover?.behavior = .transient
            settingsPopover?.contentViewController = NSHostingController(
                rootView: BubbleView(
                    onOpenSettings: { [weak self] in
                        self?.settingsPopover?.performClose(nil)
                        self?.openSettings()
                    },
                    onHidePet: { [weak self] in
                        self?.settingsPopover?.performClose(nil)
                        self?.petPanel.orderOut(nil)
                    },
                    onClose: { [weak self] in
                        self?.settingsPopover?.performClose(nil)
                    }
                )
            )
        }
        
        if let popover = settingsPopover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                // Determine whether to anchor to Status Item or Pet Panel
                if let button = statusItem.button, NSApp.currentEvent?.type == .leftMouseUp && NSApp.currentEvent?.window == button.window {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                } else {
                    popover.show(relativeTo: petPanel.contentView!.bounds, of: petPanel.contentView!, preferredEdge: .maxY)
                }
            }
        }
    }
    
    // MARK: - Settings Window
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "TokenPet 首选项"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            settingsWindow = window
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Bindings
    
    private func setupBindings() {
        // Bind AlwaysOnTop setting
        settings.$alwaysOnTop
            .sink { [weak self] alwaysOnTop in
                self?.petPanel.level = alwaysOnTop ? .floating : .normal
            }
            .store(in: &cancellables)
            
        // Bind size changes
        settings.$petSize
            .sink { _ in
                // We keep window frame constant and let view scale internally,
                // or we can adjust window size. For simplicity, scaling is handled
                // inside PetView via scaleEffect, so no frame adjustment is needed here.
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            }
        }
    }
    
    private func setupNotificationObservers() {
        // Send notification when 5h quota goes below warning
        quotaManager.$is5hWarning
            .dropFirst()
            .sink { [weak self] isWarning in
                guard let self = self, isWarning, self.settings.showNotifications else { return }
                self.sendNotification(
                    title: "5小时额度警报",
                    body: "5小时窗口额度不足！剩余额度: \(self.quotaManager.quota5hRemaining)次，请节约使用。"
                )
            }
            .store(in: &cancellables)
            
        // Send notification when 7d quota goes below warning
        quotaManager.$is7dWarning
            .dropFirst()
            .sink { [weak self] isWarning in
                guard let self = self, isWarning, self.settings.showNotifications else { return }
                self.sendNotification(
                    title: "7天周期额度警报",
                    body: "7天窗口额度不足！剩余额度: \(self.quotaManager.quota7dRemaining)次，预计重置时间: \(self.quotaManager.timeRemaining7d())。"
                )
            }
            .store(in: &cancellables)
            
        // Send notification when a workflow finishes
        stateManager.$currentState
            .sink { [weak self] state in
                guard let self = self, state == .finished, self.settings.showNotifications else { return }
                self.sendNotification(
                    title: "任务执行完成",
                    body: "AI 命令行任务已成功结束。TokenPet 恢复守护状态。"
                )
            }
            .store(in: &cancellables)
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error dispatching notification: \(error)")
            }
        }
    }
    
    // UNUserNotificationCenterDelegate
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner even when app is active
        completionHandler([.banner, .sound])
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - PetPanel NSPanel Subclass

class PetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
    }
    
    override var canBecomeKey: Bool {
        return false // Prevents stealing focus from other windows
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
