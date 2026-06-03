import SwiftUI

/// An interactive Liquid Glass button style for primary and secondary actions.
///
/// The style renders the button label on an interactive glass capsule that
/// reacts to touch (via `.interactive()`) and can be tinted to convey intent
/// (e.g. ``GlassPalette/danger`` for a destructive disconnect). Apply it with
/// the convenience accessor:
///
/// ```swift
/// Button("Connect") { connect() }
///     .buttonStyle(.glassAction)
/// ```
public struct GlassActionButtonStyle: ButtonStyle {
    /// Optional tint applied to the glass. When `nil`, the glass uses its
    /// default neutral appearance.
    private let tint: Color?

    /// Creates the style.
    /// - Parameter tint: Color used to tint the glass surface, or `nil` for the
    ///   neutral default.
    public init(tint: Color? = nil) {
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .glassEffect(glass, in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private var glass: Glass {
        let base = Glass.regular.interactive()
        if let tint {
            return base.tint(tint)
        }
        return base
    }
}

public extension ButtonStyle where Self == GlassActionButtonStyle {
    /// The default interactive glass action style with no tint.
    static var glassAction: GlassActionButtonStyle { GlassActionButtonStyle() }

    /// An interactive glass action style tinted to convey intent.
    /// - Parameter tint: Color used to tint the glass surface.
    static func glassAction(tint: Color) -> GlassActionButtonStyle {
        GlassActionButtonStyle(tint: tint)
    }
}

#Preview("Glass Action Button") {
    ZStack {
        GlassBackground()
        VStack(spacing: 20) {
            Button("Connect") {}
                .buttonStyle(.glassAction)

            Button("Disconnect") {}
                .buttonStyle(.glassAction(tint: GlassPalette.danger))

            Button {
            } label: {
                Label("Scan QR", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(.glassAction(tint: GlassPalette.accent))
        }
    }
}
