// ICD360SVPN — Models/Peer.swift
// MARK: - Peer wire model
//
// Mirrors the JSON shape returned by `GET /v1/peers` and the `peer` field
// of `POST /v1/peers`. Field names use snake_case in JSON, mapped to
// camelCase Swift properties via CodingKeys.

import Foundation

/// A WireGuard peer as exposed by the agent's REST API.
///
/// Combines static config (from `wg0.conf`) with live runtime state
/// (from `wg show wg0 dump`): `endpoint`, `lastHandshakeAt`, and the
/// transfer counters are populated only when the peer has actually
/// connected at least once.
public struct Peer: Codable, Identifiable, Hashable {
    /// Human-readable label set when the peer was created.
    public let name: String

    /// WireGuard public key (base64). Acts as the stable identifier.
    public let publicKey: String

    /// Allowed IPs assigned to this peer (typically a single /32 in
    /// the 10.8.0.0/24 subnet).
    public let allowedIPs: [String]

    /// When the peer was created. Zero value (`0001-01-01`) for legacy
    /// hand-written peers without metadata.
    public let createdAt: Date

    /// CommonName of the admin client cert that created the peer, if
    /// known. Nil for legacy peers.
    public let createdBy: String?

    /// Public IP and port the peer is currently connecting from. Nil
    /// if the peer has never connected since the agent started.
    public let endpoint: String?

    /// Time of the most recent successful handshake, or nil.
    public let lastHandshakeAt: Date?

    /// Total bytes received from this peer since the interface came up.
    public let rxBytesTotal: UInt64

    /// Total bytes sent to this peer since the interface came up.
    public let txBytesTotal: UInt64

    public var id: String { publicKey }

    enum CodingKeys: String, CodingKey {
        case name
        case publicKey       = "public_key"
        case allowedIPs      = "allowed_ips"
        case createdAt       = "created_at"
        case createdBy       = "created_by"
        case endpoint
        case lastHandshakeAt = "last_handshake_at"
        case rxBytesTotal    = "rx_bytes_total"
        case txBytesTotal    = "tx_bytes_total"
    }
}
