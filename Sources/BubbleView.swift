import SwiftUI

// MARK: - Memory Bubble View (Collapsed Pearl)

struct BubbleView: View {
    let info: MemoryInfo
    @State private var pulseScale: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0

    var pColor: Color { pressureColor(for: info.pressure) }
    var fillRatio: CGFloat { info.pressure / 100 }

    var body: some View {
        let s: CGFloat = 28

        ZStack {
            // 1. Deep pearl body — dark core with radial depth
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

            // 2. Internal pressure liquid — rises from bottom (animated)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            pColor.opacity(0.0),
                            pColor.opacity(0.20),
                            pColor.opacity(0.45),
                            pColor.opacity(0.6)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 1.0 - fillRatio),
                        endPoint: .bottom
                    )
                )
                .frame(width: s, height: s)
                .animation(.easeInOut(duration: 0.8), value: fillRatio)
                .animation(.easeInOut(duration: 0.5), value: pColor)

            // 3. Internal caustic reflections
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pColor.opacity(0.4),
                            pColor.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.3
                    )
                )
                .frame(width: s * 0.6, height: s * 0.35)
                .offset(y: s * (0.5 - fillRatio * 0.5))
                .blur(radius: 4)

            // 4. Secondary internal glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            pColor.opacity(0.2),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.25
                    )
                )
                .frame(width: s * 0.4, height: s * 0.25)
                .offset(x: -s * 0.08, y: s * 0.15)
                .blur(radius: 3)

            // 5. Pearl surface sheen
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

            // 6. Primary specular highlight
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

            // 7. Sharp specular pinpoint
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.7),
                            .white.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.08
                    )
                )
                .frame(width: s * 0.1, height: s * 0.07)
                .offset(x: -s * 0.08, y: -s * 0.2)

            // 8. Rim light
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

            // 9. Bottom reflection
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.07),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: s * 0.18
                    )
                )
                .frame(width: s * 0.35, height: s * 0.12)
                .offset(y: s * 0.34)

            // 10. Pulse glow overlay (animates on threshold crossing)
            Circle()
                .fill(pColor.opacity(0.3))
                .frame(width: s, height: s)
                .scaleEffect(pulseScale)
                .opacity(pulseScale > 1.0 ? 0.6 : 0)
                .blur(radius: 4)

            // 11. Text content
            VStack(spacing: 0) {
                Text(String(format: "%.0f%%", info.pressure))
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(pColor)
            }
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        }
        .clipShape(Circle())
        .opacity(0.9)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        .scaleEffect(pulseScale > 1.0 ? pulseScale * 0.98 : 1.0)
        .offset(x: shakeOffset)
        .onChange(of: PressureLevel.from(pressure: info.pressure)) { oldLevel, newLevel in
            if newLevel > oldLevel {
                // Pulse animation on escalation
                withAnimation(.easeInOut(duration: 0.3).repeatCount(2, autoreverses: true)) {
                    pulseScale = 1.15
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    pulseScale = 1.0
                }

                // Shake on entering red zone
                if newLevel == .red {
                    triggerShake()
                }
            }
        }
    }

    private func triggerShake() {
        let duration = 0.06
        let offsets: [CGFloat] = [4, -4, 3, -3, 2, -2, 1, 0]
        for (i, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * Double(i)) {
                withAnimation(.linear(duration: duration)) {
                    shakeOffset = offset
                }
            }
        }
    }
}
