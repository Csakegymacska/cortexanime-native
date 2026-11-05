import SwiftUI
import UIKit

// MARK: - 5.0 shell

/// iPhone keeps the five kept-alive tabs. iPad, Split View and Stage Manager get a real sidebar
/// with a persistent detail column, because a 1024 pt wide tab bar looks like a stretched phone.
struct CortexRoot5: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var layout = LayoutPreferences.shared
    @ObservedObject private var updates = UpdateCenter.shared
    /// 7.6: a lejátszó a gyökéren él, nem a shell alatt — forgatáskor a shell
    /// kicserélődik, a bemutató konténer viszont így nem.
    @StateObject private var player = PlayerPresenter.shared

    private var mode: CortexLayoutMode {
        CortexLayoutPolicy.mode(idiom: UIDevice.current.userInterfaceIdiom,
                                horizontal: sizeClass,
                                forceWide: layout.forceWide)
    }

    var body: some View {
        Group {
            switch mode {
            case .pad: CortexSplitShell()
            case .widePhone: CortexWidePhoneShell()
            case .phone: NativeRoot()
            }
        }
        .environment(\.cortexLayoutMode, mode)
        .safeAreaInset(edge: .top, spacing: 0) {
            UpdateBannerView(center: updates)
        }
        .sheet(isPresented: $updates.showSheet) {
            UpdateSheetView(center: updates)
        }
        .task { await updates.checkIfNeeded() }
        .fullScreenCover(item: $player.route) { PlayerScreen(route: $0) }
    }
}

/// 6.4: the shell for screens that are wide but still a phone — an unfolded foldable iPhone,
/// or any iPhone in landscape. A 74 pt icon rail instead of a sidebar, no extra insets, and the
/// detail column uses the whole remaining width. Nothing here is a shrunk iPad: type sizes,
/// paddings and the tab-free navigation follow the phone, only the anatomy changes.
struct CortexWidePhoneShell: View {
    @EnvironmentObject private var catalog: CatalogModel
    @EnvironmentObject private var api: APIClient
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var alerts = AlertCenter.shared
    @State private var selection: CortexSection = .home
    @State private var link: NativeLink?
    @State private var showWhatsNew = false
    @State private var booting = CortexBootGate.shouldPlay

    var body: some View {
        HStack(spacing: 0) {
            rail
            NavigationStack {
                detail
                    .background(Color.cortexBlack)
                    .navigationTitle(selection.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Color.cortexBlack, for: .navigationBar)
            }
            .tint(Color.cortexPurple)
        }
        .background(Color.cortexBlack)
        .overlay { if booting { CortexBootAnimation(onDone: finishBoot).transition(.opacity).zIndex(20) } }
        .sheet(item: $link) { target in
            NavigationStack { NativeLinkedDetail(id: target.animeID) }
                .id(target.id)
                .environmentObject(catalog)
                .environmentObject(api)
        }
        .fullScreenCover(isPresented: $showWhatsNew) { WhatsNewView { showWhatsNew = false } }
        .task {
            let isQALaunch = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--") }
            if !isQALaunch, !UserDefaults.standard.bool(forKey: WhatsNew.key) { showWhatsNew = true }
            await catalog.load()
            await alerts.loadAuthorization()
            await alerts.checkSubtitles(notify: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !catalog.titles.isEmpty { Task { await alerts.checkSubtitles(notify: true) } }
        }
        .onChange(of: alerts.pendingLink) { _, value in
            guard let value, let id = CortexSectionLink.animeID(from: value) else { return }
            link = NativeLink(animeID: id)
            alerts.pendingLink = nil
        }
        .onOpenURL { url in
            if let id = CortexSectionLink.animeID(from: url) { link = NativeLink(animeID: id) }
            if url.absoluteString.hasSuffix("://home") { selection = .home }
        }
    }

    /// Icon + caption rail. 44 pt targets, scrollable so a short landscape screen still reaches
    /// Downloads and Profile, and it never competes with the content for height.
    private var rail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                Image("CortexLogo").resizable().scaledToFit().frame(width: 26, height: 26)
                    .clipShape(Circle()).padding(.vertical, 6)
                ForEach(CortexSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selection = section }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: section.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .symbolEffect(.bounce, value: selection == section)
                            Text(section.rawValue)
                                .font(.system(size: 8.5, weight: .heavy))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(width: 64, height: 50)
                        .foregroundStyle(selection == section ? Color.white : Color.white.opacity(0.52))
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(LinearGradient(colors: [Color.cortexPurple.opacity(0.85),
                                                                  Color.cortexPurple.opacity(0.42)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(.white).frame(width: 3, height: 18).offset(x: -1)
                                    }
                                    .shadow(color: Color.cortexPurple.opacity(0.55), radius: 8, y: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rail.\(section.rawValue)")
                }
                Button { showWhatsNew = true } label: {
                    Image(systemName: "gift.fill").font(.system(size: 16, weight: .semibold))
                        .frame(width: 64, height: 46).foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rail.whatsNew")
            }
            .padding(.vertical, 8)
        }
        .frame(width: 74)
        .background(Color.cortexPanel.opacity(0.55))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
        .accessibilityIdentifier("rail.container")
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .home: NativeHome()
        case .radar: NativeRadar()
        case .search: NativeBrowse(mode: .search)
        case .hungarian: NativeBrowse(mode: .hungarian)
        case .seasonal: NativeBrowse(mode: .seasonal)
        case .subtitles: NativeSubtitleRadar()
        case .alerts: NativeAlerts()
        case .downloads: NativeDownloads()
        case .profile: NativeProfile()
        }
    }

    private func finishBoot() {
        guard booting else { return }
        withAnimation(.easeOut(duration: 0.3)) { booting = false }
    }
}

enum CortexSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case radar = "For You"
    case search = "Search"
    case hungarian = "HU Subs"
    case seasonal = "Seasonal"
    case subtitles = "Subtitles"
    case alerts = "Alerts"
    case downloads = "Downloads"
    case profile = "Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .radar: return "sparkles"
        case .search: return "magnifyingglass"
        case .hungarian: return "bookmark.fill"
        case .seasonal: return "film.fill"
        case .subtitles: return "captions.bubble.fill"
        case .alerts: return "bell.badge.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .profile: return "person.fill"
        }
    }

    static let browsing: [CortexSection] = [.home, .radar, .search, .hungarian, .seasonal]
    static let library: [CortexSection] = [.subtitles, .alerts, .downloads, .profile]
}

struct CortexSplitShell: View {
    @EnvironmentObject private var catalog: CatalogModel
    @EnvironmentObject private var api: APIClient
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var alerts = AlertCenter.shared
    @State private var selection: CortexSection? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var link: NativeLink?
    @State private var showWhatsNew = false
    @State private var booting = CortexBootGate.shouldPlay

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationTitle("CortexAnime")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.cortexBlack, for: .navigationBar)
        } detail: {
            NavigationStack {
                detail
                    .background(Color.cortexBlack)
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 720)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color.cortexPurple)
        .overlay { if booting { CortexBootAnimation(onDone: finishBoot).transition(.opacity).zIndex(20) } }
        .sheet(item: $link) { target in
            NavigationStack { NativeLinkedDetail(id: target.animeID) }
                .id(target.id)
                .environmentObject(catalog)
                .environmentObject(api)
        }
        .fullScreenCover(isPresented: $showWhatsNew) { WhatsNewView { showWhatsNew = false } }
        .task {
            let isQALaunch = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--") }
            if !isQALaunch, !UserDefaults.standard.bool(forKey: WhatsNew.key) { showWhatsNew = true }
            await catalog.load()
            await alerts.loadAuthorization()
            await alerts.check(notify: true)
            await alerts.checkSubtitles(notify: true)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !catalog.titles.isEmpty {
                Task { await alerts.check(notify: true);await alerts.checkSubtitles(notify: true) }
            }
        }
        .onChange(of: alerts.pendingLink) { _, value in
            guard let value, let id = CortexSectionLink.animeID(from: value) else { return }
            link = NativeLink(animeID: id)
            alerts.pendingLink = nil
        }
        .onOpenURL { url in
            if let id = CortexSectionLink.animeID(from: url) { link = NativeLink(animeID: id) }
            if url.absoluteString.hasSuffix("://home") { selection = .home }
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Browse") {
                ForEach(CortexSection.browsing) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                        .accessibilityIdentifier("sidebar.\(section.rawValue)")
                }
            }
            Section("Your library") {
                ForEach(CortexSection.library) { section in
                    Label {
                        HStack {
                            Text(section.rawValue)
                            Spacer()
                            if section == .alerts && !alerts.follows.isEmpty {
                                Text("\(alerts.follows.count)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Color.cortexPurple.opacity(0.25), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: section.icon)
                    }
                    .tag(section)
                    .accessibilityIdentifier("sidebar.\(section.rawValue)")
                }
            }
            Section {
                Button {
                    showWhatsNew = true
                } label: {
                    Label("What's new in \(WhatsNew.version)", systemImage: "gift.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.whatsNew")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack)
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .home {
        case .home: NativeHome()
        case .radar: NativeRadar()
        case .search: NativeBrowse(mode: .search)
        case .hungarian: NativeBrowse(mode: .hungarian)
        case .seasonal: NativeBrowse(mode: .seasonal)
        case .subtitles: NativeSubtitleRadar()
        case .alerts: NativeAlerts()
        case .downloads: NativeDownloads()
        case .profile: NativeProfile()
        }
    }

    private func finishBoot() {
        guard booting else { return }
        withAnimation(.easeOut(duration: 0.3)) { booting = false }
    }
}

enum CortexSectionLink {
    /// Accepts cortexanime-native-port://anime/<id>, https://cortanime.eu/anime/<id> and /watch/<id>/<ep>.
    static func animeID(from url: URL) -> Int? {
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == CortexNativeAddress.scheme, let host = url.host { parts.insert(host, at: 0) }
        if url.scheme == "https", url.host != "cortanime.eu" { return nil }
        guard parts.count >= 2, ["anime", "watch"].contains(parts[0]), let id = Int(parts[1]), id > 0 else { return nil }
        return id
    }
}
