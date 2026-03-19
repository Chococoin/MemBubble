import SwiftUI
import Darwin

// MARK: - Process Row View (handles its own click via NSView)

struct ProcessRowView: View {
    let process: ProcessMemInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(process.name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if process.memory > 1_073_741_824 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }

                if process.cpuPercent >= 1 {
                    Text(String(format: "%.0f%%", process.cpuPercent))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                }

                Text(formatBytes(process.memory))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(processColor(process.memory))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering || isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(
                ClickCatcher(onClick: onSelect)
            )

            if isSelected {
                ProcessActionView(process: process, onDismiss: onDismiss)
                    .padding(.top, 4)
            }
        }
    }

    func processColor(_ mem: UInt64) -> Color {
        let mb = mem / 1_048_576
        if mb > 500 { return .red }
        if mb > 200 { return .orange }
        if mb > 100 { return .yellow }
        return .white.opacity(0.8)
    }
}

// MARK: - NSView Click Catcher (bypasses SwiftUI gesture issues in floating panels)

struct ClickCatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.onClick = onClick
    }
}

class ClickCatcherView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

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
                .buttonStyle(.bordered)
                .tint(.orange)

                Button(action: { terminateProcess(signal: SIGKILL) }) {
                    Label("Force Quit", systemImage: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Spacer()

                Button("Cancel", action: onDismiss)
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
            }

            if showError {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
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
