import SwiftUI

/// A floating Liquid Glass toolbar that sits above the terminal. It exposes an
/// on-screen modifier-key bar (Esc, Ctrl, Tab, arrows) plus paste and disconnect
/// actions. `Ctrl` is a *sticky* modifier: tapping it arms the next keystroke (or
/// the next character typed on the hardware keyboard) to be sent as a control byte,
/// then auto-clears.
///
/// The toolbar is deliberately stateless about the session — it reports intent via
/// closures so it can be previewed and unit-reasoned in isolation.
struct TerminalToolbar: View {
    /// Whether `Ctrl` is currently armed. Owned by the parent so it can also be
    /// consulted when routing hardware-keyboard input.
    @Binding var ctrlArmed: Bool

    let onSpecialKey: (TerminalSpecialKey) -> Void
    let onPaste: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 8) {
                keyCap("esc") { onSpecialKey(.escape) }

                keyCap("ctrl", isActive: ctrlArmed) { ctrlArmed.toggle() }

                keyCap("tab") { onSpecialKey(.tab) }

                Divider()
                    .frame(height: 22)
                    .overlay(GlassPalette.separator)

                arrowCap("chevron.up") { onSpecialKey(.up) }
                arrowCap("chevron.down") { onSpecialKey(.down) }
                arrowCap("chevron.left") { onSpecialKey(.left) }
                arrowCap("chevron.right") { onSpecialKey(.right) }

                Spacer(minLength: 8)

                actionCap("doc.on.clipboard", label: "Paste", action: onPaste)
                actionCap(
                    "bolt.horizontal.circle",
                    label: "Disconnect",
                    role: .destructive,
                    action: onDisconnect
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .glassCard(cornerRadius: 22)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Cap builders

    private func keyCap(
        _ title: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        GlassKeyCap(title: title, isActive: isActive, action: action)
            .accessibilityLabel(Text(title))
    }

    private func arrowCap(_ systemImage: String, action: @escaping () -> Void) -> some View {
        GlassKeyCap(systemImage: systemImage, action: action)
    }

    private func actionCap(
        _ systemImage: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 36)
        }
        .buttonStyle(.glassAction)
        .accessibilityLabel(Text(label))
    }
}

#Preview("Terminal toolbar") {
    ZStack {
        GlassBackground()
        VStack {
            Spacer()
            TerminalToolbar(
                ctrlArmed: .constant(false),
                onSpecialKey: { _ in },
                onPaste: {},
                onDisconnect: {}
            )
        }
    }
}
