import SwiftUI
import UIKit
import GlassSSHCore
import GlassSSHNet

/// The detail pane that hosts a live terminal for one `ConnectionProfile`. It owns
/// a `TerminalSession`, drives the connect/disconnect lifecycle, and renders the
/// connection state as Liquid Glass chrome: a connecting spinner, an error banner
/// with reconnect, or the live `TerminalView` plus the floating `TerminalToolbar`.
struct TerminalScreenView: View {
    private let profile: ConnectionProfile

    @StateObject private var session: TerminalSession

    /// Sticky `Ctrl` armed state, shared with the toolbar and consulted when
    /// routing hardware-keyboard characters.
    @State private var ctrlArmed = false

    @FocusState private var terminalFocused: Bool

    /// - Parameters:
    ///   - profile: the destination to connect to.
    ///   - credentials: auth material the app pulled from the Keychain / Secure
    ///     Enclave.
    ///   - hostKeyValidator: trust-on-first-use decision for the server's host key.
    ///
    /// - Important: the owned `TerminalSession` is created once for the view's
    ///   lifetime. To switch to a *different* profile, callers must give this view a
    ///   distinct identity (e.g. `.id(profile.id)`) so SwiftUI tears down the old
    ///   session and builds a fresh one; reusing the view with a new `profile`
    ///   argument alone keeps the original session bound.
    init(
        profile: ConnectionProfile,
        credentials: SSHCredentials,
        hostKeyValidator: @escaping (HostKeyValidationContext) -> HostKeyValidationResult
    ) {
        self.profile = profile
        _session = StateObject(
            wrappedValue: TerminalSession(
                profile: profile,
                credentials: credentials,
                hostKeyValidator: hostKeyValidator
            )
        )
    }

    var body: some View {
        ZStack {
            GlassBackground()
                .ignoresSafeArea()

            content

            VStack {
                if case .failed(let message) = session.state {
                    errorBanner(message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if showsToolbar {
                    TerminalToolbar(
                        ctrlArmed: $ctrlArmed,
                        onSpecialKey: handleSpecialKey,
                        onPaste: paste,
                        onDisconnect: disconnect
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: stateID)
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            session.connect()
        }
        .onDisappear {
            session.disconnect()
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .idle, .connecting:
            connectingOverlay
        case .connected:
            terminal
        case .failed:
            // The terminal (if any output arrived before failure) stays visible
            // behind the banner; otherwise show an empty glass surface.
            terminal
        case .closed:
            closedOverlay
        }
    }

    private var terminal: some View {
        TerminalView(session: session)
            .focusable()
            .focused($terminalFocused)
            .onKeyPress(action: handleKeyPress)
            .onAppear { terminalFocused = true }
            .padding(.bottom, 72) // leave room for the floating toolbar
    }

    private var connectingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Connecting to \(profile.displayDestination)…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .glassCard(cornerRadius: 24)
    }

    private var closedOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "powersleep")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Session closed")
                .font(.headline)
            Button("Reconnect", action: reconnect)
                .buttonStyle(.glassAction)
        }
        .padding(28)
        .glassCard(cornerRadius: 24)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(GlassPalette.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection failed")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Reconnect", action: reconnect)
                .buttonStyle(.glassAction)
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - State helpers

    /// A value that changes whenever the high-level connection state changes, used
    /// to drive transitions without comparing the non-`Equatable` associated value.
    private var stateID: Int {
        switch session.state {
        case .idle: return 0
        case .connecting: return 1
        case .connected: return 2
        case .failed: return 3
        case .closed: return 4
        }
    }

    private var showsToolbar: Bool {
        if case .connected = session.state { return true }
        return false
    }

    // MARK: - Actions

    private func handleSpecialKey(_ key: TerminalSpecialKey) {
        // A held Ctrl has no defined combination with these special keys, so clear
        // it and send the raw sequence.
        ctrlArmed = false
        session.send(key.data)
    }

    private func paste() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        session.sendText(text)
    }

    private func disconnect() {
        session.disconnect()
    }

    private func reconnect() {
        session.connect()
    }

    /// Routes hardware-keyboard characters, applying the sticky `Ctrl` modifier when
    /// armed. When Ctrl is not armed we return `.ignored` so normal text input flows
    /// to the terminal as usual. When it is armed we consume the press and send the
    /// control byte; if the character has no control equivalent we send it verbatim
    /// so the keystroke is never silently dropped.
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        guard ctrlArmed, let character = press.characters.first else { return .ignored }
        ctrlArmed = false
        if let byte = CtrlKeyEncoder.controlByte(for: character) {
            session.send(Data([byte]))
        } else {
            session.sendText(String(character))
        }
        return .handled
    }
}

#Preview("Terminal screen") {
    NavigationStack {
        TerminalScreenView(
            profile: ConnectionProfile(
                name: "Preview Host",
                host: "example.com",
                username: "alice"
            ),
            credentials: SSHCredentials(username: "alice", method: .password("hunter2")),
            hostKeyValidator: { _ in .accept }
        )
    }
}
