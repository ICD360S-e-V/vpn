// swift-tools-version: 5.10
//
// ICD360SVPN — macOS admin app for the ICD360S WireGuard server.
//
// Single executable target. No external dependencies — Foundation,
// SwiftUI, Security, and CoreImage are all on the OS.
//
// Build and run from the command line (Mac required):
//   cd app
//   swift build
//   swift run ICD360SVPN
//
// Or open Package.swift in Xcode 15+ and use the SwiftUI previews.

import PackageDescription

let package = Package(
    name: "ICD360SVPN",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "ICD360SVPN", targets: ["ICD360SVPN"]),
    ],
    targets: [
        .executableTarget(
            name: "ICD360SVPN",
            path: "Sources/ICD360SVPN"
        ),
    ]
)
