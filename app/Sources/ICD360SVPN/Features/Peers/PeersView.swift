// ICD360SVPN — Features/Peers/PeersView.swift
// MARK: - Live list of WireGuard peers

import SwiftUI

struct PeersView: View {
    let client: APIClient

    @State private var peers: [Peer] = []
    @State private var loading: Bool = false
    @State private var loadError: String?
    @State private var showCreateSheet = false
    @State private var pendingDelete: Peer?

    var body: some View {
        Group {
            if let loadError, peers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await load() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if peers.isEmpty && !loading {
                Text("No peers yet. Tap + to add the first one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(peers) { peer in
                    PeerRow(peer: peer)
                        .contextMenu {
                            Button("Copy public key") {
                                copyToClipboard(peer.publicKey)
                            }
                            Divider()
                            Button("Revoke…", role: .destructive) {
                                pendingDelete = peer
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = peer
                            } label: {
                                Label("Revoke", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Peers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New peer", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreateSheet) {
            CreatePeerSheet(client: client) {
                await load()
            }
        }
        .alert(
            "Revoke peer?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { peer in
            Button("Cancel", role: .cancel) {}
            Button("Revoke", role: .destructive) {
                Task { await delete(peer) }
            }
        } message: { peer in
            Text("\"\(peer.name.isEmpty ? "(unnamed)" : peer.name)\" will be removed from the server immediately. Existing client devices will fail to reconnect.")
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            peers = try await client.listPeers()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ peer: Peer) async {
        do {
            try await client.deletePeer(publicKey: peer.publicKey)
            await load()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

#Preview {
    // No way to fake an APIClient here without injecting a stub
    // protocol; for now show a dummy view.
    Text("Preview not available — APIClient required")
        .foregroundStyle(.secondary)
}
