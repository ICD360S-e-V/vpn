// ICD360SVPN — Features/Enrollment/EnrollmentView.swift
// MARK: - First-run enrollment screen
//
// Asks the user to paste the three PEM blobs that `vpn-agent
// issue-cert <name>` printed on the server (CA, client cert, client
// key) plus the agent's base URL, then hands them to AppState.enroll
// which converts to PKCS#12, stores in Keychain, and connects.

import SwiftUI

struct EnrollmentView: View {
    @Environment(AppState.self) private var state

    @State private var caPEM: String = ""
    @State private var certPEM: String = ""
    @State private var keyPEM: String = ""
    @State private var baseURLString: String = "https://10.8.0.1:8443"
    @State private var urlError: String?

    private var canSubmit: Bool {
        !caPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !certPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enroll this Mac")
                    .font(.largeTitle)
                    .bold()

                Text("Paste the PEM blobs printed by `vpn-agent issue-cert <name>` on the server. The agent URL must be reachable through the WireGuard tunnel.")
                    .foregroundStyle(.secondary)

                Form {
                    Section("Server") {
                        TextField("Agent URL", text: $baseURLString)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                        if let urlError {
                            Text(urlError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Section("CA certificate") {
                        pemEditor($caPEM, placeholder: "-----BEGIN CERTIFICATE-----\n…\n-----END CERTIFICATE-----")
                    }

                    Section("Client certificate") {
                        pemEditor($certPEM, placeholder: "-----BEGIN CERTIFICATE-----\n…\n-----END CERTIFICATE-----")
                    }

                    Section("Client private key") {
                        pemEditor($keyPEM, placeholder: "-----BEGIN EC PRIVATE KEY-----\n…\n-----END EC PRIVATE KEY-----")
                    }
                }
                .formStyle(.grouped)

                if let err = state.lastError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                HStack {
                    Spacer()
                    Button("Connect") {
                        submit()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func pemEditor(_ binding: Binding<String>, placeholder: String) -> some View {
        ZStack(alignment: .topLeading) {
            if binding.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.body.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: binding)
                .font(.body.monospaced())
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.4))
        )
    }

    private func submit() {
        guard let url = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, scheme == "https" else {
            urlError = "Agent URL must be a valid https:// URL."
            return
        }
        urlError = nil
        Task {
            await state.enroll(
                certPEM: certPEM,
                keyPEM: keyPEM,
                caPEM: caPEM,
                baseURL: url
            )
        }
    }
}

#Preview {
    EnrollmentView()
        .environment(AppState())
        .frame(width: 720, height: 600)
}
