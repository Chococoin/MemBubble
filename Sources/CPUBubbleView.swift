import SwiftUI

// MARK: - CPU Bubble View

struct CPUBubbleView: View {
    let info: CPUInfo

    var cpuColor: Color {
        if info.totalUsage < 40 { return .cyan }
        if info.totalUsage < 65 { return .blue }
        if info.totalUsage < 85 { return .purple }
        return .red
    }

    var fillRatio: CGFloat { max(0.15, min(info.totalUsage / 100, 1.0)) }

    var body: some View {
        #if LIQUID_GLASS
        if #available(macOS 26, *) {
            glassBubbleBody
        } else {
            legacyBubbleBody
        }
        #else
        legacyBubbleBody
        #endif
    }

    // MARK: - Liquid Glass (macOS 26+)

    #if LIQUID_GLASS
    @available(macOS 26, *)
    private var glassBubbleBody: some View {
        GlassBubbleView(tintColor: cpuColor, fillRatio: fillRatio) {
            Text(String(format: "%.0f%%", info.totalUsage))
                .font(.system(size: 7, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
    #endif

    // MARK: - Legacy Pearl (macOS 13-15)

    private var legacyBubbleBody: some View {
        let s: CGFloat = 28

        return ZStack {
            // Pearl body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.18).opacity(0.6),
                            Color(white: 0.10).opacity(0.5),
                            Color(white: 0.05).opacity(0.4)
                        ],
                        center: .center,
                        startRadius: s * 0.05,
                        endRadius: s * 0.50
                    )
                )
                .frame(width: s, height: s)

            // CPU liquid fill
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            cpuColor.opacity(0.0),
                            cpuColor.opacity(0.20),
                            cpuColor.opacity(0.45),
                            cpuColor.opacity(0.6)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 1.0 - fillRatio),
                        endPoint: .bottom
                    )
                )
                .frame(width: s, height: s)
                .animation(.easeInOut(duration: 0.8), value: fillRatio)

            // Surface sheen
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.02),
                            .clear
                        ],
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: s * 0.0,
                        endRadius: s * 0.5
                    )
                )
                .frame(width: s, height: s)

            // Specular highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.5),
                            .white.opacity(0.1),
                            .clear
                        ],
                        center: UnitPoint(x: 0.45, y: 0.4),
                        startRadius: 0,
                        endRadius: s * 0.22
                    )
                )
                .frame(width: s * 0.4, height: s * 0.25)
                .offset(x: -s * 0.08, y: -s * 0.18)

            // Rim light
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.25),
                            .white.opacity(0.05),
                            .clear,
                            .clear,
                            .clear,
                            .white.opacity(0.08),
                            .white.opacity(0.25)
                        ],
                        center: .center,
                        startAngle: .degrees(-40),
                        endAngle: .degrees(320)
                    ),
                    lineWidth: 2
                )
                .frame(width: s - 2, height: s - 2)

            // Text
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", info.totalUsage))
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(cpuColor)
            }
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        }
        .clipShape(Circle())
        .opacity(0.9)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}
