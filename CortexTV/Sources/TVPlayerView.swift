import AVFoundation
import SwiftUI

struct TVPlayerView: View {
    let media: TVMedia
    let startEpisode: Int

    @EnvironmentObject private var store: TVStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = TVPlaybackModel()
    @State private var episode: Int

    init(media: TVMedia, startEpisode: Int) {
        self.media = media
        self.startEpisode = startEpisode
        _episode = State(initialValue: max(1, startEpisode))
    }

    private var lastEpisode: Int {
        max(media.totalEpisodes ?? 0, media.releasedEpisodes ?? 0, episode)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TVVideoSurface(player: model.player).ignoresSafeArea()

            if let text = model.activeText, model.subtitlesOn {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.62)))
                        .shadow(color: .black.opacity(0.9), radius: 8, y: 2)
                        .padding(.horizontal, 120)
                        .padding(.bottom, 175)
                }
                .allowsHitTesting(false)
            }

            switch model.state {
            case .failed(let message):
                TVPlaybackFailure(message: message) { dismiss() }
            case .loading:
                ProgressView("Finding source…")
                    .tint(TVBrand.cyan)
                    .foregroundStyle(TVBrand.text)
            default:
                EmptyView()
            }

            controls
        }
        .task(id: episode) {
            await model.load(store: store, aid: media.aid, episode: episode, lastEpisode: lastEpisode)
        }
        .onChange(of: model.requestedEpisode) { _, requested in
            guard let requested else { return }
            model.requestedEpisode = nil
            if requested <= lastEpisode { episode = requested }
        }
        .onDisappear { model.stop() }
        .onExitCommand { dismiss() }
        .onPlayPauseCommand { model.togglePlayback() }
    }

    private var controls: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(TVBrand.text)
                        .lineLimit(1)
                    Text("Episode \(episode)")
                        .font(.system(size: 20))
                        .foregroundStyle(TVBrand.dim)
                }
                Spacer()
                if model.hasSubtitles {
                    TVPill(text: model.subtitlesOn ? "Hungarian subs on" : "Hungarian subs off",
                           tint: model.subtitlesOn ? TVBrand.cyan : TVBrand.dim)
                }
            }
            .padding(.horizontal, 70)
            .padding(.top, 46)
            .padding(.bottom, 26)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            HStack(spacing: 18) {
                TVControlButton(system: "gobackward.10", label: "10 mp") { model.skip(-10) }
                TVControlButton(system: model.isPlaying ? "pause.fill" : "play.fill",
                                label: model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                TVControlButton(system: "goforward.10", label: "10 sec") { model.skip(10) }
                if model.hasSubtitles {
                    TVControlButton(system: model.subtitlesOn ? "captions.bubble.fill" : "captions.bubble",
                                    label: "Subtitles") { model.subtitlesOn.toggle() }
                }
                if model.hasNext {
                    TVControlButton(system: "forward.end.fill", label: "Next") { model.requestNext() }
                }
                Spacer()
                TVControlButton(system: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 70)
            .padding(.top, 22)
            .padding(.bottom, 46)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
    }
}

// MARK: - Controls

struct TVControlButton: View {
    let system: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 26, weight: .semibold))
                Text(label)
                    .font(.system(size: 15))
            }
            .frame(minWidth: 96)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .buttonStyle(TVControlStyle())
    }
}

struct TVControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? TVBrand.ink : TVBrand.text)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? TVBrand.cyan : Color.white.opacity(0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Video surface

struct TVVideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> TVPlayerLayerView {
        let view = TVPlayerLayerView()
        view.attach(player)
        return view
    }

    func updateUIView(_ uiView: TVPlayerLayerView, context: Context) {
        uiView.attach(player)
    }
}

final class TVPlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    func attach(_ player: AVPlayer) {
        guard let layer = self.layer as? AVPlayerLayer else { return }
        layer.player = player
        layer.videoGravity = .resizeAspect
        backgroundColor = .black
    }
}

// MARK: - Failure card

struct TVPlaybackFailure: View {
    let message: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(TVBrand.violet)
            Text("Cannot start")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(TVBrand.text)
            Text(message)
                .font(.system(size: 22))
                .foregroundStyle(TVBrand.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)
            Button("Back", action: close)
                .buttonStyle(.card)
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(TVBrand.inkSoft.opacity(0.96)))
    }
}

// MARK: - Playback model

@MainActor
final class TVPlaybackModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var activeText: String?
    @Published private(set) var isPlaying = false
    @Published var subtitlesOn = true
    @Published private(set) var hasSubtitles = false
    @Published var requestedEpisode: Int?

    let player = AVPlayer()
    private var timeline = TVSubtitleTimeline(cues: [])
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastEpisode = 1
    private var loadedEpisode = 0

    var hasNext: Bool { loadedEpisode > 0 && loadedEpisode < lastEpisode }

    func load(store: TVStore, aid: Int, episode: Int, lastEpisode: Int) async {
        guard aid > 0, episode > 0 else { return }
        self.lastEpisode = lastEpisode
        loadedEpisode = episode
        state = .loading
        stopObservers()

        let cues = await store.subtitles(aid: aid, episode: episode)
        timeline = TVSubtitleTimeline(cues: cues)
        hasSubtitles = !cues.isEmpty

        do {
            let resolved = try await store.resolve(aid: aid, episode: episode)
            guard let url = resolved.playableURL else {
                state = .failed(resolved.failureText)
                return
            }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
            state = .playing
            installObservers()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func requestNext() {
        guard hasNext else { return }
        requestedEpisode = loadedEpisode + 1
    }

    func togglePlayback() {
        guard state == .playing else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func skip(_ seconds: Double) {
        guard state == .playing else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        guard current.isFinite else { return }
        let target = max(0, current + seconds)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        player.pause()
        stopObservers()
    }

    // MARK: Observers

    private func installObservers() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    let text = self.subtitlesOn ? self.timeline.text(at: seconds) : nil
                    if text != self.activeText { self.activeText = text }
                }
                let playing = self.player.timeControlStatus == .playing
                if playing != self.isPlaying { self.isPlaying = playing }
            }
        }

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                             object: player.currentItem,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.hasNext { self.requestedEpisode = self.loadedEpisode + 1 }
            }
        }
    }

    private func stopObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        activeText = nil
        isPlaying = false
    }
}
