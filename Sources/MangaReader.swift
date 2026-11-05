import SwiftUI

/// One readable chapter. Numbers come straight from MangaDex chapter fields.
struct MangaChapter: Identifiable, Hashable {
    let id: String
    let number: Double
    let label: String
    let title: String
    let pages: Int
}

/// Direct MangaDex public API: catalog, chapter feed, and the official at-home page
/// delivery system. No scraping and no third-party mirror; the same endpoints the
/// MangaDex clients use. The host app talks HTTPS directly, no proxy required.
enum MangaDex {
    private static func get(_ url: URL) async throws -> [String:Any] {
        var request = URLRequest(url:url)
        request.timeoutInterval = 15
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("CortexAnime/\(DeviceInfo.version) (iOS app)",forHTTPHeaderField:"User-Agent")
        let (data,response) = try await URLSession.shared.data(for:request)
        guard let http = response as? HTTPURLResponse,(200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] else {
            throw AppFailure.message("MangaDex is not responding right now.")
        }
        return root
    }

    static func chapters(mangaID: String) async throws -> [MangaChapter] {
        var out: [MangaChapter] = []
        var offset = 0
        while offset < 500 {
            guard let url = URL(string:"https://api.mangadex.org/manga/\(mangaID)/feed?limit=100&offset=\(offset)&translatedLanguage[]=en&order[chapter]=asc") else { break }
            let root = try await get(url)
            let rows = root["data"] as? [[String:Any]] ?? []
            for row in rows {
                guard let id = row["id"] as? String,let a = row["attributes"] as? [String:Any] else { continue }
                let raw = (a["chapter"] as? String).flatMap(Double.init) ?? 0
                let title = (a["title"] as? String) ?? ""
                let pages = (a["pages"] as? Int) ?? 0
                out.append(MangaChapter(id:id,number:raw,label:raw == raw.rounded() ? String(Int(raw)) : String(raw),title:title,pages:pages))
            }
            if rows.count < 100 { break }
            offset += rows.count
        }
        return out.sorted { $0.number == $1.number ? $0.id < $1.id : $0.number < $1.number }
    }

    static func pages(chapterID: String) async throws -> [URL] {
        guard let url = URL(string:"https://api.mangadex.org/at-home/server/\(chapterID)") else { throw AppFailure.message("Invalid chapter.") }
        let root = try await get(url)
        guard let base = root["baseUrl"] as? String,let chapter = root["chapter"] as? [String:Any],
              let hash = chapter["hash"] as? String else { throw AppFailure.message("This chapter has no readable pages.") }
        let files = (chapter["data"] as? [String] ?? []).isEmpty ? (chapter["dataSaver"] as? [String] ?? []) : (chapter["data"] as? [String] ?? [])
        let folder = (chapter["data"] as? [String] ?? []).isEmpty ? "data-saver" : "data"
        let urls = files.compactMap { URL(string:"\(base)/\(folder)/\(hash)/\($0)") }
        guard !urls.isEmpty else { throw AppFailure.message("This chapter has no readable pages.") }
        return urls
    }
}

private struct MangaProgress {
    static func key(_ id: String) -> String { "manga.read.\(id)" }
    static func load(_ id: String) -> (chapter: String,page: Int)? {
        guard let raw = UserDefaults.standard.string(forKey:key(id)) else { return nil }
        let parts = raw.split(separator:"|")
        guard parts.count == 2,let page = Int(parts[1]) else { return nil }
        return (String(parts[0]),page)
    }
    static func save(_ id: String,chapter: String,page: Int) {
        UserDefaults.standard.set("\(chapter)|\(page)",forKey:key(id))
    }
}

// MARK: - Detail

struct NativeMangaDetail: View {
    let manga: MangaTitle
    @State private var chapters: [MangaChapter] = []
    @State private var error: String?
    @State private var loading = true
    @State private var start: MangaChapter?
    private var progress: (chapter: String,page: Int)? { MangaProgress.load(manga.id) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.top,spacing:14) {
                    AnimeArtwork(url:manga.cover).frame(width:120,height:176).clipShape(RoundedRectangle(cornerRadius:15))
                    VStack(alignment:.leading,spacing:9) {
                        Text(manga.title).font(.system(size:20,weight:.black)).lineLimit(3)
                        if !manga.status.isEmpty { Pill(text:manga.status.capitalized) }
                        if !chapters.isEmpty { Text("\(chapters.count) chapters · English").font(.caption).foregroundStyle(.secondary) }
                        Spacer(minLength:0)
                    }
                    Spacer(minLength:0)
                }
                if let progress,let match = chapters.first(where:{ $0.id == progress.chapter }) {
                    Button { start = match } label: {
                        Label("Continue · Chapter \(match.label)",systemImage:"book.fill")
                            .font(.system(size:15,weight:.bold)).frame(maxWidth:.infinity,minHeight:50)
                            .foregroundStyle(.white).background(Color.cortexPurple,in:RoundedRectangle(cornerRadius:15))
                    }.buttonStyle(.plain)
                }
                Button { start = chapters.first } label: {
                    Label(progress == nil ? "Start reading" : "Read from the beginning",systemImage:"book")
                        .font(.system(size:15,weight:.bold)).frame(maxWidth:.infinity,minHeight:50)
                        .foregroundStyle(Color.cortexPurple)
                        .background(Color.cortexPurple.opacity(0.14),in:RoundedRectangle(cornerRadius:15))
                        .overlay(RoundedRectangle(cornerRadius:15).stroke(Color.cortexPurple.opacity(0.35),lineWidth:1))
                }.buttonStyle(.plain).disabled(chapters.isEmpty)
                SectionHeading(title:"Chapters")
                if loading { ProgressView().frame(maxWidth:.infinity).padding(.vertical,20) }
                if let error { NativeError(text:error) { Task { await load() } } }
                ForEach(chapters.reversed()) { chapter in
                    Button { start = chapter } label: {
                        HStack(spacing:12) {
                            Text("Ch. \(chapter.label)").font(.system(size:14,weight:.bold)).monospacedDigit().frame(width:64,alignment:.leading)
                            VStack(alignment:.leading,spacing:2) {
                                if !chapter.title.isEmpty { Text(chapter.title).font(.system(size:13,weight:.semibold)).lineLimit(1) }
                                Text(chapter.pages > 0 ? "\(chapter.pages) pages" : " ").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical,11).padding(.horizontal,13)
                        .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:13))
                        .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .background(Color.cortexBlack)
        .navigationTitle("Manga")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item:$start) { chapter in
            NativeMangaReader(manga:manga,chapters:chapters,start:chapter)
        }
        .task { await load() }
    }
    private func load() async {
        loading = true;defer { loading = false }
        do {
            let rows = try await MangaDex.chapters(mangaID:manga.id)
            try Task.checkCancellation()
            chapters = rows;error = nil
        } catch is CancellationError {} catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Reader

struct NativeMangaReader: View {
    let manga: MangaTitle
    let chapters: [MangaChapter]
    @State private var current: MangaChapter
    @State private var pages: [URL] = []
    @State private var error: String?
    @State private var loading = true
    @State private var chromeVisible = true
    @State private var visiblePage = 1
    @Environment(\.dismiss) private var dismiss
    init(manga: MangaTitle,chapters: [MangaChapter],start: MangaChapter) {
        self.manga = manga;self.chapters = chapters
        _current = State(initialValue:start)
    }
    private var index: Int? { chapters.firstIndex(of:current) }
    var body: some View {
        ZStack(alignment:.top) {
            Color.cortexBlack.ignoresSafeArea()
            if loading && pages.isEmpty { ProgressView("Loading chapter…").tint(Color.cortexPurple).frame(maxWidth:.infinity,maxHeight:.infinity) }
            if let error { NativeError(text:error) { Task { await load() } }.frame(maxHeight:.infinity) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing:0) {
                        ForEach(Array(pages.enumerated()),id:\.offset) { pair in
                            MangaPageImage(url:pair.element)
                                .id(pair.offset)
                                .onAppear { visiblePage = pair.offset+1;MangaProgress.save(manga.id,chapter:current.id,page:visiblePage) }
                        }
                        if let next = adjacent(1) {
                            Button { Task { await open(next) } } label: {
                                Label("Next · Chapter \(next.label)",systemImage:"chevron.down")
                                    .font(.system(size:15,weight:.bold)).frame(maxWidth:.infinity,minHeight:52)
                                    .foregroundStyle(.white).background(Color.cortexPurple,in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(.plain).padding(16)
                        }
                    }
                }
                .onTapGesture { withAnimation(.easeInOut(duration:0.22)) { chromeVisible.toggle() } }
                .onChange(of:current.id) { _,_ in Task { await load();proxy.scrollTo(0,anchor:.top) } }
            }
            if chromeVisible {
                VStack {
                    HStack(spacing:12) {
                        Button { dismiss() } label: { Image(systemName:"chevron.left").font(.system(size:17,weight:.bold)).frame(width:44,height:44).background(Color.cortexPanel,in:Circle()) }.buttonStyle(.plain).accessibilityLabel("Close reader")
                        VStack(alignment:.leading,spacing:2) {
                            Text(manga.title).font(.system(size:14,weight:.bold)).lineLimit(1)
                            Text("Chapter \(current.label) · \(visiblePage)/\(max(1,pages.count))").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal,14).padding(.vertical,10)
                    .background(Color.cortexPanel.opacity(0.96),in:RoundedRectangle(cornerRadius:16))
                    .padding(.horizontal,12)
                    Spacer()
                    HStack(spacing:10) {
                        chapterButton("chevron.up","Previous",enabled:index.map({ $0 > 0 }) ?? false) { if let i = index,i > 0 { Task { await open(chapters[i-1]) } } }
                        chapterButton("chevron.down","Next",enabled:adjacent(1) != nil) { if let n = adjacent(1) { Task { await open(n) } } }
                    }
                    .padding(.horizontal,12).padding(.bottom,8)
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .task { await load() }
        .onDisappear { MangaProgress.save(manga.id,chapter:current.id,page:visiblePage) }
    }
    private func adjacent(_ delta: Int) -> MangaChapter? {
        guard let i = index else { return nil }
        let j = i+delta
        return chapters.indices.contains(j) ? chapters[j] : nil
    }
    private func chapterButton(_ icon: String,_ label: String,enabled: Bool,action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Label(label,systemImage:icon).font(.system(size:13,weight:.bold))
                .frame(maxWidth:.infinity,minHeight:46)
                .foregroundStyle(enabled ? .white : .white.opacity(0.35))
                .background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:13))
        }.buttonStyle(.plain).disabled(!enabled)
    }
    private func open(_ chapter: MangaChapter) async {
        visiblePage = 1
        current = chapter
        MangaProgress.save(manga.id,chapter:chapter.id,page:1)
    }
    private func load() async {
        loading = true;defer { loading = false }
        do {
            let urls = try await MangaDex.pages(chapterID:current.id)
            try Task.checkCancellation()
            pages = urls;error = nil
            MangaProgress.save(manga.id,chapter:current.id,page:1)
        } catch is CancellationError {} catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

private struct MangaPageImage: View {
    let url: URL
    var body: some View {
        AsyncImage(url:url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit().frame(maxWidth:.infinity)
            case .failure:
                VStack(spacing:8) {
                    Image(systemName:"photo").font(.title).foregroundStyle(.secondary)
                    Text("Page failed to load").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,minHeight:220)
            default:
                ZStack { Rectangle().fill(Color.cortexPanel.opacity(0.5));ProgressView().tint(Color.cortexPurple) }
                    .frame(maxWidth:.infinity).frame(minHeight:320)
            }
        }
        .accessibilityHidden(true)
    }
}
