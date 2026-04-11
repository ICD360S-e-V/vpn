// ICD360SVPN — Features/Main/ErrorView.swift
// MARK: - Generic error screen

import SwiftUI

struct ErrorView: View {
    let message: String

    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Something went wrong")
                .font(.title2)
                .bold()
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Reset") {
                state.logout()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ErrorView(message: "Could not reach https://10.8.0.1:8443 — is the VPN tunnel up?")
        .environment(AppState())
}
