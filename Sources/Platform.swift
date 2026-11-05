import SwiftUI
import UIKit
import Security
import Darwin

// Device diagnostics stay on-device. No UDID, serial number, IMEI or advertising ID.
enum DeviceInfo {
    static var hardware: String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
    static var model: String {
        ["iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
         "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max"][hardware] ?? UIDevice.current.model
    }
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown" }
}

struct DeviceSection: View {
    var body: some View {
        Section("About this device") {
            LabeledContent("Model", value: DeviceInfo.model)
            LabeledContent("Hardware identifier", value: DeviceInfo.hardware)
            LabeledContent("iOS", value: UIDevice.current.systemVersion)
            LabeledContent("App version", value: "\(DeviceInfo.version) (\(DeviceInfo.build))")
        }
        Section { Text("These details are shown locally. Device identifiers and passwords are not sent as diagnostics.").font(.footnote).foregroundStyle(.secondary) }
    }
}

enum Vault {
    static func save(_ value: String, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Cortex",
                                  kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AppFailure.message("Could not save the credential securely.") }
    }
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Cortex",
                              kSecAttrAccount as String: key, kSecReturnData as String: true,
                              kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                              kSecAttrService as String: Bundle.main.bundleIdentifier ?? "Cortex",
                              kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct ErrorNotice: View {
    let text: String
    var body: some View { Label(text, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange).textSelection(.enabled) }
}

// Standard SwiftUI bars adopt Liquid Glass with current SDKs and supporting iOS.
// No painted-over tab bar, fabricated blur screenshot, or forced transparency.
struct NativeCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 20)) }
}
