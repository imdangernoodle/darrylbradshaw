import SwiftUI
import GlassSSHCore

/// User-facing preferences for the terminal and connection defaults. Backed by
/// `@AppStorage` so values persist across launches without a separate store.
/// Liquid Glass styling comes from the Theme unit (`GlassBackground`,
/// `.glassCard`, `.glassAction`, `GlassPalette`).
struct SettingsView: View {
    /// Terminal preferences exposed as a value type so other units (the Terminal
    /// screen) can read the same `@AppStorage` keys.
    enum Appearance {
        static let fontSizeKey = "settings.terminal.fontSize"
        static let colorSchemeKey = "settings.terminal.colorScheme"
        static let defaultUsernameKey = "settings.connection.defaultUsername"
        static let autoPinHostKeyKey = "settings.security.autoPinHostKey"

        static let fontSizeRange: ClosedRange<Double> = 9...24
    }

    /// Terminal color scheme presets.
    enum TerminalScheme: String, CaseIterable, Identifiable {
        case system
        case glassDark
        case glassLight
        case solarized

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "System"
            case .glassDark: return "Glass Dark"
            case .glassLight: return "Glass Light"
            case .solarized: return "Solarized"
            }
        }
    }

    let credentials: any CredentialManaging
    let knownHosts: KnownHostsStore

    @AppStorage(Appearance.fontSizeKey) private var fontSize: Double = 13
    @AppStorage(Appearance.colorSchemeKey) private var colorScheme: String = TerminalScheme.system.rawValue
    @AppStorage(Appearance.defaultUsernameKey) private var defaultUsername: String = ""
    @AppStorage(Appearance.autoPinHostKeyKey) private var autoPinHostKey: Bool = true

    private var selectedScheme: Binding<TerminalScheme> {
        Binding(
            get: { TerminalScheme(rawValue: colorScheme) ?? .system },
            set: { colorScheme = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        appearanceSection
                        connectionSection
                        securitySection
                        managementSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", systemImage: "textformat.size") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Terminal Font Size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $fontSize,
                        in: Appearance.fontSizeRange,
                        step: 1
                    )
                    Text("The quick brown fox")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Divider()

                Picker("Color Scheme", selection: selectedScheme) {
                    ForEach(TerminalScheme.allCases) { scheme in
                        Text(scheme.title).tag(scheme)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var connectionSection: some View {
        SettingsSection(title: "Connection", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Default Username")
                TextField("e.g. admin", text: $defaultUsername)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Used to prefill new connections.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var securitySection: some View {
        SettingsSection(title: "Security", systemImage: "lock.shield") {
            Toggle(isOn: $autoPinHostKey) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-pin Host Keys")
                    Text("Trust new host keys on first connection (TOFU).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var managementSection: some View {
        SettingsSection(title: "Management", systemImage: "key") {
            VStack(spacing: 0) {
                NavigationLink {
                    KeyManagementView(credentials: credentials)
                } label: {
                    SettingsRowLabel(
                        title: "SSH Keys",
                        systemImage: "key.fill",
                        detail: "\(credentials.keys.count)"
                    )
                }
                Divider()
                NavigationLink {
                    KnownHostsView(store: knownHosts)
                } label: {
                    SettingsRowLabel(
                        title: "Known Hosts",
                        systemImage: "checkmark.shield.fill",
                        detail: "\(knownHosts.allEntries.count)"
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// A titled Liquid Glass card grouping related settings controls.
struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(16)
        .glassCard(cornerRadius: 22)
    }
}

/// A tappable row used inside `SettingsSection` for navigation entries.
struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(GlassPalette.accent)
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview {
    SettingsView(
        credentials: PreviewCredentialStore(),
        knownHosts: PreviewKnownHosts.populated()
    )
}
