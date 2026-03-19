import Cocoa
import SwiftUI

// MARK: - Menu Bar Controller

class MenuBarController {
    private var statusItem: NSStatusItem?
    private var memoryReader: MemoryReader
    private var cpuReader: CPUReader
    var onToggleBubble: (() -> Void)?
    var onShowSettings: (() -> Void)?
    var onCalibrate: (() -> Void)?
    var onRefresh: (() -> Void)?

    init(memoryReader: MemoryReader, cpuReader: CPUReader) {
        self.memoryReader = memoryReader
        self.cpuReader = cpuReader
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        update()
    }

    func update() {
        guard let button = statusItem?.button else { return }

        let pressure = memoryReader.info.pressure
        let level = PressureLevel.from(pressure: pressure)
        let color: NSColor
        switch level {
        case .green: color = .systemGreen
        case .yellow: color = .systemYellow
        case .orange: color = .systemOrange
        case .red: color = .systemRed
        }

        // Colored dot + percentage
        let title = NSMutableAttributedString()

        let dot = NSAttributedString(string: "● ", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 10)
        ])
        title.append(dot)

        let text = NSAttributedString(
            string: String(format: "%.0f%%", pressure),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        title.append(text)

        button.attributedTitle = title
    }

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onToggleBubble?()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Toggle Bubble", action: #selector(toggleBubbleAction), keyEquivalent: ""))
        menu.items.last?.target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: ""))
        menu.items.last?.target = self

        menu.addItem(NSMenuItem(title: "Calibrate (Set Zero)", action: #selector(calibrateAction), keyEquivalent: ""))
        menu.items.last?.target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(settingsAction), keyEquivalent: ","))
        menu.items.last?.target = self

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit MemBubble", action: #selector(quitAction), keyEquivalent: "q"))
        menu.items.last?.target = self

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil  // Remove after showing so left-click works again
    }

    @objc private func toggleBubbleAction() { onToggleBubble?() }
    @objc private func refreshAction() { onRefresh?() }
    @objc private func calibrateAction() { onCalibrate?() }
    @objc private func settingsAction() { onShowSettings?() }
    @objc private func quitAction() { NSApplication.shared.terminate(nil) }
}
