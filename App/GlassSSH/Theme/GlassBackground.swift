import SwiftUI

/// A full-bleed adaptive background suitable for placing behind Liquid Glass
/// content.
///
/// It layers a soft vertical gradient derived from the accent token over the
/// system background material so that translucent glass surfaces (`GlassCard`,
/// `GlassActionButtonStyle`, etc.) have something with depth to refract. The
/// gradient is intentionally subtle and respects the current color scheme.
public struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Creates a full-bleed glass background.
    public init() {}

    public var body: some View {
        ZStack {
            // Base material so the gradient blends with the system appearance.
            Rectangle()
                .fill(.background)

            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        let intensity: Double = colorScheme == .dark ? 0.30 : 0.14
        return [
            GlassPalette.accent.opacity(intensity),
            Color.clear,
            GlassPalette.accent.opacity(intensity * 0.5)
        ]
    }
}

#Preview("Glass Background") {
    GlassBackground()
}
