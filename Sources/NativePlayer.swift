import SwiftUI
import AVKit

struct Cue {
    let start: Double
    let end: Double
    let text: String
}
enum WebVTT {
    static func time(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        let p = parts.compactMap { Double($0) }
        guard p.count == parts.count, p.count == 2 || p.count == 3, p.allSatisfy({ $0.isFinite && $0 >= 0 }),
              p.last! < 60, p[p.count - 2] < 60 else { return nil }
        return p.count == 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1]
    }
    static func parse(_ text: String) -> [Cue] {
        text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n").compactMap { block in
                let lines = block.components(separatedBy: "\n")
                if let first = lines.first, first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") { return nil }
                guard let i = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
                let range = lines[i].components(separatedBy: "-->")
                guard range.count == 2, let start = time(range[0]), let end = time(String(range[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "")), end > start else { return nil }
                var content = lines.dropFirst(i + 1).joined(separator: "\n").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                for (encoded, decoded) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] { content = content.replacingOccurrences(of: encoded, with: decoded) }
                let flattened = content.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                // Some upstreams mislabel storyboard WebVTT as English subtitles.
                guard !flattened.isEmpty, flattened.range(of: "#xywh=|(?:thumbnails?|sprites?)/|^\\S+\\.(?:webp|jpe?g|png|avif)(?:[?#].*)?$", options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
                return Cue(start: start, end: end, text: content)
            }.sorted { $0.start < $1.start }
    }
}
struct CueTimeline {
    private let cues: [Cue]
    private let maximumEnd: [Double]
    init(_ cues: [Cue]) {
        self.cues = cues.sorted { $0.start < $1.start }
        var end = 0.0
        maximumEnd = self.cues.map { end = max(end, $0.end); return end }
    }
    func text(at time: Double) -> String {
        guard time.isFinite else { return "" }
        var low = 0, high = cues.count
        while low < high { let middle = (low + high) / 2; if cues[middle].start <= time { low = middle + 1 } else { high = middle } }
        var index = low - 1, active: [String] = []
        while index >= 0 && maximumEnd[index] > time {
            if cues[index].end > time { active.append(cues[index].text) }
            index -= 1
        }
        return active.reversed().joined(separator: "\n")
    }
}
enum PlaybackPolicy {
    static func resumePosition(saved: Double, duration: Double) -> Double? {
        guard saved.isFinite, duration.isFinite, saved >= 3, duration > 0, saved < duration - 15 else { return nil }
        return saved
    }
}
enum PlaybackPhase: String, Equatable { case loading, buffering, playing, paused, ended, failed }
struct PlaybackRoute: Identifiable {
    let id = UUID()
    let title: String
    var url: URL
    let key: String
    let subtitleURL: URL?
    /// Remote source of a downloaded episode. Used only when the saved package
    /// cannot be started, so a broken offline copy is not a dead end.
    var remoteFallback: URL? = nil
    var anime: Anime? = nil
    var episode: Int = 1
    var language: String = "hun"
    var episodeLabel: String = ""
    var subtitleMessage: String? = nil
    var info: StreamInfo? = nil
    var reload: (@MainActor () async throws -> PlaybackRoute)? = nil
    var next: (@MainActor () async throws -> PlaybackRoute)? = nil
}

@MainActor final class Playback: ObservableObject {
    let player = AVPlayer()
    @Published var route: PlaybackRoute
    @Published var phase: PlaybackPhase = .loading
    @Published var subtitle = ""
    @Published var error: String?
    @Published var subtitleNotice: String?
    @Published var savedCaptionURL: URL?
    @Published var selectedCaption: String?
    @Published private(set) var captionCueCount = 0
    @Published var position = 0.0
    @Published var duration = 0.0
    /// Subtitle timing offset in seconds. Positive shows captions later.
    @Published private(set) var subtitleDelay = UserDefaults.standard.double(forKey: "player.subtitleDelay")
    private var timeline = CueTimeline([])
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var controlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var sleepTask: Task<Void, Never>?
    @Published var sleepDeadline: Date?
    private var timeout: Task<Void, Never>?
    private var captionTask: Task<Void, Never>?
    private var generation = UUID()
    private var captionGeneration = UUID()
    private var lastSaved = -1
    private var resumePending = true
    /// Absolute position already handed to the credit store (so only deltas are counted).
    private var accountedPosition = 0.0
    private var readyHandled = false
    private var autoRetries = 0
    private var recoveryAnchor = -1.0
    /// A broken offline package may hand the episode to the remote source once.
    private var usedRemoteFallback = false
    init(route: PlaybackRoute) { self.route = route; player.automaticallyWaitsToMinimizeStalling = true }
    var isWaiting: Bool { phase == .loading || phase == .buffering }
    var introEnd: Double? {
        guard let intro = route.info?.skip?.intro, intro.valid, position >= intro.start, position < intro.end,
              duration > 0, intro.end < duration else { return nil }
        return intro.end
    }
    var outroStart: Double? {
        guard let outro = route.info?.skip?.outro, outro.valid, position >= outro.start, position < outro.end,
              duration > 0, outro.end <= duration else { return nil }
        return outro.end
    }
    func start() {
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try AVAudioSession.sharedInstance().setActive(true) }
        catch { if !(error is CancellationError),!Task.isCancelled { subtitleNotice = "Audio session configuration failed. \(error.localizedDescription)" } }
        open(route)
    }
    func open(_ nextRoute: PlaybackRoute) {
        savePosition(); clearItemObservers()
        if nextRoute.key != route.key { autoRetries = 0; recoveryAnchor = -1 }
        if !nextRoute.url.isFileURL { usedRemoteFallback = false }
        generation = UUID(); let token = generation
        player.pause(); route = nextRoute; phase = .loading; error = nil; subtitleNotice = nextRoute.subtitleMessage
        position = 0; duration = 0; lastSaved = -1; resumePending = true; readyHandled = false; accountedPosition = 0
        timeline = CueTimeline([]); captionCueCount = 0;subtitle = ""; savedCaptionURL = nil; selectedCaption = nextRoute.subtitleURL?.absoluteString
        if nextRoute.url.isFileURL {
            let fm = FileManager.default
            let canonical = nextRoute.url.standardizedFileURL.resolvingSymlinksInPath().path
            if !fm.fileExists(atPath: canonical),!fm.fileExists(atPath: nextRoute.url.path) {
                fail("The offline package is missing. Remove it and download again."); return
            }
        }
        let item = AVPlayerItem(url: nextRoute.url)
        player.replaceCurrentItem(with: item)
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if item.status == .failed {
                    if nextRoute.url.isFileURL, !self.usedRemoteFallback, let remote = nextRoute.remoteFallback {
                        // A saved HLS package can become unreadable after the system clears it.
                        // Retry the same episode from its original source instead of failing.
                        self.usedRemoteFallback = true
                        var replacement = nextRoute
                        replacement.url = remote
                        replacement.subtitleMessage = "The saved offline copy could not be started, so CortexPlayer switched to the online source. Delete the download and save it again to repair it."
                        self.open(replacement)
                        return
                    }
                    self.fail(nextRoute.url.isFileURL
                              ? "The saved offline copy could not be started. Remove this download and download the episode again."
                              : "This episode could not be played. Its source may have expired or may not support native iOS playback.",
                              transient: !nextRoute.url.isFileURL)
                }
                if item.status == .readyToPlay && !self.readyHandled {
                    self.readyHandled = true
                    let loaded = (try? await item.asset.load(.duration))?.seconds ?? item.duration.seconds
                    guard self.generation == token else { return }
                    self.duration = loaded.isFinite && loaded > 0 ? loaded : 0
                    let saved = UserDefaults.standard.double(forKey: "resume." + self.route.key)
                    if let resume = PlaybackPolicy.resumePosition(saved: saved, duration: self.duration) {
                        let finished = await self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        guard self.generation == token else { return }
                        if !finished { self.fail("The saved position could not be restored. Try restarting the episode.", transient: true); return }
                    }
                    self.resumePending = false; self.phase = .buffering; self.player.play(); self.armTimeout()
                }
            }
        }
        controlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, self.generation == token, !self.resumePending, self.phase != .failed, self.phase != .ended else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.phase = .playing; self.timeout?.cancel()
                    let wanted = Float(PlaybackPrefs8.rate)
                    if wanted > 0, abs(self.player.rate - wanted) > 0.01 { self.player.rate = wanted }
                case .waitingToPlayAtSpecifiedRate: self.phase = .buffering; self.armTimeout()
                case .paused: self.phase = .paused; self.timeout?.cancel(); self.savePosition()
                @unknown default: break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.phase = .ended; self.timeout?.cancel(); self.subtitle = ""
                UserDefaults.standard.removeObject(forKey: "resume." + self.route.key)
                self.recordHistory(completed: true)
                // The player screen owns what happens next: its countdown can be
                // cancelled, and the inactivity guard must be able to step in
                // before another episode starts. Advancing here would bypass both.
            }
        }
        failedObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self, self.generation == token else { return }; self.fail("Playback was interrupted. Retry to request a fresh episode source.", transient: true) }
        }
        if observer == nil {
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                Task { @MainActor in
                    guard let self, !self.resumePending, self.phase != .failed, self.phase != .ended, time.seconds.isFinite else { return }
                    self.position = max(0, time.seconds)
                    if self.recoveryAnchor >= 0, abs(self.position - self.recoveryAnchor) >= 12 { self.autoRetries = 0; self.recoveryAnchor = -1 }
                    let length = self.player.currentItem?.duration.seconds ?? 0
                    if length.isFinite && length > 0 { self.duration = length }
                    self.subtitle = self.selectedCaption == nil ? "" : self.timeline.text(at: self.position - self.subtitleDelay)
                    if Int(self.position) / 10 != self.lastSaved { self.lastSaved = Int(self.position) / 10; self.savePosition() }
                }
            }
        }
        armTimeout()
        if let url = nextRoute.subtitleURL { captionTask = Task { await captions(from: url) } }
    }
    private func armTimeout() {
        timeout?.cancel(); let token = generation
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)); try Task.checkCancellation() } catch { return }
            guard let self, self.generation == token, self.isWaiting else { return }
            self.fail("The episode took too long to load. Check your connection or retry for a fresh source.", transient: true)
        }
    }
    private func fail(_ message: String, transient: Bool = false) {
        savePosition(); generation = UUID(); player.pause(); player.currentItem?.asset.cancelLoading()
        timeout?.cancel(); captionTask?.cancel(); subtitle = ""
        if transient, autoRetries < 3 {
            autoRetries += 1; recoveryAnchor = position
            phase = .loading; error = nil
            let token = generation
            Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(1400)); try Task.checkCancellation() } catch { return }
                guard let self, self.generation == token, self.phase == .loading, self.error == nil else { return }
                await self.retry(manual: false)
            }
            return
        }
        phase = .failed; error = message
    }
    func retry(manual: Bool = true) async {
        if manual { autoRetries = 0 }
        generation = UUID(); let token = generation
        player.pause(); phase = .loading; error = nil; armTimeout()
        do {
            let fresh = try await route.reload?() ?? route
            guard generation == token, !Task.isCancelled else { return }
            open(fresh)
        } catch { if generation == token && !Task.isCancelled { fail(error.localizedDescription) } }
    }
    func nextEpisode() async {
        guard let next = route.next, !isWaiting else { return }
        generation = UUID(); let token = generation; phase = .loading; error = nil; armTimeout()
        do { let fresh = try await next(); guard token == generation, !Task.isCancelled else { return }; open(fresh) }
        catch { if token == generation && !Task.isCancelled { fail(error.localizedDescription) } }
    }
    func restart() {
        guard !isWaiting, phase != .failed else { return }
        autoRetries = 0; recoveryAnchor = -1
        UserDefaults.standard.removeObject(forKey: "resume." + route.key)
        let token = generation
        resumePending = true; phase = .buffering; subtitle = ""; player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                guard finished else { self.fail("The episode could not be restarted. Retry the source."); return }
                self.position = 0; self.lastSaved = -1; self.resumePending = false; self.player.play(); self.armTimeout()
            }
        }
        armTimeout()
    }
    func seek(_ value: Double) {
        guard value.isFinite, value >= 0, phase != .failed else { return }
        let target = duration > 0 ? min(value,duration) : value
        player.seek(to:CMTime(seconds:target,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero)
        position = target
    }
    func skipIntro() { if let end = introEnd { player.seek(to: CMTime(seconds: end, preferredTimescale: 600)) } }
    func skipOutro() { if let end = outroStart { player.seek(to: CMTime(seconds: end, preferredTimescale: 600)) } }
    func selectCaption(_ url: URL?) {
        captionTask?.cancel(); captionGeneration = UUID(); timeline = CueTimeline([]);captionCueCount = 0; subtitle = ""; subtitleNotice = nil; savedCaptionURL = nil
        selectedCaption = url?.absoluteString
        if let url { captionTask = Task { await captions(from: url) } }
    }
    func retryCaptions() {
        guard let reload = route.reload else { selectCaption(selectedCaption.flatMap(URL.init(string:)) ?? route.subtitleURL);return }
        captionTask?.cancel();captionGeneration = UUID()
        let token = generation,captionToken = captionGeneration
        subtitleNotice = "Loading subtitles…"
        captionTask = Task {
            do {
                let fresh = try await reload();try Task.checkCancellation()
                guard token == generation,captionToken == captionGeneration else { return }
                route.info = fresh.info
                guard let url = fresh.subtitleURL else { subtitleNotice = "Selected subtitles unavailable for this episode.";return }
                selectedCaption = url.absoluteString
                await captions(from:url)
            } catch {
                if token == generation,captionToken == captionGeneration,!Task.isCancelled { subtitleNotice = "Subtitles could not be refreshed. Try again when connected." }
            }
        }
    }
    private func captions(from url: URL) async {
        let token = generation,captionToken = captionGeneration,deadline = Date().addingTimeInterval(30)
        subtitleNotice = "Loading subtitles…"
        let requested = route.info?.tracks?.first { $0.url == url }
        var candidates = [url]
        if let requested {
            let alternatives = (route.info?.tracks ?? []).filter { track in
                if let language = CaptionPolicy.language(requested) { return CaptionPolicy.matches(track,language:language) }
                return track.label == requested.label
            }.compactMap(\.url).filter { $0 != url }
            candidates.append(contentsOf:alternatives.prefix(7))
        }
        for source in candidates {
            do {
                try Task.checkCancellation()
                let data: Data
                var usedSavedCaption = false
                let raw = route.info?.tracks?.first(where:{ $0.url == source })?.file ?? source.absoluteString
                if source.isFileURL { data = try Data(contentsOf:source) }
                else if let prepared = route.info?.preparedCaptions[raw] { data = prepared }
                else if let saved = SubtitleCache.load(source) { data = saved;usedSavedCaption = true }
                else {
                    guard source.scheme == "https",source.host != nil,deadline.timeIntervalSinceNow > 0 else { continue }
                    var request = URLRequest(url:source);request.timeoutInterval = min(15,max(1,deadline.timeIntervalSinceNow));request.cachePolicy = .reloadIgnoringLocalCacheData
                    let (bytes,response) = try await URLSession.shared.data(for:request);try APIClient.check(response);data = bytes
                }
                try Task.checkCancellation()
                guard token == generation,captionToken == captionGeneration else { return }
                guard data.count <= 2_000_000,let text = String(data:data,encoding:.utf8) else { continue }
                let cues = WebVTT.parse(text);guard !cues.isEmpty else { continue }
                timeline = CueTimeline(cues);captionCueCount = cues.count;selectedCaption = source.absoluteString
                savedCaptionURL = source.isFileURL ? source : (try? SubtitleCache.save(data,source:source))
                subtitleNotice = usedSavedCaption ? "Using saved subtitles." : nil
                subtitle = timeline.text(at:position)
                return
            } catch { if Task.isCancelled { return } }
        }
        if token == generation,captionToken == captionGeneration,!Task.isCancelled { subtitleNotice = "Subtitles could not be loaded. Use Retry subtitles in player options." }
    }
    private func savePosition() {
        guard !resumePending, position.isFinite, position >= 3, [.playing, .paused, .buffering].contains(phase) else { return }
        if phase == .ended { UserDefaults.standard.removeObject(forKey: "resume." + route.key); recordHistory(completed: true); return }
        UserDefaults.standard.set(position, forKey: "resume." + route.key)
        recordHistory()
    }
    private func recordHistory(completed: Bool = false) {
        if let anime = route.anime {
            AnimeLibrary.shared.record(anime: anime, episode: route.episode, language: route.language, seconds: position, duration: duration, completed: completed)
            // Watch time must be the INCREMENT since the last save. Passing the absolute
            // position every ten seconds inflated every watch-time statistic in the app.
            let delta = max(0, position - accountedPosition)
            accountedPosition = max(accountedPosition, position)
            CreditStore.shared.noteWatch(animeID: anime.id, animeTitle: anime.title, episode: route.episode,
                                         completed: completed, seconds: delta, duration: duration)
        }
    }
    /// Shifts subtitle timing by `delta` seconds (clamped to ±5 s) and reapplies it at once.
    func adjustSubtitleDelay(by delta: Double) {
        setSubtitleDelay(subtitleDelay + delta)
    }

    func setSubtitleDelay(_ value: Double) {
        let clamped = min(5, max(-5, (value * 20).rounded() / 20))
        subtitleDelay = clamped
        UserDefaults.standard.set(clamped, forKey: "player.subtitleDelay")
        // Repaint immediately instead of waiting for the next tick.
        subtitle = selectedCaption == nil ? "" : timeline.text(at: position - clamped)
    }

    func setSleepTimer(minutes: Int?) {
        setSleepTimer(seconds: minutes.map { Double($0) * 60 })
    }
    func setSleepTimer(seconds: Double?) {
        sleepTask?.cancel(); sleepDeadline = seconds.map { Date().addingTimeInterval($0) }
        guard let seconds, seconds > 0 else { sleepDeadline = nil; return }
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)); try Task.checkCancellation() } catch { return }
            guard let self else { return }; self.player.pause(); self.sleepDeadline = nil
        }
    }
    private func clearItemObservers() {
        timeout?.cancel(); captionTask?.cancel(); captionGeneration = UUID()
        statusObserver = nil; controlObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let failedObserver { NotificationCenter.default.removeObserver(failedObserver); self.failedObserver = nil }
    }
    func stop() {
        sleepTask?.cancel(); sleepDeadline = nil
        savePosition(); generation = UUID(); player.pause(); clearItemObservers(); player.currentItem?.asset.cancelLoading()
        if let observer { player.removeTimeObserver(observer); self.observer = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
// The app owns the inline caption layer. AVKit's contentOverlayView can be
// nil during creation or hidden/replaced by its presentation lifecycle.
struct CaptionOverlay: View {
    let text: String
    let size: CGSize
    var fontSize: Double = SubtitleSizePolicy.defaultSize
    var background: CaptionBackground = .box
    var position: CaptionPosition = .standard
    @ScaledMetric(relativeTo:.title3) private var scaledBase = 20.0
    @AppStorage(CaptionPrefs8.colorKey) private var captionColor = CaptionPalette8.white.rawValue
    @AppStorage(CaptionPrefs8.boldKey) private var captionBold = true
    @AppStorage(CaptionPrefs8.plateKey) private var captionPlate = 0.80
    @AppStorage(CaptionPrefs8.widthKey) private var captionWidth = CaptionWidth8.standard.rawValue
    var body: some View {
        GeometryReader { geometry in
            let ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 16.0 / 9.0
            let width = min(geometry.size.width, geometry.size.height * ratio)
            let height = min(geometry.size.height, geometry.size.width / ratio)
            VStack {
                Spacer(minLength: 0)
                if !text.isEmpty {
                    Text(text).font(.system(size:CGFloat(SubtitleSizePolicy.clamped(fontSize) * scaledBase / SubtitleSizePolicy.defaultSize),weight: captionBold ? .bold : .semibold))
                        .foregroundStyle(CaptionPrefs8.palette(captionColor).color).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, background == .box ? 10 : 2)
                        .padding(.vertical, background == .box ? 6 : 0)
                        .background {
                            if background == .box { RoundedRectangle(cornerRadius: 7).fill(.black.opacity(captionPlate)) }
                        }
                        .shadow(color: .black, radius: background == .outline ? 3 : 2)
                        .padding(.horizontal, CaptionPrefs8.width(captionWidth).inset).padding(.bottom, 12 + position.extraBottomPadding)
                        .accessibilityIdentifier("player.caption")
                        .accessibilityValue("Subtitle size \(Int(SubtitleSizePolicy.clamped(fontSize))) points")
                }
            }.frame(width: width, height: height).position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }.allowsHitTesting(false)
    }
}
