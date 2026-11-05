import SwiftUI
import UIKit

// MARK: - 1.5.0 · Service Health
//
// When a page is empty, the question is always the same: is it the app, the
// network, or the server? This screen answers it in one press — real requests to
// the endpoints the app uses, with their status and latency — and reports how
// complete the catalogue actually is on this device.

struct Health15Probe: Identifiable {
    let id: String
    let name: String
    let path: String
    var status: Int?
    var milliseconds: Int?
    var error: String?
    var checkedAt: Date?

    var ok: Bool { (status ?? 0) >= 200 && (status ?? 0) < 400 }
}

@MainActor final class Health15Store: ObservableObject {
    static let shared = Health15Store()

    @Published private(set) var probes: [Health15Probe] = [
        Health15Probe(id: "site", name: "Website", path: "/"),
        Health15Probe(id: "version", name: "App version API", path: "/api/app/version"),
        Health15Probe(id: "catalog", name: "Catalogue API", path: "/api/hu-catalog"),
        Health15Probe(id: "messages", name: "Chat API", path: "/api/messages"),
        Health15Probe(id: "manifest", name: "iOS manifest", path: "/api/app/ipa")
    ]
    @Published private(set) var running = false
    @Published private(set) var history: [Bool] = []
    @Published private(set) var lastRun: Date?
    @Published var autoCheck: Bool { didSet { defaults.set(autoCheck, forKey: "lab15.health.auto") } }

    private let defaults = UserDefaults.standard
    private let base = URL(string: "https://cortanime.eu")!

    init() {
        autoCheck = defaults.object(forKey: "lab15.health.auto") as? Bool ?? false
        history = (defaults.array(forKey: "lab15.health.history") as? [Bool]) ?? []
        lastRun = defaults.object(forKey: "lab15.health.last") as? Date
    }

    var allOK: Bool { probes.allSatisfy { $0.ok } }
    var averageLatency: Int? {
        let values = probes.compactMap { $0.milliseconds }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }
    var successRate: Int {
        guard !history.isEmpty else { return 0 }
        return Int((Double(history.filter { $0 }.count) / Double(history.count) * 100).rounded())
    }

    func run() async {
        guard !running else { return }
        running = true
        var results: [Health15Probe] = []
        for probe in probes {
            var copy = probe
            copy.error = nil
            copy.status = nil
            copy.milliseconds = nil
            guard let url = URL(string: probe.path, relativeTo: base) else {
                copy.error = "Bad URL"
                results.append(copy)
                continue
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("CortexLab/1.5.0", forHTTPHeaderField: "User-Agent")
            let started = Date()
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                copy.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
                copy.status = (response as? HTTPURLResponse)?.statusCode
            } catch {
                copy.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
                copy.error = (error as NSError).code == NSURLErrorTimedOut ? "Timed out" : error.localizedDescription
            }
            copy.checkedAt = Date()
            results.append(copy)
        }
        probes = results
        running = false
        let now = Date()
        lastRun = now
        history.append(allOK)
        if history.count > 40 { history = Array(history.suffix(40)) }
        defaults.set(now, forKey: "lab15.health.last")
        defaults.set(history, forKey: "lab15.health.history")
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: "lab15.health.history")
        defaults.removeObject(forKey: "lab15.health.last")
        lastRun = nil
    }

    func report(catalog: [Anime]) -> String {
        var lines = ["CortexAnime \(Lab15.version) (\(Lab15.build)) service report",
                     "Generated \(Self.stamp.string(from: Date()))",
                     "Device \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(UIDevice.current.model)",
                     ""]
        for probe in probes {
            let status = probe.status.map(String.init) ?? "—"
            let latency = probe.milliseconds.map { "\($0) ms" } ?? "—"
            lines.append("\(probe.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(status) \(latency) \(probe.error ?? "")")
        }
        lines.append("")
        lines.append("Catalogue: \(catalog.count) titles")
        if !catalog.isEmpty {
            let hu = catalog.filter { $0.hasHungarian }.count
            let covers = catalog.filter { $0.cover != nil }.count
            let synopsis = catalog.filter { !$0.synopsis.isEmpty }.count
            lines.append("HU subtitles: \(hu) (\(percent(hu, of: catalog.count))%)")
            lines.append("Covers: \(covers) (\(percent(covers, of: catalog.count))%)")
            lines.append("Synopsis: \(synopsis) (\(percent(synopsis, of: catalog.count))%)")
        }
        if let average = averageLatency { lines.append("Average latency: \(average) ms") }
        lines.append("Success rate (last \(history.count) runs): \(successRate)%")
        return lines.joined(separator: "\n")
    }

    func percent(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

struct ServiceHealth15View: View {
    @ObservedObject private var store = Health15Store.shared
    @EnvironmentObject private var catalog: CatalogModel
    @State private var copied = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headline
                LabCard(title: "Endpoints", footnote: "Each probe is a real request with the same timeout the app uses. A 401 from the chat API is expected when signed out.") {
                    ForEach(store.probes) { probe in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(probe.checkedAt == nil ? Color.white.opacity(0.15) : (probe.ok ? Color.cortexMint : Color.orange))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(probe.name).font(.system(size: 13.5, weight: .semibold))
                                Text(probe.error ?? probe.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(probe.status.map(String.init) ?? "—")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(probe.ok ? Color.cortexMint : .white.opacity(0.5))
                                Text(probe.milliseconds.map { "\($0) ms" } ?? "")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 9)
                        Divider().overlay(Color.white.opacity(0.06))
                    }
                }
                coverage
                history
                buttons
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Service Health")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.autoCheck, store.lastRun == nil { await store.run() }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LabStat(value: store.averageLatency.map { "\($0)ms" } ?? "—", label: "average", tint: .cortexMint)
                LabStat(value: "\(store.successRate)%", label: "success rate")
                LabStat(value: "\(store.history.count)", label: "runs")
            }
            HStack(spacing: 8) {
                Pill(text: store.running ? "Checking…" : (store.allOK ? "All systems nominal" : "Waiting for a check"),
                     color: store.running ? .cortexPurple : (store.allOK ? .cortexMint : .orange))
                Spacer()
                if let last = store.lastRun {
                    Text(Health15Store.stamp.string(from: last)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var coverage: some View {
        let titles = catalog.titles
        let total = titles.count
        let hu = titles.filter { $0.hasHungarian }.count
        let covers = titles.filter { $0.cover != nil }.count
        let synopsis = titles.filter { !$0.synopsis.isEmpty }.count
        return LabCard(title: "Catalogue coverage", footnote: "Measured on the catalogue this device has loaded, so it matches what you can actually search right now.") {
            LabRow(title: "Titles indexed", detail: "loaded in memory", symbol: "books.vertical.fill") {
                Text("\(total)").font(.system(size: 13, weight: .bold, design: .rounded))
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Hungarian subtitles", detail: "\(hu) of \(total)", symbol: "character.bubble.fill") {
                Text("\(store.percent(hu, of: total))%").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cortexMint)
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Artwork", detail: "\(covers) of \(total)", symbol: "photo.fill") {
                Text("\(store.percent(covers, of: total))%").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cortexPurple)
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Synopsis", detail: "\(synopsis) of \(total)", symbol: "text.alignleft") {
                Text("\(store.percent(synopsis, of: total))%").font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow)
            }
        }
    }

    private var history: some View {
        LabCard(title: "History", footnote: "One mark per check, oldest on the left. Green means every endpoint answered.") {
            HStack(alignment: .bottom, spacing: 3) {
                if store.history.isEmpty {
                    Text("No checks yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
                } else {
                    ForEach(Array(store.history.enumerated()), id: \.offset) { pair in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(pair.element ? Color.cortexMint : Color.orange)
                            .frame(width: 6, height: pair.element ? 26 : 12)
                    }
                }
                Spacer()
            }
            .frame(height: 34)
            .padding(.vertical, 8)
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Check on open", detail: "Runs the probes when this screen appears", symbol: "bolt.fill") {
                Toggle("", isOn: $store.autoCheck).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            Button { store.clearHistory() } label: {
                Label("Clear history", systemImage: "eraser").font(.system(size: 12.5, weight: .semibold)).padding(.vertical, 4)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await store.run() }
            } label: {
                HStack(spacing: 8) {
                    if store.running { ProgressView().tint(.white) }
                    else { Image(systemName: "antenna.radiowaves.left.and.right") }
                    Text(store.running ? "Checking…" : "Run all checks")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(store.running)

            Button {
                UIPasteboard.general.string = store.report(catalog: catalog.titles)
                copied = true
            } label: {
                Label(copied ? "Report copied" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}
