import Cocoa
import SwiftUI
import ServiceManagement

// MARK: - Custom Hosting View for Right-Click

class RightClickHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: ((NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
}

// MARK: - Floating Panel (stays on all spaces, even with .regular activation)

class FloatingWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        level = .floating
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: FloatingWindow!
    var settingsWindow: NSWindow?
    var thresholdsWindow: NSWindow?
    var anchorPoint: NSPoint = .zero      // the fixed corner when resizing
    var anchorQuadrant: AnchorQuadrant = .topRight  // which corner is anchored

    let memoryReader = MemoryReader()
    let cpuReader = CPUReader()
    let session = WorkSession()
    let settings = SettingsManager.shared
    var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular mode: shows dock icon. Floating panel stays on all spaces.
        NSApp.setActivationPolicy(.regular)

        // Request notification permission
        NotificationManager.shared.requestPermission()

        // Start recording snapshots for session export
        SessionExporter.shared.startRecording(memoryReader: memoryReader, cpuReader: cpuReader)

        // Setup menu bar
        menuBarController = MenuBarController(memoryReader: memoryReader, cpuReader: cpuReader)
        menuBarController.onToggleBubble = { [weak self] in
            self?.toggleBubbleVisibility()
        }
        menuBarController.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        menuBarController.onCalibrate = { [weak self] in
            self?.memoryReader.calibrate()
        }
        menuBarController.onRefresh = { [weak self] in
            self?.memoryReader.refresh()
            self?.cpuReader.refresh()
        }

        // Create main bubble window
        let contentView = ContentView(
            memoryReader: memoryReader,
            cpuReader: cpuReader,
            session: session,
            settings: settings
        )

        window = FloatingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false

        let hostingView = RightClickHostingView(rootView: contentView)
        hostingView.onRightClick = { [weak self] event in
            guard let self = self else { return }
            NSMenu.popUpContextMenu(self.contextMenu, with: event, for: hostingView)
        }
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Auto-resize window based on content
        window.contentView?.setFrameSize(window.contentView?.fittingSize ?? NSSize(width: 80, height: 80))

        // Restore saved anchor + quadrant, or default to top-right of screen
        let bubbleSize = window.frame.size
        if let saved = settings.loadWindowAnchor() {
            anchorPoint = saved.point
            anchorQuadrant = saved.quadrant
        } else if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            anchorPoint = NSPoint(x: sf.maxX - 10, y: sf.maxY - 10)
            anchorQuadrant = .topRight
        }
        window.setFrameOrigin(anchorQuadrant.origin(for: anchorPoint, size: bubbleSize))

        // Observe content size changes — keep anchored corner fixed
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: window.contentView,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let contentView = self.window.contentView else { return }
            let newSize = contentView.fittingSize
            let origin = self.anchorQuadrant.origin(for: self.anchorPoint, size: newSize)

            self.window.setFrame(
                NSRect(origin: origin, size: newSize),
                display: true,
                animate: true
            )
        }

        // Observe window move (user dragging) to update anchor + quadrant
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let frame = self.window.frame
            // Determine quadrant from window center relative to screen
            if let screen = self.window.screen ?? NSScreen.main {
                self.anchorQuadrant = AnchorQuadrant.from(
                    windowCenter: NSPoint(x: frame.midX, y: frame.midY),
                    screen: screen
                )
            }
            self.anchorPoint = self.anchorQuadrant.anchorPoint(from: frame)
            self.settings.saveWindowAnchor(self.anchorPoint, quadrant: self.anchorQuadrant)
        }

        // Timer to record pressure history, send notifications, update menu bar
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.session.record(
                pressure: self.memoryReader.info.pressure,
                cpuUsage: self.cpuReader.info.totalUsage,
                memoryUsed: self.memoryReader.info.used
            )
            NotificationManager.shared.checkPressureAndNotify(self.memoryReader.info.pressure)
            self.menuBarController.update()

            // Write shared data for widget
            SharedData.write(
                pressure: self.memoryReader.info.pressure,
                cpuUsage: self.cpuReader.info.totalUsage,
                usedMemory: self.memoryReader.info.used,
                totalMemory: self.memoryReader.info.total
            )
        }

        // Force glass to re-sample background when switching spaces
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Nudge the window to force the glass effect to re-render
            let frame = self.window.frame
            self.window.setFrame(frame.offsetBy(dx: 0, dy: 1), display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.window.setFrame(frame, display: true)
            }
        }

        window.orderFrontRegardless()
    }

    private func toggleBubbleVisibility() {
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    // MARK: - Context Menu

    lazy var contextMenu: NSMenu = {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshMemory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Calibrate (Set Zero)", action: #selector(calibrateBaseline), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Display mode submenu
        let displayMenu = NSMenu()
        let memItem = NSMenuItem(title: "Memory Only", action: #selector(setDisplayMemory), keyEquivalent: "")
        let cpuItem = NSMenuItem(title: "CPU Only", action: #selector(setDisplayCPU), keyEquivalent: "")
        let bothItem = NSMenuItem(title: "Memory + CPU", action: #selector(setDisplayBoth), keyEquivalent: "")
        let allItem = NSMenuItem(title: "Memory + Activity + CPU", action: #selector(setDisplayAll), keyEquivalent: "")
        displayMenu.addItem(memItem)
        displayMenu.addItem(cpuItem)
        displayMenu.addItem(bothItem)
        displayMenu.addItem(allItem)
        let displaySubmenu = NSMenuItem(title: "Display Mode", action: nil, keyEquivalent: "")
        displaySubmenu.submenu = displayMenu
        menu.addItem(displaySubmenu)

        // Sort submenu
        let sortMenu = NSMenu()
        sortMenu.addItem(NSMenuItem(title: "By Memory", action: #selector(setSortMemory), keyEquivalent: ""))
        sortMenu.addItem(NSMenuItem(title: "By CPU", action: #selector(setSortCPU), keyEquivalent: ""))
        sortMenu.addItem(NSMenuItem(title: "By Name", action: #selector(setSortName), keyEquivalent: ""))
        let sortSubmenu = NSMenuItem(title: "Sort Processes", action: nil, keyEquivalent: "")
        sortSubmenu.submenu = sortMenu
        menu.addItem(sortSubmenu)

        menu.addItem(NSMenuItem.separator())

        // Notification toggle
        let muteItem = NSMenuItem(title: "Mute Notifications", action: #selector(toggleMuteNotifications), keyEquivalent: "")
        muteItem.state = settings.notificationsMuted ? .on : .off
        menu.addItem(muteItem)

        // Alert sound toggle
        let soundItem = NSMenuItem(title: "Alert Sound", action: #selector(toggleAlertSound), keyEquivalent: "")
        soundItem.state = settings.alertSoundEnabled ? .on : .off
        menu.addItem(soundItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = UserDefaults.standard.bool(forKey: SettingsKey.launchAtLogin) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Export submenu
        let exportMenu = NSMenu()
        exportMenu.addItem(NSMenuItem(title: "Export All (JSON + CSV + HTML)", action: #selector(exportAll), keyEquivalent: ""))
        exportMenu.addItem(NSMenuItem.separator())
        exportMenu.addItem(NSMenuItem(title: "Export JSON", action: #selector(exportJSON), keyEquivalent: ""))
        exportMenu.addItem(NSMenuItem(title: "Export CSV", action: #selector(exportCSV), keyEquivalent: ""))
        exportMenu.addItem(NSMenuItem(title: "Export HTML Report", action: #selector(exportHTML), keyEquivalent: ""))
        let exportSubmenu = NSMenuItem(title: "Export Session", action: nil, keyEquivalent: "")
        exportSubmenu.submenu = exportMenu
        menu.addItem(exportSubmenu)
        menu.addItem(NSMenuItem(title: "Open Sessions Folder", action: #selector(openSessionsFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Thresholds...", action: #selector(showThresholds), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit MemBubble", action: #selector(quitApp), keyEquivalent: ""))

        return menu
    }()

    @objc func refreshMemory() {
        memoryReader.refresh()
        cpuReader.refresh()
    }

    @objc func calibrateBaseline() {
        memoryReader.calibrate()
    }

    @objc func setDisplayMemory() { settings.displayMode = .memoryOnly }
    @objc func setDisplayCPU() { settings.displayMode = .cpuOnly }
    @objc func setDisplayBoth() { settings.displayMode = .both }
    @objc func setDisplayAll() { settings.displayMode = .all }

    @objc func setSortMemory() { settings.processSortMode = .byMemory }
    @objc func setSortCPU() { settings.processSortMode = .byCPU }
    @objc func setSortName() { settings.processSortMode = .byName }

    @objc func toggleMuteNotifications() {
        settings.notificationsMuted.toggle()
    }

    @objc func toggleAlertSound() {
        settings.alertSoundEnabled.toggle()
    }

    @objc func toggleLaunchAtLogin() {
        let current = UserDefaults.standard.bool(forKey: SettingsKey.launchAtLogin)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: SettingsKey.launchAtLogin)

        if #available(macOS 13.0, *) {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Requires .app bundle to work
            }
        }
    }

    @objc func showThresholds() {
        if thresholdsWindow == nil {
            let view = ThresholdSettingsView(settings: settings)
            let hostingController = NSHostingController(rootView: view)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                styleMask: [.titled, .closable, .hudWindow, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = hostingController
            panel.title = "Thresholds"
            panel.center()
            panel.isFloatingPanel = true
            thresholdsWindow = panel
        }
        thresholdsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings)
            let hostingController = NSHostingController(rootView: view)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            win.contentViewController = hostingController
            win.title = "MemBubble Settings"
            win.center()
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func exportAll() {
        if let url = SessionExporter.shared.exportAll(session: session) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func exportJSON() {
        if let url = SessionExporter.shared.exportJSON(session: session) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    @objc func exportCSV() {
        if let url = SessionExporter.shared.exportCSV(session: session) {
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    @objc func exportHTML() {
        if let url = SessionExporter.shared.exportHTML(session: session) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openSessionsFolder() {
        NSWorkspace.shared.open(SessionExporter.shared.sessionsDirectory)
    }

    @objc func quitApp() {
        // Auto-export session in all formats on quit
        _ = SessionExporter.shared.exportAll(session: session)
        NSApplication.shared.terminate(nil)
    }
}
