// ICD360SVPN — Models/APIError.swift
// MARK: - Typed API error
//
// Anything that can go wrong during a call to vpn-agent is normalised
// into one of these cases. The view layer matches on them to render
// readable feedback (and to distinguish "you need to enroll" from
// "the server is down").

import Foundation

public enum APIError: Error, LocalizedError {
    /// Lower-level transport problem (DNS, TCP, TLS handshake, …).
    case transport(Error)

    /// Server returned a non-HTTPURLResponse — should never happen.
    case invalidResponse

    /// Non-2xx response with a body that we could not parse as
    /// `application/problem+json`.
    case http(status: Int, body: Data?)

    /// RFC 7807 problem+json error returned by the agent.
    case problemDetails(ProblemDetails)

    /// JSON decoding failed.
    case decoding(Error)

    /// No client identity in the keychain — caller needs to enroll.
    case missingIdentity

    /// RFC 7807 Problem Details for HTTP APIs.
    public struct ProblemDetails: Decodable, Sendable {
        public let type: String
        public let title: String
        public let status: Int
        public let detail: String?
    }

    public var errorDescription: String? {
        switch self {
        case .transport(let err):
            return "Network error: \(err.localizedDescription)"
        case .invalidResponse:
            return "The server returned a malformed response."
        case .http(let status, _):
            return "HTTP \(status) from the agent."
        case .problemDetails(let pd):
            if let detail = pd.detail, !detail.isEmpty {
                return "\(pd.title): \(detail)"
            }
            return pd.title
        case .decoding(let err):
            return "Could not decode the agent's response: \(err.localizedDescription)"
        case .missingIdentity:
            return "No saved credentials. Please enroll first."
        }
    }
}
