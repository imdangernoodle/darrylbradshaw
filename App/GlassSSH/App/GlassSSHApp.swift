import SwiftUI

/// App entry point. Holds the shared `AppModel` and routes incoming
/// `glassssh://` deep links (from scanned QR codes or universal links).
@main
struct GlassSSHApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onOpenURL { url in
                    model.handleIncomingURL(url)
                }
        }
    }
}
