// ICD360SVPN — Features/Peers/PeerRow.swift
// MARK: - One peer rendered as a list row

import SwiftUI

struct PeerRow: View {
    let peer: Peer

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(peer.name.isEmpty ? "(unnamed)" : peer.name)
                    .font(.headline)

                Text(peer.publicKey)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Label(peer.allowedIPs.joined(separator: ", "),
                          systemImage: "network")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let endpoint = peer.endpoint {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(endpoint)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let createdBy = peer.createdBy, !createdBy.isEmpty {
                    Text("by \(createdBy)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(handshakeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    Text(Self.byteFormatter.string(fromByteCount: Int64(peer.rxBytesTotal)))
                }
                .font(.caption2.monospaced())

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text(Self.byteFormatter.string(fromByteCount: Int64(peer.txBytesTotal)))
                }
                .font(.caption2.monospaced())
            }
        }
        .padding(.vertical, 6)
    }

    private var handshakeText: String {
        guard let handshake = peer.lastHandshakeAt else {
            return "Never connected"
        }
        return handshake.formatted(.relative(presentation: .named))
    }
}

#Preview {
    List {
        PeerRow(peer: .preview)
        PeerRow(peer: .previewIdle)
    }
    .frame(width: 600)
}

extension Peer {
    static let preview = Peer(
        name: "phone-andrei",
        publicKey: "BHGx8AUbsGFzkJgEhWS5O7djtVnq9HZ2XJCXXUvjeDs=",
        allowedIPs: ["10.8.0.2/32"],
        createdAt: Date().addingTimeInterval(-86400 * 3),
        createdBy: "andrei-laptop",
        endpoint: "5.75.233.126:51820",
        lastHandshakeAt: Date().addingTimeInterval(-90),
        rxBytesTotal: 12_582_912,
        txBytesTotal: 4_194_304
    )

    static let previewIdle = Peer(
        name: "old-spare-laptop",
        publicKey: "abcdefg1234567890+/=ZZZZZZZZZZZZZZZZZZZZZZZ=",
        allowedIPs: ["10.8.0.7/32"],
        createdAt: Date().addingTimeInterval(-86400 * 30),
        createdBy: nil,
        endpoint: nil,
        lastHandshakeAt: nil,
        rxBytesTotal: 0,
        txBytesTotal: 0
    )
}
