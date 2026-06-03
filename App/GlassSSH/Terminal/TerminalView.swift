import SwiftUI
import SwiftTerm

/// SwiftUI entry point for an interactive SSH terminal. Hosts the SwiftTerm
/// surface and wires its delegate callbacks (data to send, size changed) to the
/// `TerminalSession` that owns the SSH connection.
///
/// Note: SwiftTerm also vends a UIKit class named `TerminalView`; within this
/// file the underlying class is referenced as `SwiftTerm.TerminalView` to avoid
/// the name clash with this SwiftUI view.
struct TerminalView: View {
    @ObservedObject private var session: TerminalSession

    /// Holds a weak reference to the live SwiftTerm view so output bytes from the
    /// session can be fed into it without the view re-creating the session.
    @State private var surface = SurfaceHolder()

    init(session: TerminalSession) {
        self.session = session
    }

    var body: some View {
        TerminalSurfaceView(
            onData: { data in
                session.send(data)
            },
            onSizeChanged: { cols, rows in
                session.resize(cols: cols, rows: rows)
            },
            onReady: { terminalView in
                surface.terminal = terminalView
            }
        )
        .onAppear {
            // Route shell output into the SwiftTerm view as it arrives.
            session.onOutput = { [surface] bytes in
                surface.terminal?.feed(byteArray: bytes)
            }
            session.connect()
        }
        .onDisappear {
            session.onOutput = nil
            session.disconnect()
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Reference box so the closure capturing the SwiftTerm view survives view
    /// re-evaluations without forcing the value-type `View` to be mutable.
    @MainActor
    final class SurfaceHolder {
        weak var terminal: SwiftTerm.TerminalView?
    }
}
