import XCTest
@testable import GlassSSHNet

/// End-to-end test of the SwiftNIO-SSH networking layer against a *real* sshd.
///
/// This test is intentionally a no-op unless every `GLASSSSH_E2E_*` environment
/// variable is set, so it stays inert during ordinary local development and the
/// normal Linux unit-test run. The `ssh-e2e` GitHub Actions workflow stands up an
/// `openssh-server`, exports the variables, and runs `swift test --filter
/// GlassSSHNetE2E` to exercise the full connect -> authenticate -> shell path.
final class GlassSSHNetE2ETests: XCTestCase {
    private struct E2EConfig {
        let host: String
        let port: Int
        let user: String
        let password: String
    }

    /// Reads the E2E configuration from the environment, or `nil` if any piece is
    /// missing/blank. Callers turn a `nil` into an `XCTSkip`.
    private func loadConfig() -> E2EConfig? {
        let env = ProcessInfo.processInfo.environment

        func value(_ key: String) -> String? {
            guard let raw = env[key], !raw.isEmpty else { return nil }
            return raw
        }

        guard
            let host = value("GLASSSSH_E2E_HOST"),
            let portString = value("GLASSSSH_E2E_PORT"),
            let port = Int(portString),
            let user = value("GLASSSSH_E2E_USER"),
            let password = value("GLASSSSH_E2E_PASSWORD")
        else {
            return nil
        }

        return E2EConfig(host: host, port: port, user: user, password: password)
    }

    func testShellEchoRoundTripAgainstRealSSHD() async throws {
        guard let config = loadConfig() else {
            throw XCTSkip(
                "GLASSSSH_E2E_HOST/PORT/USER/PASSWORD not all set; skipping live sshd test."
            )
        }

        let marker = "glassssh-e2e-ok"

        let client = SSHClient()

        let output: String
        do {
            try await client.connect(
                host: config.host,
                port: config.port,
                credentials: .init(
                    username: config.user,
                    method: .password(config.password)
                ),
                hostKeyValidator: { _, _ in .accept }
            )

            let session = try await client.startShell()

            try await session.sendText("echo \(marker)\n")

            output = try await readUntil(
                session: session,
                containing: marker,
                timeout: .seconds(15)
            )

            await session.close()
        } catch {
            // Ensure the event-loop group is shut down before propagating.
            await client.disconnect()
            throw error
        }

        await client.disconnect()

        XCTAssertTrue(
            output.contains(marker),
            "Expected shell output to contain \"\(marker)\"; got:\n\(output)"
        )
    }

    /// Accumulates decoded shell output until it contains `needle`, or throws once
    /// `timeout` elapses. Decoding is permissive (UTF-8, lossy) because a real PTY
    /// interleaves prompts and control sequences with our echoed text.
    private func readUntil(
        session: ShellSession,
        containing needle: String,
        timeout: Duration
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var accumulated = ""
                for try await chunk in session.output {
                    accumulated += String(decoding: chunk, as: UTF8.self)
                    if accumulated.contains(needle) {
                        return accumulated
                    }
                }
                return accumulated
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw E2ETimeout(needle: needle)
            }

            // The first task to finish wins; cancel the rest (the timeout sleep or
            // the still-reading stream).
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw E2ETimeout(needle: needle)
            }
            return result
        }
    }

    private struct E2ETimeout: Error, CustomStringConvertible {
        let needle: String
        var description: String {
            "Timed out waiting for shell output containing \"\(needle)\"."
        }
    }
}
