import Foundation
import Security
import ToolchordProviderIPC

public enum EndpointCredentials {
    private static func query(endpoint: String) throws -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ch.lkmc.Toolchord.generation-endpoint",
            kSecAttrAccount as String: try ProviderEndpoint.baseURL(endpoint).absoluteString
        ]
    }

    public static func read(endpoint: String) throws -> String? {
        var query = try query(endpoint: endpoint)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw ProviderFailure("The saved API key could not be read. Replace it in the provider settings.")
        }
        return key
    }

    public static func store(_ key: String?, endpoint: String) throws {
        let identity = try query(endpoint: endpoint)
        guard let key, !key.isEmpty else {
            let status = SecItemDelete(identity as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
            return
        }
        try EndpointProvider.validate(key: key)
        let change = [kSecValueData as String: Data(key.utf8)]
        // An in-place update preserves the existing item and its access policy
        // if Keychain refuses the replacement.
        let status = SecItemUpdate(identity as CFDictionary, change as CFDictionary)
        guard status == errSecItemNotFound else { try check(status); return }
        var item = identity
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Toolchord generation endpoint"
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecDuplicateItem {
            try check(SecItemUpdate(identity as CFDictionary, change as CFDictionary))
        } else {
            try check(added)
        }
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            throw ProviderFailure("Couldn’t access the endpoint API key in Keychain. " + reason)
        }
    }
}
