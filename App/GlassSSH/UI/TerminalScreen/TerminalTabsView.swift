import SwiftUI
import GlassSSHCore
import GlassSSHNet

/// One open terminal tab: a profile plus the credentials/host-key policy needed to
/// (re)connect it. Identity is per-tab, so the same profile can be opened twice.
struct TerminalTab: Identifiable {
    let id = UUID()
    let profile: ConnectionProfile
    let credentials: SSHCredentials
    let hostKeyValidator: (HostKeyValidationContext) -> HostKeyValidationResult
}

/// Hosts one or more `TerminalScreenView`s as switchable tabs with a Liquid Glass
/// tab strip. Used when the detail pane should keep several sessions alive at once;
/// a single connection can also just present `TerminalScreenView` directly.
struct TerminalTabsView: View {
    @State private var tabs: [TerminalTab]
    @State private var selection: TerminalTab.ID

    let onCloseLast: () -> Void

    init(tabs: [TerminalTab], onCloseLast: @escaping () -> Void = {}) {
        precondition(!tabs.isEmpty, "TerminalTabsView requires at least one tab")
        _tabs = State(initialValue: tabs)
        _selection = State(initialValue: tabs[0].id)
        self.onCloseLast = onCloseLast
    }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                tabStrip
            }
            ZStack {
                ForEach(tabs) { tab in
                    TerminalScreenView(
                        profile: tab.profile,
                        credentials: tab.credentials,
                        hostKeyValidator: tab.hostKeyValidator
                    )
                    .opacity(tab.id == selection ? 1 : 0)
                    .allowsHitTesting(tab.id == selection)
                }
            }
        }
    }

    private var tabStrip: some View {
        GlassEffectContainer(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .glassCard(cornerRadius: 18)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func tabChip(_ tab: TerminalTab) -> some View {
        let isSelected = tab.id == selection
        return HStack(spacing: 6) {
            Text(tab.profile.name)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .lineLimit(1)
            Button {
                close(tab)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close \(tab.profile.name)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassCard(cornerRadius: 12)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(GlassPalette.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = tab.id }
    }

    private func close(_ tab: TerminalTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        guard !tabs.isEmpty else {
            onCloseLast()
            return
        }
        if selection == tab.id {
            // Select the neighbour that took the closed tab's slot, clamped to range.
            selection = tabs[min(index, tabs.count - 1)].id
        }
    }
}

#Preview("Terminal tabs") {
    let validator: (HostKeyValidationContext) -> HostKeyValidationResult = { _ in .accept }
    return NavigationStack {
        TerminalTabsView(
            tabs: [
                TerminalTab(
                    profile: ConnectionProfile(name: "web-01", host: "10.0.0.1", username: "root"),
                    credentials: SSHCredentials(username: "root", method: .password("x")),
                    hostKeyValidator: validator
                ),
                TerminalTab(
                    profile: ConnectionProfile(name: "db-02", host: "10.0.0.2", username: "admin"),
                    credentials: SSHCredentials(username: "admin", method: .password("y")),
                    hostKeyValidator: validator
                )
            ]
        )
    }
}
