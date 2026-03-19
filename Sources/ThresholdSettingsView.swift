import SwiftUI

// MARK: - Threshold Settings Panel

struct ThresholdSettingsView: View {
    @ObservedObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pressure Thresholds")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            VStack(spacing: 12) {
                thresholdSlider(
                    label: "Yellow (Elevated)",
                    value: $settings.thresholds.yellow,
                    color: .yellow,
                    range: 20...60
                )

                thresholdSlider(
                    label: "Orange (High)",
                    value: $settings.thresholds.orange,
                    color: .orange,
                    range: 40...80
                )

                thresholdSlider(
                    label: "Red (Critical)",
                    value: $settings.thresholds.red,
                    color: .red,
                    range: 60...95
                )
            }

            HStack {
                Button("Reset to Defaults") {
                    settings.thresholds = ThresholdConfig.default
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    func thresholdSlider(label: String, value: Binding<Double>, color: Color, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                Text(String(format: "%.0f%%", value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range, step: 5)
                .tint(color)
        }
    }
}
