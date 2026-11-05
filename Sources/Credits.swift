import SwiftUI

// MARK: - Teljes stáblista / kreditek (2.0)
// Rendező, stúdió, teljes stáb + szereposztás a szinkronszínészekkel.

struct CreditPerson: Identifiable {
    let id: Int
    let name: String
    let role: String
    let image: String?
}

struct NativeFullCast: Identifiable {
    let id: Int
    let name: String
    let role: String
    let image: String?
    let voices: [String]
}

struct CreditsData {
    var staff: [CreditPerson] = []
    var studios: [String] = []
    var cast: [NativeFullCast] = []
}

@MainActor final class CreditsModel: ObservableObject {
    @Published var data = CreditsData()
    @Published var loading = false
    @Published var error: String?

    func load(mediaID: Int, api: APIClient) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let result = try await api.graph(
                "query($id:Int){Media(id:$id,type:ANIME){" +
                "staff(sort:RELEVANCE,perPage:30){edges{role node{id name{full} image{large}}}}" +
                "mainStudios:studios(isMain:true){nodes{name}}" +
                "subStudios:studios(isMain:false,perPage:8){nodes{name}}" +
                "characters(perPage:28,sort:ROLE){edges{role node{id name{full} image{large}} voiceActors(language:JAPANESE){name{full}}}}" +
                "}}",
                variables: ["id": mediaID]
            )
            let media = result["Media"] as? [String: Any] ?? [:]

            data.staff = ((media["staff"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []).compactMap { edge in
                guard let node = edge["node"] as? [String: Any], let id = node["id"] as? Int else { return nil }
                let name = (node["name"] as? [String: Any])?["full"] as? String ?? "Staff"
                return CreditPerson(id: id, name: name, role: edge["role"] as? String ?? "", image: Anime.imageURL((node["image"] as? [String: Any])?["large"] as? String)?.absoluteString)
            }
            let main = ((media["mainStudios"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            var studios = main.compactMap { $0["name"] as? String }
            let extra = ((media["subStudios"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            for s in extra.compactMap({ $0["name"] as? String }) where !studios.contains(s) {
                studios.append(s)
            }
            data.studios = studios
            data.cast = ((media["characters"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []).compactMap { edge in
                guard let node = edge["node"] as? [String: Any], let id = node["id"] as? Int else { return nil }
                let name = (node["name"] as? [String: Any])?["full"] as? String ?? "Character"
                let voices = (edge["voiceActors"] as? [[String: Any]] ?? []).compactMap { ($0["name"] as? [String: Any])?["full"] as? String }
                return NativeFullCast(id: id, name: name, role: edge["role"] as? String ?? "", image: Anime.imageURL((node["image"] as? [String: Any])?["large"] as? String)?.absoluteString, voices: voices)
            }
            error = nil
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = Self.readable(error) }
        }
    }

    /// A GraphQL sentence is never the viewer's truth: say what happened, plainly.
    static func readable(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.contains("AniList:") || raw.contains("GraphQL") || raw.contains("Field") {
            return "AniList did not return the credits for this title just now. Tap Retry."
        }
        return raw
    }
}

struct CreditPersonTile: View {
    let person: CreditPerson
    var body: some View {
        VStack(spacing:7) {
            AnimeArtwork(url: Anime.imageURL(person.image))
                .frame(width:86,height:86)
                .clipShape(RoundedRectangle(cornerRadius:16))
            Text(person.name).font(.system(size:11.5,weight:.bold)).lineLimit(2).multilineTextAlignment(.center)
            if !person.role.isEmpty {
                Text(person.role).font(.system(size:9.5)).foregroundStyle(Color.cortexPurple).lineLimit(1)
            }
        }.frame(width:96)
    }
}

struct FullCastTile: View {
    let person: NativeFullCast
    var body: some View {
        VStack(spacing:7) {
            AnimeArtwork(url: Anime.imageURL(person.image))
                .frame(width:86,height:86)
                .clipShape(RoundedRectangle(cornerRadius:16))
            Text(person.name).font(.system(size:11.5,weight:.bold)).lineLimit(2).multilineTextAlignment(.center)
            if !person.voices.isEmpty {
                Text(person.voices.joined(separator:", ")).font(.system(size:9.5)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
            } else if !person.role.isEmpty {
                Text(person.role).font(.system(size:9.5)).foregroundStyle(Color.cortexPurple).lineLimit(1)
            }
        }.frame(width:96)
    }
}

/// Teljes kreditek szekció az adatlapon.
struct NativeCreditsSection: View {
    let mediaID: Int
    @EnvironmentObject private var api: APIClient
    @StateObject private var model = CreditsModel()
    @State private var expanded = false

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            SectionHeading(title:"Credits")
            if model.loading {
                HStack(spacing:10) {
                    ProgressView()
                    Text("Loading credits…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity,alignment:.center).padding(.vertical,10)
            } else if model.data.staff.isEmpty && model.data.cast.isEmpty {
                if let error = model.error {
                    VStack(alignment:.leading,spacing:10) {
                        ErrorNotice(text:error)
                        Button("Retry") { Task { await model.load(mediaID:mediaID, api:api) } }
                            .font(.caption.bold())
                            .foregroundStyle(Color.cortexPurple)
                            .frame(minHeight:44)
                    }
                } else {
                    Text("Credits are not available at the moment.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                if !model.data.studios.isEmpty {
                    FlowChips(items: model.data.studios.map { ChipItem(icon: "studio.fill", text: $0) })
                }
                if !model.data.staff.isEmpty {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Staff").font(.system(size:13,weight:.black)).foregroundStyle(.secondary)
                        ScrollView(.horizontal,showsIndicators:false) {
                            LazyHStack(alignment:.top,spacing:12) {
                                ForEach(expanded ? model.data.staff : Array(model.data.staff.prefix(12))) { p in
                                    CreditPersonTile(person:p)
                                }
                            }
                        }
                    }
                }
                if !model.data.cast.isEmpty {
                    VStack(alignment:.leading,spacing:8) {
                        Text("Cast & voice actors").font(.system(size:13,weight:.black)).foregroundStyle(.secondary)
                        ScrollView(.horizontal,showsIndicators:false) {
                            LazyHStack(alignment:.top,spacing:12) {
                                ForEach(expanded ? model.data.cast : Array(model.data.cast.prefix(14))) { c in
                                    FullCastTile(person:c)
                                }
                            }
                        }
                    }
                }
                if model.data.staff.count > 12 || model.data.cast.count > 14 {
                    Button(expanded ? "Show less" : "Show full credits") {
                        withAnimation(.easeInOut(duration:0.25)) { expanded.toggle() }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(Color.cortexPurple)
                    .frame(minHeight:44)
                }
            }
        }
        .task(id:mediaID) {
            if model.data.staff.isEmpty { await model.load(mediaID:mediaID, api:api) }
        }
    }
}

/// Egyszerű folyó címkék (stúdiók, szerepkörök).
struct ChipItem: Hashable {
    let icon: String
    let text: String
}

struct FlowChips: View {
    let items: [ChipItem]
    var body: some View {
        FlexibleView(data: items, spacing: 8, alignment: .leading) { item in
            Label(item.text, systemImage: item.icon)
                .font(.system(size:11.5,weight:.semibold))
                .padding(.horizontal,11).padding(.vertical,6)
                .background(Color.cortexPurple.opacity(0.16), in: Capsule())
                .foregroundStyle(Color.cortexPurple)
        }
    }
}

/// Könnyű "flow" elrendezés (iOS 15+).
struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content
    @State private var totalHeight: CGFloat = .zero

    var body: some View {
        GeometryReader { geo in
            generateContent(in: geo)
        }
        .frame(height: totalHeight)
    }

    private func generateContent(in geo: GeometryProxy) -> some View {
        var width = CGFloat.zero
        var height = CGFloat.zero
        return ZStack(alignment: Alignment(horizontal: alignment, vertical: .top)) {
            ForEach(Array(data), id: \.self) { item in
                content(item)
                    .padding(.horizontal, 2)
                    .alignmentGuide(.leading) { d in
                        if abs(width - d.width) > geo.size.width {
                            width = 0
                            height -= d.height + spacing
                        }
                        let result = width
                        width -= d.width + spacing
                        return result
                    }
                    .alignmentGuide(.top) { _ in
                        let result = height
                        return result
                    }
            }
        }
        .background(HeightReader(height: $totalHeight))
    }
}

private struct HeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: HeightPreferenceKey.self, value: geo.size.height)
        }
        .onPreferenceChange(HeightPreferenceKey.self) { height = $0 }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = .zero
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
