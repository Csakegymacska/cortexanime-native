import SwiftUI

struct NativeDetail: View {
    let seed: Anime
    var resumeEpisode: Int = 1
    @EnvironmentObject private var catalog: CatalogModel
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var downloads: Downloads
    @ObservedObject private var library = AnimeLibrary.shared
    @ObservedObject private var credits = CreditStore.shared
    @ObservedObject private var alerts = AlertCenter.shared
    @State private var fresh: Anime?
    @State private var language = "hun"
    @State private var route: PlaybackRoute?
    @State private var source: StreamInfo?
    @State private var episode = 1
    @State private var jump = ""
    @State private var error: String?
    @State private var retry: (() -> Void)?
    @State private var busy = false
    @State private var resolveTask: Task<Void,Never>?
    @State private var fullSynopsis = false
    @State private var showDownloads = false
    private var anime: Anime { fresh ?? seed }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:23) {
                detailHero
                HStack(spacing:10) {
                    PrimaryButton(title:busy ? "Finding source…" : "Watch Now") { play(episode) }.disabled(busy || anime.episodeLimit(language:language) == 0)
                    Button { Task { await toggleWatchlist() } } label: { Image(systemName:library.favorites.contains(anime.id) ? "checkmark" : "plus").font(.title2).frame(width:52,height:52).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:18)) }.accessibilityLabel("Toggle watchlist")
                    Button { alerts.toggle(anime) } label: { Image(systemName:alerts.isFollowing(anime.id) ? "bell.fill" : "bell").font(.title2).frame(width:52,height:52).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:18)).foregroundStyle(alerts.isFollowing(anime.id) ? Color.cortexPurple : .white) }.accessibilityLabel(alerts.isFollowing(anime.id) ? "Stop episode alerts" : "Get episode alerts").accessibilityIdentifier("detail.alerts")
                    if let share = URL(string: "https://cortanime.eu/anime/\(anime.id)") {
                        ShareLink(item: share) {
                            Image(systemName: "square.and.arrow.up").font(.title2).frame(width:52,height:52)
                                .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:18))
                        }
                        .accessibilityLabel("Share series")
                        .accessibilityIdentifier("detail.share")
                    }
                }
                Button { showDownloads = true } label: {
                    HStack { Image(systemName:"arrow.down.circle.fill").font(.title2);VStack(alignment:.leading,spacing:3) { Text("Download").font(.headline);Text("Episode or full season · Offline on this device").font(.caption).foregroundStyle(.secondary) };Spacer();Image(systemName:"chevron.right").font(.caption.bold()) }.padding(14).frame(minHeight:58).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color.cortexPurple.opacity(0.35)))
                }.buttonStyle(.plain).tint(Color.cortexPurple).disabled(anime.episodeLimit(language:language) == 0).accessibilityIdentifier("detail.download")
                summary
                if let error { NativeError(text:error) { retry?() } }
                if !anime.plainSynopsis.isEmpty { VStack(alignment:.leading,spacing:10) { SectionHeading(title:"Synopsis");Text(anime.plainSynopsis).font(.subheadline).foregroundStyle(.white.opacity(0.6)).lineSpacing(5).lineLimit(fullSynopsis ? nil : 5);Button(fullSynopsis ? "Less" : "More") { fullSynopsis.toggle() }.font(.caption.bold()).frame(minHeight:44) } }
                Picker("Subtitle language",selection:$language) { Text("Hungarian").tag("hun");Text("English").tag("eng");Text("French").tag("fra") }.pickerStyle(.segmented)
                episodes

                NativeDetailExtras(id:anime.id)
                NativeComments(animeID:anime.id)
            }.padding(16).padding(.bottom,20)
        }.background(Color.cortexBlack).navigationBarTitleDisplayMode(.inline).navigationTitle("Anime")
            .toolbarBackground(Color.cortexBlack,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
            .task { episode = resumeEpisode;await refresh() }
            .onDisappear { resolveTask?.cancel() }
            .handOffPlayerRoute($route)
            .sheet(isPresented:$showDownloads) { NativeDownloadOptions(anime:anime,initialEpisode:episode,language:$language) }
    }
    private var detailHero: some View {
        ZStack(alignment:.bottomLeading) {
            AnimeArtwork(url:anime.banner ?? anime.cover);LinearGradient(colors:[.clear,Color.cortexBlack],startPoint:.top,endPoint:.bottom)
            HStack(alignment:.bottom,spacing:14) {
                AnimeArtwork(url:anime.cover).frame(width:88,height:130).clipShape(RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color.cortexPurple.opacity(0.4),lineWidth:1))
                VStack(alignment:.leading,spacing:9) { Text(anime.title).font(.system(size:23,weight:.black)).lineLimit(4);HStack(spacing:5) { if let score = anime.score { Pill(text:String(format:"%.1f",score),color:.yellow) };if let year = anime.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) };Text(anime.status == "RELEASING" ? "Airing" : anime.status.capitalized).font(.caption.bold()).foregroundStyle(.green) } }
            }.padding(12)
        }.frame(minHeight:290,alignment:.bottom).clipShape(RoundedRectangle(cornerRadius:23))
    }
    private var summary: some View {
        HStack(spacing:9) {
            stat("EPISODES",anime.availableEpisodes.map { anime.episodes > 0 ? "\($0) / \(anime.episodes)" : String($0) } ?? "Unknown","tv")
                .accessibilityIdentifier("detail.episodeSummary")
            stat("STATUS",anime.status == "RELEASING" ? "Airing" : anime.status.capitalized,"clock")
            stat("SEASON",anime.year.map(String.init) ?? "—","calendar")
        }
    }
    private func stat(_ title: String,_ value: String,_ icon: String) -> some View { VStack(spacing:7) { Image(systemName:icon).foregroundStyle(.white.opacity(0.4));Text(title).font(.system(size:9)).foregroundStyle(.white.opacity(0.4));Text(value).font(.system(size:13,weight:.bold)).lineLimit(1).minimumScaleFactor(0.7) }.frame(maxWidth:.infinity,minHeight:85).padding(6).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:19)) }
    private var episodes: some View {
        VStack(alignment:.leading,spacing:13) {
            HStack {
                SectionHeading(title:"Episodes")
                if let latest = anime.availableEpisodes, latest > 0 {
                    if let next = nextUnwatched(upTo: latest), next < latest {
                        Button("Continue: EP \(next)") { play(next) }
                            .font(.caption.bold()).frame(minHeight:44)
                            .accessibilityIdentifier("detail.continue")
                    }
                    Button("Latest: EP \(latest)") { play(latest) }.font(.caption.bold()).frame(minHeight:44).accessibilityIdentifier("detail.latest")
                }
            }
            if let available = anime.availableEpisodes,available > 0 {
                HStack { TextField("EP 1–\(available)",text:$jump).keyboardType(.numberPad).textFieldStyle(.roundedBorder);Button("Jump") { if let ep = Int(jump),ep > 0,ep <= available { play(ep) } else { error = "Choose an episode from 1 to \(available)." } }.frame(minHeight:44) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:12)],spacing:12) { ForEach(1...available,id:\.self) { ep in
                    Button { play(ep) } label: { VStack(alignment:.leading,spacing:8) {
                        AnimeArtwork(url:anime.cover).frame(height:88).clipShape(RoundedRectangle(cornerRadius:11))
                            .overlay(alignment:.bottomTrailing) { Text("EP \(ep)").font(.caption2.bold()).padding(5).background(.black.opacity(0.8),in:Capsule()).padding(5) }
                            .overlay(alignment:.topLeading) {
                                if credits.hasCompleted(animeID: anime.id, episode: ep) {
                                    Image(systemName:"checkmark.circle.fill").font(.system(size:16,weight:.bold))
                                        .foregroundStyle(Color.cortexPurple).padding(5)
                                        .background(.black.opacity(0.55),in:Circle()).padding(5)
                                }
                            }
                        Text("Episode \(ep)").font(.caption.bold())
                            .foregroundStyle(credits.hasCompleted(animeID: anime.id, episode: ep) ? Color.white.opacity(0.55) : Color.white)
                    }.padding(7).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15)) }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("episode.\(ep)").contextMenu { Button("Download episode") { episode = ep;showDownloads = true } }
                } }
            } else { NativeEmpty(title:anime.availableEpisodes == 0 ? "No released episodes yet" : "Episode count unavailable",detail:"Refresh current metadata before choosing an episode.",icon:"calendar") }
        }
    }
    /// First episode that is still unfinished, so "Continue" always resumes where the
    /// viewer actually stopped instead of jumping to the newest episode.
    private func nextUnwatched(upTo limit: Int) -> Int? {
        for ep in 1...max(1, limit) where !credits.hasCompleted(animeID: anime.id, episode: ep) { return ep }
        return nil
    }
    private func refresh() async { do { fresh = try await catalog.detail(seed.id,cached:seed);error = nil;retry = nil } catch { if !(error is CancellationError),!Task.isCancelled { fail("Showing saved series information. " + error.localizedDescription) { Task { await refresh() } } } } }
    /// One error surface, and Retry repeats exactly what failed.
    private func fail(_ message: String,again action: (() -> Void)?) { error = message;retry = action }
    private func play(_ ep: Int) {
        guard !busy,ep > 0,ep <= anime.episodeLimit(language:language) else { return };busy = true;error = nil;retry = nil;episode = ep
        resolveTask?.cancel()
        resolveTask = Task { defer { busy = false };do { let info = try await catalog.resolve(anime,episode:ep,language:language);try Task.checkCancellation();source = info;route = try catalog.route(for:anime,episode:ep,language:language,info:info) } catch is CancellationError {} catch { if !Task.isCancelled { let message = error.localizedDescription;fail(message) { play(ep) } } } }
    }
    private func toggleWatchlist() async { do { if api.signedIn { if library.favorites.contains(anime.id) { _ = try await api.json("/api/watchlist",method:"DELETE",query:["animeId":String(anime.id)]) } else { _ = try await api.json("/api/watchlist",method:"POST",body:["animeId":anime.id,"title":anime.title,"cover":anime.cover?.absoluteString ?? ""]) } };library.toggle(anime.id) } catch { if !(error is CancellationError),!Task.isCancelled { let message = error.localizedDescription;fail(message) { Task { await toggleWatchlist() } } } } }

}

struct NativeComment: Identifiable { let id: Int;let author: String;let text: String;let userID: Int
    init?(_ r: [String:Any]) { guard let id = r["id"] as? Int else { return nil };self.id = id;author = r["username"] as? String ?? "User";text = r["text"] as? String ?? "";userID = r["userId"] as? Int ?? 0 }
}
struct NativeComments: View {
    let animeID: Int
    @EnvironmentObject private var api: APIClient
    @State private var comments: [NativeComment] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View { VStack(alignment:.leading,spacing:12) { SectionHeading(title:"Comments");if api.signedIn { HStack { TextField("Write a comment",text:$draft,axis:.vertical).lineLimit(1...4);Button("Send") { Task { await send() } }.frame(minHeight:44).disabled(busy || draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) } };if let error { ErrorNotice(text:error) };ForEach(comments) { c in VStack(alignment:.leading,spacing:6) { HStack { Text(c.author).font(.caption.bold()).foregroundStyle(Color.cortexPurple);Spacer();if api.user?.id == c.userID { Button("Delete",role:.destructive) { Task { await remove(c) } }.font(.caption).frame(minHeight:44) } };Text(c.text).font(.subheadline) }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:13)) };if comments.isEmpty { Text("No comments yet.").font(.caption).foregroundStyle(.secondary) } }.task { if !CatalogModel.fixture { await load() } } }
    private func load() async { do { let r = try await api.json("/api/comments",query:["animeId":String(animeID)]);comments = (r["comments"] as? [[String:Any]] ?? []).compactMap(NativeComment.init);error = nil } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
    private func send() async { busy = true;defer { busy = false };do { _ = try await api.json("/api/comments",method:"POST",body:["animeId":animeID,"text":String(draft.prefix(500))]);draft = "";await load() } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
    private func remove(_ c: NativeComment) async { do { _ = try await api.json("/api/comments",method:"DELETE",query:["id":String(c.id)]);await load() } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}
