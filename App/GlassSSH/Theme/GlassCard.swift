import SwiftUI

/// Default corner radius for glass panels in the design system.
private let defaultCardCornerRadius: CGFloat = 20

/// A rounded, translucent Liquid Glass panel that hosts arbitrary content.
///
/// Use this to group related controls or information on a `GlassBackground`. The
/// panel applies the iPadOS 26 `glassEffect` with a rounded-rectangle shape so
/// the content appears to float on frosted glass.
///
/// ```swift
/// GlassCard {
///     VStack { Text("Host"); Text("example.com") }
/// }
/// ```
public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    /// Creates a glass card wrapping the supplied content.
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the panel. Defaults to the design
    ///     system standard.
    ///   - content: The view hierarchy rendered inside the panel.
    public init(
        cornerRadius: CGFloat = defaultCardCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

public extension View {
    /// Applies the standard Liquid Glass card treatment to any view.
    ///
    /// Unlike ``GlassCard``, this does not add internal padding — it only wraps
    /// the receiver in the regular glass effect clipped to a rounded rectangle,
    /// so callers retain full control over their own layout.
    /// - Parameter cornerRadius: Corner radius of the glass surface.
    func glassCard(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

#Preview("Glass Card") {
    ZStack {
        GlassBackground()
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("production-db")
                    .font(.headline)
                Text("deploy@example.com:2222")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview("glassCard modifier") {
    ZStack {
        GlassBackground()
        Label("Connected", systemImage: "bolt.fill")
            .padding()
            .glassCard(cornerRadius: 14)
    }
}
