// ICD360SVPN — ICD360SVPNApp.swift
// MARK: - App entry point

import SwiftUI

/// Top-level @main entry. Owns a single AppState that drives every
/// screen via its `phase` property.
@main
struct ICD360SVPNApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("ICD360S VPN", id: "main") {
            ContentView()
                .environment(appState)
                .task {
                    await appState.bootstrap()
                }
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}
