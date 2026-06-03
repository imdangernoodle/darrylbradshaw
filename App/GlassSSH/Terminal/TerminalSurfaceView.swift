import SwiftUI
import SwiftTerm
import os

/// `UIViewRepresentable` wrapping SwiftTerm's `TerminalView`. Configures an
/// xterm-256color terminal with a monospaced font, opts into SwiftTerm's
/// Metal/GPU renderer where available (falling back to the default CoreText
/// renderer), and routes terminal callbacks (data to send, size changed) through
/// a `Coordinator` so the owning view can forward them to a `TerminalSession`.
struct TerminalSurfaceView: UIViewRepresentable {
    /// Called when the terminal produces bytes to send to the remote shell.
    var onData: (ArraySlice<UInt8>) -> Void
    /// Called when the terminal's character grid changes (cols/rows).
    var onSizeChanged: (Int, Int) -> Void
    /// Receives a reference to the live `TerminalView` so output can be fed in.
    var onReady: (SwiftTerm.TerminalView) -> Void

    /// Point size for the monospaced terminal font.
    var fontSize: CGFloat = 13

    private static let log = Logger(subsystem: "com.darrylbradshaw.glassssh", category: "Terminal")

    func makeCoordinator() -> Coordinator {
        Coordinator(onData: onData, onSizeChanged: onSizeChanged)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminal = SwiftTerm.TerminalView(frame: .zero, font: Self.monospacedFont(size: fontSize))
        terminal.terminalDelegate = context.coordinator

        // Prefer the GPU-accelerated Metal renderer when the device and SwiftTerm
        // build support it; otherwise stay on the default CoreText renderer.
        Self.enableMetalIfAvailable(on: terminal)

        onReady(terminal)
        return terminal
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.onData = onData
        context.coordinator.onSizeChanged = onSizeChanged

        let desired = Self.monospacedFont(size: fontSize)
        if uiView.font.pointSize != desired.pointSize {
            uiView.font = desired
        }
    }

    // MARK: - Configuration helpers

    /// A sensible monospaced terminal font: Menlo (always present on iOS) with a
    /// fallback to the system monospaced face.
    private static func monospacedFont(size: CGFloat) -> UIFont {
        UIFont(name: "Menlo", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Turns on SwiftTerm's Metal renderer when the device can create it. Gated
    /// behind `#if canImport(Metal)` and an availability check; `setUseMetal`
    /// throws when the hardware/pipeline can't initialize Metal, in which case
    /// the default CoreText renderer remains active.
    private static func enableMetalIfAvailable(on terminal: SwiftTerm.TerminalView) {
        #if canImport(Metal)
        if #available(iOS 14.0, *) {
            do {
                try terminal.setUseMetal(true)
                log.debug("Terminal Metal renderer enabled: \(terminal.isUsingMetalRenderer, privacy: .public)")
            } catch {
                // Hardware/pipeline can't init Metal: keep the CoreText renderer.
                log.notice("Metal renderer unavailable, using CoreText: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    // MARK: - Coordinator

    /// Bridges SwiftTerm's UIKit delegate callbacks to plain closures.
    final class Coordinator: NSObject, TerminalViewDelegate {
        var onData: (ArraySlice<UInt8>) -> Void
        var onSizeChanged: (Int, Int) -> Void

        init(
            onData: @escaping (ArraySlice<UInt8>) -> Void,
            onSizeChanged: @escaping (Int, Int) -> Void
        ) {
            self.onData = onData
            self.onSizeChanged = onSizeChanged
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            onData(data)
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            onSizeChanged(newCols, newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}

        func bell(source: SwiftTerm.TerminalView) {}

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
