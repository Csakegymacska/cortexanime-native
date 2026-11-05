import SwiftUI

func watchlistAnime(_ row: [String:Any]) -> Anime? { var json = row;json["id"] = row["animeId"] ?? row["anilist_id"] ?? row["anime_id"];return Anime(json:json) }
struct NativeWatchlist: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var catalog: CatalogModel
    @ObservedObject private var library = AnimeLibrary.shared
    @State private var items: [Anime] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View { ScrollView { VStack(spacing:16) { if !api.signedIn { Text("Local watchlist · Sign in for account sync").font(.caption).foregroundStyle(.secondary) };if let error { NativeError(text:error) { Task { await load() } } };if loading { ProgressView() };AnimeGrid(items:items);if items.isEmpty && !loading { NativeEmpty(title:"Your watchlist is empty",detail:"Use + on an anime's detail page.",icon:"bookmark") } }.padding(16) }.background(Color.cortexBlack).navigationTitle("Watchlist").task { await load() }.refreshable { await load() } }
    private func load() async { loading = true;defer { loading = false };do { if api.signedIn { let row = try await api.json("/api/watchlist");items = (row["items"] as? [[String:Any]] ?? []).compactMap(watchlistAnime);library.mergeFavorites(Set(items.map(\.id))) } else { let known = catalog.titles+catalog.trending+catalog.seasonal+library.history.map(\.anime);var ids = Set<Int>();items = known.filter { library.favorites.contains($0.id) && ids.insert($0.id).inserted };for id in library.favorites where !ids.contains(id) { if let item = try? await catalog.detail(id) { items.append(item) } } };error = nil } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}
struct NativeHistory: View {
    @ObservedObject private var library = AnimeLibrary.shared
    var body: some View { List { if library.history.isEmpty { NativeEmpty(title:"No watch history yet",detail:"Episodes played in this app appear here.",icon:"clock") };ForEach(library.history) { record in NavigationLink { NativeDetail(seed:record.anime,resumeEpisode:record.episode) } label: { VStack(alignment:.leading,spacing:7) { Text(record.anime.title).font(.subheadline.bold());Text("Episode \(record.episode) · \(Int(record.seconds)/60) min · \(record.completed ? "Completed" : "In progress")").font(.caption).foregroundStyle(.secondary);if record.duration > 0 { ProgressView(value:min(1,record.seconds/record.duration)) } } }.swipeActions { Button("Remove",role:.destructive) { library.removeHistory([record.id]) } } } }.navigationTitle("Watch history") }
}
struct NativeAniList: View {
    @EnvironmentObject private var api: APIClient
    @State private var value = ""
    @State private var linked = ""
    @State private var message: String?
    @State private var error: String?
    @State private var busy = false
    var body: some View { Form { Section("Public AniList profile") { TextField("AniList username or numeric ID",text:$value).textInputAutocapitalization(.never).autocorrectionDisabled();Button("Link public profile") { Task { await link() } }.disabled(value.isEmpty || busy);if !linked.isEmpty { Text("Linked: \(linked)") };Text("This links the selected public profile; it is not OAuth proof of ownership.").font(.caption).foregroundStyle(.secondary) };Section("Watchlist") { Button("Sync public list to CortexAnime") { Task { await command("sync") } }.disabled(busy);Button("Unlink",role:.destructive) { Task { await command("unlink") } }.disabled(busy) };if let message { Section { Text(message) } };if let error { Section { ErrorNotice(text:error) } } }.navigationTitle("AniList").task { do { let r = try await api.json("/api/auth/me");linked = ((r["user"] as? [String:Any])?["anilist"] as? [String:Any])?["name"] as? String ?? "" } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } } }
    private func link() async { busy = true;defer { busy = false };do { var input = value.trimmingCharacters(in:.whitespacesAndNewlines);if let url = URL(string:input),url.host == "anilist.co" { input = url.pathComponents.last ?? input };let byID = Int(input);let result = try await api.graph(byID == nil ? "query($name:String){User(name:$name){id name avatar{large}}}" : "query($id:Int){User(id:$id){id name avatar{large}}}",variables:byID.map { ["id":$0] } ?? ["name":input]);guard let user = result["User"] as? [String:Any],let id = user["id"] as? Int,let name = user["name"] as? String else { throw AppFailure.message("AniList user not found.") };let avatar = (user["avatar"] as? [String:Any])?["large"] as? String ?? "";_ = try await api.json("/api/anilist/link",method:"POST",body:["value":input,"anilist":["id":id,"name":name,"avatar":avatar]]);linked = name;message = "AniList profile linked.";error = nil } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
    private func command(_ action: String) async { busy = true;defer { busy = false };do { let result = try await api.json("/api/anilist/\(action)",method:"POST");if action == "unlink" { linked = "";message = "AniList unlinked." } else { message = "\(result["synced"] as? Int ?? 0) anime synced." };error = nil } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}
