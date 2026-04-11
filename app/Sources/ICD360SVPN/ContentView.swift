// ICD360SVPN — ContentView.swift
// MARK: - Root view (phase router)

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        switch state.phase {
        case .bootstrapping:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .needsEnrollment:
            EnrollmentView()

        case .connecting:
            ProgressView("Connecting…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .connected(let client):
            MainView(client: client)

        case .error(let msg):
            ErrorView(message: msg)
        }
    }
}

#Preview("Bootstrapping") {
    let s = AppState()
    s.phase = .bootstrapping
    return ContentView()
        .environment(s)
}

#Preview("Needs enrollment") {
    let s = AppState()
    s.phase = .needsEnrollment
    return ContentView()
        .environment(s)
}
