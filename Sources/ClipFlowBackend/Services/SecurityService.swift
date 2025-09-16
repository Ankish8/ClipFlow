import Foundation
import Security
import CryptoKit
import ClipFlowCore

// MARK: - Security Service

@MainActor
public class SecurityService {
    public static let shared = SecurityService()

    private let keychain = KeychainService()
    private let encryptionConfig = EncryptionConfiguration()

    // Security policies
    private var shouldEncryptSensitiveContent = true
    private var shouldEncryptAllContent = false
    private var sensitiveContentRetentionDays = 7
    private var regularContentRetentionDays = 30

    private init() {
        Task {
            await initializeSecurityKeys()
        }
    }

    // MARK: - Encryption Operations

    public func encryptContent(_ data: Data) async throws -> EncryptedContent {
        let key = try await getOrCreateEncryptionKey()
        let nonce = AES.GCM.Nonce()

        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        guard let encryptedData = sealedBox.combined else {
            throw SecurityError.encryptionFailed("Failed to combine sealed box")
        }

        let keyID = try await getKeyID(for: key)

        return EncryptedContent(
            data: encryptedData,
            keyID: keyID,
            algorithm: .aes256GCM,
            encryptedAt: Date()
        )
    }

    public func decryptContent(_ encryptedContent: EncryptedContent) async throws -> Data {
        let key = try await getEncryptionKey(for: encryptedContent.keyID)

        let sealedBox = try AES.GCM.SealedBox(combined: encryptedContent.data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    public func shouldEncrypt(_ item: ClipboardItem) async -> Bool {
        // Always encrypt if global encryption is enabled
        if shouldEncryptAllContent {
            return true
        }

        // Encrypt sensitive content
        if shouldEncryptSensitiveContent && item.security.isSensitive {
            return true
        }

        // Encrypt based on content type
        switch item.content {
        case .text(let textContent):
            return await detectSensitiveText(textContent.plainText)
        case .richText(let richContent):
            return await detectSensitiveText(richContent.plainTextFallback)
        case .code(let codeContent):
            return await detectSensitiveCode(codeContent.code)
        case .file(let fileContent):
            return await detectSensitiveFiles(fileContent.urls)
        default:
            return false
        }
    }

    // MARK: - Key Management

    private func initializeSecurityKeys() async {
        do {
            _ = try await getOrCreateEncryptionKey()
            print("Security keys initialized successfully")
        } catch {
            print("Failed to initialize security keys: \(error)")
        }
    }

    private func getOrCreateEncryptionKey() async throws -> SymmetricKey {
        let keyName = "clipboard_encryption_key_v1"

        // Try to retrieve existing key
        if let existingKeyData = try? await keychain.retrieve(keyName) {
            return SymmetricKey(data: existingKeyData)
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        try await keychain.store(keyData, for: keyName, requireBiometric: true)
        return newKey
    }

    private func getEncryptionKey(for keyID: String) async throws -> SymmetricKey {
        let keyName = "clipboard_encryption_key_\(keyID)"

        guard let keyData = try? await keychain.retrieve(keyName) else {
            throw SecurityError.keyNotFound(keyID)
        }

        return SymmetricKey(data: keyData)
    }

    private func getKeyID(for key: SymmetricKey) async throws -> String {
        let keyData = key.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: keyData)
        return Data(hash.prefix(8)).base64EncodedString() // Use first 8 bytes as ID
    }

    // MARK: - Content Analysis

    private func detectSensitiveText(_ text: String) async -> Bool {
        let sensitivePatterns = [
            // Passwords
            #"(?i)(password|pwd|pass|secret|token|key)\s*[:=]\s*\S+"#,
            #"(?i)(api[_-]?key|access[_-]?token|auth[_-]?token)\s*[:=]\s*\S+"#,

            // Credit cards
            #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,

            // Social Security Numbers
            #"\b\d{3}-\d{2}-\d{4}\b"#,

            // Banking information
            #"(?i)(account[_\s]?number|routing[_\s]?number|iban)\s*[:=]\s*\S+"#,

            // Email addresses in certain contexts
            #"(?i)(login|username|email)\s*[:=]\s*\S+@\S+"#,

            // Private keys
            #"-----BEGIN (RSA )?PRIVATE KEY-----"#,
            #"-----BEGIN ENCRYPTED PRIVATE KEY-----"#,

            // SSH keys
            #"ssh-rsa\s+[A-Za-z0-9+/]+"#,
            #"ssh-ed25519\s+[A-Za-z0-9+/]+"#,
        ]

        return sensitivePatterns.contains { pattern in
            text.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func detectSensitiveCode(_ code: String) async -> Bool {
        let codePatterns = [
            // Environment variables with sensitive names
            #"(?i)(password|secret|key|token|auth|api).*=.*"#,

            // Database connection strings
            #"(?i)(mongodb|mysql|postgresql|oracle)://.*:.*@"#,

            // JWT tokens
            #"ey[A-Za-z0-9_-]*\.ey[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*"#,

            // AWS credentials
            #"AKIA[0-9A-Z]{16}"#,
            #"(?i)aws[_\s]?secret[_\s]?access[_\s]?key"#,

            // GitHub tokens
            #"ghp_[0-9a-zA-Z]{36}"#,
            #"gho_[0-9a-zA-Z]{36}"#,

            // Private key markers
            #"-----BEGIN.*PRIVATE.*KEY-----"#,
        ]

        return codePatterns.contains { pattern in
            code.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func detectSensitiveFiles(_ urls: [URL]) async -> Bool {
        let sensitiveExtensions = [
            "key", "pem", "p12", "pfx", "keychain", "keystore",
            "wallet", "dat", "config", "env", "credentials"
        ]

        let sensitiveFilenames = [
            ".env", ".env.local", ".env.production",
            "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
            "config", "credentials", "keychain", "wallet.dat"
        ]

        for url in urls {
            let filename = url.lastPathComponent.lowercased()
            let pathExtension = url.pathExtension.lowercased()

            if sensitiveExtensions.contains(pathExtension) ||
               sensitiveFilenames.contains(filename) {
                return true
            }

            // Check for hidden files that might be sensitive
            if filename.hasPrefix(".") && filename.contains("key") {
                return true
            }
        }

        return false
    }

    // MARK: - Access Control

    public func validateAccess(to item: ClipboardItem, from application: String?) async -> Bool {
        // Check if access control allows access
        switch item.security.accessControl {
        case .public:
            return true
        case .private:
            return await validatePrivateAccess()
        case .restricted:
            return await validateRestrictedAccess(from: application)
        case .shared:
            return await validateSharedAccess(item: item)
        }
    }

    private func validatePrivateAccess() async -> Bool {
        // Could require biometric authentication for private content
        return await requestBiometricAuth()
    }

    private func validateRestrictedAccess(from application: String?) async -> Bool {
        // Validate that the requesting application is allowed
        guard let app = application else { return false }

        let allowedApplications = [
            "com.apple.dt.Xcode",
            "com.microsoft.VSCode",
            // Add more allowed applications
        ]

        return allowedApplications.contains(app)
    }

    private func validateSharedAccess(item: ClipboardItem) async -> Bool {
        // Validate shared access permissions
        // This could involve checking collection permissions
        return true
    }

    private func requestBiometricAuth() async -> Bool {
        // Request biometric authentication
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        do {
            let result = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Access sensitive clipboard content"
            )
            return result
        } catch {
            return false
        }
    }

    // MARK: - Data Expiration

    public func scheduleExpiration(for item: ClipboardItem) async -> ClipboardItem {
        var updatedItem = item
        let retentionDays = item.security.isSensitive ? sensitiveContentRetentionDays : regularContentRetentionDays

        updatedItem.timestamps.setExpiration(days: retentionDays)
        return updatedItem
    }

    public func cleanupExpiredSecureData() async {
        // This would be called periodically to securely delete expired sensitive content
        print("Cleaning up expired secure data...")
    }

    // MARK: - Security Configuration

    public func updateSecurityPolicy(_ policy: SecurityPolicy) async {
        shouldEncryptSensitiveContent = policy.encryptSensitiveContent
        shouldEncryptAllContent = policy.encryptAllContent
        sensitiveContentRetentionDays = policy.sensitiveRetentionDays
        regularContentRetentionDays = policy.regularRetentionDays
    }

    public func getSecurityPolicy() async -> SecurityPolicy {
        SecurityPolicy(
            encryptSensitiveContent: shouldEncryptSensitiveContent,
            encryptAllContent: shouldEncryptAllContent,
            sensitiveRetentionDays: sensitiveContentRetentionDays,
            regularRetentionDays: regularContentRetentionDays
        )
    }

    // MARK: - Security Audit

    public func performSecurityAudit() async -> SecurityAuditReport {
        let totalItems = 0 // Would query database
        let encryptedItems = 0 // Would query database
        let sensitiveItems = 0 // Would query database
        let expiredItems = 0 // Would query database

        return SecurityAuditReport(
            totalItems: totalItems,
            encryptedItems: encryptedItems,
            sensitiveItems: sensitiveItems,
            expiredItems: expiredItems,
            auditDate: Date(),
            recommendations: generateSecurityRecommendations()
        )
    }

    private func generateSecurityRecommendations() -> [SecurityRecommendation] {
        var recommendations: [SecurityRecommendation] = []

        if !shouldEncryptSensitiveContent {
            recommendations.append(SecurityRecommendation(
                type: .enableEncryption,
                severity: .high,
                description: "Enable encryption for sensitive content",
                action: "Go to Security settings and enable sensitive content encryption"
            ))
        }

        return recommendations
    }
}

// MARK: - Supporting Types

public struct EncryptedContent: Codable {
    public let data: Data
    public let keyID: String
    public let algorithm: EncryptionAlgorithm
    public let encryptedAt: Date

    public init(data: Data, keyID: String, algorithm: EncryptionAlgorithm, encryptedAt: Date) {
        self.data = data
        self.keyID = keyID
        self.algorithm = algorithm
        self.encryptedAt = encryptedAt
    }
}

public enum EncryptionAlgorithm: String, Codable {
    case aes256GCM = "AES-256-GCM"
    case chaCha20Poly1305 = "ChaCha20-Poly1305"
}

public struct EncryptionConfiguration {
    let algorithm: EncryptionAlgorithm = .aes256GCM
    let keySize: Int = 256
    let requireBiometric: Bool = true
}

public struct SecurityPolicy {
    public let encryptSensitiveContent: Bool
    public let encryptAllContent: Bool
    public let sensitiveRetentionDays: Int
    public let regularRetentionDays: Int

    public init(
        encryptSensitiveContent: Bool = true,
        encryptAllContent: Bool = false,
        sensitiveRetentionDays: Int = 7,
        regularRetentionDays: Int = 30
    ) {
        self.encryptSensitiveContent = encryptSensitiveContent
        self.encryptAllContent = encryptAllContent
        self.sensitiveRetentionDays = sensitiveRetentionDays
        self.regularRetentionDays = regularRetentionDays
    }
}

public struct SecurityAuditReport {
    public let totalItems: Int
    public let encryptedItems: Int
    public let sensitiveItems: Int
    public let expiredItems: Int
    public let auditDate: Date
    public let recommendations: [SecurityRecommendation]

    public var encryptionRate: Double {
        totalItems > 0 ? Double(encryptedItems) / Double(totalItems) : 0
    }

    public var sensitiveContentRate: Double {
        totalItems > 0 ? Double(sensitiveItems) / Double(totalItems) : 0
    }
}

public struct SecurityRecommendation {
    public let type: RecommendationType
    public let severity: Severity
    public let description: String
    public let action: String

    public enum RecommendationType {
        case enableEncryption, updateRetentionPolicy, reviewSensitiveContent, enableBiometric
    }

    public enum Severity {
        case low, medium, high, critical
    }
}

public enum SecurityError: Error {
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keyNotFound(String)
    case keychainAccessDenied
    case biometricAuthFailed
    case invalidKeyData
    case unsupportedAlgorithm
}

// MARK: - Keychain Service

actor KeychainService {
    func store(_ data: Data, for key: String, requireBiometric: Bool = false) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "ClipFlow",
            kSecValueData as String: data
        ]

        if requireBiometric {
            var accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )

            if accessControl != nil {
                query[kSecAttrAccessControl as String] = accessControl
            }
        }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "ClipFlow"
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainAccessDenied
        }
    }

    func retrieve(_ key: String) async throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "ClipFlow",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw SecurityError.keyNotFound(key)
        }

        return data
    }

    func delete(_ key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "ClipFlow"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityError.keychainAccessDenied
        }
    }
}

// MARK: - Local Authentication Import

import LocalAuthentication