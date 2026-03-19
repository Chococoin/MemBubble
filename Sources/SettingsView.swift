import SwiftUI
import ServiceManagement

// MARK: - Settings Window View

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
                .tag(0)

            thresholdsTab
                .tabItem { Label("Thresholds", systemImage: "slider.horizontal.3") }
                .tag(1)

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(2)

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(3)
        }
        .padding(20)
        .frame(width: 420, height: 300)
    }

    // MARK: - General Tab

    var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Launch at Login", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: SettingsKey.launchAtLogin) },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: SettingsKey.launchAtLogin)
                    if #available(macOS 13.0, *) {
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Silently fail — requires .app bundle
                        }
                    }
                }
            ))

            Picker("Display Mode", selection: $settings.displayMode) {
                Text("Memory Only").tag(DisplayMode.memoryOnly)
                Text("CPU Only").tag(DisplayMode.cpuOnly)
                Text("Memory + CPU").tag(DisplayMode.both)
            }
            .pickerStyle(.segmented)

            Picker("Process Sort", selection: $settings.processSortMode) {
                Text("By Memory").tag(ProcessSortMode.byMemory)
                Text("By Name").tag(ProcessSortMode.byName)
            }
            .pickerStyle(.segmented)

            Spacer()
        }
    }

    // MARK: - Thresholds Tab

    var thresholdsTab: some View {
        ThresholdSettingsView(settings: settings)
    }

    // MARK: - Notifications Tab

    var notificationsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Mute Notifications", isOn: $settings.notificationsMuted)

            Toggle("Alert Sound", isOn: $settings.alertSoundEnabled)

            Text("Notifications are sent when memory pressure escalates between zones (green → yellow → orange → red). A 5-minute cooldown prevents spam.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Appearance Tab

    var appearanceTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The pearl bubble appearance is automatic based on memory pressure level and your configured thresholds.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                colorSwatch("Normal", .green)
                colorSwatch("Elevated", .yellow)
                colorSwatch("High", .orange)
                colorSwatch("Critical", .red)
            }

            Spacer()
        }
    }

    func colorSwatch(_ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Circle().fill(color).frame(width: 20, height: 20)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}
