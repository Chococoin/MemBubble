import SwiftUI

// MARK: - Liquid Glass Bubble Wrapper (macOS 26+)
// Uses ultraThinMaterial for stable glass look regardless of window focus state.
// Uses #if LIQUID_GLASS compile-time flag (set by build.sh when SDK >= 26).

#if LIQUID_GLASS

@available(macOS 26, *)
struct GlassBubbleView<Label: View>: View {
    let tintColor: Color
    let size: CGFloat
    let fillRatio: CGFloat
    let label: Label

    init(tintColor: Color, size: CGFloat = 27, fillRatio: CGFloat = 0.5, @ViewBuilder label: () -> Label) {
        self.tintColor = tintColor
        self.size = size
        self.fillRatio = fillRatio
        self.label = label()
    }

    var body: some View {
        ZStack {
            // Glass base — nearly invisible material, maximum transparency
            Circle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.04)
                .frame(width: size, height: size)

            // Liquid fill — rises from bottom, vivid color
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            tintColor.opacity(0.0),
                            tintColor.opacity(0.30),
                            tintColor.opacity(0.80)
                        ],
                        startPoint: UnitPoint(x: 0.5, y: 1.0 - fillRatio),
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .animation(.easeInOut(duration: 0.8), value: fillRatio)

            // 3D: top-left specular highlight
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.44),
                            .white.opacity(0.11),
                            .clear
                        ],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.5, height: size * 0.35)
                .offset(x: -size * 0.08, y: -size * 0.15)

            // 3D: sharp specular pinpoint
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.08
                    )
                )
                .frame(width: size * 0.12, height: size * 0.08)
                .offset(x: -size * 0.1, y: -size * 0.2)

            // 3D: rim light
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .white.opacity(0.40),
                            .white.opacity(0.08),
                            .clear,
                            .clear,
                            .clear,
                            .white.opacity(0.12),
                            .white.opacity(0.40)
                        ],
                        center: .center,
                        startAngle: .degrees(-40),
                        endAngle: .degrees(320)
                    ),
                    lineWidth: 0.5
                )
                .frame(width: size - 1, height: size - 1)

            // 3D: bottom reflection
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(0.14),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.2
                    )
                )
                .frame(width: size * 0.4, height: size * 0.14)
                .offset(y: size * 0.32)

            label
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.57), radius: 3.3, x: 0, y: 3)
    }
}

// MARK: - Detail Panel Background (availability bridge)

struct DetailPanelBackground: ViewModifier {
    let pColor: Color

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.08).opacity(0.88))

                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .opacity(0.4)
                    }
                    .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    pColor.opacity(0.5),
                                    pColor.opacity(0.15),
                                    .white.opacity(0.08),
                                    pColor.opacity(0.15),
                                    pColor.opacity(0.5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: pColor.opacity(0.15), radius: 20, x: 0, y: 4)
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(pColor.opacity(0.4), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        }
    }
}

#endif
