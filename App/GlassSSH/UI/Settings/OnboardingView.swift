import SwiftUI
import GlassSSHCore

/// First-run flow introducing GlassSSH, ending in a "Scan to pair" call-to-action
/// that hands off to the QR/pairing unit. The final-step action and dismissal are
/// injected so this view stays decoupled from navigation: `onScanToPair` should
/// present the scanner; `onFinish` marks onboarding complete.
struct OnboardingView: View {
    var onScanToPair: () -> Void = {}
    var onFinish: () -> Void = {}

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "terminal.fill",
            title: "Welcome to GlassSSH",
            message: "A native, Liquid Glass SSH client built for iPad. Connect to your servers with a terminal that feels at home."
        ),
        OnboardingPage(
            systemImage: "lock.shield.fill",
            title: "Keys Stay Private",
            message: "Generate SSH keys in the Secure Enclave. Private material never leaves your device — only the public key is shared."
        ),
        OnboardingPage(
            systemImage: "qrcode.viewfinder",
            title: "Pair in Seconds",
            message: "Scan a QR code from your server or another device to import a connection instantly."
        )
    ]

    private var isLastPage: Bool { page == pages.count - 1 }

    var body: some View {
        ZStack {
            GlassBackground()
            VStack(spacing: 0) {
                header
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(page: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut, value: page)

                footer
                    .padding(20)
            }
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            if !isLastPage {
                Button("Skip", action: onFinish)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .frame(height: 32)
    }

    @ViewBuilder
    private var footer: some View {
        if isLastPage {
            VStack(spacing: 12) {
                Button {
                    onFinish()
                    onScanToPair()
                } label: {
                    Label("Scan to Pair", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassAction)

                Button("Maybe Later", action: onFinish)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                withAnimation { page += 1 }
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassAction)
        }
    }
}

/// Content model for a single onboarding page.
private struct OnboardingPage: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let message: String
}

/// Renders one onboarding page inside a Liquid Glass card.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: page.systemImage)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(GlassPalette.accent)
                .symbolRenderingMode(.hierarchical)
                .padding(28)
                .glassCard(cornerRadius: 32)

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
