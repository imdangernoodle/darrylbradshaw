import Foundation
import GlassSSHCore
import GlassSSHNet
import NIOSSH

/// Drives a live SSH shell for a single `ConnectionProfile` and bridges it to a
/// SwiftTerm `TerminalView`. Network I/O runs on GlassSSHNet's `SSHClient`; the
/// observable `state` and all terminal feeds are published on the main actor so
/// SwiftUI and the UIKit terminal stay in sync.
///
/// Secrets are never stored here: the caller supplies an `SSHCredentials` value
/// (pulled from the Keychain / Secure Enclave) via the `credentialsProvider`
/// closure, and host-key trust is delegated to `hostKeyValidator`.
@MainActor
public final class TerminalSession: ObservableObject {
    public enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
        case closed
    }

    /// Connection lifecycle, observed by the UI.
    @Published public private(set) var state: State = .idle

    public let profile: ConnectionProfile

    /// Supplies credentials at connect time. Throwing surfaces as `.failed`.
    private let credentialsProvider: () throws -> SSHCredentials

    /// Decides whether to trust the server's host key. Defaults to rejecting
    /// everything so a caller must make an explicit trust decision.
    private let hostKeyValidator: (NIOSSHPublicKey, HostKeyValidationContext) -> HostKeyValidationResult

    /// Receives raw bytes from the remote shell; the SwiftUI view wires this to
    /// `TerminalView.feed(byteArray:)`.
    public var onOutput: ((ArraySlice<UInt8>) -> Void)?

    private var client: SSHClient?
    private var shell: ShellSession?
    private var pumpTask: Task<Void, Never>?

    /// The terminal geometry the session believes it should use. Updated by the
    /// view before/while connecting so the PTY is requested at the right size.
    private var cols: Int = 80
    private var rows: Int = 24

    public init(
        profile: ConnectionProfile,
        credentialsProvider: @escaping () throws -> SSHCredentials,
        hostKeyValidator: @escaping (NIOSSHPublicKey, HostKeyValidationContext) -> HostKeyValidationResult = { _, _ in .reject }
    ) {
        self.profile = profile
        self.credentialsProvider = credentialsProvider
        self.hostKeyValidator = hostKeyValidator
    }

    deinit {
        pumpTask?.cancel()
        // The pump task holds the only other reference once we're gone; explicitly
        // tear down the connection so a deallocation mid-session doesn't leak the
        // SSHClient's socket and EventLoopGroup.
        if let shell, let client {
            Task { await shell.close(); await client.disconnect() }
        } else if let client {
            Task { await client.disconnect() }
        }
    }

    // MARK: - Lifecycle

    /// Connects, authenticates, requests a PTY-backed shell, and starts pumping
    /// output into the terminal. Safe to call once per session; re-entrant calls
    /// while connecting or connected are ignored.
    public func connect() {
        switch state {
        case .connecting, .connected:
            return
        case .idle, .failed, .closed:
            break
        }

        state = .connecting

        let credentials: SSHCredentials
        do {
            credentials = try credentialsProvider()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let host = profile.host
        let port = profile.port
        let term = "xterm-256color"
        let cols = self.cols
        let rows = self.rows
        let validator = hostKeyValidator

        pumpTask = Task { [weak self] in
            let client = SSHClient()
            // If disconnect() cancelled us before the client was even stored,
            // tear the fresh client down rather than leaking it.
            if Task.isCancelled {
                await client.disconnect()
                return
            }
            await MainActor.run { self?.client = client }

            do {
                try await client.connect(
                    host: host,
                    port: port,
                    credentials: credentials,
                    hostKeyValidator: validator
                )
                let shell = try await client.startShell(term: term, cols: cols, rows: rows)

                let attached = await MainActor.run { () -> Bool in
                    guard let self else { return false }
                    self.shell = shell
                    self.state = .connected
                    return true
                }
                // Session was deallocated between connect and here: tear the local
                // shell/client down rather than leaking them.
                guard attached else {
                    await shell.close()
                    await client.disconnect()
                    return
                }

                for try await chunk in shell.output {
                    if Task.isCancelled { break }
                    let bytes = ArraySlice(chunk)
                    await MainActor.run { self?.onOutput?(bytes) }
                }

                // Stream finished without error: the remote side closed cleanly.
                await MainActor.run { self?.handleStreamEnd(error: nil) }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { self?.handleStreamEnd(error: error) }
            }
        }
    }

    /// Tears down the shell and underlying connection. Idempotent.
    public func disconnect() {
        pumpTask?.cancel()
        pumpTask = nil

        let shell = self.shell
        let client = self.client
        self.shell = nil
        self.client = nil

        // Preserve an existing failure reason; otherwise mark closed.
        switch state {
        case .failed:
            break
        default:
            state = .closed
        }

        Task {
            await shell?.close()
            await client?.disconnect()
        }
    }

    // MARK: - Terminal -> remote

    /// Forwards user keystrokes (already encoded by SwiftTerm) to the shell.
    public func send(_ data: ArraySlice<UInt8>) {
        guard let shell else { return }
        let payload = Data(data)
        Task { try? await shell.send(payload) }
    }

    /// Convenience for sending text (e.g. paste).
    public func sendText(_ text: String) {
        guard let shell else { return }
        Task { try? await shell.sendText(text) }
    }

    /// Reports a new terminal size. Caches it for the next connect and, when a
    /// shell is live, forwards a window-change request.
    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        self.cols = cols
        self.rows = rows
        guard let shell else { return }
        Task { try? await shell.resize(cols: cols, rows: rows) }
    }

    // MARK: - Helpers

    private func handleStreamEnd(error: Error?) {
        shell = nil
        if let error {
            state = .failed(error.localizedDescription)
        } else {
            // Only mark closed if we were actually connected; a failure during
            // connect already set `.failed`.
            if state == .connected {
                state = .closed
            }
        }
        let client = self.client
        self.client = nil
        Task { await client?.disconnect() }
    }
}
