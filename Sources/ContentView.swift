import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var memoryReader: MemoryReader
    @ObservedObject var cpuReader: CPUReader
    @ObservedObject var session: WorkSession
    @ObservedObject var settings: SettingsManager
    @State private var expanded = false
    @State private var showContent = true  // controls fade in/out

    var body: some View {
        Group {
            if expanded {
                DetailView(
                    info: memoryReader.info,
                    diskInfo: memoryReader.diskInfo,
                    processes: memoryReader.topProcesses,
                    session: session,
                    activity: memoryReader.activity,
                    cpuInfo: settings.displayMode != .memoryOnly ? cpuReader.info : nil,
                    onClose: { collapse() }
                )
                .opacity(showContent ? 1 : 0)
            } else {
                bubbleContent
                    .opacity(showContent ? 1 : 0)
                    .onTapGesture { expand() }
            }
        }
    }

    private func expand() {
        // Fade out bubble
        withAnimation(.easeOut(duration: 0.1)) {
            showContent = false
        }
        // Switch to detail after fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            expanded = true
            // Fade in detail
            withAnimation(.easeIn(duration: 0.15)) {
                showContent = true
            }
        }
    }

    private func collapse() {
        // Fade out detail
        withAnimation(.easeOut(duration: 0.1)) {
            showContent = false
        }
        // Switch to bubble after fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            expanded = false
            withAnimation(.easeIn(duration: 0.15)) {
                showContent = true
            }
        }
    }

    @ViewBuilder
    var bubbleContent: some View {
        switch settings.displayMode {
        case .memoryOnly:
            BubbleView(info: memoryReader.info)
        case .cpuOnly:
            CPUBubbleView(info: cpuReader.info)
        case .both:
            HStack(spacing: 4) {
                BubbleView(info: memoryReader.info)
                CPUBubbleView(info: cpuReader.info)
            }
        case .all:
            HStack(spacing: 4) {
                BubbleView(info: memoryReader.info)
                ActivityBubbleView(activity: memoryReader.activity)
                CPUBubbleView(info: cpuReader.info)
            }
        }
    }
}
