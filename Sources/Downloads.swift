import Foundation
import Combine
import AVFoundation
import UIKit

struct DownloadItem: Codable, Identifiable {
    var id: UUID
    var animeID: Int
    var title: String
    var episode: Int
    var state: String
    var progress: Double
    var relativeLocation: String?
    var subtitlePath: String?
    var note: String?
    var mediaKind: String?
    var subtitleLabel: String?
    // Optional fields preserve indexes written by earlier app builds.
    var subtitleRequired: Bool?
    var language: String?
    var bytesOnDisk: Int64?
    var anime: Anime?
    var imported: Bool?
    var batchID: String?
    var queueRequest: Bool?
    var queuedAt: Date?
    // Auto-retry bookkeeping (transient 5xx/host hiccups). Optional keeps old indexes readable.
    var attempts: Int?
    var retryAt: Date?
    /// Original stream address, so a saved package can be played from the source
    /// when the offline copy cannot be opened.
    var remoteURL: String?
    var statusLabel: String {
        switch state {
        case "downloaded": return (subtitleRequired == false && subtitlePath == nil) ? "Offline ready · no subtitles" : "Offline ready"
        case "queued": return (retryAt?.timeIntervalSinceNow ?? -1) > 0 ? "Waiting to retry" : "Queued"
        case "resolving": return "Checking source"
        case "resuming": return "Resuming transfer"
        case "downloading": return "Downloading"
        case "paused": return "Paused"
        case "verifying": return "Verifying local files"
        default: return "Incomplete"
        }
    }
}

@MainActor final class Downloads: NSObject, ObservableObject {
    static let shared = Downloads()
    @Published private(set) var items: [DownloadItem] = []
    @Published private(set) var storageError: String?
    private let index: OfflineIndex
    private var session: AVAssetDownloadURLSession!
    private var files: URLSession!
    private var preparing = Set<String>()
    private var indexReadable = true
    private var reconciled = false
    #if DEBUG
    var qaReconciled: Bool { reconciled }
    #endif
    private var schedulerRunning = false
    private var lastProgressSave = Date.distantPast
    private let liveStatus = DownloadLiveStatus()
    var sourceResolver: ((Anime,Int,String) async throws -> StreamInfo)?
    func configure(catalog: CatalogModel) {
        sourceResolver = { anime,episode,language in
            _ = try await catalog.api.json("/api/plus/download/authorize",method:"POST",body:[:])
            return try await catalog.resolve(anime,episode:episode,language:language,refresh:true)
        }
        kick()
    }
    var activeCount: Int { items.filter { DownloadQueuePolicy.activeStates.contains($0.state) || $0.state == "queued" }.count }
    var queueRows: [DownloadItem] {
        guard let batch = currentTransfer?.batchID ?? items.last(where:{ $0.batchID != nil })?.batchID else { return [] };return items.filter { $0.batchID == batch }
    }
    var currentTransfer: DownloadItem? { items.first { DownloadQueuePolicy.activeStates.contains($0.state) } ?? items.first { $0.state == "queued" } }
    func enqueue(anime: Anime,episodes: [Int],language: String) throws -> Int {
        guard indexReadable else { throw AppFailure.message(storageError ?? "Offline storage is unavailable.") }
        let selected = DownloadQueuePolicy.missingEpisodes(episodes,limit:anime.episodeLimit(language:language),existing:items,animeID:anime.id)
        guard !selected.isEmpty else { return 0 }
        let batch = UUID().uuidString,previous = items
        // Failed entries may be retried from the queue, without duplicating their old partial files.
        for item in items where item.animeID == anime.id && selected.contains(item.episode) && item.state == "failed" { eraseFiles(item) }
        items.removeAll { $0.animeID == anime.id && selected.contains($0.episode) && $0.state == "failed" }
        let records = selected.map { ep in DownloadItem(id:UUID(),animeID:anime.id,title:anime.title,episode:ep,state:"queued",progress:0,subtitleRequired:true,language:language,anime:anime,batchID:batch,queueRequest:true,queuedAt:Date()) }
        items.append(contentsOf:records)
        guard persist() else { items = previous;throw AppFailure.message(storageError ?? "Could not save the download queue.") }
        kick();return records.count
    }
    func retryQueued(_ item: DownloadItem) throws {
        guard let i = items.firstIndex(where:{ $0.id == item.id }),items[i].state == "failed",items[i].imported != true else { return }
        guard items[i].anime != nil else { throw AppFailure.message("Open this anime's detail page to queue a fresh download.") }
        eraseFiles(items[i]);items[i].relativeLocation = nil;items[i].subtitlePath = nil;items[i].mediaKind = nil
        items[i].state = "queued";items[i].progress = 0;items[i].note = nil;items[i].queueRequest = true;items[i].attempts = nil;items[i].retryAt = nil
        if items[i].batchID == nil { items[i].batchID = UUID().uuidString }
        guard persist() else { throw AppFailure.message(storageError ?? "Could not save the retry.") };kick()
    }
    func kick() {
        liveStatus.refresh(items)
        guard reconciled,indexReadable,!schedulerRunning,!Connectivity.shared.isOffline,sourceResolver != nil,!items.contains(where:{ DownloadQueuePolicy.activeStates.contains($0.state) }) else { finishBackgroundEvents();return }
        schedulerRunning = true
        Task { @MainActor in
            defer { self.schedulerRunning = false;self.finishBackgroundEvents() }
            while !Connectivity.shared.isOffline,!self.items.contains(where:{ DownloadQueuePolicy.activeStates.contains($0.state) }),let next = self.items.first(where:{ $0.state == "queued" && $0.queueRequest == true && ($0.retryAt ?? .distantPast) <= Date() }) {
                // 1.5.1: egy régi indexből visszamaradt, anime nélküli sor eddig megakasztotta
                // a teljes sort (break). Most megjelöljük és továbblépünk a következőre.
                guard let anime = next.anime else {
                    self.updateID(next.id) { $0.state = "failed";$0.note = "Open this anime's detail page to queue a fresh download." }
                    continue
                }
                guard let resolve = self.sourceResolver else { break }
                self.updateID(next.id) { $0.state = "resolving";$0.note = nil }
                do {
                    let info = try await resolve(anime,next.episode,next.language ?? "hun")
                    guard self.items.first(where:{ $0.id == next.id })?.state == "resolving" else { continue }
                    // Subtitle pick degrades gracefully: selected language -> English -> video only.
                    let pick = DownloadQueuePolicy.pickSubtitle(from:info,language:next.language ?? "hun")
                    try await self.start(anime:anime,episode:next.episode,info:info,subtitle:pick,language:next.language ?? "hun",recordID:next.id)
                    return
                } catch {
                    // Szüneteltetés/törlés miatti megszakítás nem hiba, ne írjon rá hibaüzenetet.
                    if !(error is CancellationError) {
                        self.scheduleTransientRetry(next.id,transient:DownloadQueuePolicy.isTransient(error)) { item in
                            if item.state != "paused" { item.state = "failed";item.note = DownloadQueuePolicy.friendly(error) }
                        }
                    }
                    try? await Task.sleep(for:.milliseconds(250))
                }
            }
            self.scheduleWake()
        }
    }
    private var wakeTask: Task<Void, Never>?
    /// Starts the scheduler again when the nearest backoff expires, so a busy host heals itself.
    private func scheduleWake() {
        guard wakeTask == nil else { return }
        let next = items.filter { $0.state == "queued" && $0.queueRequest == true }.compactMap { $0.retryAt }.min()
        guard let next,next.timeIntervalSinceNow > 0 else { return }
        wakeTask = Task { @MainActor in
            try? await Task.sleep(for:.seconds(min(600,max(1,next.timeIntervalSinceNow))))
            self.wakeTask = nil;self.kick()
        }
    }
    /// Transient host errors (5xx, timeouts) retry automatically with backoff instead of failing.
    private func scheduleTransientRetry(_ id: UUID,transient: Bool,fail: (inout DownloadItem)->Void) {
        let attempts = items.first(where:{ $0.id == id })?.attempts ?? 0
        guard transient,attempts < DownloadQueuePolicy.maxAutoRetries else {
            updateID(id) { item in
                fail(&item)
                if item.state == "failed",transient { item.note = (item.note ?? "Incomplete.") + " (Automatic retries ran out.)" }
            }
            return
        }
        let n = attempts+1,delay = DownloadQueuePolicy.retryDelay(attempt:n)
        eraseFiles(items.first(where:{ $0.id == id }) ?? DownloadItem(id:id,animeID:0,title:"",episode:0,state:"failed",progress:0))
        updateID(id) {
            $0.attempts = n;$0.state = "queued";$0.progress = 0;$0.relativeLocation = nil;$0.mediaKind = nil
            $0.retryAt = Date().addingTimeInterval(delay);$0.queueRequest = true
            if $0.batchID == nil { $0.batchID = UUID().uuidString }
            $0.note = "The video host is temporarily busy. Auto-retry \(n)/\(DownloadQueuePolicy.maxAutoRetries) in \(Int(delay))s."
        }
        scheduleWake()
    }
    private func finishBackgroundEvents() {
        guard !schedulerRunning else { return }
        let callbacks = backgroundCompletions.values; backgroundCompletions.removeAll()
        callbacks.forEach { $0() }
    }
    private func eraseFiles(_ item: DownloadItem) {
        // 1.5.2: a saját HLS-csomag egy mappa — az egészet törölni kell, nem csak az indexet.
        try? FileManager.default.removeItem(at:hlsFolder(item.id))
        for relative in [item.relativeLocation,item.subtitlePath] { if let url = OfflineFiles.resolve(relative) { try? FileManager.default.removeItem(at:url) } }
    }
    private func hlsFolder(_ id: UUID) -> URL {
        OfflineFiles.mediaFolder.appendingPathComponent(id.uuidString+".hls",isDirectory:true)
    }
    var backgroundCompletions: [String:() -> Void] = [:]
    static let sessionID = "eu.cortexanime.port.hls-downloads"
    static let fileSessionID = "eu.cortexanime.port.file-downloads"
    var savedBytes: Int64 { items.reduce(0) { $0+($1.bytesOnDisk ?? 0) } }

    override init() {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
        index = OfflineIndex(url:root.appendingPathComponent("downloads.json"))
        super.init()
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try OfflineStorage.ensureFolder(OfflineFiles.mediaFolder)
            items = try index.load()
        } catch { if !(error is CancellationError),!Task.isCancelled { indexReadable = false;storageError = error.localizedDescription } }
        func configuration(_ id:String) -> URLSessionConfiguration {
            let config = URLSessionConfiguration.background(withIdentifier:id)
            config.isDiscretionary = false;config.allowsCellularAccess = false;config.sessionSendsLaunchEvents = true
            return config
        }
        session = AVAssetDownloadURLSession(configuration:configuration(Self.sessionID),assetDownloadDelegate:self,delegateQueue:.main)
        files = URLSession(configuration:configuration(Self.fileSessionID),delegate:self,delegateQueue:.main)
        // Reconcile only the records loaded at startup, not downloads started while callbacks are pending.
        let restoredIDs = Set(items.map(\.id)),directSession = files!
        session.getAllTasks { [weak self] hls in
            directSession.getAllTasks { direct in
                let active = Set((hls+direct).compactMap(\.taskDescription))
                Task { @MainActor in
                    guard let self,self.indexReadable else { return }
                    for i in self.items.indices where restoredIDs.contains(self.items[i].id) {
                        if self.items[i].queueRequest == true,self.items[i].state == "resolving" { self.items[i].state = "queued" }
                        if self.items[i].queueRequest == true,["queued","paused"].contains(self.items[i].state),self.items[i].mediaKind == nil { continue }
                        if self.items[i].state == "resuming",active.contains(self.items[i].id.uuidString) {
                            (hls+direct).filter { $0.taskDescription == self.items[i].id.uuidString }.forEach { $0.resume() };self.items[i].state = "downloading"
                        }
                        if ["queued","resuming","downloading","paused","verifying"].contains(self.items[i].state),!active.contains(self.items[i].id.uuidString) {
                            self.items[i].state = "failed";self.items[i].note = "The download was interrupted. Retry it online or remove it."
                        } else if self.items[i].state == "downloaded",self.localURL(self.items[i]) == nil {
                            self.items[i].state = "failed";self.items[i].note = "The saved video is missing or damaged. Use Download again to repair it."
                        }
                    }
                    self.reconciled = true;_ = self.persist();self.kick()
                }
            }
        }
    }
    @discardableResult private func persist() -> Bool {
        guard indexReadable else { return false }
        do { try index.save(items);storageError = nil;liveStatus.refresh(items);return true }
        catch { if !(error is CancellationError),!Task.isCancelled { storageError = "Offline library could not be saved: "+error.localizedDescription };return false }
    }
    func start(anime: Anime,episode: Int,info: StreamInfo,subtitle: SubtitleTrack?,language: String = "hun",recordID: UUID? = nil) async throws {
        guard indexReadable else { throw AppFailure.message(storageError ?? "Offline storage is unavailable.") }
        let (url,direct) = try await OfflineSource.inspect(info)
        let key = "\(anime.id).\(episode)"
        guard !preparing.contains(key),!items.contains(where:{ $0.animeID == anime.id && $0.episode == episode && $0.state != "failed" && $0.id != recordID }) else { throw AppFailure.message("This episode is already in Downloads.") }
        preparing.insert(key);defer { preparing.remove(key) }
        try OfflineStorage.requireSpace()
        let id = recordID ?? UUID()
        let previous = items.first(where:{ $0.id == id })
        if recordID != nil { guard previous?.state == "resolving" else { throw CancellationError() } }
        var record = DownloadItem(id:id,animeID:anime.id,title:anime.title,episode:episode,state:"queued",progress:0,mediaKind:direct ? "file" : "hls15",subtitleLabel:subtitle?.label,subtitleRequired:subtitle != nil,language:language,anime:anime,batchID:previous?.batchID,queueRequest:previous?.queueRequest,queuedAt:previous?.queuedAt,attempts:previous?.attempts,retryAt:nil)
        record.remoteURL = (try? OfflineSource.candidate(info))?.absoluteString
        if let subtitle, let source = subtitle.url {
            // Subtitles are best effort: a missing or broken track must not block the video download.
            var data = info.preparedCaptions[subtitle.file]
            if data.map(OfflineStorage.captions) != true { data = SubtitleCache.load(source).flatMap { OfflineStorage.captions($0) ? $0 : nil } }
            if data == nil {
                do {
                    var request = URLRequest(url:source);request.timeoutInterval = 15
                    let (bytes,response) = try await URLSession.shared.data(for:request);try APIClient.check(response)
                    if OfflineStorage.captions(bytes) { data = bytes }
                } catch { data = nil }
            }
            if let data,OfflineStorage.captions(data) {
                let destination = OfflineFiles.mediaFolder.appendingPathComponent(id.uuidString+".vtt")
                try data.write(to:destination,options:.atomic);try OfflineStorage.protect(destination)
                record.subtitlePath = OfflineFiles.relative(destination)
            } else {
                record.subtitleRequired = false;record.subtitleLabel = nil
            }
        }
        if recordID != nil,items.first(where:{ $0.id == id })?.state != "resolving" {
            eraseFiles(record);throw CancellationError()
        }
        // 1.5.2: az AVAssetDownloadTask helyett saját szegmens-letöltő. Az AVFoundation
        // csak akkor ismeri fel a HLS-t, ha a URL .m3u8-ra végződik; a CortexAnime
        // streamjei /api/hls-proxy?tk=… címen jönnek, ezért az AVAssetDownloadTask
        // minden epizódnál elhasalt, mielőtt egy bájt is átjött volna.
        if !direct {
            record.state = "downloading";record.mediaKind = "hls15"
            if let i = items.firstIndex(where:{ $0.id == id }) { items[i] = record } else { items.insert(record,at:0) }
            guard persist() else {
                items.removeAll { $0.id == id };if let previous { items.append(previous) }
                if let saved = OfflineFiles.resolve(record.subtitlePath) { try? FileManager.default.removeItem(at:saved) }
                throw AppFailure.message(storageError ?? "The offline library could not be saved.")
            }
            try await runHLSDownload(id:id,info:info,record:record)
            return
        }
        let task = files.downloadTask(with:url)
        task.taskDescription = id.uuidString;record.state = "downloading"
        if let i = items.firstIndex(where:{ $0.id == id }) { items[i] = record } else { items.insert(record,at:0) }
        guard persist() else {
            task.cancel();items.removeAll { $0.id == id };if let previous { items.append(previous) }
            if let saved = OfflineFiles.resolve(record.subtitlePath) { try? FileManager.default.removeItem(at:saved) }
            throw AppFailure.message(storageError ?? "The offline library could not be saved.")
        }
        task.resume()
    }

    /// 1.5.2: a saját HLS-letöltő futtatása. A szegmensek a saját mappájukba kerülnek,
    /// a kész playlist relatív fájlnevekkel hivatkozik rájuk, így az AVPlayer helyi
    /// m3u8-ként játssza le őket. Hideg indítás után a kész szegmenseket kihagyja.
    private func runHLSDownload(id: UUID,info: StreamInfo,record: DownloadItem) async throws {
        let folder = OfflineFiles.mediaFolder.appendingPathComponent(id.uuidString+".hls",isDirectory:true)
        do {
            let index = try await HLS15Engine.shared.download(id:id,info:info,quality:DownloadQuality15.current,folder:folder) { fraction in
                self.updateID(id) { item in
                    guard item.state == "downloading" else { return }
                    item.progress = min(1,max(0,fraction))
                }
            }
            guard self.items.contains(where:{ $0.id == id }) else {
                try? FileManager.default.removeItem(at:folder)
                throw CancellationError()
            }
            guard self.items.first(where:{ $0.id == id })?.state == "downloading" else { throw CancellationError() }
            let captionsSaved = (record.subtitleRequired != true && record.subtitlePath == nil) || self.subtitleURL(record) != nil
            guard HLS15Engine.verify(folder:folder),captionsSaved else {
                self.updateID(id) { $0.state = "failed";$0.note = "The saved package did not pass the offline check. Download it again." }
                throw CancellationError()
            }
            let bytes = OfflineStorage.bytes(at:folder),relative = OfflineFiles.relative(index)
            self.updateID(id) {
                $0.relativeLocation = relative;$0.bytesOnDisk = bytes
                $0.state = "downloaded";$0.progress = 1;$0.note = nil
            }
        } catch is CancellationError {
            self.updateID(id) { item in
                if item.state == "downloading" { item.state = "queued";item.queueRequest = true }
            }
            throw CancellationError()
        } catch {
            self.updateID(id) { item in
                if item.state != "paused" { item.state = "failed";item.note = DownloadQueuePolicy.friendly(error) }
            }
            throw error
        }
        // A sor a következő várakozó epizóddal folytatódik.
        Task { @MainActor in self.kick() }
    }
    func localURL(_ item: DownloadItem) -> URL? {
        guard item.state == "downloaded" else { return nil }
        // 1.5.2: a saját HLS-csomag akkor indul, ha a playlist ÉS minden szegmens megvan.
        if item.mediaKind == "hls15" {
            guard let index = OfflineFiles.resolve(item.relativeLocation),
                  HLS15Engine.verify(folder:index.deletingLastPathComponent()) else { return nil }
            return index
        }
        guard let url = OfflineFiles.resolve(item.relativeLocation) else { return nil }
        // 6.0: an episode whose subtitles are required is not "offline ready" while the
        // caption file is missing — otherwise it would play silently instead of asking
        // the viewer to repair the download.
        if item.subtitleRequired == true,subtitleURL(item) == nil { return nil }
        if item.mediaKind == "file" || ["mp4","m4v","mov"].contains(url.pathExtension.lowercased()) {
            return OfflineStorage.bytes(at:url) > 0 ? url : nil
        }
        if OfflineStorage.localMediaReady(url) { return url }
        return AVURLAsset(url:url).assetCache?.isPlayableOffline == true ? url : nil
    }
    func subtitleURL(_ item: DownloadItem) -> URL? {
        guard let url = OfflineFiles.resolve(item.subtitlePath),let size = try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 2_000_000,let data = try? Data(contentsOf:url),OfflineStorage.captions(data) else { return nil };return url
    }
    func route(for item: DownloadItem) throws -> PlaybackRoute {
        guard let local = localURL(item) else { throw AppFailure.message("This episode is not fully available offline. In Downloads, use Download again to repair it.") }
        var route = PlaybackRoute(title:item.title,url:local,key:"\(item.animeID).\(item.episode)",subtitleURL:subtitleURL(item),episodeLabel:"Episode \(item.episode) · Offline")
        route.anime = item.anime;route.episode = item.episode;route.language = item.language ?? "hun"
        route.remoteFallback = item.remoteURL.flatMap { OfflineSource.secure($0) }
        if (item.subtitleRequired == true || item.subtitlePath != nil),subtitleURL(item) == nil {
            route.subtitleMessage = "The saved subtitles are missing for this offline episode."
        }
        return route
    }
    /// Re-queues a record whose saved files disappeared, without leaving the stale index entry.
    func repair(_ item: DownloadItem) throws {
        guard let i = items.firstIndex(where:{ $0.id == item.id }) else { return }
        guard items[i].anime != nil else { throw AppFailure.message("Open this anime's detail page to download the episode again.") }
        eraseFiles(items[i])
        items[i].relativeLocation = nil;items[i].subtitlePath = nil;items[i].mediaKind = nil
        items[i].state = "queued";items[i].progress = 0;items[i].note = nil;items[i].queueRequest = true
        items[i].attempts = nil;items[i].retryAt = nil
        if items[i].batchID == nil { items[i].batchID = UUID().uuidString }
        guard persist() else { throw AppFailure.message(storageError ?? "Could not save the repair queue entry.") }
        kick()
    }
    func pause(_ item: DownloadItem) {
        if ["queued","resolving"].contains(item.state),item.queueRequest == true { updateID(item.id) { $0.state = "paused" };kick();return }
        // 1.5.2: a saját HLS-letöltés jelzővel áll le; a kész szegmensek a lemezen maradnak.
        if item.mediaKind == "hls15",item.state == "downloading" {
            HLS15Engine.shared.cancel(item.id)
            updateID(item.id) { $0.state = "paused";$0.note = nil }
            return
        }
        guard item.state == "downloading" || item.state == "queued" else { return }
        updateID(item.id) { if ["queued","downloading"].contains($0.state) { $0.state = "paused" } }
        for candidate in [session as URLSession,files!] { candidate.getAllTasks { tasks in
            Task { @MainActor in
                guard self.items.first(where:{ $0.id == item.id })?.state == "paused" else { return }
                tasks.filter { $0.taskDescription == item.id.uuidString }.forEach { $0.suspend() }
            }
        } }
    }
    func resume(_ item: DownloadItem) {
        guard item.state == "paused" else { return }
        if item.mediaKind == "hls15" || (item.mediaKind == nil && item.queueRequest == true) {
            updateID(item.id) { $0.state = "queued";$0.queueRequest = true;$0.note = nil }
            kick();return
        }
        if item.queueRequest == true,item.mediaKind == nil { updateID(item.id) { $0.state = "queued" };kick();return }
        guard !items.contains(where:{ $0.id != item.id && DownloadQueuePolicy.activeStates.contains($0.state) }) else {
            updateID(item.id) { $0.note = "Pause the current transfer before resuming this episode." };return
        }
        updateID(item.id) { $0.state = "resuming";$0.note = nil }
        let directSession = files!
        session.getAllTasks { hls in directSession.getAllTasks { direct in
            let matches = (hls+direct).filter { $0.taskDescription == item.id.uuidString }
            Task { @MainActor in
                guard self.items.first(where:{ $0.id == item.id })?.state == "resuming" else { return }
                guard !matches.isEmpty else { self.updateID(item.id) { $0.state = "failed";$0.note = "The suspended transfer is no longer available. Retry it online." };self.kick();return }
                self.updateID(item.id) { $0.state = "downloading" };matches.forEach { $0.resume() }
            }
        } }
    }
    func importVideo(_ source: URL) async throws {
        guard indexReadable else { throw AppFailure.message(storageError ?? "Offline storage is unavailable.") }
        let scoped = source.startAccessingSecurityScopedResource();defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let ext = source.pathExtension.lowercased()
        guard ["mp4","m4v","mov"].contains(ext) else { throw AppFailure.message("Choose an MP4, M4V or MOV video compatible with the native player.") }
        let size = OfflineStorage.bytes(at:source);guard size > 0 else { throw AppFailure.message("The selected video is empty.") };try OfflineStorage.requireSpace(size)
        let id = UUID(),destination = OfflineFiles.mediaFolder.appendingPathComponent(UUID().uuidString+"."+ext)
        // FileManager streams the copy; the entire episode is never read into RAM.
        try await Task.detached(priority:.userInitiated) { try FileManager.default.copyItem(at:source,to:destination) }.value
        do {
            try OfflineStorage.protect(destination)
            guard (try? await AVURLAsset(url:destination).load(.isPlayable)) == true else { throw AppFailure.message("This video's codec is not supported by the native player.") }
            let title = source.deletingPathExtension().lastPathComponent
            let item = DownloadItem(id:id,animeID:Int.random(in:1_000_000_000...2_000_000_000),title:title,episode:1,state:"downloaded",progress:1,relativeLocation:OfflineFiles.relative(destination),mediaKind:"file",subtitleRequired:false,language:"und",bytesOnDisk:size,imported:true)
            items.insert(item,at:0)
            guard persist() else { items.removeAll { $0.id == id };throw AppFailure.message(storageError ?? "Could not save the imported episode.") }
        } catch { try? FileManager.default.removeItem(at:destination);throw error }
    }
    func importSubtitles(_ source: URL,for item: DownloadItem) throws {
        let scoped = source.startAccessingSecurityScopedResource();defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let size = try? source.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 2_000_000 else { throw AppFailure.message("Choose a subtitle file smaller than 2 MB.") }
        let data = try Data(contentsOf:source)
        guard OfflineStorage.captions(data) else { throw AppFailure.message("This file contains no valid VTT or SRT dialogue.") }
        let destination = OfflineFiles.mediaFolder.appendingPathComponent(item.id.uuidString+".vtt")
        try data.write(to:destination,options:.atomic);try OfflineStorage.protect(destination)
        updateID(item.id) { $0.subtitlePath = OfflineFiles.relative(destination);$0.subtitleRequired = true;$0.subtitleLabel = "Imported subtitles" }
    }
    func remove(_ item: DownloadItem) {
        for candidate in [session as URLSession,files!] { candidate.getAllTasks { tasks in tasks.filter { $0.taskDescription == item.id.uuidString }.forEach { $0.cancel() } } }
        let current = items.first(where:{ $0.id == item.id }) ?? item
        HLS15Engine.shared.cancel(item.id)
        try? FileManager.default.removeItem(at:hlsFolder(item.id))
        for relative in [current.relativeLocation,current.subtitlePath] { if let url = OfflineFiles.resolve(relative) { try? FileManager.default.removeItem(at:url) } }
        items.removeAll { $0.id == item.id };_ = persist();kick()
    }
    private func updateID(_ id: UUID,action:(inout DownloadItem)->Void) {
        guard let i = items.firstIndex(where:{ $0.id == id }) else { return }
        let oldState = items[i].state;action(&items[i])
        if oldState != items[i].state || Date().timeIntervalSince(lastProgressSave) >= 1 || items[i].progress >= 1 {
            lastProgressSave = Date();_ = persist()
        } else { liveStatus.refresh(items) }
    }
    private func update(_ task: URLSessionTask,action:(inout DownloadItem)->Void) {
        guard let raw = task.taskDescription,let id = UUID(uuidString:raw) else { return };updateID(id,action:action)
    }
    private func completed(_ task: URLSessionTask,error: String?,transient: Bool = false) async {
        defer { kick() }
        if let error {
            if transient,let raw = task.taskDescription,let id = UUID(uuidString:raw) {
                scheduleTransientRetry(id,transient:true) { item in
                    item.state = "failed";item.note = error
                }
                return
            }
            update(task) { $0.state = "failed";$0.note = error };return
        }
        for _ in 0..<40 {
            if items.first(where:{ $0.id.uuidString == task.taskDescription })?.relativeLocation != nil { break }
            try? await Task.sleep(for:.milliseconds(50))
        }
        guard let item = items.first(where:{ $0.id.uuidString == task.taskDescription }) else { return }
        guard let url = OfflineFiles.resolve(item.relativeLocation) else { update(task) { $0.state = "failed";$0.note = $0.note ?? "The offline package was not saved." };return }
        update(task) { $0.state = "verifying" }
        let asset = AVURLAsset(url:url)
        let playable = (try? await asset.load(.isPlayable)) == true || OfflineStorage.localMediaReady(url)
        let offline = item.mediaKind == "file" || OfflineStorage.localMediaReady(url) || asset.assetCache?.isPlayableOffline == true
        let captionsSaved = (item.subtitleRequired != true && item.subtitlePath == nil) || subtitleURL(item) != nil
        let bytes = OfflineStorage.bytes(at:url)+(subtitleURL(item).map { OfflineStorage.bytes(at:$0) } ?? 0)
        update(task) {
            $0.bytesOnDisk = bytes
            if playable && offline && captionsSaved { $0.state = "downloaded";$0.progress = 1;$0.note = nil }
            else { $0.state = "failed";$0.note = "The video or selected subtitles did not pass the offline check." }
        }
    }
}

extension Downloads: AVAssetDownloadDelegate, URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession,assetDownloadTask: AVAssetDownloadTask,didFinishDownloadingTo location: URL) {
        let policy = AVMutableAssetDownloadStorageManagementPolicy();policy.priority = .important;policy.expirationDate = .distantFuture
        AVAssetDownloadStorageManager.shared().setStorageManagementPolicy(policy,for:location)
        // A csomagot a saját OfflineMedia mappánkba mozgatjuk (mint a közvetlen fájloknál),
        // so the relative/resolve pair always finds it — this was the earlier "package not saved" bug.
        var saved = location
        do {
            try OfflineStorage.ensureFolder(OfflineFiles.mediaFolder)
            let name = assetDownloadTask.taskDescription ?? UUID().uuidString
            let destination = OfflineFiles.mediaFolder.appendingPathComponent(name+".movpkg")
            try? FileManager.default.removeItem(at:destination)
            try FileManager.default.moveItem(at:location,to:destination)
            saved = destination
        } catch {}
        try? OfflineStorage.protect(saved)
        let relative = OfflineFiles.relative(saved)
        Task { @MainActor in guard self.items.contains(where:{ $0.id.uuidString == assetDownloadTask.taskDescription }) else { try? FileManager.default.removeItem(at:saved);return }
            self.update(assetDownloadTask) { $0.relativeLocation = relative } }
    }
    nonisolated func urlSession(_ session: URLSession,downloadTask: URLSessionDownloadTask,didFinishDownloadingTo location: URL) {
        guard let raw = downloadTask.taskDescription,let id = UUID(uuidString:raw) else { return }
        do {
            if let response = downloadTask.response as? HTTPURLResponse,!(200..<300).contains(response.statusCode) { throw AppFailure.message("The download server returned HTTP \(response.statusCode). Retry online for a fresh source.") }
            try OfflineStorage.ensureFolder(OfflineFiles.mediaFolder)
            let destination = OfflineFiles.mediaFolder.appendingPathComponent(id.uuidString+".mp4")
            try FileManager.default.moveItem(at:location,to:destination);try OfflineStorage.protect(destination)
            let relative = OfflineFiles.relative(destination)
            Task { @MainActor in
                guard self.items.contains(where:{ $0.id == id }) else { try? FileManager.default.removeItem(at:destination);return }
                self.update(downloadTask) { $0.relativeLocation = relative }
            }
        } catch {
            if !(error is CancellationError),!Task.isCancelled {
                let message = error.localizedDescription
                Task { @MainActor in self.update(downloadTask) { $0.state = "failed";$0.note = message } }
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession,downloadTask: URLSessionDownloadTask,didWriteData bytesWritten: Int64,totalBytesWritten: Int64,totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? min(1,max(0,Double(totalBytesWritten)/Double(totalBytesExpectedToWrite))) : 0
        Task { @MainActor in self.update(downloadTask) { if ["queued","downloading"].contains($0.state) { $0.progress = progress;$0.state = "downloading" } } }
    }
    nonisolated func urlSession(_ session: URLSession,assetDownloadTask: AVAssetDownloadTask,didLoad timeRange: CMTimeRange,totalTimeRangesLoaded loaded: [NSValue],timeRangeExpectedToLoad expected: CMTimeRange) {
        let duration = CMTimeGetSeconds(expected.duration),seconds = loaded.reduce(0.0) { $0+CMTimeGetSeconds($1.timeRangeValue.duration) }
        let progress = duration > 0 && duration.isFinite ? min(1,max(0,seconds/duration)) : 0
        Task { @MainActor in self.update(assetDownloadTask) { if ["queued","downloading"].contains($0.state) { $0.progress = progress;$0.state = "downloading" } } }
    }
    nonisolated func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: Error?) {
        let message = error.map { DownloadQueuePolicy.friendly($0) }
        let transient = error.map { DownloadQueuePolicy.isTransient($0) } ?? false
        Task { @MainActor in await self.completed(task,error:message,transient:transient) }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let id = session.configuration.identifier else { return }
        Task { @MainActor in _ = id;self.kick() }
    }
}

@MainActor final class AnimeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,handleEventsForBackgroundURLSession identifier: String,completionHandler: @escaping () -> Void) {
        guard [Downloads.sessionID,Downloads.fileSessionID].contains(identifier) else { completionHandler();return }
        Downloads.shared.backgroundCompletions[identifier] = completionHandler
    }
}
