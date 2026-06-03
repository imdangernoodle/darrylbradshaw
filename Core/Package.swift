// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GlassSSHCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Pure, platform-agnostic logic. Fully unit-tested in Linux CI.
        .library(name: "GlassSSHCore", targets: ["GlassSSHCore"]),
        // SwiftNIO-SSH networking layer. Compiled in CI; exercised on-device.
        .library(name: "GlassSSHNet", targets: ["GlassSSHNet"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "GlassSSHCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "GlassSSHNet",
            dependencies: [
                "GlassSSHCore",
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "GlassSSHCoreTests",
            dependencies: ["GlassSSHCore"]
        ),
    ]
)
