import SwiftUI

enum BrowseMode: String { case search = "Search", hungarian = "HU Subs", seasonal = "Seasonal", movies = "Movies" }

/// Always-visible search input. The system `.searchable` bar is unreliable inside the app's
/// kept-alive tab NavigationStacks (multiple stacks share one window and the field never
/// appears/focuses), so search uses a plain TextField that works on every iOS build.
struct NativeSearchField: View {
    @Binding var text: String
    var prompt: String = "Title or original name"
    var body: some View {
        HStack(spacing:8) {
            Image(systemName:"magnifyingglass").font(.subheadline).foregroundStyle(.secondary)
            TextField(prompt,text:$text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.subheadline)
                .foregroundStyle(.white)
                .tint(Color.cortexPurple)
                .accessibilityIdentifier("search.field")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName:"xmark.circle.fill").font(.subheadline).foregroundStyle(.secondary)
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Clear search").accessibilityIdentifier("search.clear")
            }
        }
        .padding(10)
        .frame(maxWidth:.infinity)
        .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:16))
    }
}
struct NativeBrowse: View {
    let mode: BrowseMode
    var initialGenre = ""
    @EnvironmentObject private var catalog: CatalogModel
    @State private var query = ""
    @State private var genre = ""
    @State private var format = ""
    @State private var sort = "TRENDING_DESC"
    @State private var season = ["WINTER","SPRING","SUMMER","FALL"][(Calendar.current.component(.month,from:Date())-1)/3]
    @State private var year = Calendar.current.component(.year,from:Date())
    @State private var items: [Anime] = []
    @State private var page = 1
    @State private var loading = false
    @State private var error: String?
    @State private var hasMore = true
    @State private var primed = false
    @ObservedObject private var recents = RecentSearches.shared
    private var signature: String { [query,genre,format,sort,season,String(year)].joined(separator:"|") }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                NativeSearchField(text:$query)
                if query.isEmpty {
                    RecentSearchChips(store: recents) { picked in query = picked }
                }
                filters
                if mode == .hungarian { Text("The site's Hungarian-subtitle catalog. Video and subtitle availability are checked when an episode opens.").font(.caption).foregroundStyle(.secondary) }
                if let error { NativeError(text:error) { Task { await load(reset:true) } } }
                AnimeGrid(items:visible)
                if loading { ProgressView("Loading…").frame(maxWidth:.infinity).padding() }
                if primed && visible.isEmpty && !loading { NativeEmpty(title:"No titles found",detail:"Try another title or filter.",icon:"magnifyingglass") }
                if hasMore && mode != .hungarian && !items.isEmpty { Button("Load more") { Task { await load(reset:false) } }.frame(maxWidth:.infinity,minHeight:48).disabled(loading) }
            }.padding(16)
        }.background(Color.cortexBlack).navigationTitle(mode.rawValue).navigationBarTitleDisplayMode(.inline)
            .onAppear { if genre.isEmpty { genre = initialGenre } }
            .task(id:signature) {
                do {
                    try await Task.sleep(for:.milliseconds(300));try Task.checkCancellation()
                    await load(reset:true)
                    if !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { recents.remember(query) }
                } catch {}
            }
            .refreshable { await load(reset:true) }
    }
    private var visible: [Anime] {
        guard mode == .hungarian else { return items }
        return catalog.titles.filter { item in (query.isEmpty || item.title.localizedCaseInsensitiveContains(query)) && (genre.isEmpty || item.genres.contains(genre)) }
    }
    private var filters: some View {
        VStack(spacing:8) {
            HStack {
                Picker("Genre",selection:$genre) { Text("All genres").tag("");ForEach(["Action","Adventure","Comedy","Drama","Ecchi","Fantasy","Horror","Romance","Sci-Fi","Slice of Life","Sports","Supernatural"],id:\.self) { Text($0).tag($0) } }
                Picker("Sort",selection:$sort) { Text("Trending").tag("TRENDING_DESC");Text("Score").tag("SCORE_DESC");Text("Popularity").tag("POPULARITY_DESC");Text("Updated").tag("UPDATED_AT_DESC") }
            }.font(.caption)
            if mode == .seasonal { HStack {
                Picker("Season",selection:$season) { ForEach(["WINTER","SPRING","SUMMER","FALL"],id:\.self) { Text($0.capitalized).tag($0) } }
                Picker("Year",selection:$year) { ForEach(2000...(Calendar.current.component(.year,from:Date())+1),id:\.self) { Text(String($0)).tag($0) } }
            } }
            if mode == .search { Picker("Format",selection:$format) { Text("All formats").tag("");Text("TV").tag("TV");Text("Movie").tag("MOVIE");Text("OVA").tag("OVA");Text("ONA").tag("ONA");Text("Short").tag("TV_SHORT") }.pickerStyle(.menu) }
        }.padding(10).frame(maxWidth:.infinity).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:16))
    }
    private func load(reset: Bool) async {
        if mode == .hungarian { if catalog.titles.isEmpty { await catalog.load() };primed = true;return }
        if !reset && loading { return };loading = true;defer { loading = false;primed = true }
        do {
            let requestedPage = reset ? 1 : page+1
            let values = try await catalog.discover(query:query,genre:genre,format:mode == .movies ? "MOVIE" : format,season:mode == .seasonal ? season : "",year:mode == .seasonal ? year : nil,sort:sort,page:requestedPage)
            try Task.checkCancellation();let existing = reset ? [] : items;var ids = Set(existing.map(\.id));items = existing + values.filter { ids.insert($0.id).inserted };page = requestedPage;hasMore = values.count == 24;error = nil
        } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}
