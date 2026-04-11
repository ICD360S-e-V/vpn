// ICD360SVPN — Models/PeerCreateResponse.swift
// MARK: - Peer create response

import Foundation

/// Response of `POST /v1/peers`.
///
/// `clientConfig` is a ready-to-import WireGuard `.conf` file the UI
/// can show in a copyable text view, write to disk, or render as a QR
/// code locally with CoreImage.
public struct PeerCreateResponse: Decodable {
    public let peer: Peer
    public let clientConfig: String

    enum CodingKeys: String, CodingKey {
        case peer
        case clientConfig = "client_config"
    }
}
