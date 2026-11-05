import SwiftUI
import WidgetKit
import CoreSpotlight

@main struct CortexAnimeNativeApp: App {
    @UIApplicationDelegateAdaptor(AnimeAppDelegate.self) private var delegate
    @StateObject private var api: APIClient
    @StateObject private var catalog: CatalogModel
    @StateObject private var downloads = Downloads.shared
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--plus-beta-qa") && ProcessInfo.processInfo.arguments.contains("--beta-reset") { BetaSubscription.shared.cancelPreview() }
        #endif
        let client = APIClient(),model = CatalogModel(api:client);_api = StateObject(wrappedValue:client);_catalog = StateObject(wrappedValue:model);Downloads.shared.configure(catalog:model) }
    var body: some Scene {
        WindowGroup {
            CortexRoot5()
                .environmentObject(api).environmentObject(catalog).environmentObject(downloads)
                .modifier(CortexAppearance())
                .task {
                    // 6.7: a re-signed install keeps the bundle icon but forgets the alternate
                    // selection, so the saved choice is re-applied once per launch.
                    AppIconStore.shared.reconcile()
                }
        }
    }
}
struct NativeLink: Identifiable { let animeID: Int;let id = UUID() }
struct NativeRoot: View {
    @EnvironmentObject private var downloads: Downloads
    @State private var showDownloadLibrary = false
    @EnvironmentObject private var catalog: CatalogModel
    @EnvironmentObject private var api: APIClient
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @GestureState private var navigationDrag: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visitedTabs: Set<Int> = [0]
    @State private var link: NativeLink?
    @State private var fixturePlayer: PlaybackRoute?
    @State private var nativeQAError: String?
    @State private var booting = CortexBootGate.shouldPlay
    @StateObject private var connectivity = Connectivity.shared
    @State private var showWhatsNew = false
    private var offlineMode: Bool { connectivity.isOffline || catalog.networkUnavailable || (catalog.error != nil && catalog.trending.isEmpty) }
    var body: some View {
        ZStack {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--plus-beta-qa") { BetaPurchaseQALobby().zIndex(10) }
            #endif
            ForEach(0..<5,id:\.self) { index in
                if visitedTabs.contains(index) {
                    tabContent(index)
                        .opacity(tab == index ? 1 : 0)
                        .allowsHitTesting(tab == index)
                        .accessibilityHidden(tab != index)
                }
            }
        }
            .safeAreaInset(edge:.bottom,spacing:0) { VStack(spacing:0) { if let item = downloads.currentTransfer { DownloadTransferBanner(item:item,count:downloads.activeCount) { showDownloadLibrary = true } };tabBar } }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--plus-beta-qa") { return }
                if ProcessInfo.processInfo.arguments.contains(where:{ ["--offline-download-cold-qa","--offline-play-cold-qa","--offline-player-ui-qa"].contains($0) }) {
                    do { fixturePlayer = try await OfflineNativeQA.run(downloads) }
                    catch { if !(error is CancellationError),!Task.isCancelled { nativeQAError = error.localizedDescription;try? OfflineNativeQA.report("plus-offline-error",["error":error.localizedDescription]) } }
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("--caption-detail-qa") {
                    let raw = ProcessInfo.processInfo.arguments.first(where:{ $0.hasPrefix("--qa-anime=") })?.split(separator:"=").last
                    if let raw,let id = Int(raw) { link = NativeLink(animeID:id) }
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("--live-hu-qa") {
                    do {
                        let anime = try await catalog.detail(185874)
                        UserDefaults.standard.removeObject(forKey:"resume.185874.9")
                        let info = try await catalog.resolve(anime,episode:9,language:"hun")
                        fixturePlayer = try catalog.route(for:anime,episode:9,language:"hun",info:info)
                    } catch { if !(error is CancellationError),!Task.isCancelled { nativeQAError = error.localizedDescription } }
                    return
                }
                #endif
                #if DEBUG
                if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil && !CatalogModel.fixture { return }
                #endif
                guard !connectivity.isOffline else { return };if !CatalogModel.fixture { WidgetCenter.shared.reloadTimelines(ofKind:"CortexLatestEpisodes"); WidgetCenter.shared.reloadTimelines(ofKind:"CortexNewReleases");WidgetCenter.shared.reloadTimelines(ofKind:"CortexTrending");WidgetCenter.shared.reloadTimelines(ofKind:"CortexSubtitleRadar") };await catalog.load();if !CatalogModel.fixture { await api.refreshAccount() }
                if !CatalogModel.fixture { SpotlightIndex.refreshIfNeeded(catalog.titles) }

                if CatalogModel.fixture && ProcessInfo.processInfo.arguments.contains("--player-fixture"),let url = Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"mp4") {
                    UserDefaults.standard.removeObject(forKey:"resume.fixture")
                    fixturePlayer = PlaybackRoute(title:"Authored native playback test",url:url,key:"fixture",subtitleURL:Bundle.main.url(forResource:"NativePlaybackFixture",withExtension:"vtt"),episodeLabel:"Native playback test")
                }
            }
            .onChange(of:scenePhase) { _,phase in if phase == .active { downloads.kick();Task { await AlertCenter.shared.check(notify: true);await AlertCenter.shared.checkSubtitles(notify: true) } };if phase == .active && !connectivity.isOffline && !CatalogModel.fixture && (catalog.updated.map { Date().timeIntervalSince($0)>300 } ?? true) { Task { await catalog.load() } } }
            .onChange(of:offlineMode) { _,offline in
                if offline { selectTab(0) }
                else { downloads.kick();Task { await catalog.load() } }
            }
            .overlay(alignment:.top) {
                #if DEBUG
                if let nativeQAError { Text("Native HU QA: "+nativeQAError).font(.caption).padding().background(Color.cortexBlack).accessibilityIdentifier("qa.error") }
                #endif
            }
            .onOpenURL { open($0) }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let id = SpotlightIndex.animeID(from: raw), id > 0 else { return }
                link = NativeLink(animeID: id)
            }
            .task {
                AlertCenter.shared.configure()
                // QA and fixture launches pass --flags; a onboarding cover must never sit
                // in front of them or the UI tests cannot reach the screens they check.
                let isQALaunch = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--") }
                if !isQALaunch, !UserDefaults.standard.bool(forKey: WhatsNew.key) { showWhatsNew = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cortexShowWhatsNew)) { _ in showWhatsNew = true }
            .fullScreenCover(isPresented: $showWhatsNew) { WhatsNewView { showWhatsNew = false } }
            .overlay { if booting { CortexBootAnimation(onDone:finishBoot).transition(.opacity).zIndex(20) } }
            .sheet(isPresented:$showDownloadLibrary) { NavigationStack { NativeDownloads().toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { showDownloadLibrary = false } } } } }
            .sheet(item:$link) { target in NavigationStack { NativeLinkedDetail(id:target.animeID) }.id(target.id).environmentObject(catalog).environmentObject(api) }
            .fullScreenCover(item:$fixturePlayer) { PlayerScreen(route:$0) }
    }
    @ViewBuilder private func tabContent(_ index: Int) -> some View {
        switch index {
        case 0: NavigationStack { if offlineMode { NativeDownloads().safeAreaInset(edge:.top) { Text("Offline library · Saved episodes").font(.caption).padding(8).background(Color.cortexBlack).accessibilityIdentifier("offline.banner") } } else { NativeHome() } }
        case 1: NavigationStack { NativeBrowse(mode:.search) }
        case 2: NavigationStack { NativeBrowse(mode:.hungarian) }
        case 3: NavigationStack { NativeBrowse(mode:.seasonal) }
        default: NavigationStack { NativeProfile() }
        }
    }
    private var tabBar: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width,620)
            let margin = (geometry.size.width-width)/2
            let cell = max(0,(width-16)/5)
            let progress = navigationDrag.map { NativeGesturePolicy.tabProgress(x:Double($0-margin),width:Double(width),count:5) } ?? Double(tab)
            let preview = Int(progress.rounded())
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:14,style:.continuous)
                    .fill(LinearGradient(colors:[Color.cortexPurple.opacity(0.24),Color.cortexPurple.opacity(0.10)],startPoint:.topLeading,endPoint:.bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(LinearGradient(colors:[Color.cortexPurple.opacity(0.55),Color.cortexPurple.opacity(0.16)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
                    .frame(width:max(0,cell-8),height:46)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : (progress-progress.rounded())*24),axis:(x:0,y:1,z:0),perspective:0.5)
                    .shadow(color:Color.cortexPurple.opacity(reduceMotion ? 0 : 0.30),radius:10,y:3)
                    .offset(x:margin+12+CGFloat(progress)*cell,y:7)
                    .animation(reduceMotion || navigationDrag != nil ? nil : .spring(response:0.30,dampingFraction:0.82),value:progress)
                    .allowsHitTesting(false).accessibilityHidden(true)
                HStack(spacing:0) {
                    tabButton(0,"Home","house",selectedIcon:"house.fill",preview:preview)
                    tabButton(1,"Search","magnifyingglass",preview:preview)
                    tabButton(2,"HU Subs","bookmark",selectedIcon:"bookmark.fill",preview:preview)
                    tabButton(3,"Seasonal","film",selectedIcon:"film.fill",preview:preview)
                    tabButton(4,"Profile","person",selectedIcon:"person.fill",preview:preview)
                }.padding(.horizontal,8).frame(width:width).offset(x:margin)
            }
            .frame(width:geometry.size.width,height:60)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance:12)
                .updating($navigationDrag) { value,state,_ in
                    if abs(value.translation.width) > abs(value.translation.height)*1.2 { state = value.location.x }
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height)*1.2 else { return }
                    selectTab(NativeGesturePolicy.tabIndex(x:Double(value.location.x-margin),width:Double(width),count:5))
                })
        }
        .frame(height:60)
        .frame(maxWidth:.infinity)
        .background { LinearGradient(colors:[Color.cortexPanel,Color.cortexBlack],startPoint:.top,endPoint:.bottom).ignoresSafeArea(edges:.bottom) }
        .overlay(alignment:.top) {
            LinearGradient(colors:[.clear,Color.cortexPurple.opacity(0.55),Color.cyan.opacity(0.30),.clear],startPoint:.leading,endPoint:.trailing)
                .frame(height:1.5).accessibilityHidden(true)
        }
        .accessibilityElement(children:.contain)
        .accessibilityIdentifier("navigation.bottom")
        .sensoryFeedback(.selection,trigger:tab)
    }
    private func selectTab(_ value: Int) { visitedTabs.insert(value);tab = value }
    private func finishBoot() { guard booting else { return };withAnimation(.easeOut(duration:0.3)) { booting = false } }
    private func tabButton(_ value: Int,_ name: String,_ icon: String,selectedIcon: String? = nil,preview: Int) -> some View {
        let highlighted = preview == value
        return Button { selectTab(value) } label: {
            VStack(spacing:4) {
                Image(systemName:highlighted ? selectedIcon ?? icon : icon)
                    .font(.system(size:20,weight:.semibold))
                    .frame(height:23)
                    .shadow(color:highlighted ? Color.cortexPurple.opacity(0.9) : .clear,radius:7)
                Text(name).font(.system(size:10,weight:highlighted ? .bold : .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .frame(maxWidth:.infinity,minHeight:60)
            .foregroundStyle(highlighted ? Color.cortexPurple : Color.white.opacity(0.55))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(tab == value ? .isSelected : [])
        .accessibilityIdentifier("tab.\(value)")
    }
    private func open(_ url: URL) {
        guard ["https",CortexNativeAddress.scheme].contains(url.scheme ?? "") else { return }
        if url.scheme == "https" && (url.host != "cortanime.eu" || url.user != nil || url.password != nil) { return }
        if url.scheme == CortexNativeAddress.scheme,url.host == "downloads" { showDownloadLibrary = true;return }
        if url.scheme == CortexNativeAddress.scheme,url.host == "home" { link = nil;selectTab(0);return }
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == CortexNativeAddress.scheme,let host = url.host { parts.insert(host,at:0) }
        if parts.count >= 2,["anime","watch"].contains(parts[0]),let id = Int(parts[1]),id > 0 { link = NativeLink(animeID:id) }
    }
}
struct NativeLinkedDetail: View {
    let id: Int
    @EnvironmentObject private var catalog: CatalogModel
    @State private var anime: Anime?
    @State private var error: String?
    var body: some View { Group { if let anime { NativeDetail(seed:anime) } else if let error { NativeError(text:error) { Task { await load() } }.padding() } else { ProgressView("Loading anime…") } }.task(id:id) { await load() } }
    private func load() async { error = nil;do { let result = try await catalog.detail(id);try Task.checkCancellation();anime = result } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}
