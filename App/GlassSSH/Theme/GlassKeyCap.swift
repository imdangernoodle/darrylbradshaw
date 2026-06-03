import SwiftUI

/// A small interactive glass key button for an on-screen modifier-key bar.
///
/// Use these to surface keys that aren't easily available on a software keyboard
/// (Esc, Ctrl, Tab, arrows) above a terminal. Each cap is a compact glass button
/// that triggers its action on tap and can be marked as `isActive` to reflect a
/// latched modifier (e.g. Ctrl held down).
public struct GlassKeyCap: View {
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    /// Creates a key cap.
    /// - Parameters:
    ///   - label: Short glyph or text shown on the cap (e.g. `"esc"`, `"⌃"`).
    ///   - isActive: Whether the key is currently latched/held. Latched caps are
    ///     tinted with the accent color. Defaults to `false`.
    ///   - action: Invoked when the cap is tapped.
    public init(
        _ label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .frame(minWidth: 36, minHeight: 32)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .rect(cornerRadius: 8))
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var glass: Glass {
        let base = Glass.regular.interactive()
        return isActive ? base.tint(GlassPalette.accent) : base
    }
}

#Preview("Glass Key Cap Bar") {
    ZStack {
        GlassBackground()
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                GlassKeyCap("esc") {}
                GlassKeyCap("⌃", isActive: true) {}
                GlassKeyCap("⇥") {}
                GlassKeyCap("←") {}
                GlassKeyCap("↑") {}
                GlassKeyCap("↓") {}
                GlassKeyCap("→") {}
            }
        }
        .padding()
    }
}
