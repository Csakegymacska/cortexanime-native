import SwiftUI

struct NativeHome: View {
    @Environment(\.cortexLayoutMode) private var layoutMode
    @EnvironmentObject private var catalog: CatalogModel
    @ObservedObject private var library = AnimeLibrary.shared
    @StateObject private var releases = ReleaseFeed.shared
    @StateObject private var subtitles = SubtitleFeed.shared
    @ObservedObject private var alertSettings = SubtitleAlertSettings.shared
    @ObservedObject private var alerts = AlertCenter.shared
    @State private var slide = 0
    @State private var heroInteracting = false
    @ObservedObject private var home8 = HomeLayout8.shared
    @ObservedObject private var studio = Studio8.shared
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                CortexHeader()
                SubtitleRadarBanner(drop: subtitles.latest,
                                    counts: (subtitles.count(language: .hungarian), subtitles.count(language: .english)),
                                    settingsSummary: alertSettings.enabled ? "Alerts on" : "Alerts off")
                    .accessibilityIdentifier("home.radarbanner")
                if CatalogModel.fixture { Pill(text:"Recorded metadata · UI test fixture",color:.orange) }
                if catalog.backupMetadata { Pill(text:"Backup catalog · Live airing counts may be unavailable",color:.orange).accessibilityIdentifier("home.metadataBackup") }
                if catalog.savedData { Pill(text:"Saved metadata · Pull to refresh",color:.orange) }
                if let anime = catalog.trending.isEmpty ? nil : catalog.trending[min(slide,catalog.trending.count-1)] {
                    NativeHero(anime:anime,slide:$slide,count:min(6,catalog.trending.count),interacting:$heroInteracting)
                } else if catalog.loading { ProgressView("Loading current anime…").frame(maxWidth:.infinity,minHeight:320) }
                if let error = catalog.error { NativeError(text:error) { Task { await catalog.load() } } }
                orderedShelves
                genreLinks
                SurpriseMe8Button()
                Text(catalog.updated.map { "Source: " + catalog.metadataSource + " · Updated " + $0.formatted(date:.abbreviated,time:.shortened) } ?? "Live metadata with an automatic backup catalog.").font(.caption2).foregroundStyle(.white.opacity(0.4)).accessibilityIdentifier("home.metadataSource")
                HStack { NavigationLink("FAQ") { NativeInformation(kind:.faq) };Spacer();NavigationLink("Privacy") { NativeInformation(kind:.privacy) };Spacer();NavigationLink("DMCA") { NativeInformation(kind:.dmca) } }.font(.caption).padding(.vertical,12)
            }
            // 6.4: on a wide phone (unfolded foldable, landscape iPhone) the column is capped and
            // centred, so shelves do not stretch across a 900 pt screen and the hero keeps its shape.
            .frame(maxWidth: layoutMode == .widePhone ? 860 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, layoutMode == .widePhone ? 22 : 16)
            .padding(.bottom,25)
        }.background(Color.cortexBlack).toolbar(.hidden,for:.navigationBar).refreshable { await catalog.load(); await releases.load(force:true);await subtitles.load(force:true) }
            .task { await releases.load();await subtitles.load() }
            .task(id:catalog.trending.count) { slide = min(slide,max(0,min(6,catalog.trending.count)-1));guard catalog.trending.count > 1 else { return };while !Task.isCancelled { do { try await Task.sleep(for:.seconds(10)) } catch { return };if !heroInteracting { slide = (slide+1)%min(6,catalog.trending.count) } } }
    }
    /// 8.0: the shelves are rendered from the user's own order (Profile → Home layout).
    @ViewBuilder private var orderedShelves: some View {
        ForEach(home8.order) { section in
            if home8.shows(section) { shelf(section) }
        }
    }

    @ViewBuilder private func shelf(_ section: HomeSection8) -> some View {
        switch section {
        case .quick:
            quickActions
        case .continueWatching:
            if !library.history.isEmpty && !studio.hideActivity { continueWatching }
        case .releases:
            if !releases.items.isEmpty { ReleaseShelf(items: releases.items) }
        case .subtitles:
            if !subtitles.drops.isEmpty {
                SubtitleDropShelf(title:"Subtitle radar", drops: subtitles.drops, limit: 16, trailing:"HU + EN")
                    .accessibilityIdentifier("home.subtitles")
            }
        case .trending:
            if !catalog.trending.isEmpty { trending }
        case .seasonal:
            if !catalog.seasonal.isEmpty {
                AnimeShelf(title:catalog.backupMetadata ? "Started this quarter" : "This season",items:catalog.seasonal)
            }
        case .radar:
            if !radarPicks.isEmpty { radarShelf }
        case .hungarian:
            if !catalog.titles.isEmpty { AnimeShelf(title:"Hungarian subtitles",items:Array(catalog.titles.prefix(15))) }
        }
    }

    /// 5.0 entry points: the personal radar and the episode alert centre.
    private var quickActions: some View {
        // 6.4: three tiles side by side get cramped at 390 pt, but on a wide phone they can breathe;
        // an adaptive grid picks 1, 3 or 4 columns without a second code path.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: layoutMode == .widePhone ? 190 : 118), spacing: 10)],
                  alignment: .leading, spacing: 10) {
            NavigationLink { NativeRadar() } label: {
                HStack(spacing: 8) {
                    Image(systemName:"sparkles").foregroundStyle(Color.cortexPurple)
                    VStack(alignment:.leading,spacing:1) { Text("For You").font(.caption.bold());Text("Picked from your taste").font(.system(size:9)).foregroundStyle(.white.opacity(0.45)) }
                    Spacer(minLength:0)
                }
                .padding(11).frame(maxWidth:.infinity,minHeight:52)
                .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15))
                .overlay(RoundedRectangle(cornerRadius:15).stroke(Color.cortexPurple.opacity(0.28)))
            }.cortexPress3D().accessibilityIdentifier("home.radar")
            NavigationLink { NativeAlerts() } label: {
                HStack(spacing: 8) {
                    Image(systemName:"bell.badge").foregroundStyle(Color.cortexPurple)
                    VStack(alignment:.leading,spacing:1) { Text("Alerts").font(.caption.bold());Text(alerts.follows.isEmpty ? "Follow a series" : "\(alerts.follows.count) followed").font(.system(size:9)).foregroundStyle(.white.opacity(0.45)) }
                    Spacer(minLength:0)
                }
                .padding(11).frame(maxWidth:.infinity,minHeight:52)
                .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15))
            }.cortexPress3D().accessibilityIdentifier("home.alerts")
            NavigationLink { NativeSubtitleRadar() } label: {
                HStack(spacing: 8) {
                    Image(systemName:"captions.bubble").foregroundStyle(SubtitleLanguage.hungarian.color)
                    VStack(alignment:.leading,spacing:1) { Text("Subtitles").font(.caption.bold());Text(subtitles.latest.map { $0.language.badge + " · " + $0.ageText } ?? "HU + EN").font(.system(size:9)).foregroundStyle(.white.opacity(0.45)) }
                    Spacer(minLength:0)
                }
                .padding(11).frame(maxWidth:.infinity,minHeight:52)
                .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15))
            }.cortexPress3D().accessibilityIdentifier("home.subradar")
        }.foregroundStyle(.white)
    }

    private var radarPicks: [RadarSuggestion] {
        guard !catalog.titles.isEmpty else { return [] }
        let picks = RadarEngine.suggestions(pool: catalog.titles, history: library.history, favorites: library.favorites, limit: 12)
        return picks.count >= 4 ? picks : []
    }

    private var radarShelf: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { SectionHeading(title:"For you");Pill(text:"On-device") }
            ScrollView(.horizontal,showsIndicators:false) {
                LazyHStack(alignment:.top,spacing:12) {
                    ForEach(radarPicks) { pick in
                        NavigationLink { NativeDetail(seed:pick.anime) } label: {
                            VStack(alignment:.leading,spacing:7) {
                                AnimeArtwork(url:pick.anime.cover).frame(width:136,height:200).clipShape(RoundedRectangle(cornerRadius:16))
                                Text(pick.anime.title).font(.system(size:12,weight:.bold)).lineLimit(2).frame(width:136,alignment:.leading)
                                Text(pick.reason).font(.system(size:9,weight:.bold)).foregroundStyle(Color.cortexPurple).lineLimit(1).frame(width:136,alignment:.leading)
                            }.foregroundStyle(.white)
                        }.buttonStyle(.plain)
                            .cortexShelfTilt()
                            .accessibilityLabel("\(pick.anime.title), \(pick.reason)")
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }

    private var genreLinks: some View {
        ScrollView(.horizontal,showsIndicators:false) { HStack(spacing:9) { ForEach(["Action","Fantasy","Romance","Comedy","Ecchi"],id:\.self) { genre in NavigationLink { NativeBrowse(mode:.search,initialGenre:genre) } label: { Text(genre).font(.caption.bold()).padding(.horizontal,16).frame(minHeight:44).background(.white.opacity(0.05),in:Capsule()).overlay(Capsule().stroke(.white.opacity(0.08),lineWidth:1)) }.buttonStyle(.plain) } } }
    }
    private var trending: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack { SectionHeading(title:catalog.backupMetadata ? "Popular now" : "Top 10 Trending");Pill(text:catalog.backupMetadata ? "Kitsu backup" : "AniList") }
            ForEach(Array(catalog.trending.prefix(10).enumerated()),id:\.element.id) { rank,anime in
                NavigationLink { NativeDetail(seed:anime) } label: { NativeTrendingRow(anime:anime,rank:rank) }.buttonStyle(.plain)
            }
        }
    }
    /// Share of the episode already watched, used by the progress bar.
    private func progressFraction(_ record: WatchRecord) -> Double {
        guard record.duration > 0 else { return record.completed ? 1 : 0 }
        return min(1, max(0, record.seconds / record.duration))
    }
    private var continueWatching: some View {
        VStack(alignment:.leading,spacing:12) { SectionHeading(title:"Continue watching");ForEach(library.history.prefix(3)) { record in NavigationLink { NativeDetail(seed:record.anime,resumeEpisode:record.episode) } label: { HStack(spacing:12) { AnimeArtwork(url:record.anime.cover).frame(width:45,height:65).clipShape(RoundedRectangle(cornerRadius:9));VStack(alignment:.leading,spacing:6) {
                            Text(record.anime.title).font(.subheadline.bold()).lineLimit(1)
                            Text("Episode \(record.episode) · \(Int(record.seconds)/60) min watched").font(.caption).foregroundStyle(.secondary)
                            GeometryReader { geo in
                                ZStack(alignment:.leading) {
                                    Capsule().fill(Color.white.opacity(0.10)).frame(height:4)
                                    Capsule().fill(LinearGradient(colors:[Color.cortexPurple,.cyan],startPoint:.leading,endPoint:.trailing))
                                        .frame(width:max(4,geo.size.width*progressFraction(record)),height:4)
                                }
                            }.frame(height:4)
                        };Spacer();Image(systemName:"play.circle.fill").font(.title2).foregroundStyle(Color.cortexPurple) }.padding(12).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:17)) }.buttonStyle(.plain) } }
    }
}
struct NativeHero: View {
    let anime: Anime
    @Binding var slide: Int
    let count: Int
    @Binding var interacting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var motion = MotionSettings.shared
    @GestureState private var horizontalDrag: CGFloat = 0

    /// 0...1 how hard the card is currently being pulled. Eases the depth in instead of snapping.
    private var pull: Double {
        guard !reduceMotion, motion.cardTilt else { return 0 }
        return Double(min(1, abs(horizontalDrag) / 90))
    }
    /// About four degrees at a full-screen swipe. 6.2 tilted the whole card, which read as the
    /// text wobbling; the angle now only drives the artwork layer underneath it.
    private var tiltDegrees: Double {
        guard pull > 0 else { return 0 }
        return Double(max(-120, min(120, horizontalDrag))) / 30
    }
    @Environment(\.cortexLayoutMode) private var layoutMode
    /// Landscape iPhone has roughly 390 pt of height, so a fixed 430 pt card would fill it.
    /// The inner display of a foldable is wide and tall enough for a taller hero than a phone's.
    private var heroHeight: CGFloat {
        if verticalSizeClass == .compact { return 300 }
        // A folded-but-wide window can be narrower than an unfolded one, so the wide layout gives
        // the hero a touch less height; the artwork still fills the card.
        return layoutMode == .widePhone ? 380 : 430
    }

    var body: some View {
        ZStack(alignment:.bottomLeading) {
            // Depth layer: the poster and its gradient move, the type above them stays flat.
            ZStack(alignment:.bottomLeading) {
                AnimeArtwork(url:anime.banner ?? anime.cover)
                    .scaleEffect(1.04)
                    .rotation3DEffect(.degrees(tiltDegrees),axis:(x:0,y:1,z:0),perspective:0.3)
                    .offset(x:horizontalDrag*0.10)
                LinearGradient(colors:[.clear,.black.opacity(0.35),Color.cortexBlack],startPoint:.top,endPoint:.bottom)
                    .rotation3DEffect(.degrees(tiltDegrees*0.35),axis:(x:0,y:1,z:0),perspective:0.3)
            }
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:6) { Pill(text:"CORTEX SPOTLIGHT");if let score = anime.score { Pill(text:String(format:"%.1f",score),color:.yellow) };if let year = anime.year { Pill(text:String(year),color:.white) } }
                Text(anime.title).font(.system(size:27,weight:.black)).lineLimit(3).accessibilityIdentifier("home.hero.title")
                Text(anime.plainSynopsis).font(.system(size:12)).lineLimit(2).foregroundStyle(.white.opacity(0.75))
                HStack(spacing:10) {
                    NavigationLink { NativeDetail(seed:anime) } label: { Label("WATCH NOW",systemImage:"play.fill").font(.system(size:12,weight:.black)).frame(minWidth:142,minHeight:46).background(.white,in:Capsule()).foregroundStyle(.black) }.buttonStyle(.plain).accessibilityIdentifier("home.watch")
                    NavigationLink { NativeDetail(seed:anime) } label: { Label("DETAILS",systemImage:"info.circle").font(.system(size:11,weight:.bold)).frame(minWidth:100,minHeight:46).overlay(Capsule().stroke(.white.opacity(0.25),lineWidth:1)) }.buttonStyle(.plain)
                }
                HStack(spacing:5) { ForEach(0..<max(1,count),id:\.self) { index in Capsule().fill(index == slide ? Color.cortexPurple : Color.white.opacity(0.25)).frame(width:index == slide ? 23 : 7,height:3) } }
            }.padding(20).offset(x:horizontalDrag*0.03)
        }.frame(height:heroHeight).clipShape(RoundedRectangle(cornerRadius:25))
            .overlay(RoundedRectangle(cornerRadius:25).stroke(.white.opacity(0.1),lineWidth:1))
            .shadow(color:.black.opacity(0.30+pull*0.25),radius:16+CGFloat(pull)*14,y:10+CGFloat(pull)*6)
            .overlay(alignment:.topTrailing) { HStack(spacing:6) { Button { slide = (slide-1+max(1,count))%max(1,count) } label: { Image(systemName:"chevron.left").frame(width:44,height:44) };Button { slide = (slide+1)%max(1,count) } label: { Image(systemName:"chevron.right").frame(width:44,height:44) } }.background(.black.opacity(0.45),in:Capsule()).padding(12) }
            .onChange(of:horizontalDrag) { _,value in interacting = value != 0 }
            .onDisappear { interacting = false }
            .simultaneousGesture(DragGesture(minimumDistance:18)
                .updating($horizontalDrag) { value,state,_ in
                    if abs(value.translation.width) > abs(value.translation.height)*1.2 { state = value.translation.width }
                }
                .onEnded { value in
                    let delta = NativeGesturePolicy.pageDelta(horizontal:Double(value.translation.width),vertical:Double(value.translation.height))
                    guard count > 1,delta != 0 else { return }
                    withAnimation(reduceMotion ? nil : .spring(response:0.32,dampingFraction:0.85)) { slide = (slide+delta+count)%count }
                })

    }
}

struct NativeTrendingRow: View {
    let anime: Anime
    let rank: Int
    var body: some View {
        HStack(spacing:12) {
            Text(String(format:"%02d",rank+1)).font(.system(size:30,weight:.black,design:.rounded)).italic().foregroundStyle(rank == 0 ? Color.yellow : Color.cortexPurple).frame(width:43)
            AnimeArtwork(url:anime.banner ?? anime.cover).frame(width:80,height:58).clipShape(RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:5) {
                Text(anime.title).font(.system(size:12,weight:.bold)).lineLimit(2)
                HStack { if let score = anime.score { Text(String(format:"%.1f",score)).foregroundStyle(.yellow) };Text(anime.format ?? "Anime").foregroundStyle(.white.opacity(0.5)) }.font(.caption2)
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.white.opacity(0.4))
        }.padding(10).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:17))
    }
}
