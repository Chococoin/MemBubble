import SwiftUI
import Darwin

// MARK: - Process Action View

struct ProcessActionView: View {
    let process: ProcessMemInfo
    let onDismiss: () -> Void
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(process.name)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Text("PID \(process.pid)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }

            Text(formatBytes(process.memory))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            Divider().background(Color.white.opacity(0.2))

            HStack(spacing: 8) {
                Button(action: { terminateProcess(signal: SIGTERM) }) {
                    Label("Terminate", systemImage: "xmark.circle")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.orange)

                Button(action: { terminateProcess(signal: SIGKILL) }) {
                    Label("Force Quit", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Spacer()

                Button("Cancel", action: onDismiss)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.6))
            }

            if showError {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func terminateProcess(signal: Int32) {
        let result = kill(process.pid, signal)
        if result != 0 {
            let err = errno
            if err == EPERM {
                errorMessage = "Permission denied — system process"
            } else {
                errorMessage = "Failed: \(String(cString: strerror(err)))"
            }
            showError = true
        } else {
            onDismiss()
        }
    }
}
