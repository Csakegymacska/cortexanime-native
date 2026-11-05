import SwiftUI

struct AiringEntry: Identifiable { let anime: Anime;let episode: Int;let date: Date;var id: String { "\(anime.id).\(episode)" }
    init?(_ row: [String:Any]) { guard let media = row["media"] as? [String:Any],let anime = Anime(json:media),anime.status != "FINISHED",let episode = row["episode"] as? Int,let time = (row["airingAt"] as? NSNumber)?.doubleValue,time >= Date().timeIntervalSince1970-1800 else { return nil };self.anime = anime;self.episode = episode;date = Date(timeIntervalSince1970:time) }
}
struct NativeSchedule: View {
    @EnvironmentObject private var api: APIClient
    @State private var entries: [AiringEntry] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        List {
            Section { Text("Upcoming episodes in your device's local time. Airing dates do not guarantee a playable stream or subtitle availability.").font(.caption).foregroundStyle(.secondary) }
            if loading { ProgressView("Loading schedule…") }
            if let error { NativeError(text:error) { Task { await load() } } }
            ForEach(entries) { entry in
                NavigationLink { NativeDetail(seed:entry.anime) } label: { NativeAiringRow(entry:entry) }
            }
            if entries.isEmpty && !loading && error == nil { NativeEmpty(title:"No upcoming episodes returned",icon:"calendar") }
        }.navigationTitle("Release schedule").task { await load() }.refreshable { await load() }
    }
    private func load() async { loading = true;defer { loading = false };do { var rows: [[String:Any]] = [];if let cache = try? await api.json("/api/al-cache",query:["op":"airing","q":"week"]) { rows = (((cache["data"] as? [String:Any])?["Page"] as? [String:Any])?["airingSchedules"] as? [[String:Any]]) ?? [] };var parsed = rows.compactMap(AiringEntry.init);if parsed.isEmpty { let now = Int(Date().timeIntervalSince1970);let data = try await api.graph("query($gt:Int,$lt:Int){Page(page:1,perPage:50){airingSchedules(airingAt_greater:$gt,airingAt_lesser:$lt,sort:TIME){episode airingAt media{\(CatalogModel.fields)}}}}",variables:["gt":now-1800,"lt":now+7*86400]);rows = (data["Page"] as? [String:Any])?["airingSchedules"] as? [[String:Any]] ?? [];parsed = rows.compactMap(AiringEntry.init) };entries = parsed.sorted { $0.date<$1.date };error = nil } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}

struct NativeAiringRow: View {
    let entry: AiringEntry
    var body: some View {
        HStack(spacing:12) {
            AnimeArtwork(url:entry.anime.cover).frame(width:50,height:70).clipShape(RoundedRectangle(cornerRadius:10))
            VStack(alignment:.leading,spacing:7) {
                Text(entry.anime.title).font(.subheadline.bold()).lineLimit(2)
                Text("Episode \(entry.episode) · "+entry.date.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(Color.cortexPurple)
            }
        }
    }
}
