import SwiftUI
import AVKit

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
@MainActor final class NativeSurfaceController: NSObject,ObservableObject,AVPictureInPictureControllerDelegate {
    @Published var possible = false
    @Published var active = false
    private var pip: AVPictureInPictureController?
    private var observer: NSKeyValueObservation?
    func bind(_ layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pip = AVPictureInPictureController(playerLayer:layer);pip?.delegate = self;pip?.canStartPictureInPictureAutomaticallyFromInline = true
        observer = pip?.observe(\.isPictureInPicturePossible,options:[.initial,.new]) { [weak self] obj,_ in Task { @MainActor in self?.possible = obj.isPictureInPicturePossible } }
    }
    func toggle() { guard let pip else { return };if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() } }
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { Task { @MainActor [weak self] in self?.active = true } }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { Task { @MainActor [weak self] in self?.active = false } }
}
struct NativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let controller: NativeSurfaceController
    func makeUIView(context: Context) -> PlayerLayerView { let view = PlayerLayerView();view.backgroundColor = .black;view.videoLayer.videoGravity = .resizeAspect;view.videoLayer.player = player;controller.bind(view.videoLayer);return view }
    func updateUIView(_ uiView: PlayerLayerView,context: Context) { if uiView.videoLayer.player !== player { uiView.videoLayer.player = player } }
}
struct NativeAirPlay: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView();view.tintColor = .white;view.activeTintColor = .systemPurple;view.prioritizesVideoDevices = true;return view }
    func updateUIView(_ uiView: AVRoutePickerView,context: Context) {}
}
struct PlayerScreen: View {
    @StateObject private var playback: Playback
    @StateObject private var surface = NativeSurfaceController()
    @StateObject private var party = WatchPartyModel()
    @StateObject private var chrome = PlayerChromeState()
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var downloads: Downloads
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var showParty = false
    @State private var showOptions = false
    @State private var sheetTab = 0
    @State private var rate: Float = 1
    @State private var muted = false
    @State private var saveMessage: String?
    @AppStorage("player.subtitleSize") private var subtitleSize = SubtitleSizePolicy.defaultSize
    @AppStorage("player.skipIntro") private var showIntro = true
    @AppStorage("player.skipOutro") private var showOutro = true
    @AppStorage("player.syncProgress") private var sync = true
    @State private var syncedBucket = -1
    @AppStorage("player.autoNext") private var autoNext = true
    @State private var hudKind: PlayerHUDKind?
    @State private var flashText: String?
    @State private var scrubAnchor = 0.0
    @State private var scrubPreview = 0.0
    @State private var hudClearTask: Task<Void, Never>?
    @State private var autoNextLeft: Int?
    @State private var autoNextTask: Task<Void, Never>?
    @StateObject private var guardWatch = WatchGuard()
    @AppStorage(WatchGuardPolicy.enabledKey) private var guardEnabled = true
    @AppStorage(WatchGuardPolicy.episodeKey) private var guardEpisodes = WatchGuardPolicy.defaultEpisodes
    @AppStorage(WatchGuardPolicy.minutesKey) private var guardMinutes = WatchGuardPolicy.defaultMinutes
    @AppStorage(CaptionStyle.backgroundKey) private var captionBackground = CaptionBackground.box.rawValue
    @AppStorage(CaptionStyle.positionKey) private var captionPosition = CaptionPosition.standard.rawValue
    @AppStorage("player.defaultSpeed") private var defaultSpeed = 1.0
    init(route: PlaybackRoute) { _playback = StateObject(wrappedValue:Playback(route:route)) }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                NativeVideoSurface(player:playback.player,controller:surface).accessibilityElement(children:.ignore).accessibilityLabel("CortexPlayer native video").accessibilityValue("\(playback.phase.rawValue) \(Int(playback.position))\(playback.route.url.isFileURL ? " · Local file" : "")").accessibilityIdentifier("player.video")
                    .contentShape(Rectangle())
                    .overlay {
                        PlayerGestureView(
                            toggleChrome: { guardWatch.noteInteraction(); chrome.toggleFromVideo() },
                            seekBy: { delta in
                                guardWatch.noteInteraction()
                                let step = Int(PlaybackPrefs8.seekStep)
                                let label = (delta > 0 ? "+" : "-") + String(step)
                                flashText = label
                                playback.seek(max(0, playback.position + delta))
                                party.control("seek", time: playback.position)
                                Task { try? await Task.sleep(for: .milliseconds(700)); if flashText == label { flashText = nil } }
                            },
                            scrubStart: { guardWatch.noteInteraction(); scrubbing = true; scrubAnchor = playback.position },
                            scrubTo: { offset in
                                scrubPreview = min(max(0, scrubAnchor + offset), max(1, playback.duration))
                                showHUD(.seek(clock(scrubPreview)))
                            },
                            scrubEnd: {
                                guardWatch.noteInteraction()
                                scrubbing = false
                                playback.seek(scrubPreview)
                                party.control("seek", time: scrubPreview)
                                hudClearTask?.cancel()
                                hudClearTask = Task { try? await Task.sleep(for: .milliseconds(500)); hudKind = nil }
                            },
                            hud: { kind in showHUD(kind) }
                        )
                    }
                    .accessibilityAddTraits(.isButton).accessibilityAction { guardWatch.noteInteraction();chrome.toggleFromVideo() }
                CaptionOverlay(text:playback.subtitle,size:playback.player.currentItem?.presentationSize ?? .zero,fontSize:subtitleSize,
                               background:CaptionStyle.background(captionBackground),position:CaptionStyle.position(captionPosition))
                    .padding(.bottom,chrome.visible ? (geometry.size.height < 440 ? 60 : 95) : 0)
                if let hudKind { PlayerHUD(kind:hudKind).frame(maxHeight:.infinity,alignment:.center).allowsHitTesting(false) }
                if let flashText { SeekFlash(text:flashText).frame(maxHeight:.infinity,alignment:.center).allowsHitTesting(false) }
                VStack(spacing:0) {
                    if chrome.visible { header.simultaneousGesture(TapGesture().onEnded { chrome.interacted() }) }
                    Spacer(minLength:0)
                    if playback.isWaiting { ProgressView(playback.phase == .loading ? "Loading episode…" : "Buffering…").tint(.white).padding(22).background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:18)) }
                    if [.failed,.ended].contains(playback.phase) {
                        if playback.phase == .ended, autoNext, playback.route.next != nil, autoNextLeft != nil { autoNextPanel }
                        else { endPanel }
                    }
                    Spacer(minLength:0)
                    if chrome.visible {
                        if let notice = playback.subtitleNotice { Text(notice).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(3).padding(.horizontal,14) }
                        if let saveMessage { Text(saveMessage).font(.caption2).foregroundStyle(.orange).padding(.horizontal,14) }
                        if let prompt = skipPrompt {
                            HStack(spacing:0) { Spacer(minLength:0);skipButton(prompt) }
                                .padding(.horizontal,16).padding(.bottom,geometry.size.height < 440 ? 2 : 7)
                                .simultaneousGesture(TapGesture().onEnded { guardWatch.noteInteraction();chrome.interacted() })
                        }
                        controls(compact:geometry.size.height < 440).simultaneousGesture(TapGesture().onEnded { guardWatch.noteInteraction();chrome.interacted() })
                    }
                }
                if let reason = guardWatch.asking {
                    WatchGuardPrompt(reason: reason, remaining: guardWatch.remaining,
                                     continueWatching: continueAfterGuard, stopWatching: stopAfterGuard)
                        .zIndex(10)
                }
            }.foregroundStyle(.white).animation(.easeInOut(duration:0.2),value:chrome.visible)
        }.background(.black).preferredColorScheme(.dark).statusBarHidden(true).tint(Color.cortexPurple)
            .task {
                subtitleSize = SubtitleSizePolicy.clamped(subtitleSize)
                rate = Float(defaultSpeed)
                playback.player.defaultRate = rate
                playback.start();party.configure(api:api,playback:playback);updateChrome()
            }
            .task { await watchGuardClock() }
            .onAppear { guardWatch.onTimeout = { _ in finishForInactivity() } }
            .onDisappear { chrome.cancel();cancelAutoNext();hudClearTask?.cancel();if sync && api.signedIn && !playback.route.url.isFileURL { Task { await syncProgress() } };party.leave();playback.stop() }
            .onChange(of:playback.position) { _,value in if !scrubbing { scrub = min(max(0,value),max(1,playback.duration)) };if sync && !playback.route.url.isFileURL && api.signedIn && Int(value)/30 != syncedBucket && value >= 10 { syncedBucket = Int(value)/30;Task { await syncProgress() } } }
            .onChange(of:playback.route.id) { _,_ in party.leave();syncedBucket = -1;updateChrome() }
            .onChange(of:playback.phase) { _,phase in
                updateChrome()
                if phase == .ended {
                    guardWatch.noteEpisodeFinished()
                    if autoNext, playback.route.next != nil, !guardWatch.shouldHoldBeforeNextEpisode() { startAutoNextCountdown() }
                } else { cancelAutoNext() }
            }
            .onChange(of:showOptions) { _,_ in updateChrome() }
            .onChange(of:showParty) { _,_ in updateChrome() }
            .onChange(of:scenePhase) { _,state in if state == .active { guardWatch.noteInteraction() };updateChrome() }
            .onReceive(NotificationCenter.default.publisher(for:UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in updateChrome() }
            .sheet(isPresented:$showParty) { NativeWatchParty(party:party) }
            .sheet(isPresented:$showOptions) { playerSettings }
    }
    /// Intro/outro skipping sits next to the sound and playback controls, so the
    /// top bar stays exactly as it is.
    private enum SkipPrompt {
        case intro(Double),outro(Double)
        var title: String { switch self { case .intro: return "Skip intro";case .outro: return "Skip outro" } }
        var shortTitle: String { switch self { case .intro: return "Intro";case .outro: return "Outro" } }
        var target: Double { switch self { case .intro(let end),.outro(let end): return end } }
        var identifier: String { switch self { case .intro: return "player.skipIntro";case .outro: return "player.skipOutro" } }
    }
    private var skipPrompt: SkipPrompt? {
        guard ![.failed,.ended].contains(playback.phase) else { return nil }
        if showIntro,let end = playback.introEnd { return .intro(end) }
        if showOutro,let end = playback.outroStart { return .outro(end) }
        return nil
    }
    private func skipButton(_ prompt: SkipPrompt) -> some View {
        Button {
            guardWatch.noteInteraction();playback.seek(prompt.target);party.control("seek",time:prompt.target);chrome.interacted()
        } label: {
            HStack(spacing:7) {
                Image(systemName:"forward.end.fill").font(.system(size:12,weight:.bold))
                Text(prompt.title).font(.system(size:13,weight:.bold))
            }.padding(.horizontal,16).frame(minHeight:44).foregroundStyle(.white)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.cortexPurple.opacity(0.55),lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(prompt.title).accessibilityIdentifier(prompt.identifier)
    }
    private var header: some View {
        HStack(spacing: 10) {
            PlayerCircleButton(systemImage: "chevron.left", size: 40, label: "Close player", identifier: "player.close") {
                party.leave(); playback.stop(); dismiss()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NOW PLAYING").font(.system(size: 9, weight: .black)).tracking(1.6).foregroundStyle(Color.cortexPurple)
                Text(playback.route.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                if !playback.route.episodeLabel.isEmpty {
                    Text(playback.route.episodeLabel).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 6)
            options
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 18)
        .background(LinearGradient(colors: [.black.opacity(0.82), .black.opacity(0)], startPoint: .top, endPoint: .bottom))
    }
    private var options: some View {
        PlayerCircleButton(systemImage: "slider.horizontal.3", size: 40, label: "Player options", identifier: "player.options") {
            guardWatch.noteInteraction(); showOptions = true
        }
    }
    /// The 6.7 settings sheet: three tabs, glass rows, everything one tap away.
    private var playerSettings: some View {
        NavigationStack {
            ZStack {
                CortexTheme.cosmic.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Tab", selection: $sheetTab) {
                            Text("Episode").tag(0); Text("Subtitles").tag(1); Text("Playback").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 14)

                        switch sheetTab {
                        case 0: episodeTab
                        case 1: subtitleTab
                        default: playbackTab
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showOptions = false }.accessibilityIdentifier("player.settingsDone")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.cortexPurple)
    }

    private func sheetCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .foregroundStyle(.white)
            .playerGlass(radius: 20, stroke: 0.09)
            .padding(.horizontal, 14)
    }

    private var episodeTab: some View {
        VStack(spacing: 14) {
            sheetCard {
                PlayerSheetRow(title: playback.route.title, systemImage: "play.rectangle.fill",
                               detail: playback.route.episodeLabel.isEmpty ? "Now playing" : playback.route.episodeLabel) {
                    Text(clock(playback.position) + " / " + clock(playback.duration)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Next episode", systemImage: "forward.end.fill",
                               detail: playback.route.next == nil ? "This is the last available episode" : "Plays after this one",
                               trailing: { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.35)) }) {
                    guardWatch.noteInteraction(); Task { await playback.nextEpisode() }
                }
                .opacity(playback.route.next == nil ? 0.45 : 1)
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Restart episode", systemImage: "backward.end.fill", detail: nil,
                               trailing: { EmptyView() }) {
                    guardWatch.noteInteraction(); playback.restart(); party.control("seek", time: 0)
                }
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Watch Party", systemImage: "person.2.fill",
                               detail: playback.route.anime == nil ? "Needs a catalogue episode" : "Watch together, in sync",
                               trailing: { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.35)) }) {
                    showOptions = false
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); showParty = true }
                }
                .opacity(playback.route.anime == nil || playback.route.url.isFileURL ? 0.45 : 1)
            }

            sheetCard {
                PlayerSheetRow(title: "Chapters", systemImage: "list.bullet", detail: nil,
                               trailing: { Text("\(chapters.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5)) }) {}
                ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                    Button {
                        playback.seek(max(0, chapter.start)); party.control("seek", time: max(0, chapter.start))
                    } label: {
                        HStack(spacing: 10) {
                            Capsule().fill(abs(playback.position - chapter.start) < 1 ? Color.cortexPurple : .white.opacity(0.25)).frame(width: 3, height: 16)
                            Text(chapter.title).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(clock(chapter.start)).monospacedDigit().font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("player.chapter.\(chapter.title)")
                }
                Text("Markers come from the intro and outro ranges of the episode.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }

    private var subtitleTab: some View {
        VStack(spacing: 14) {
            sheetCard {
                PlayerSheetRow(title: "Subtitle size", systemImage: "textformat.size",
                               detail: "\(Int(SubtitleSizePolicy.clamped(subtitleSize))) pt on this device",
                               trailing: { EmptyView() }) {}
                Slider(value: Binding(get: { SubtitleSizePolicy.clamped(subtitleSize) },
                                      set: { subtitleSize = SubtitleSizePolicy.clamped($0) }),
                       in: SubtitleSizePolicy.minimum...SubtitleSizePolicy.maximum, step: 1)
                    .tint(Color.cortexPurple)
                    .padding(.horizontal, 14).padding(.bottom, 6)
                    .accessibilityLabel("Subtitle size").accessibilityIdentifier("player.subtitleSize")
                Text("Subtitle preview").font(.system(size: CGFloat(SubtitleSizePolicy.clamped(subtitleSize)), weight: .semibold))
                    .foregroundStyle(.white).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(10)
                    .background(.black, in: RoundedRectangle(cornerRadius: 7))
                    .padding(.horizontal, 14).padding(.bottom, 10)
                    .accessibilityIdentifier("player.subtitlePreview")
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Reset size", systemImage: "arrow.counterclockwise", detail: nil, trailing: { EmptyView() }) {
                    subtitleSize = SubtitleSizePolicy.defaultSize
                }
                .accessibilityIdentifier("player.resetSubtitleSize")
            }

            sheetCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BACKGROUND").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.45))
                    Picker("Background", selection: $captionBackground) {
                        ForEach(CaptionBackground.allCases) { option in Text(option.title).tag(option.rawValue) }
                    }.pickerStyle(.segmented)
                    Text("POSITION").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.45)).padding(.top, 4)
                    Picker("Position", selection: $captionPosition) {
                        ForEach(CaptionPosition.allCases) { option in Text(option.title).tag(option.rawValue) }
                    }.pickerStyle(.segmented)
                    CaptionStylePreview(background: CaptionStyle.background(captionBackground),
                                        position: CaptionStyle.position(captionPosition),
                                        size: subtitleSize)
                        .padding(.top, 4)
                }
                .padding(14)
            }

            sheetCard {
                HStack {
                    Text("Timing offset").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(String(format: "%+.2f s", playback.subtitleDelay)).monospacedDigit()
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(abs(playback.subtitleDelay) < 0.001 ? .white.opacity(0.5) : Color.cortexPurple)
                        .accessibilityIdentifier("player.subtitleDelayValue")
                }.padding(.horizontal, 14).padding(.top, 12)
                HStack(spacing: 10) {
                    Button { playback.adjustSubtitleDelay(by: -0.25) } label: {
                        Label("Earlier", systemImage: "minus").frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.plain).background(.white.opacity(0.08), in: Capsule())
                        .accessibilityIdentifier("player.subtitleEarlier")
                    Button { playback.adjustSubtitleDelay(by: 0.25) } label: {
                        Label("Later", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 40)
                    }.buttonStyle(.plain).background(.white.opacity(0.08), in: Capsule())
                        .accessibilityIdentifier("player.subtitleLater")
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                Menu {
                    Button("Subtitles off" + (playback.selectedCaption == nil ? " · Selected" : "")) { playback.selectCaption(nil) }
                    ForEach(playback.route.info?.tracks ?? []) { track in
                        if let url = track.url {
                            Button(track.label + (playback.selectedCaption == track.file ? " · Selected" : "")) { playback.selectCaption(url) }
                        }
                    }
                    if playback.route.url.isFileURL, let url = playback.route.subtitleURL {
                        Button("Downloaded subtitles") { playback.selectCaption(url) }
                    }
                    Button("Retry subtitles") { playback.retryCaptions() }.accessibilityIdentifier("player.retryCaptions")
                } label: {
                    HStack {
                        Label("Track", systemImage: "captions.bubble")
                        Spacer()
                        Text(playback.selectedCaption == nil ? "Off" : "On").foregroundStyle(.white.opacity(0.55))
                        if playback.captionCueCount > 0 { Text("· \(playback.captionCueCount) cues").foregroundStyle(.white.opacity(0.35)) }
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                if let file = playback.savedCaptionURL {
                    Divider().overlay(.white.opacity(0.08))
                    ShareLink("Save the subtitles", item: file)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
    }

    private var playbackTab: some View {
        VStack(spacing: 14) {
            sheetCard {
                PlayerSheetRow(title: "Speed", systemImage: "gauge.with.needle", detail: "Applies right now",
                               trailing: { Text(String(format: "%.2gx", rate)).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cortexPurple) }) {}
                HStack(spacing: 8) {
                    ForEach([Float(0.5), 0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                        Button(String(format: "%.2gx", speed)) {
                            rate = speed; playback.player.defaultRate = speed
                            if playback.phase == .playing { playback.player.rate = speed }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(rate == speed ? .black : .white)
                        .background(rate == speed ? Color.white : .white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Default speed", systemImage: "play.circle", detail: "Every new episode starts here",
                               trailing: { Text(String(format: "%.2gx", Float(defaultSpeed))).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cortexPurple) }) {}
                HStack(spacing: 8) {
                    ForEach([0.75, 1, 1.25, 1.5, 2], id: \.self) { speed in
                        Button(String(format: "%.2gx", Float(speed))) {
                            defaultSpeed = speed; rate = Float(speed); playback.player.defaultRate = Float(speed)
                            if playback.phase == .playing { playback.player.rate = Float(speed) }
                        }
                        .font(.system(size: 11, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(abs(defaultSpeed - speed) < 0.001 ? .black : .white)
                        .background(abs(defaultSpeed - speed) < 0.001 ? Color.white : .white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 14).padding(.bottom, 12)
                Divider().overlay(.white.opacity(0.08))
                Menu {
                    Button("Auto") { setQuality(0, CGSize.zero) }
                    Button("Up to 1080p") { setQuality(6_000_000, CGSize(width: 1920, height: 1080)) }
                    Button("Up to 720p") { setQuality(3_000_000, CGSize(width: 1280, height: 720)) }
                    Button("Up to 480p") { setQuality(1_000_000, CGSize(width: 854, height: 480)) }
                } label: {
                    HStack { Label("Quality limit", systemImage: "4k.tv"); Spacer(); Text("Source dependent").foregroundStyle(.white.opacity(0.5)) }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                }
            }

            sheetCard {
                PlayerSheetRow(title: "Play the next episode", systemImage: "arrow.triangle.2.circlepath",
                               detail: "A countdown starts at the end", trailing: { Toggle("", isOn: $autoNext).labelsHidden().tint(Color.cortexPurple) }) {}
                Divider().overlay(.white.opacity(0.08))
                PlayerSheetRow(title: "Sync viewing progress", systemImage: "icloud.and.arrow.up",
                               detail: "Uses the website account", trailing: { Toggle("", isOn: $sync).labelsHidden().tint(Color.cortexPurple) }) {}
                Divider().overlay(.white.opacity(0.08))
                Menu {
                    ForEach([15, 30, 60], id: \.self) { value in Button("Pause in \(value) minutes") { playback.setSleepTimer(minutes: value) } }
                    Button("Cancel timer") { playback.setSleepTimer(minutes: nil) }
                } label: {
                    HStack {
                        Label("Sleep timer", systemImage: "moon.zzz")
                        Spacer()
                        Text(playback.sleepDeadline.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Off")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                }
            }

            sheetCard {
                PlayerSheetRow(title: "Are you still watching?", systemImage: "eye.slash",
                               detail: "Pauses and closes when nobody answers", trailing: { Toggle("", isOn: $guardEnabled).labelsHidden().tint(Color.cortexPurple) }) {}
                if guardEnabled {
                    Divider().overlay(.white.opacity(0.08))
                    Menu {
                        ForEach(WatchGuardPolicy.episodeChoices, id: \.self) { count in
                            Button("\(count) episodes" + (WatchGuardPolicy.clampedEpisodes(guardEpisodes) == count ? " · Selected" : "")) { guardEpisodes = count }
                        }
                    } label: {
                        HStack { Text("Ask after"); Spacer(); Text("\(WatchGuardPolicy.clampedEpisodes(guardEpisodes)) episodes").foregroundStyle(.white.opacity(0.5)) }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                    }
                    Divider().overlay(.white.opacity(0.08))
                    Menu {
                        ForEach(WatchGuardPolicy.minuteChoices, id: \.self) { minutes in
                            Button(WatchGuardPolicy.durationText(Int(minutes)) + (guardMinutes == minutes ? " · Selected" : "")) { guardMinutes = minutes }
                        }
                        Button("Off" + (guardMinutes <= 0 ? " · Selected" : "")) { guardMinutes = 0 }
                    } label: {
                        HStack { Text("Long playback check"); Spacer(); Text(guardMinutes > 0 ? WatchGuardPolicy.durationText(Int(guardMinutes)) : "Off").foregroundStyle(.white.opacity(0.5)) }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                    }
                }
            }

            if let share = shareURL {
                sheetCard {
                    ShareLink(item: share) {
                        HStack { Label("Share this episode", systemImage: "square.and.arrow.up"); Spacer() }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("player.share")
                }
            }
        }
    }

    /// The new chrome: time row, custom scrubber, one focal play button, quiet satellites.
    private func controls(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 12) {
            if !compact, playback.route.next != nil {
                PlayerQueueCard(title: playback.route.title,
                                episodeLabel: playback.route.episodeLabel,
                                nextLabel: "Episode \(playback.route.episode + 1)",
                                hasNext: true) {
                    guardWatch.noteInteraction(); Task { await playback.nextEpisode() }
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
            VStack(spacing: 8) {
                PlayerScrubber(value: $scrub, duration: playback.duration, chapters: chapters.map { $0.start }) { editing in
                    scrubbing = editing; updateChrome()
                    if !editing {
                        guardWatch.noteInteraction(); playback.seek(scrub); party.control("seek", time: scrub)
                    }
                }
                .disabled(playback.duration <= 0 || playback.isWaiting)
                .opacity(playback.duration <= 0 || playback.isWaiting ? 0.5 : 1)
                .accessibilityIdentifier("player.seek")

                HStack {
                    Text(clock(scrubbing ? scrub : playback.position)).monospacedDigit()
                    Spacer()
                    if !currentChapterTitle.isEmpty, currentChapterTitle != "Episode" {
                        Text(currentChapterTitle.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(1)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    Text(clock(playback.duration)).monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 18)

            HStack(alignment: .center) {
                PlayerCircleButton(systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 40, label: "Toggle mute", identifier: "player.mute") {
                    guardWatch.noteInteraction(); muted.toggle(); playback.player.isMuted = muted
                }
                Spacer(minLength: 4)
                PlayerCircleButton(systemImage: "gobackward.10", size: 46, label: "Back \(Int(PlaybackPrefs8.seekStep)) seconds", identifier: "player.back10") {
                    guardWatch.noteInteraction()
                    playback.seek(max(0, playback.position - PlaybackPrefs8.seekStep))
                    party.control("seek", time: playback.position)
                }
                Spacer(minLength: 4)
                PlayerPlayButton(playing: playback.phase == .playing, disabled: ![.playing, .paused].contains(playback.phase)) {
                    toggle()
                }
                Spacer(minLength: 4)
                PlayerCircleButton(systemImage: "goforward.10", size: 46, label: "Forward \(Int(PlaybackPrefs8.seekStep)) seconds", identifier: "player.forward") {
                    guardWatch.noteInteraction()
                    playback.seek(playback.position + PlaybackPrefs8.seekStep)
                    party.control("seek", time: playback.position)
                }
                Spacer(minLength: 4)
                PlayerCircleButton(systemImage: "pip", size: 40, disabled: !surface.possible, label: "Picture in Picture", identifier: "player.pip") {
                    surface.toggle()
                }
            }
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.bottom, compact ? 2 : 6)

            if !compact {
                HStack(spacing: 22) {
                    NativeAirPlay().frame(width: 30, height: 26)
                    PlayerCircleButton(systemImage: "person.2.fill", size: 32, disabled: playback.route.anime == nil || playback.route.url.isFileURL, label: "Watch Party", identifier: "player.party") {
                        guardWatch.noteInteraction(); showParty = true
                    }
                    Button {
                        guardWatch.noteInteraction(); showOptions = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "captions.bubble.fill").font(.system(size: 12, weight: .semibold))
                            Text("Subtitles").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("player.subtitlesShortcut")
                    PlayerCircleButton(systemImage: "moon.zzz.fill", size: 32, label: "Sleep timer", identifier: "player.sleep") {
                        playback.setSleepTimer(minutes: playback.sleepDeadline == nil ? 30 : nil)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
                .opacity(0.95)
            }
        }
        .padding(.top, 10)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }
    private var endPanel: some View {
        VStack(spacing:14) {
            Image(systemName:playback.phase == .ended ? "checkmark.circle" : "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Color.cortexPurple)
            Text(playback.phase == .ended ? "Episode finished" : "Unable to play").font(.headline)
            if let error = playback.error { Text(error).font(.subheadline).multilineTextAlignment(.center) }
            if playback.phase == .ended && playback.route.next != nil { Button("Next episode") { guardWatch.noteInteraction();Task { await playback.nextEpisode() } }.buttonStyle(.borderedProminent) }
            Button(playback.phase == .ended ? "Watch again" : "Retry episode") { guardWatch.noteInteraction();if playback.phase == .ended { playback.restart() } else { Task { await playback.retry() } } }.buttonStyle(.bordered).frame(minHeight:44)
            if playback.route.url.isFileURL, let broken = brokenDownload {
                Button("Remove broken download") {
                    downloads.remove(broken);party.leave();playback.stop();dismiss()
                }.buttonStyle(.borderedProminent).frame(minHeight:44).accessibilityIdentifier("player.removeBrokenDownload")
                if broken.anime != nil {
                    Button("Download again") {
                        do { try downloads.retryQueued(broken) } catch {}
                        party.leave();playback.stop();dismiss()
                    }.buttonStyle(.bordered).frame(minHeight:44).accessibilityIdentifier("player.downloadAgain")
                }
            }
            Button("Close player") { party.leave();playback.stop();dismiss() }.buttonStyle(.borderless).frame(minHeight:44).foregroundStyle(.white.opacity(0.7)).accessibilityLabel("Close player").accessibilityIdentifier("player.closeEndPanel")
        }
        .padding(22).frame(maxWidth:360)
        .playerGlass(radius:24).padding(18)
    }
    private var brokenDownload: DownloadItem? {
        downloads.items.first { "\($0.animeID).\($0.episode)" == playback.route.key }
    }
    private var autoNextPanel: some View {
        VStack(spacing: 14) {
            Text("Next episode is starting…").font(.headline).accessibilityIdentifier("player.autoNextTitle")
            Text(playback.route.next != nil ? "Episode \(playback.route.episode + 1) in \(autoNextLeft ?? 0) s" : "")
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            ProgressView(value: Double(8 - (autoNextLeft ?? 0)), total: 8)
                .tint(Color.cortexPurple).frame(maxWidth: 240).accessibilityIdentifier("player.autoNextProgress")
            HStack(spacing: 10) {
                Button("Play now") { guardWatch.noteInteraction();cancelAutoNext(); Task { await playback.nextEpisode() } }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("player.autoNextPlayNow")
                Button("Cancel") { cancelAutoNext() }
                    .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("player.autoNextCancel")
            }
            Button("Watch again") { cancelAutoNext(); playback.restart() }
                .buttonStyle(.borderless).frame(minHeight: 44).foregroundStyle(.white.opacity(0.7))
        }
        .padding(22).frame(maxWidth: 360)
        .playerGlass(radius: 24).padding(18)
    }
    private var chapters: [(title: String, start: Double)] {
        var out: [(String, Double)] = [("Beginning", 0)]
        if let intro = playback.route.info?.skip?.intro, intro.valid {
            out.append(("Intro", intro.start))
            out.append(("After the intro", intro.end))
        }
        if let outro = playback.route.info?.skip?.outro, outro.valid {
            out.append(("Outro", outro.start))
            out.append(("Ending", outro.end))
        }
        return out
    }
    private var currentChapterTitle: String {
        var title = "Episode"
        for chapter in chapters where chapter.start <= playback.position + 0.5 { title = chapter.title }
        return title
    }
    private func showHUD(_ kind: PlayerHUDKind) {
        hudKind = kind
        hudClearTask?.cancel()
        hudClearTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            if !Task.isCancelled { hudKind = nil }
        }
    }
    private var shareURL: URL? {
        guard let anime = playback.route.anime else { return nil }
        return URL(string: "https://cortanime.eu/watch/\(anime.id)/\(playback.route.episode)")
    }
    /// Runs while the player is open and feeds the inactivity clock.
    private func watchGuardClock() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guardWatch.tick(playing: playback.phase == .playing)
        }
    }
    private func continueAfterGuard() {
        guardWatch.acknowledge()
        if playback.phase == .ended, autoNext, playback.route.next != nil { startAutoNextCountdown() }
    }
    private func stopAfterGuard() {
        guardWatch.acknowledge()
        cancelAutoNext()
        if playback.phase == .playing { playback.player.pause() }
    }
    /// Nobody answered the guard: stop the sound, close the player, let the screen lock.
    private func finishForInactivity() {
        cancelAutoNext()
        party.leave()
        playback.stop()
        dismiss()
    }
    private func startAutoNextCountdown() {
        cancelAutoNext()
        autoNextLeft = 8
        autoNextTask = Task { @MainActor in
            while let left = autoNextLeft, left > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                autoNextLeft = left - 1
            }
            if !Task.isCancelled, autoNextLeft == 0 {
                autoNextLeft = nil
                await playback.nextEpisode()
            }
        }
    }
    private func cancelAutoNext() {
        autoNextTask?.cancel(); autoNextTask = nil; autoNextLeft = nil
    }
    private func updateChrome() {
        chrome.update(playing:playback.phase == .playing,scrubbing:scrubbing,settingsOpen:showOptions || guardWatch.asking != nil,partyOpen:showParty,voiceOver:UIAccessibility.isVoiceOverRunning,active:scenePhase == .active)
    }
    private func toggle() { guardWatch.noteInteraction();if playback.phase == .playing { playback.player.pause();party.control("pause",time:playback.position) } else { playback.player.playImmediately(atRate:rate);party.control("play",time:playback.position) } }
    private func setQuality(_ bitrate: Double,_ size: CGSize) { playback.player.currentItem?.preferredPeakBitRate = bitrate;playback.player.currentItem?.preferredMaximumResolution = size }
    private func clock(_ value: Double) -> String { let safe = value.isFinite ? max(0,Int(value)) : 0;guard safe >= 3600 else { return String(format:"%02d:%02d",safe/60,safe%60) };return String(format:"%d:%02d:%02d",safe/3600,(safe/60)%60,safe%60) }
    private func syncProgress() async { guard let anime = playback.route.anime else { return };do { _ = try await api.json("/api/watchlist/progress",method:"POST",body:["animeId":anime.id,"episode":playback.route.episode,"time":playback.position,"duration":playback.duration,"title":anime.title,"cover":anime.cover?.absoluteString ?? "","completed":playback.phase == .ended]) } catch { if !(error is CancellationError),!Task.isCancelled { saveMessage = "Account progress not synced: "+error.localizedDescription } } }
}
