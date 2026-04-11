// ICD360SVPN — Networking/MTLSDelegate.swift
// MARK: - mTLS URLSession delegate
//
// All HTTPS calls from the macOS app to vpn-agent go through a
// URLSession built with this delegate. It handles two challenges:
//
//  1. Server trust — pin to a single CA certificate that we shipped
//     in (or stored in Keychain). The OS trust store is irrelevant
//     because the agent uses an internal self-signed CA.
//
//  2. Client cert — present the SecIdentity loaded from Keychain.
//
// Anything else falls back to default handling, which for our use
// case effectively means "fail closed".

import Foundation
import Security

/// URLSessionDelegate that pins the server cert to a private CA and
/// presents a client identity for mutual TLS.
final class MTLSDelegate: NSObject, URLSessionDelegate {

    private let identity: SecIdentity
    private let trustedCA: SecCertificate

    /// - Parameters:
    ///   - identity: The client identity (cert + private key) loaded
    ///     from the keychain. Sent during the client-cert challenge.
    ///   - trustedCA: The single CA certificate the server's cert
    ///     must chain to. Used as the only trust anchor.
    init(identity: SecIdentity, trustedCA: SecCertificate) {
        self.identity = identity
        self.trustedCA = trustedCA
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod

        switch method {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrust(challenge, completionHandler: completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCert(challenge, completionHandler: completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func handleServerTrust(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Anchor the trust evaluation to ONLY our CA — ignore the
        // system trust store entirely.
        let anchorStatus = SecTrustSetAnchorCertificates(trust, [trustedCA] as CFArray)
        guard anchorStatus == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let onlyAnchorStatus = SecTrustSetAnchorCertificatesOnly(trust, true)
        guard onlyAnchorStatus == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        var trustErr: CFError?
        if SecTrustEvaluateWithError(trust, &trustErr) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func handleClientCert(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let credential = URLCredential(
            identity: identity,
            certificates: nil,
            persistence: .forSession
        )
        completionHandler(.useCredential, credential)
    }
}
