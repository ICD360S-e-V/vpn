// ICD360SVPN — Networking/APIClient.swift
// MARK: - Typed JSON client for vpn-agent
//
// Wraps a URLSession built with `MTLSDelegate`. Each public method
// corresponds 1:1 to an endpoint defined in proto/openapi.yaml.
//
// All methods are async-throwing. JSON encoding uses
// `convertToSnakeCase` and decoding uses `convertFromSnakeCase`, so
// Swift's camelCase property names map automatically to the agent's
// snake_case wire format.

import Foundation
import Security

/// HTTP client for the vpn-agent management API. Thread-safe by
/// virtue of being an actor — all calls are serialised.
public actor APIClient {

    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameters:
    ///   - baseURL: The agent's base URL, e.g. `https://10.8.0.1:8443`.
    ///   - identity: Client identity loaded from Keychain.
    ///   - trustedCA: The single CA the server must chain to.
    public init(baseURL: URL, identity: SecIdentity, trustedCA: SecCertificate) {
        self.baseURL = baseURL
        let delegate = MTLSDelegate(identity: identity, trustedCA: trustedCA)
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": "ICD360SVPN-mac/0.1"]
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Each APIClient gets its own session because the delegate is
        // bound to a specific identity. Don't reuse across users.
        self.session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = APIClient.makeDateDecodingStrategy()
        self.decoder = dec
    }

    // MARK: - Endpoints

    /// `GET /v1/health`
    public func health() async throws -> Health {
        try await request("GET", "/v1/health", body: Optional<Never>.none, decode: Health.self)
    }

    /// `GET /v1/peers`
    public func listPeers() async throws -> [Peer] {
        try await request("GET", "/v1/peers", body: Optional<Never>.none, decode: [Peer].self)
    }

    /// `POST /v1/peers`
    public func createPeer(name: String) async throws -> PeerCreateResponse {
        let body = PeerCreateRequest(name: name)
        return try await request("POST", "/v1/peers", body: body, decode: PeerCreateResponse.self)
    }

    /// `DELETE /v1/peers/{pubkey}` — public key is percent-encoded.
    public func deletePeer(publicKey: String) async throws {
        // Base64 contains `/` and `+`, both of which must be
        // percent-encoded inside a URL path component. We use
        // `.alphanumerics` (the most aggressive built-in set) so the
        // result is unambiguous.
        guard let encoded = publicKey
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw APIError.invalidResponse
        }
        let _: EmptyResponse = try await request(
            "DELETE",
            "/v1/peers/\(encoded)",
            body: Optional<Never>.none,
            decode: EmptyResponse.self
        )
    }

    // MARK: - Private

    /// Generic request helper. Encodes `body` if non-nil, decodes a
    /// successful response into `T`, and translates errors into
    /// `APIError`. For 204 responses with `T == EmptyResponse`,
    /// returns immediately without decoding.
    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        body: Encodable?,
        decode: T.Type
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var req = URLRequest(url: url)
        req.httpMethod = method

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                req.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.decoding(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // 2xx → success
        if (200..<300).contains(http.statusCode) {
            // 204 No Content has no body — return EmptyResponse if T allows it.
            // The conditional cast is safe: if T is anything other than
            // EmptyResponse, we fall through to the decode path below
            // which will report a clean DecodingError on empty data.
            if (http.statusCode == 204 || data.isEmpty),
               let empty = EmptyResponse() as? T {
                return empty
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        }

        // Error path: try to parse application/problem+json first.
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.lowercased().hasPrefix("application/problem+json") {
            if let pd = try? JSONDecoder().decode(APIError.ProblemDetails.self, from: data) {
                throw APIError.problemDetails(pd)
            }
        }
        throw APIError.http(status: http.statusCode, body: data)
    }

    // MARK: - Date decoding strategy
    //
    // The agent emits times like `2026-04-11T13:14:18.895571198Z` —
    // RFC 3339 with high-precision fractional seconds. Standard
    // `JSONDecoder.DateDecodingStrategy.iso8601` does not handle
    // fractional seconds. We use `Date.ISO8601FormatStyle` (modern,
    // Sendable, value-typed) instead of `ISO8601DateFormatter` (a
    // non-Sendable reference type that triggers warnings under Swift
    // 6 strict concurrency).

    private static func makeDateDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        return .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            // Try with fractional seconds first — that's what the agent emits.
            if let d = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return d
            }
            // Fall back to plain RFC 3339 without fractional seconds.
            if let d = try? Date(raw, strategy: Date.ISO8601FormatStyle()) {
                return d
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected RFC 3339 date, got \(raw)"
            )
        }
    }
}

// MARK: - Internal helpers

/// Marker type used when an endpoint has no body to decode (e.g. 204).
struct EmptyResponse: Decodable {}

/// Type-erasing wrapper so the generic `body: Encodable?` parameter
/// can be encoded directly. Required because `Encodable` cannot be
/// used as a generic type itself prior to Swift 5.7's existential
/// `any Encodable`, and even with that, JSONEncoder needs a concrete
/// type to encode.
private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
