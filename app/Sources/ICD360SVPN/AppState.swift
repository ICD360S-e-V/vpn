// ICD360SVPN — AppState.swift
// MARK: - App-wide state machine
//
// One AppState instance is owned by the @main App and shared via
// SwiftUI's environment. It tracks the high-level lifecycle phase
// (do we need to enroll? are we connected? is there an error?) and
// owns the singleton APIClient once it exists.

import Foundation
import Observation
import Security

/// Lifecycle phases of the app.
public enum AppPhase {
    /// Initial state, while we probe Keychain for an existing identity.
    case bootstrapping

    /// No identity in Keychain — show the EnrollmentView.
    case needsEnrollment

    /// In flight: importing PEMs, building the APIClient.
    case connecting

    /// Connected and ready. Carries the live APIClient.
    case connected(APIClient)

    /// Unrecoverable error. Carries a human-readable message.
    case error(String)
}

@Observable
@MainActor
public final class AppState {

    /// Current lifecycle phase. Drives ContentView's switch.
    public var phase: AppPhase = .bootstrapping

    /// Last error message — bound to inline labels in the enrollment
    /// form so the user can see why a save failed without losing the
    /// pasted PEMs.
    public var lastError: String?

    // Keychain labels and the default agent URL are private knobs
    // tucked here so the rest of the app does not have to know.
    private static let identityLabel = "ICD360SVPN.admin"
    private static let caLabel       = "ICD360SVPN.ca"
    private static let pkcs12Pass    = "icd360s-local-only"  // PKCS12 envelope passphrase, never leaves the host
    public  static let defaultBaseURL = URL(string: "https://10.8.0.1:8443")!

    public init() {}

    /// Tries to load a saved identity + CA from the Keychain. On
    /// success, builds an APIClient and transitions to `.connected`.
    /// On failure (or absence) transitions to `.needsEnrollment`.
    public func bootstrap() async {
        phase = .bootstrapping
        do {
            guard let identity = try KeychainStore.loadIdentity(label: AppState.identityLabel),
                  let ca = try KeychainStore.loadCA(label: AppState.caLabel) else {
                phase = .needsEnrollment
                return
            }
            let client = APIClient(
                baseURL: AppState.defaultBaseURL,
                identity: identity,
                trustedCA: ca
            )
            phase = .connected(client)
        } catch {
            lastError = error.localizedDescription
            phase = .needsEnrollment
        }
    }

    /// Imports the pasted PEMs into the Keychain and connects.
    public func enroll(
        certPEM: String,
        keyPEM: String,
        caPEM: String,
        baseURL: URL
    ) async {
        phase = .connecting
        lastError = nil
        do {
            let p12 = try KeychainStore.pemBundleToPKCS12(
                certPEM: certPEM,
                keyPEM: keyPEM,
                passphrase: AppState.pkcs12Pass
            )
            try KeychainStore.saveIdentity(
                pkcs12Data: p12,
                passphrase: AppState.pkcs12Pass,
                label: AppState.identityLabel
            )
            try KeychainStore.saveCA(certPEM: caPEM, label: AppState.caLabel)

            guard let identity = try KeychainStore.loadIdentity(label: AppState.identityLabel),
                  let ca = try KeychainStore.loadCA(label: AppState.caLabel) else {
                throw KeychainError.itemNotFound
            }

            let client = APIClient(
                baseURL: baseURL,
                identity: identity,
                trustedCA: ca
            )
            phase = .connected(client)
        } catch {
            lastError = error.localizedDescription
            phase = .needsEnrollment
        }
    }

    /// Clears the saved identity + CA and returns to enrollment.
    public func logout() {
        try? KeychainStore.deleteIdentity(label: AppState.identityLabel)
        // CA cleanup is intentionally lenient — it's a public cert,
        // leaving it behind is harmless if delete fails.
        let caQuery: [String: Any] = [
            kSecClass as String:     kSecClassCertificate,
            kSecAttrLabel as String: AppState.caLabel,
        ]
        _ = SecItemDelete(caQuery as CFDictionary)
        lastError = nil
        phase = .needsEnrollment
    }
}
