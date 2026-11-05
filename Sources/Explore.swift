import SwiftUI

struct MangaTitle: Identifiable {
    let id: String, title: String, status: String
    let cover: URL?
    init?(_ r: [String:Any]) { guard let id = r["id"] as? String,UUID(uuidString:id) != nil,let attributes = r["attributes"] as? [String:Any] else { return nil };self.id = id;let titles = attributes["title"] as? [String:String] ?? [:];title = titles["en"] ?? titles.values.first ?? "Manga";status = attributes["status"] as? String ?? "";let relation = (r["relationships"] as? [[String:Any]] ?? []).first { $0["type"] as? String == "cover_art" };let filename = (relation?["attributes"] as? [String:Any])?["fileName"] as? String;cover = filename.flatMap { Anime.imageURL("https://cortanime.eu/api/manga-cover/\(id)/\($0).256.jpg") } }
}
struct NativeManga: View {
    @EnvironmentObject private var api: APIClient
    @State private var query = ""
    @State private var items: [MangaTitle] = []
    @State private var error: String?
    @State private var loading = false
    @State private var offset = 0
    @State private var total = 0
    @State private var primed = false
    var body: some View { ScrollView { VStack(alignment:.leading,spacing:18) { NativeSearchField(text:$query,prompt:"Search MangaDex");Text("Browse manga from MangaDex. Open a title to see its chapters and start reading inside the app.").font(.caption).foregroundStyle(.secondary);if let error { NativeError(text:error) { Task { await load(reset:true) } } };LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:14)],spacing:20) { ForEach(items) { manga in NavigationLink { NativeMangaDetail(manga:manga) } label: { VStack(alignment:.leading,spacing:7) { AnimeArtwork(url:manga.cover).aspectRatio(0.68,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:15));Text(manga.title).font(.caption.bold()).lineLimit(2);Text(manga.status.capitalized).font(.caption2).foregroundStyle(.secondary) }.foregroundStyle(.white) }.buttonStyle(.plain) } };if loading { ProgressView().frame(maxWidth:.infinity) };if primed && !loading && items.isEmpty { NativeEmpty(title:"No manga found",icon:"book") };if items.count < total { Button("Load more") { Task { await load(reset:false) } }.frame(maxWidth:.infinity,minHeight:44).disabled(loading) } }.padding(16) }.background(Color.cortexBlack).navigationTitle("Manga").task(id:query) { do { try await Task.sleep(for:.milliseconds(350));try Task.checkCancellation();await load(reset:true) } catch {} } }
    private func load(reset: Bool) async { loading = true;defer { loading = false;primed = true };do { let next = reset ? 0 : offset;var params = ["offset":String(next)];if !query.isEmpty { params["q"] = query };let r = try await api.json("/api/manga",query:params);try Task.checkCancellation();let batch = (r["data"] as? [[String:Any]] ?? []).compactMap(MangaTitle.init);var seen = Set((reset ? [] : items).map(\.id));items = (reset ? [] : items)+batch.filter { seen.insert($0.id).inserted };offset = next+batch.count;total = r["total"] as? Int ?? items.count;error = nil } catch is CancellationError {} catch { if !Task.isCancelled { self.error = error.localizedDescription } } }
}
enum InformationKind: String { case faq, privacy, dmca
    var title: String { switch self { case .faq:return "Frequently Asked Questions";case .privacy:return "Privacy Policy";case .dmca:return "DMCA & Copyright" } }
}
struct InformationEntry: Decodable, Identifiable { let title: String, text: String;var id: String { title+text } }
struct NativeInformation: View {
    let kind: InformationKind
    private var entries: [InformationEntry] { guard let url = Bundle.main.url(forResource:"WebsiteInformation",withExtension:"json"),let bytes = try? Data(contentsOf:url),let all = try? JSONDecoder().decode([String:[InformationEntry]].self,from:bytes) else { return [] };return all[kind.rawValue] ?? [] }
    var body: some View { ScrollView { VStack(alignment:.leading,spacing:18) {
        if kind == .faq { Text("Native app note: CortexPlayer uses AVPlayer, not a web embed. Email login works through the native API; browser-only OAuth is not yet native-compatible. Home-screen/PWA instructions below refer to the website.").font(.caption).foregroundStyle(.orange).padding(14).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15)) }
        if kind == .privacy { Text("Native app storage: the session cookie is saved in iOS Keychain. Local watch history, preferences and permitted offline media stay in this app's sandbox. Metadata/image requests reach AniList and the listed providers. Sign out removes the native session; Settings can clear local history.").font(.caption).padding(14).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15)) }
        Text("Website information · snapshot 20 October 2026").font(.caption2).foregroundStyle(.secondary)
        ForEach(entries) { entry in if kind == .faq { DisclosureGroup { Text(entry.text).font(.subheadline).foregroundStyle(.secondary).padding(.top,8) } label: { Text(entry.title).font(.subheadline.bold()) }.padding(14).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:15)) } else { VStack(alignment:.leading,spacing:8) { if !entry.title.isEmpty { Text(entry.title).font(.headline) };Text(entry.text).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }.frame(maxWidth:.infinity,alignment:.leading) } }
        Link("Contact: cortexanime@proton.me",destination:URL(string:"mailto:cortexanime@proton.me")!).font(.subheadline).frame(minHeight:44)
    }.padding(16) }.background(Color.cortexBlack).navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline) }
}
