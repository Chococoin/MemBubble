import SwiftUI

// MARK: - Rotary Knob Control

struct KnobView: View {
    let label: String
    let color: Color
    @Binding var value: Double  // 0.0 to 1.0

    @State private var dragAngle: Double = 0

    // Knob range: -135° to +135° (270° sweep)
    private let minAngle: Double = -135
    private let maxAngle: Double = 135

    private var currentAngle: Double {
        minAngle + (maxAngle - minAngle) * value
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))

            ZStack {
                // Track background
                Circle()
                    .trim(from: trimStart, to: trimEnd)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(135))

                // Active arc
                Circle()
                    .trim(from: trimStart, to: trimStart + (trimEnd - trimStart) * value)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(135))

                // Knob body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(white: 0.35),
                                Color(white: 0.20),
                                Color(white: 0.12)
                            ],
                            center: UnitPoint(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: 22
                        )
                    )
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

                // Indicator line
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 12)
                    .offset(y: -10)
                    .rotationEffect(.degrees(currentAngle))

                // Center dot
                Circle()
                    .fill(Color(white: 0.25))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 60, height: 60)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let center = CGPoint(x: 30, y: 30)
                        let vector = CGPoint(
                            x: gesture.location.x - center.x,
                            y: gesture.location.y - center.y
                        )
                        let angle = atan2(vector.x, -vector.y) * 180 / .pi // 0° = top

                        // Map angle to value (clamped to knob range)
                        let clamped = max(minAngle, min(maxAngle, angle))
                        value = (clamped - minAngle) / (maxAngle - minAngle)
                    }
            )

            Text(String(format: "%.0f%%", value * 100))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private var trimStart: CGFloat { 0.0 }
    private var trimEnd: CGFloat { 0.75 }  // 270° / 360°
}
