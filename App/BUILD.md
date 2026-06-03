# Building GlassSSH (iPadOS 26)

The Xcode project is generated from [`project.yml`](project.yml) with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so that source files can be added
without `.pbxproj` merge conflicts.

## Prerequisites
- macOS with **Xcode 26** (Liquid Glass + the SwiftTerm Metal renderer require the iOS 26 SDK).
- An iPad Pro on **iPadOS 26**.
- XcodeGen: `brew install xcodegen`

## Generate & open
```bash
cd App
xcodegen generate
open GlassSSH.xcodeproj
```

Select your development team under **Signing & Capabilities**, then build/run on
your iPad.

## Layout
```
App/
├─ project.yml              # XcodeGen spec (single source of truth)
└─ GlassSSH/
   ├─ App/                  # @main entry, AppModel coordinator, protocol interfaces, RootView
   ├─ Theme/                # Liquid Glass design system
   ├─ Terminal/            # SwiftTerm view + Metal renderer + SSH bridge
   ├─ Security/             # Secure Enclave keys, Keychain, NIOSSH signer
   ├─ Bonjour/             # NWBrowser discovery
   ├─ QR/                   # scanning + generation + glassssh:// routing
   ├─ Data/                 # profile/settings/known-hosts persistence
   ├─ UI/                   # SwiftUI screens (Connections, TerminalScreen, Settings)
   └─ Resources/            # asset catalog
```

Dependencies (resolved by SwiftPM via `project.yml`):
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — GPU-accelerated terminal engine
- `GlassSSHCore` / `GlassSSHNet` — the local Swift package in [`../Core`](../Core)
