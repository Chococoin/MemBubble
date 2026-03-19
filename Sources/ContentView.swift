import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @ObservedObject var memoryReader: MemoryReader
    @ObservedObject var cpuReader: CPUReader
    @ObservedObject var session: WorkSession
    @ObservedObject var settings: SettingsManager
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                DetailView(
                    info: memoryReader.info,
                    diskInfo: memoryReader.diskInfo,
                    processes: memoryReader.topProcesses,
                    session: session,
                    cpuInfo: settings.displayMode != .memoryOnly ? cpuReader.info : nil,
                    onClose: { expanded = false }
                )
            } else {
                bubbleContent
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expanded = true
                        }
                    }
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
        }
    }
}
