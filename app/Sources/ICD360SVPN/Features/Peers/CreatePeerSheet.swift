// ICD360SVPN — Features/Peers/CreatePeerSheet.swift
// MARK: - Modal sheet for creating a new peer

import SwiftUI

struct CreatePeerSheet: View {
    let client: APIClient
    let onCreated: () async -> Void

    @State private var name: String = ""
    @State private var creating: Bool = false
    @State private var result: PeerCreateResponse?
    @State private var errorMessage: String?
    @State private var showQR: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result {
                resultBody(result)
            } else {
                inputBody
            }
        }
        .padding(20)
        .frame(width: 520, height: result == nil ? 220 : 560)
    }

    private var inputBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New peer")
                .font(.title2)
                .bold()
            Text("Pick a label, e.g. ‘phone’ or ‘work-laptop’. The server allocates the IP and generates the keys.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .disabled(creating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
        }
    }

    @ViewBuilder
    private func resultBody(_ res: PeerCreateResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Peer created")
                .font(.title2)
                .bold()
            Text("Save this config or scan the QR code with the WireGuard mobile app.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if showQR {
                QRCodeView(res.clientConfig, size: 280)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    Text(res.clientConfig)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.4))
                )
                .frame(maxHeight: 320)
            }

            HStack(spacing: 8) {
                Button(showQR ? "Show text" : "Show QR code") {
                    showQR.toggle()
                }
                Button("Copy config") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(res.clientConfig, forType: .string)
                }
                Spacer()
                Button("Done") {
                    Task {
                        await onCreated()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let res = try await client.createPeer(name: name.trimmingCharacters(in: .whitespaces))
            result = res
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
