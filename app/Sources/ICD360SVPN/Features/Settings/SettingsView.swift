// ICD360SVPN — Features/Settings/SettingsView.swift
// MARK: - Logout + about

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Account") {
                Text("You are connected with the saved admin certificate. Logging out clears the cert from Keychain — you will need to enroll again with a fresh `vpn-agent issue-cert` bundle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    state.logout()
                } label: {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionString)
                        .foregroundStyle(.secondary)
                        .font(.body.monospaced())
                }
                Link(destination: URL(string: "https://github.com/ICD360S-e-V/vpn")!) {
                    Label("github.com/ICD360S-e-V/vpn", systemImage: "link")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 500, height: 400)
}
