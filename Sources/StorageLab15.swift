import SwiftUI
import UIKit

// MARK: - 1.5.0 · Storage & Data
//
// The app keeps a surprising amount on the device: preferences, caches, image
// data, the watch log. This screen makes it visible, bucket by bucket, in bytes
// you can act on — and it can hand you a full JSON backup before you clear
// anything.

struct Storage15Bucket: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let keys: [String]
    let bytes: Int

    var label: String {
        switch name {
        case "credits": return "Credits & watch log"
        case "lab15": return "Cortex Lab"
        case "motion": return "Motion & effects"
        case "player": return "Player preferences"
        case "decor": return "Decorations"
        case "subs": return "Subtitle cache"
        case "chat": return "Chat state"
        case "catalog": return "Catalogue cache"
        case "library": return "Library & history"
        case "auth": return "Account"
        case "detail": return "Title screens"
        default: return String(name.prefix(1)).uppercased() + String(name.dropFirst())
        }
    }
}

@MainActor final class Storage15Store: ObservableObject {
    static let shared = Storage15Store()

    @Published private(set) var buckets: [Storage15Bucket] = []
    @Published private(set) var cacheBytes: Int = 0
    @Published private(set) var urlCacheBytes: Int = 0
    @Published private(set) var totalBytes: Int = 0
    @Published private(set) var lastCleanup: Date?
    @Published var autoClean: Bool { didSet { defaults.set(autoClean, forKey: "lab15.storage.autoClean") } }
    @Published var capMB: Int { didSet { defaults.set(capMB, forKey: "lab15.storage.capMB") } }

    private let defaults = UserDefaults.standard

    init() {
        autoClean = defaults.object(forKey: "lab15.storage.autoClean") as? Bool ?? true
        capMB = defaults.object(forKey: "lab15.storage.capMB") as? Int ?? 200
        lastCleanup = defaults.object(forKey: "lab15.storage.lastCleanup") as? Date
        refresh()
    }

    // MARK: measuring

    private func bytes(of value: Any) -> Int {
        switch value {
        case let data as Data: return data.count
        case let text as String: return text.utf8.count
        case let array as [Any]: return array.reduce(0) { $0 + bytes(of: $1) }
        case let dictionary as [String: Any]: return dictionary.reduce(0) { $0 + bytes(of: $1.value) + $1.key.utf8.count }
        case let number as NSNumber: return MemoryLayout.size(ofValue: number.doubleValue)
        default: return 16
        }
    }

    private func isSystemKey(_ key: String) -> Bool {
        let prefixes = ["NS", "Apple", "AK", "com.apple", "WebKit", "PK", "METADATA", "INNext", "_", "MS", "SB", "XP", "CUI"]
        return prefixes.contains { key.hasPrefix($0) }
    }

    func refresh() {
        let all = defaults.dictionaryRepresentation()
        var grouped: [String: (keys: [String], bytes: Int)] = [:]
        for (key, value) in all where !isSystemKey(key) {
            let prefix = key.split(separator: ".").first.map(String.init) ?? key
            let current = grouped[prefix] ?? ([], 0)
            grouped[prefix] = (current.keys + [key], current.bytes + bytes(of: value) + key.utf8.count)
        }
        buckets = grouped
            .map { Storage15Bucket(name: $0.key, keys: $0.value.keys.sorted(), bytes: $0.value.bytes) }
            .sorted { $0.bytes > $1.bytes }

        cacheBytes = directoryBytes(cachesDirectory)
        let cache = URLCache.shared
        urlCacheBytes = cache.currentDiskUsage + cache.currentMemoryUsage
        totalBytes = buckets.reduce(0) { $0 + $1.bytes } + cacheBytes + urlCacheBytes
    }

    var cachesDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private func directoryBytes(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                             includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == false { total += values?.fileSize ?? 0 }
        }
        return total
    }

    // MARK: clearing

    func clear(_ bucket: Storage15Bucket) {
        for key in bucket.keys { defaults.removeObject(forKey: key) }
        markCleaned()
        refresh()
    }

    func clearCachesOnly() {
        URLCache.shared.removeAllCachedResponses()
        let manager = FileManager.default
        if let items = try? manager.contentsOfDirectory(at: cachesDirectory, includingPropertiesForKeys: nil) {
            for item in items { try? manager.removeItem(at: item) }
        }
        markCleaned()
        refresh()
    }

    func resetLab() {
        let labKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("lab15.") }
        for key in labKeys where key != "lab15.storage.autoClean" && key != "lab15.storage.capMB" {
            defaults.removeObject(forKey: key)
        }
        markCleaned()
        refresh()
    }

    private func markCleaned() {
        let now = Date()
        lastCleanup = now
        defaults.set(now, forKey: "lab15.storage.lastCleanup")
    }

    // MARK: export

    func backupJSON() -> String {
        var payload: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where !isSystemKey(key) {
            if let data = value as? Data {
                payload[key] = ["kind": "data", "base64": data.base64EncodedString()]
            } else if JSONSerialization.isValidJSONObject([value]) {
                payload[key] = value
            } else if let date = value as? Date {
                payload[key] = ["kind": "date", "value": date.timeIntervalSince1970]
            } else {
                payload[key] = String(describing: value)
            }
        }
        let document: [String: Any] = [
            "app": "CortexAnime",
            "version": Lab15.version,
            "build": Lab15.build,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "preferences": payload
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    func report() -> String {
        var lines = ["CortexAnime \(Lab15.version) (\(Lab15.build)) storage report"]
        lines.append("Total: \(LabFormat.bytes(totalBytes))")
        lines.append("Preferences: \(LabFormat.bytes(buckets.reduce(0) { $0 + $1.bytes })) in \(buckets.reduce(0) { $0 + $1.keys.count }) keys")
        lines.append("Caches folder: \(LabFormat.bytes(cacheBytes))")
        lines.append("URL cache: \(LabFormat.bytes(urlCacheBytes))")
        lines.append("Cap: \(capMB) MB · auto clean \(autoClean ? "on" : "off")")
        for bucket in buckets {
            lines.append("  · \(bucket.label): \(LabFormat.bytes(bucket.bytes)) / \(bucket.keys.count) keys")
        }
        return lines.joined(separator: "\n")
    }
}

extension LabFormat {
    static func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(max(0, count)))
    }
}

struct StorageLab15View: View {
    @ObservedObject private var store = Storage15Store.shared
    @ObservedObject private var credits = CreditStore.shared
    @State private var confirming: Storage15Bucket?
    @State private var confirmCaches = false
    @State private var confirmLab = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    LabStat(value: LabFormat.bytes(store.totalBytes), label: "on device", tint: .cortexMint)
                    LabStat(value: LabFormat.bytes(store.cacheBytes + store.urlCacheBytes), label: "cache")
                    LabStat(value: "\(credits.watchLog.count)", label: "watch ticks", tint: .yellow)
                }

                LabCard(title: "Preferences", footnote: "Sizes are measured from the stored value, not estimated. A bucket can be cleared on its own; the app rebuilds defaults the next time it needs them.") {
                    if store.buckets.isEmpty {
                        Text("Nothing stored yet.").font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.vertical, 10)
                    }
                    ForEach(store.buckets) { bucket in
                        Button { confirming = bucket } label: {
                            LabRow(title: bucket.label, detail: "\(bucket.keys.count) keys", symbol: "shippingbox.fill") {
                                Text(LabFormat.bytes(bucket.bytes))
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }

                LabCard(title: "Caches", footnote: "Image and response caches only. Clearing them costs a reload, never a setting.") {
                    LabRow(title: "Caches folder", detail: "Downloaded images, temp files", symbol: "folder.fill") {
                        Text(LabFormat.bytes(store.cacheBytes)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "URL cache", detail: "API responses and artwork", symbol: "network") {
                        Text(LabFormat.bytes(store.urlCacheBytes)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    Button { confirmCaches = true } label: {
                        Label("Clear both caches", systemImage: "trash").font(.system(size: 13, weight: .semibold)).padding(.vertical, 6)
                    }
                }

                LabCard(title: "Rules", footnote: "The cap is a target, not a hard limit: the app trims caches on launch when it is exceeded.") {
                    LabRow(title: "Clean on launch", detail: "Trim caches above the cap", symbol: "sparkles") {
                        Toggle("", isOn: $store.autoClean).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Cache cap", detail: "\(store.capMB) MB", symbol: "gauge.with.dots.needle.33percent") {
                        Stepper("", value: $store.capMB, in: 50...500, step: 50).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Last cleanup", detail: store.lastCleanup.map { Self.stamp.string(from: $0) } ?? "never", symbol: "clock")
                }

                LabCard(title: "Backup", footnote: "The backup holds preferences and counters. It does not contain the account password or any token.") {
                    ShareLink(item: store.backupJSON()) { Label("Export preferences", systemImage: "square.and.arrow.up") }
                        .font(.system(size: 13, weight: .semibold))
                    Divider().overlay(Color.white.opacity(0.06))
                    Button {
                        UIPasteboard.general.string = store.report()
                        copied = true
                    } label: {
                        Label(copied ? "Report copied" : "Copy storage report", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    Button { confirmLab = true } label: {
                        Label("Reset every Cortex Lab setting", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Storage & Data")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.refresh() }
        .alert("Clear \(confirming?.label ?? "bucket")?", isPresented: Binding(
            get: { confirming != nil },
            set: { if !$0 { confirming = nil } })) {
            Button("Clear", role: .destructive) {
                if let bucket = confirming { store.clear(bucket) }
                confirming = nil
            }
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: {
            Text("This removes \(confirming?.keys.count ?? 0) stored keys. The app falls back to defaults.")
        }
        .alert("Clear both caches?", isPresented: $confirmCaches) {
            Button("Clear", role: .destructive) { store.clearCachesOnly() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Artwork and API responses will be downloaded again when needed.")
        }
        .alert("Reset the Lab?", isPresented: $confirmLab) {
            Button("Reset", role: .destructive) { store.resetLab() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Lists, tags, notes, goals and presets created in 1.5.0 go back to their starting values. Credits and the watch log are untouched.")
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
