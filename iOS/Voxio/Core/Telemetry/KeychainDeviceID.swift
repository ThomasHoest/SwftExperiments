import Foundation
import Security

nonisolated enum KeychainDeviceID {

    private static let service = "T-Creative.Voxio"
    private static let account = "voxio.telemetry.deviceId"

    static func read() -> UUID? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }

    static func write(_ id: UUID) {
        let data = id.uuidString.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let addQuery = query.merging([kSecValueData: data] as [CFString: Any]) { _, new in new }

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func readOrCreate() -> UUID {
        if let existing = read() { return existing }
        let newId = UUID()
        write(newId)
        return newId
    }
}
