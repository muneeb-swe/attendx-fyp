import Foundation
import Security
import LocalAuthentication

class KeychainHelper {
    
    private static let keyTag = "com.example.attendance_app.key"
    
    // Generate RSA key pair in Regular Keychain with biometric requirement
    static func generateKeyPair() throws -> String {
        // Delete existing key first
        deleteKey()
        
        // Access control — requires biometric to use key
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryAny,
            nil
        ) else {
            throw NSError(domain: "KeychainHelper", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create access control"])
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
            throw NSError(domain: "KeychainHelper", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get public key"])
        }
        
        return try exportPublicKey(publicKey)
    }
    
    // Export public key as Base64 DER format (same as Android)
    static func exportPublicKey(_ publicKey: SecKey) throws -> String {
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return (keyData as Data).base64EncodedString()
    }
    
    // Get existing public key
    static func getPublicKey() throws -> String? {
        guard let privateKey = getPrivateKey() else { return nil }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        return try exportPublicKey(publicKey)
    }
    
    // Check if key exists
    static func hasKey() -> Bool {
        return getPrivateKey() != nil
    }
    
    // Get private key from Keychain
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
    
    // Sign data using private key — biometric required by access control
    static func signData(_ data: String) throws -> String {
        guard let privateKey = getPrivateKey() else {
            throw NSError(domain: "KeychainHelper", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No key found. Enroll device first."])
        }
        
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, algorithm) else {
            throw NSError(domain: "KeychainHelper", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Algorithm not supported"])
        }
        
        guard let dataToSign = data.data(using: .utf8) else {
            throw NSError(domain: "KeychainHelper", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Invalid data"])
        }
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            dataToSign as CFData,
            &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }
        
        return (signature as Data).base64EncodedString()
    }
    
    // Delete key from Keychain
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
        ]
        SecItemDelete(query as CFDictionary)
    }
}