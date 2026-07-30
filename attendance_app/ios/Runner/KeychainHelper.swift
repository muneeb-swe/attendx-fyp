import Foundation
import Security
import LocalAuthentication

class KeychainHelper {

    private static let keyTag = "com.example.attendance_app.key"

    // MARK: - Key Generation

    /// Generates RSA 2048-bit key pair in Keychain with biometric access control
    /// Returns Base64 DER-encoded public key (same format as Android Keystore)
    static func generateKeyPair() throws -> String {
        // Delete existing key first
        deleteKey()

        // Access control — biometric required, no PIN fallback
        // .biometryAny = Touch ID or Face ID
        // kSecAttrAccessibleWhenUnlockedThisDeviceOnly = device bound, survives reinstall
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) else {
            throw KeychainError.accessControlFailed
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: access,
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error!.takeRetainedValue() as Error
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw KeychainError.publicKeyExportFailed
        }

        return try exportPublicKey(publicKey)
    }

    // MARK: - Key Export

    /// Exports public key as Base64 DER string
    /// Matches Android's Base64.encodeToString(publicKeyBytes, Base64.NO_WRAP)
    static func exportPublicKey(_ publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return (keyData as Data).base64EncodedString()
    }

    // MARK: - Key Retrieval

    /// Returns existing public key as Base64 DER string
    static func getPublicKey() throws -> String? {
        guard let privateKey = getPrivateKey() else { return nil }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        return try exportPublicKey(publicKey)
    }

    /// Checks if key exists in Keychain
    static func hasKey() -> Bool {
        return getPrivateKey() != nil
    }

    /// Retrieves private key reference from Keychain
    /// Does NOT expose key material — returns opaque reference only
    static func getPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return (item as! SecKey)
    }

    // MARK: - Biometric-Gated Signing

    /// Signs data using private key — biometric authentication required
    /// iOS equivalent of Android BiometricPrompt + CryptoObject pattern
    /// LAContext handles biometric prompt and unlocks key for signing
    /// Algorithm: rsaSignatureMessagePKCS1v15SHA256
    /// Matches Android SHA256withRSA and Python padding.PKCS1v15() + hashes.SHA256()
    static func signData(_ data: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let privateKey = getPrivateKey() else {
            completion(.failure(KeychainError.keyNotFound))
            return
        }

        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            completion(.failure(KeychainError.algorithmNotSupported))
            return
        }

        guard let dataToSign = data.data(using: .utf8) else {
            completion(.failure(KeychainError.invalidData))
            return
        }

        // LAContext evaluates biometric before allowing key use
        // The .biometryAny access control on the key enforces this at OS level
        // Even if LAContext is bypassed, SecKeyCreateSignature will fail
        // because the key requires biometric authentication at hardware level
        let context = LAContext()
        context.evaluateAccessControl(
            SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )!,
            operation: .useKeySign,
            localizedReason: "Verify your identity to mark attendance"
        ) { success, error in
            guard success else {
                completion(.failure(error ?? KeychainError.biometricFailed))
                return
            }

            // Biometric passed — sign data
            var signError: Unmanaged<CFError>?
            guard let signature = SecKeyCreateSignature(
                privateKey,
                algorithm,
                dataToSign as CFData,
                &signError
            ) else {
                completion(.failure(signError!.takeRetainedValue() as Error))
                return
            }

            let base64Signature = (signature as Data).base64EncodedString()
            completion(.success(base64Signature))
        }
    }

    // MARK: - Key Deletion

    /// Deletes key from Keychain
    /// Note: Unlike Android Keystore, iOS Keychain keys survive app uninstall
    /// This method is called during re-enrollment to force new key generation
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case accessControlFailed
    case publicKeyExportFailed
    case keyNotFound
    case algorithmNotSupported
    case invalidData
    case biometricFailed

    var errorDescription: String? {
        switch self {
        case .accessControlFailed: return "Failed to create access control"
        case .publicKeyExportFailed: return "Failed to export public key"
        case .keyNotFound: return "No key found. Enroll device first."
        case .algorithmNotSupported: return "Algorithm not supported"
        case .invalidData: return "Invalid data to sign"
        case .biometricFailed: return "Biometric authentication failed"
        }
    }
}