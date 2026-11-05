import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 1.5.1 · Downloads, redesigned
//
// The old screen was a list of rows and, in each row, seven text buttons. This
// one is built around the two questions people actually ask: "what is on this
// phone" (series, episodes, bytes) and "what is happening right now" (the live
// transfer, its batch, what comes next). Everything that used to be a button in
// every row is now a chip you tap, or a menu you open on the episode you care
// about. The engine underneath is untouched: same queue, same files, same
// offline player.

enum DownloadFilter15: String, CaseIterable, Identifiable {
    case all, active, ready, attention, imported
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .active: return "Downloading"
        case .ready: return "Ready"
        case .attention: return "Needs attention"
        case .imported: return "Imported"
        }
    }
}

struct DownloadSeries15: Identifiable {
    let id: Int
    let title: String
    let cover: URL?
    let items: [DownloadItem]

    var ready: Int { items.filter { $0.state == "downloaded" }.count }
    var failed: Int { items.filter { $0.state == "failed" }.count }
    var bytes: Int64 { items.reduce(0) { $0 + ($1.bytesOnDisk ?? 0) } }
    var active: Bool { items.contains { DownloadQueuePolicy.activeStates.contains($0.state) || $0.state == "queued" } }
    var imported: Bool { items.contains { $0.imported == true } }
    var highestEpisode: Int { items.map(\.episode).max() ?? 0 }
}

enum CleanupPlan15: String, Identifiable {
    case watched, failed, imported
    var id: String { rawValue }

    var title: String {
        switch self {
        case .watched: return "Remove episodes you finished?"
        case .failed: return "Remove the broken downloads?"
        case .imported: return "Remove the imported videos?"
        }
    }

    var action: String {
        switch self {
        case .watched: return "Remove watched"
        case .failed: return "Remove broken"
        case .imported: return "Remove imported"
        }
    }

    var detail: String {
        switch self {
        case .watched: return "These episodes are marked completed in your watch log. The files are deleted from this device; the history entry stays."
        case .failed: return "Broken entries and their partial files are deleted. You can download the episodes again from their anime page."
        case .imported: return "Videos you imported from Files are deleted. Nothing else is removed."
        }
    }
}

@MainActor final class DownloadStudio15: ObservableObject {
    static let shared = DownloadStudio15()

    @Published var filter: DownloadFilter15 = .all
    @Published private(set) var free: Int64 = 0
    @Published private(set) var total: Int64 = 0
    /// 1.5.2: a saját HLS-letöltő választja ki ezzel a variánst a playlistből.
    @Published var quality: DownloadQuality15 {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: "downloads.quality15") }
    }

    init() { quality = DownloadQuality15.current }

    func refreshSpace() {
        let values = try? OfflineFiles.mediaFolder.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(values?.volumeTotalCapacity ?? 0)
    }

    func series(from items: [DownloadItem]) -> [DownloadSeries15] {
        var buckets: [Int: [DownloadItem]] = [:]
        for item in items { buckets[item.animeID, default: []].append(item) }
        let groups: [DownloadSeries15] = buckets.map { key, list in
            let sorted = list.sorted { $0.episode < $1.episode }
            return DownloadSeries15(id: key,
                                    title: sorted.first?.title ?? "Imported video",
                                    cover: sorted.compactMap { $0.anime?.cover }.first,
                                    items: sorted)
        }
        return groups.sorted { left, right in
            if left.active != right.active { return left.active }
            if left.failed != right.failed { return left.failed > right.failed }
            if left.highestEpisode != right.highestEpisode { return left.highestEpisode > right.highestEpisode }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    func filtered(_ groups: [DownloadSeries15]) -> [DownloadSeries15] {
        switch filter {
        case .all: return groups
        case .active: return groups.filter { $0.active }
        case .ready: return groups.filter { $0.ready > 0 }
        case .attention: return groups.filter { $0.failed > 0 }
        case .imported: return groups.filter { $0.imported }
        }
    }

    func count(_ filter: DownloadFilter15, groups: [DownloadSeries15]) -> Int {
        switch filter {
        case .all: return groups.reduce(0) { $0 + $1.items.count }
        case .active: return groups.reduce(0) { $0 + $1.items.filter { DownloadQueuePolicy.activeStates.contains($0.state) || $0.state == "queued" }.count }
        case .ready: return groups.reduce(0) { $0 + $1.ready }
        case .attention: return groups.reduce(0) { $0 + $1.failed }
        case .imported: return groups.reduce(0) { $0 + $1.items.filter { $0.imported == true }.count }
        }
    }
}

// MARK: - Screen

struct NativeDownloads: View {
    @EnvironmentObject private var downloads: Downloads
    @ObservedObject private var credits = CreditStore.shared
    @ObservedObject private var connectivity = Connectivity.shared
    @ObservedObject private var studio = DownloadStudio15.shared

    @State private var route: PlaybackRoute?
    @State private var importingVideo = false
    @State private var importingSubtitles = false
    @State private var subtitleTarget: DownloadItem?
    @State private var busy = false
    @State private var message: String?
    @State private var plan: CleanupPlan15?
    @State private var showCleanup = false

    private var groups: [DownloadSeries15] { studio.series(from: downloads.items) }
    private var visible: [DownloadSeries15] { studio.filtered(groups) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                storageCard
                if let live = downloads.currentTransfer { transferCard(live) }
                if connectivity.isOffline && !downloads.items.isEmpty { offlineNotice }
                filters
                if visible.isEmpty {
                    emptyState
                } else {
                    ForEach(visible) { group in seriesCard(group) }
                }
                qualityCard
                cleanupCard
                rulesCard
                if let error = downloads.storageError {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                }
                if let message {
                    Text(message).font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importingVideo = true } label: { Label("Import video from Files", systemImage: "folder.badge.plus") }
                    Button { showCleanup = true } label: { Label("Free up space", systemImage: "scissors") }
                    if !downloads.items.isEmpty {
                        Divider()
                        Button(role: .destructive) {
                            for item in downloads.items where item.state == "failed" { downloads.remove(item) }
                        } label: { Label("Remove broken downloads", systemImage: "trash") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityIdentifier("downloads.menu")
            }
        }
        .onAppear { studio.refreshSpace() }
        .handOffPlayerRoute($route)
        .fileImporter(isPresented: $importingVideo,
                      allowedContentTypes: [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "m4v") ?? .movie]) { result in
            switch result {
            case .success(let url):
                busy = true
                Task {
                    defer { busy = false }
                    do { try await downloads.importVideo(url); message = nil; studio.refreshSpace() }
                    catch { if !(error is CancellationError), !Task.isCancelled { message = error.localizedDescription } }
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importingSubtitles,
                      allowedContentTypes: [.plainText, .text,
                                            UTType(filenameExtension: "vtt") ?? .plainText,
                                            UTType(filenameExtension: "srt") ?? .plainText]) { result in
            guard let item = subtitleTarget else { return }
            do { try downloads.importSubtitles(result.get(), for: item); message = nil }
            catch { if !(error is CancellationError), !Task.isCancelled { message = error.localizedDescription } }
        }
        .confirmationDialog(Text(plan?.title ?? "Free up space"),
                            isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }),
                            titleVisibility: .visible,
                            presenting: plan) { current in
            Button(current.action, role: .destructive) { perform(current) }
            Button("Cancel", role: .cancel) { plan = nil }
        } message: { current in
            Text(current.detail)
        }
        .confirmationDialog("Free up space", isPresented: $showCleanup, titleVisibility: .visible) {
            if !watchedSaved.isEmpty {
                Button("Remove \(watchedSaved.count) watched episodes") { plan = .watched }
            }
            if !failedItems.isEmpty {
                Button("Remove \(failedItems.count) broken downloads") { plan = .failed }
            }
            if !importedItems.isEmpty {
                Button("Remove \(importedItems.count) imported videos") { plan = .imported }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Choose what to delete. Everything here can be downloaded again later.")
        }
    }

    // MARK: storage

    private var storageCard: some View {
        let used = downloads.savedBytes
        let fraction: Double = {
            guard studio.total > 0 else { return 0 }
            let devicesUsed = Double(max(0, studio.total - studio.free))
            return min(1, max(0, devicesUsed / Double(max(1, studio.total))))
        }()
        let libraryFraction: Double = {
            guard studio.total > 0 else { return 0 }
            return min(1, Double(used) / Double(max(1, studio.total)))
        }()
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Offline library")
                        .font(.system(size: 10.5, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.42))
                    Text(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(readyCount) ready")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.cortexMint)
                    Text("\(groups.count) series · \(downloads.items.count) episodes")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .frame(width: max(2, geo.size.width * fraction))
                        Capsule()
                            .fill(LinearGradient(colors: [Color.cortexPurple, Color.cortexPurple.opacity(0.55)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(2, geo.size.width * libraryFraction))
                    }
                }
                .frame(height: 9)
                HStack {
                    Text(studio.total > 0
                         ? "\(ByteCountFormatter.string(fromByteCount: studio.free, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: studio.total, countStyle: .file))"
                         : "Device capacity unavailable")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text("Wi-Fi only")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
    }

    private var readyCount: Int { downloads.items.filter { $0.state == "downloaded" }.count }

    // MARK: live transfer

    private func transferCard(_ item: DownloadItem) -> some View {
        let batch = downloads.queueRows
        let done = batch.filter { $0.state == "downloaded" }.count
        let next = downloads.items.first { $0.state == "queued" && $0.id != item.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AnimeArtwork(url: item.anime?.cover)
                    .frame(width: 46, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW DOWNLOADING")
                        .font(.system(size: 9.5, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(Color.cortexPurple)
                    Text(item.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text("Episode \(item.episode) · \(item.statusLabel)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 4)
                Button {
                    if ["paused"].contains(item.state) { downloads.resume(item) } else { downloads.pause(item) }
                } label: {
                    Image(systemName: item.state == "paused" ? "play.fill" : "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.cortexPurple.opacity(0.18), in: Circle())
                        .foregroundStyle(Color.cortexPurple)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("downloads.toggle")
            }
            VStack(spacing: 6) {
                ProgressView(value: min(1, max(0, item.progress)))
                    .tint(Color.cortexPurple)
                    .scaleEffect(x: 1, y: 1.6, anchor: .center)
                HStack {
                    Text("\(done) of \(batch.count) in this batch")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text("\(Int(min(1, max(0, item.progress)) * 100))%")
                        .font(.system(size: 11.5, weight: .black, design: .rounded))
                        .foregroundStyle(Color.cortexPurple)
                        .contentTransition(.numericText())
                }
            }
            if let next {
                Divider().overlay(Color.white.opacity(0.06))
                HStack(spacing: 8) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Next: \(next.title) · EP \(next.episode)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.cortexPurple.opacity(0.28)))
    }

    private var offlineNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "wifi.slash").font(.system(size: 13, weight: .bold))
            Text("Offline. Downloads are paused until a Wi-Fi network is back; everything already saved still plays.")
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityIdentifier("downloads.offline")
    }

    // MARK: filters

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DownloadFilter15.allCases) { option in
                    let selected = studio.filter == option
                    let count = studio.count(option, groups: groups)
                    Button { studio.filter = option } label: {
                        HStack(spacing: 5) {
                            Text(option.title)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(selected ? Color.white.opacity(0.75) : Color.white.opacity(0.35))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.62))
                        .background(selected ? Color.cortexPurple : Color.cortexPanel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeEmpty(title: studio.filter == .all ? "No offline episodes" : "Nothing in this filter",
                        detail: studio.filter == .all
                        ? "Download an episode from its anime page over Wi-Fi, or import an MP4, M4V or MOV file from Files. Saved episodes play here without a connection."
                        : "Switch back to All to see everything on this device.",
                        icon: "arrow.down.circle")
            Button { importingVideo = true } label: {
                Label("Import video from Files", systemImage: "folder.badge.plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("downloads.import")
        }
    }

    // MARK: series

    private func seriesCard(_ group: DownloadSeries15) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                AnimeArtwork(url: group.cover)
                    .frame(width: 40, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title).font(.system(size: 13.5, weight: .bold)).lineLimit(2)
                    Text(summary(group))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
                Menu {
                    if group.items.contains(where: { downloads.localURL($0) != nil }) {
                        Button { playFirstReady(group) } label: { Label("Play the next ready episode", systemImage: "play.fill") }
                    }
                    if group.failed > 0 {
                        Button { retryAll(group) } label: { Label("Retry \(group.failed) failed", systemImage: "arrow.clockwise") }
                    }
                    if group.items.contains(where: { ["downloading", "queued", "resolving"].contains($0.state) }) {
                        Button { pauseAll(group) } label: { Label("Pause this series", systemImage: "pause.fill") }
                    }
                    if group.items.contains(where: { $0.state == "paused" }) {
                        Button { resumeAll(group) } label: { Label("Resume this series", systemImage: "play.fill") }
                    }
                    Divider()
                    Button(role: .destructive) { for item in group.items { downloads.remove(item) } } label: {
                        Label("Remove all \(group.items.count) episodes", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityIdentifier("downloads.seriesMenu.\(group.id)")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 62), spacing: 8)], spacing: 8) {
                ForEach(group.items) { item in
                    DownloadEpisode15(item: item,
                                      playable: downloads.localURL(item) != nil,
                                      onTap: { act(on: item) },
                                      onRepair: { repair(item) },
                                      onSubtitles: { subtitleTarget = item; importingSubtitles = true },
                                      onRemove: { downloads.remove(item) })
                }
            }
        }
        .padding(13)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
    }

    private func summary(_ group: DownloadSeries15) -> String {
        var parts = ["\(group.ready) of \(group.items.count) ready"]
        if group.bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: group.bytes, countStyle: .file)) }
        if group.failed > 0 { parts.append("\(group.failed) failed") }
        if group.active { parts.append("in progress") }
        return parts.joined(separator: " · ")
    }

    // MARK: actions

    private func act(on item: DownloadItem) {
        switch item.state {
        case "downloaded":
            play(item)
        case "failed":
            do { try downloads.retryQueued(item); message = nil }
            catch { message = "Open this anime's page to download the episode again." }
        case "paused":
            downloads.resume(item)
        case "queued", "resolving", "downloading", "verifying", "resuming":
            downloads.pause(item)
        default:
            play(item)
        }
    }

    private func play(_ item: DownloadItem) {
        do { route = try downloads.route(for: item) }
        catch { if !(error is CancellationError), !Task.isCancelled { message = error.localizedDescription } }
    }

    private func playFirstReady(_ group: DownloadSeries15) {
        guard let item = group.items.first(where: { downloads.localURL($0) != nil }) else { return }
        play(item)
    }

    private func repair(_ item: DownloadItem) {
        do { try downloads.repair(item); message = "Episode \(item.episode) is queued again." }
        catch { message = error.localizedDescription }
    }

    private func retryAll(_ group: DownloadSeries15) {
        for item in group.items where item.state == "failed" {
            try? downloads.retryQueued(item)
        }
    }

    private func pauseAll(_ group: DownloadSeries15) {
        for item in group.items where ["downloading", "queued", "resolving"].contains(item.state) { downloads.pause(item) }
    }

    private func resumeAll(_ group: DownloadSeries15) {
        for item in group.items where item.state == "paused" { downloads.resume(item) }
    }

    // MARK: cleanup

    private var watchedSaved: [DownloadItem] {
        let finished = Set(credits.watchLog.filter { $0.completed }.map { "\($0.animeID)#\($0.episode)" })
        return downloads.items.filter { $0.state == "downloaded" && finished.contains("\($0.animeID)#\($0.episode)") }
    }
    private var failedItems: [DownloadItem] { downloads.items.filter { $0.state == "failed" } }
    private var importedItems: [DownloadItem] { downloads.items.filter { $0.imported == true } }

    private func perform(_ plan: CleanupPlan15) {
        let targets: [DownloadItem]
        switch plan {
        case .watched: targets = watchedSaved
        case .failed: targets = failedItems
        case .imported: targets = importedItems
        }
        let freed = targets.reduce(Int64(0)) { $0 + ($1.bytesOnDisk ?? 0) }
        for item in targets { downloads.remove(item) }
        message = "Removed \(targets.count) episode\(targets.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)) freed."
        studio.refreshSpace()
        self.plan = nil
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DOWNLOAD QUALITY")
                .font(.system(size: 10.5, weight: .black)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    ForEach(DownloadQuality15.allCases) { option in
                        Button { studio.quality = option } label: {
                            Text(option.title)
                                .font(.system(size: 12.5, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(studio.quality == option ? Color.white : Color.white.opacity(0.6))
                                .background(studio.quality == option ? Color.cortexPurple : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(studio.quality.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Applies to the next episode that starts downloading. Saved episodes keep the quality they were downloaded at.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var cleanupCard: some View {
        let watchedBytes = watchedSaved.reduce(Int64(0)) { $0 + ($1.bytesOnDisk ?? 0) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("FREE UP SPACE")
                .font(.system(size: 10.5, weight: .black)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                cleanupRow(title: "Episodes you finished",
                           detail: watchedSaved.isEmpty ? "Nothing watched is still saved" : "\(watchedSaved.count) episodes · \(ByteCountFormatter.string(fromByteCount: watchedBytes, countStyle: .file))",
                           symbol: "checkmark.circle",
                           enabled: !watchedSaved.isEmpty) { plan = .watched }
                Divider().overlay(Color.white.opacity(0.06))
                cleanupRow(title: "Broken downloads",
                           detail: failedItems.isEmpty ? "Nothing to clean" : "\(failedItems.count) entries with partial files",
                           symbol: "exclamationmark.triangle",
                           enabled: !failedItems.isEmpty) { plan = .failed }
                Divider().overlay(Color.white.opacity(0.06))
                cleanupRow(title: "Imported videos",
                           detail: importedItems.isEmpty ? "No files imported" : "\(importedItems.count) files from Files",
                           symbol: "folder",
                           enabled: !importedItems.isEmpty) { plan = .imported }
            }
            .padding(.horizontal, 14)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func cleanupRow(title: String, detail: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? Color.cortexPurple : .white.opacity(0.25))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(enabled ? 0.3 : 0.12))
            }
            .padding(.vertical, 11)
            .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HOW OFFLINE WORKS")
                .font(.system(size: 10.5, weight: .black)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 10) {
                rule("wifi", "Wi-Fi only, one episode at a time", "Cellular is never used, even on an unlimited plan.")
                rule("captions.bubble", "Subtitles travel with the episode", "The chosen language is saved first, then English, then video only.")
                rule("internaldrive", "64 MB always stays free", "A download that would fill the device is refused before it starts.")
                rule("arrow.triangle.2.circlepath", "A broken save can be repaired", "Tap a failed episode to retry it, or download it again from the anime page.")
            }
            .padding(14)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func rule(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.cortexPurple)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Episode chip

struct DownloadEpisode15: View {
    let item: DownloadItem
    let playable: Bool
    let onTap: () -> Void
    let onRepair: () -> Void
    let onSubtitles: () -> Void
    let onRemove: () -> Void

    private var fill: Color {
        switch item.state {
        case "downloaded": return playable ? Color.cortexPurple : Color.orange.opacity(0.45)
        case "failed": return Color.orange.opacity(0.32)
        case "paused": return Color.white.opacity(0.16)
        case "queued": return Color.white.opacity(0.1)
        default: return Color.cortexPurple.opacity(0.42)
        }
    }

    private var border: Color {
        switch item.state {
        case "downloaded": return playable ? Color.cortexPurple : Color.orange
        case "failed": return Color.orange
        case "paused": return .white.opacity(0.3)
        default: return .clear
        }
    }

    private var showsProgress: Bool {
        ["downloading", "resolving", "verifying", "resuming", "queued"].contains(item.state)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .frame(height: 42)
                HStack(spacing: 3) {
                    Text("\(item.episode)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    if item.state == "failed" {
                        Image(systemName: "exclamationmark").font(.system(size: 8, weight: .black)).foregroundStyle(.white)
                    }
                    if item.state == "paused" {
                        Image(systemName: "pause.fill").font(.system(size: 7, weight: .black)).foregroundStyle(.white.opacity(0.7))
                    }
                    if playable {
                        Image(systemName: "play.fill").font(.system(size: 7, weight: .black)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsProgress && item.progress > 0 {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: max(0, geo.size.width * min(1, max(0, item.progress))))
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(playable
                                 ? "download.play.\(item.animeID).\(item.episode)"
                                 : "download.item.\(item.animeID).\(item.episode)")
        .contextMenu {
            if playable {
                Button { onTap() } label: { Label("Play offline", systemImage: "play.fill") }
            }
            Button { onRepair() } label: { Label(item.state == "failed" ? "Retry download" : "Download again", systemImage: "arrow.clockwise") }
            Button { onSubtitles() } label: {
                Label(item.subtitlePath == nil ? "Add subtitles from Files" : "Replace subtitles", systemImage: "captions.bubble")
            }
            Divider()
            Button(role: .destructive) { onRemove() } label: { Label("Remove", systemImage: "trash") }
        }
    }
}

// MARK: - Download sheet (anime page)

struct NativeDownloadOptions: View {
    let anime: Anime
    let initialEpisode: Int
    @Binding var language: String
    @EnvironmentObject private var downloads: Downloads
    @EnvironmentObject private var catalog: CatalogModel
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var selected = 1
    @State private var message: String?
    @State private var error: String?

    private var limit: Int { anime.episodeLimit(language: language) }
    private var savedEpisodes: Set<Int> {
        Set(downloads.items.filter { $0.animeID == anime.id && $0.state != "failed" }.map(\.episode))
    }
    private var remaining: Int {
        DownloadQueuePolicy.missingEpisodes(Array(1...max(1, limit)), limit: limit, existing: downloads.items, animeID: anime.id).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    languageRow
                    if limit > 0 {
                        episodeGrid
                        actions
                    } else {
                        noEpisodes
                    }
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.cortexMint)
                            .accessibilityIdentifier("download.result")
                    }
                    if let error {
                        Text(error).font(.system(size: 12.5)).foregroundStyle(.orange)
                    }
                    qualityRow
                    finePrint
                }
                .padding(18)
            }
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("download.done")
                }
            }
            .onAppear { selected = min(max(1, initialEpisode), max(1, limit)) }
            .onChange(of: limit) { _, value in selected = min(max(1, selected), max(1, value)) }
        }
        .preferredColorScheme(.dark)
        .tint(Color.cortexPurple)
    }

    private var header: some View {
        HStack(spacing: 13) {
            AnimeArtwork(url: anime.cover)
                .frame(width: 62, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(anime.title).font(.system(size: 16, weight: .bold)).lineLimit(3)
                Text(limit > 0 ? "\(limit) episodes available" : "Episode count not published yet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                Text("\(savedEpisodes.count) already on this device")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(savedEpisodes.isEmpty ? Color.white.opacity(0.45) : Color.cortexMint)
            }
            Spacer(minLength: 0)
        }
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUBTITLES")
                .font(.system(size: 10.5, weight: .black)).tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))
            HStack(spacing: 8) {
                ForEach(["hun", "eng", "fra"], id: \.self) { code in
                    Button { language = code } label: {
                        Text(languageName(code))
                            .font(.system(size: 12.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(language == code ? Color.white : Color.white.opacity(0.6))
                            .background(language == code ? Color.cortexPurple : Color.cortexPanel, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier("download.language")
            Text("Saved with the episode when the source has it; English is used if the chosen language is missing, then video only.")
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "hun": return "Hungarian"
        case "eng": return "English"
        case "fra": return "French"
        default: return code.uppercased()
        }
    }

    private var episodeGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("EPISODES")
                    .font(.system(size: 10.5, weight: .black)).tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))
                Spacer()
                Text("Tap to choose · check = saved")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.32))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 62), spacing: 8)], spacing: 8) {
                ForEach(1...limit, id: \.self) { episode in
                    let saved = savedEpisodes.contains(episode)
                    Button { selected = episode } label: {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected == episode ? Color.cortexPurple : (saved ? Color.cortexPurple.opacity(0.22) : Color.cortexPanel))
                                .frame(height: 42)
                            Text("\(episode)")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if saved {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(Color.cortexMint)
                                    .padding(5)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(selected == episode ? Color.white.opacity(0.35) : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button { add([selected]) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download episode \(selected)")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("download.episode")

            Button { add(Array(1...limit)) } label: {
                VStack(spacing: 2) {
                    Text("Download the whole season")
                        .font(.system(size: 13.5, weight: .bold))
                    Text(remaining == 0 ? "Every episode is already saved" : "\(remaining) new episode\(remaining == 1 ? "" : "s") · saved and queued ones are skipped")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(busy || remaining == 0)
            .accessibilityIdentifier("download.season")

            if busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing the download…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noEpisodes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No released episodes are listed for this title yet.")
                .font(.system(size: 13, weight: .semibold))
            Text("Downloads become available when the catalogue publishes an episode count for the season.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
    }

    private var qualityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "dial.medium")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.cortexPurple)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quality").font(.system(size: 13, weight: .semibold))
                Text(DownloadStudio15.shared.quality.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 6)
            Menu {
                ForEach(DownloadQuality15.allCases) { option in
                    Button(option.title) { DownloadStudio15.shared.quality = option }
                }
            } label: {
                Text(DownloadStudio15.shared.quality.title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.cortexPurple)
            }
        }
        .padding(13)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 13))
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Wi-Fi only · one episode at a time", systemImage: "wifi")
            Label("Progress appears in Downloads and in the Live Activity", systemImage: "waveform.path")
            Label("Season means the episodes on this page; future episodes are not queued", systemImage: "calendar")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.white.opacity(0.38))
    }

    private func add(_ episodes: [Int]) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await catalog.api.json("/api/plus/download/authorize", method: "POST", body: [:])
                downloads.configure(catalog: catalog)
                let count = try downloads.enqueue(anime: anime, episodes: episodes, language: language)
                if count == 0 {
                    message = remaining == 0
                        ? "Every episode in this selection is already saved or queued."
                        : "Nothing could be queued from this selection. Open the anime page and try again."
                } else {
                    message = "\(count) episode\(count == 1 ? "" : "s") added to Downloads."
                }
                error = nil
            } catch {
                if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
