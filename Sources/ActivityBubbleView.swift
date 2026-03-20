import SwiftUI

// MARK: - Activity Bubble View (baseline-relative usage)

struct ActivityBubbleView: View {
    let activity: Double

    var activityColor: Color {
        if activity < 30 { return .mint }
        if activity < 55 { return .teal }
        if activity < 80 { return .indigo }
        return .pink
    }

    var fillRatio: CGFloat { min(activity / 100, 1.0) }

    var body: some View {
        let s: CGFloat = 28

        ZStack {
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

            // Activity liquid fill
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            activityColor.opacity(0.0),
                            activityColor.opacity(0.20),
                            activityColor.opacity(0.45),
                            activityColor.opacity(0.6)
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
                Text(String(format: "%.0f%%", activity))
                    .font(.system(size: 6, weight: .bold, design: .rounded))
                    .foregroundStyle(activityColor)
            }
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        }
        .clipShape(Circle())
        .opacity(0.9)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}
