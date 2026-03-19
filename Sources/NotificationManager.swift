import Cocoa
import UserNotifications

// MARK: - Notification Manager

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var lastNotificationDate: Date?
    private var lastNotifiedLevel: PressureLevel = .green
    private let cooldownInterval: TimeInterval = 300  // 5 minutes

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    SettingsManager.shared.notificationsMuted = true
                }
            }
        }
    }

    func checkPressureAndNotify(_ pressure: Double) {
        guard !SettingsManager.shared.notificationsMuted else { return }

        let level = PressureLevel.from(pressure: pressure)

        // Only notify on escalation (green→yellow→orange→red)
        guard level > lastNotifiedLevel else {
            // If pressure dropped back, reset so we can re-alert on next escalation
            if level < lastNotifiedLevel {
                lastNotifiedLevel = level
            }
            return
        }

        // Cooldown check
        if let last = lastNotificationDate, Date().timeIntervalSince(last) < cooldownInterval {
            return
        }

        sendNotification(level: level, pressure: pressure)
        lastNotifiedLevel = level
        lastNotificationDate = Date()
    }

    private func sendNotification(level: PressureLevel, pressure: Double) {
        let content = UNMutableNotificationContent()
        content.title = "MemBubble — \(level.label)"
        content.body = String(format: "Memory pressure at %.0f%%", pressure)

        switch level {
        case .yellow:
            content.body += " — memory usage is elevated"
        case .orange:
            content.body += " — consider closing unused apps"
        case .red:
            content.body += " — system may become unresponsive"
        case .green:
            break
        }

        if SettingsManager.shared.alertSoundEnabled {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "pressure-\(level.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        // Also play alert sound through NSSound if enabled
        if SettingsManager.shared.alertSoundEnabled {
            NSSound(named: "Purr")?.play()
        }
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
