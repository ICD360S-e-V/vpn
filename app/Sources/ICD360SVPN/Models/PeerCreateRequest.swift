// ICD360SVPN — Models/PeerCreateRequest.swift
// MARK: - Peer create request body

import Foundation

/// Body of `POST /v1/peers`.
///
/// Server allocates the IP, generates the keypair + PSK, and returns
/// a fully-rendered client config in the response — the caller only
/// has to pick a human-readable label.
public struct PeerCreateRequest: Encodable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
