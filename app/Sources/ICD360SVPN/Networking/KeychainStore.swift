// ICD360SVPN — Networking/KeychainStore.swift
// MARK: - Keychain wrapper for the admin client identity
//
// All Security framework interaction lives here so the rest of the
// app never has to touch CFTypeRef and OSStatus.
//
// We store two items, both keyed by a label string:
//
//   1. The admin client SecIdentity (cert + private key) imported
//      from a PKCS#12 blob, under `kSecClassIdentity`.
//   2. The agent's CA certificate, under `kSecClassCertificate`.
//
// On first run the user pastes three PEM blobs (cert, key, ca) into
// the EnrollmentView; we convert (cert + key) to PKCS#12, save the
// resulting identity, save the CA separately, and from then on the
// app boots straight into the connected state.
//
// PKCS#12 export from PEM is annoying on Apple platforms — there is
// no public API. For M3 we shell out to /usr/bin/openssl. M4 should
// replace this with a pure-Swift implementation.

import Foundation
import Security

public enum KeychainStore {

    // MARK: - Identity (cert + private key)

    /// Imports a PKCS#12 blob and stores the resulting identity under
    /// `label`. Any pre-existing identity with the same label is
    /// deleted first to avoid duplicates.
    public static func saveIdentity(
        pkcs12Data: Data,
        passphrase: String,
        label: String
    ) throws {
        try? deleteIdentity(label: label)

        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
        ]
        var rawItems: CFArray?
        let importStatus = SecPKCS12Import(
            pkcs12Data as CFData,
            options as CFDictionary,
            &rawItems
        )
        guard importStatus == errSecSuccess else {
            throw KeychainError.pkcs12ImportFailed(importStatus)
        }
        guard let items = rawItems as? [[String: Any]],
              let first = items.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw KeychainError.pkcs12ImportFailed(errSecItemNotFound)
        }
        // The cast is safe: kSecImportItemIdentity is documented to
        // produce a SecIdentity.
        let secIdentity = identity as! SecIdentity  // SAFETY: see above

        let addQuery: [String: Any] = [
            kSecClass as String:     kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecValueRef as String:  secIdentity,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Returns the identity stored under `label`, or nil if none.
    public static func loadIdentity(label: String) throws -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String:     kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let item else {
            throw KeychainError.unexpectedStatus(status)
        }
        // SAFETY: kSecClassIdentity guarantees a SecIdentity result.
        return (item as! SecIdentity)
    }

    /// Deletes any identity stored under `label`. Treats "not found"
    /// as success.
    public static func deleteIdentity(label: String) throws {
        let query: [String: Any] = [
            kSecClass as String:     kSecClassIdentity,
            kSecAttrLabel as String: label,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - CA certificate (server trust pin)

    /// Stores a PEM-encoded CA cert under `label`.
    public static func saveCA(certPEM: String, label: String) throws {
        let derData = try pemBodyToDER(certPEM, expectedHeader: "CERTIFICATE")
        guard let cert = SecCertificateCreateWithData(nil, derData as CFData) else {
            throw KeychainError.invalidPEM
        }
        // Delete any pre-existing CA with the same label.
        let deleteQuery: [String: Any] = [
            kSecClass as String:     kSecClassCertificate,
            kSecAttrLabel as String: label,
        ]
        _ = SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:     kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecValueRef as String:  cert,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Loads the CA cert stored under `label`, or nil if missing.
    public static func loadCA(label: String) throws -> SecCertificate? {
        let query: [String: Any] = [
            kSecClass as String:     kSecClassCertificate,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let item else {
            throw KeychainError.unexpectedStatus(status)
        }
        // SAFETY: kSecClassCertificate guarantees a SecCertificate.
        return (item as! SecCertificate)
    }

    // MARK: - PEM → PKCS#12 conversion (M3 stopgap)

    /// Converts a PEM cert + PEM private key into a PKCS#12 blob ready
    /// for `SecPKCS12Import`.
    ///
    /// **Implementation note:** Apple does not expose a public API for
    /// exporting a PKCS#12. For M3 we shell out to `/usr/bin/openssl`,
    /// which ships with macOS via LibreSSL. M4 should replace this
    /// with a pure-Swift implementation (e.g. via swift-asn1 or a
    /// hand-rolled minimal PKCS12).
    public static func pemBundleToPKCS12(
        certPEM: String,
        keyPEM: String,
        passphrase: String
    ) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
        let certURL = tmp.appendingPathComponent("icd-\(UUID().uuidString).crt")
        let keyURL = tmp.appendingPathComponent("icd-\(UUID().uuidString).key")
        let outURL = tmp.appendingPathComponent("icd-\(UUID().uuidString).p12")

        defer {
            try? FileManager.default.removeItem(at: certURL)
            try? FileManager.default.removeItem(at: keyURL)
            try? FileManager.default.removeItem(at: outURL)
        }

        do {
            try certPEM.write(to: certURL, atomically: true, encoding: .utf8)
            try keyPEM.write(to: keyURL, atomically: true, encoding: .utf8)
        } catch {
            throw KeychainError.openSSLFailed(stderr: "writing temp files: \(error.localizedDescription)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "pkcs12", "-export",
            "-in", certURL.path,
            "-inkey", keyURL.path,
            "-out", outURL.path,
            "-password", "pass:\(passphrase)",
            "-name", "ICD360SVPN admin",
            // Force a modern KDF the macOS SecPKCS12Import accepts.
            "-keypbe", "PBE-SHA1-3DES",
            "-certpbe", "PBE-SHA1-3DES",
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()  // discard stdout

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw KeychainError.openSSLFailed(stderr: error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            let stderrText = String(data: stderrData ?? Data(), encoding: .utf8) ?? "(unreadable)"
            throw KeychainError.openSSLFailed(stderr: stderrText)
        }

        do {
            return try Data(contentsOf: outURL)
        } catch {
            throw KeychainError.openSSLFailed(stderr: "reading p12: \(error.localizedDescription)")
        }
    }

    // MARK: - PEM helpers

    /// Strips the BEGIN/END header lines, removes whitespace, and
    /// base64-decodes the body.
    private static func pemBodyToDER(_ pem: String, expectedHeader: String) throws -> Data {
        let begin = "-----BEGIN \(expectedHeader)-----"
        let end = "-----END \(expectedHeader)-----"
        guard let beginRange = pem.range(of: begin),
              let endRange = pem.range(of: end),
              beginRange.upperBound < endRange.lowerBound else {
            throw KeychainError.invalidPEM
        }
        let body = pem[beginRange.upperBound..<endRange.lowerBound]
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let data = Data(base64Encoded: body) else {
            throw KeychainError.invalidPEM
        }
        return data
    }
}

// MARK: - Errors

public enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case invalidPEM
    case pkcs12ImportFailed(OSStatus)
    case openSSLFailed(stderr: String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found."
        case .unexpectedStatus(let s):
            return "Keychain returned unexpected status \(s)."
        case .invalidPEM:
            return "The PEM blob is malformed."
        case .pkcs12ImportFailed(let s):
            return "PKCS#12 import failed (status \(s)). Check the passphrase."
        case .openSSLFailed(let stderr):
            return "openssl failed: \(stderr)"
        }
    }
}
