import SwiftUI

struct NativeCharacter: Identifiable {
    let id: Int, name: String, role: String, voice: String
    let image: URL?
    init?(_ edge: [String:Any]) { guard let n = edge["node"] as? [String:Any],let id = n["id"] as? Int else { return nil };self.id = id;name = (n["name"] as? [String:Any])?["full"] as? String ?? "Character";role = edge["role"] as? String ?? "";image = Anime.imageURL((n["image"] as? [String:Any])?["large"] as? String);let actors = edge["voiceActors"] as? [[String:Any]] ?? [];voice = (actors.first?["name"] as? [String:Any])?["full"] as? String ?? "" }
}
struct NativeDetailExtras: View {
    let id: Int
    @EnvironmentObject private var api: APIClient
    @State private var related: [Anime] = []
    @State private var recommended: [Anime] = []
    @State private var characters: [NativeCharacter] = []
    @State private var trailer: URL?
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            if let trailer { Link(destination:trailer) { Label("Watch official trailer on YouTube",systemImage:"play.rectangle").font(.subheadline.bold()).frame(minHeight:44) } }
            NativeCreditsSection(mediaID:id)
            if !related.isEmpty { AnimeShelf(title:"Related titles",items:related) }
            if !recommended.isEmpty { AnimeShelf(title:"Recommended",items:recommended) }
            if let error { Text("Related metadata: "+error).font(.caption).foregroundStyle(.secondary) }
        }.task(id:id) { if !CatalogModel.fixture { await load() } }
    }
    private func load() async { do {
        let fields = CatalogModel.fields
        let result = try await api.graph("query($id:Int){Media(id:$id,type:ANIME){trailer{id site} characters(perPage:24,sort:ROLE){edges{role voiceActors(language:JAPANESE){name{full}} node{id name{full} image{large}}}} relations{edges{relationType node{\(fields)}}} recommendations(perPage:12,sort:RATING_DESC){nodes{mediaRecommendation{\(fields)}}}}}",variables:["id":id])
        guard let media = result["Media"] as? [String:Any] else { return }
        characters = ((media["characters"] as? [String:Any])?["edges"] as? [[String:Any]] ?? []).compactMap(NativeCharacter.init)
        var ids = Set<Int>();related = ((media["relations"] as? [String:Any])?["edges"] as? [[String:Any]] ?? []).compactMap { ($0["node"] as? [String:Any]).flatMap { Anime(json:$0) } }.filter { ids.insert($0.id).inserted }
        ids = [];recommended = ((media["recommendations"] as? [String:Any])?["nodes"] as? [[String:Any]] ?? []).compactMap { ($0["mediaRecommendation"] as? [String:Any]).flatMap { Anime(json:$0) } }.filter { ids.insert($0.id).inserted }
        if let tr = media["trailer"] as? [String:Any],tr["site"] as? String == "youtube",let value = tr["id"] as? String,value.range(of:"^[A-Za-z0-9_-]{6,20}$",options:.regularExpression) != nil { trailer = URL(string:"https://www.youtube.com/watch?v=\(value)") }
        error = nil
    } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
}

struct NativeCharacterTile: View {
    let person: NativeCharacter
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            AnimeArtwork(url:person.image).frame(width:100,height:130).clipShape(RoundedRectangle(cornerRadius:15))
            Text(person.name).font(.caption.bold()).lineLimit(2)
            Text(person.role.capitalized).font(.caption2).foregroundStyle(Color.cortexPurple)
            if !person.voice.isEmpty { Text(person.voice).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }.frame(width:100,alignment:.leading)
    }
}
