import Foundation
import SwiftUI

struct Anime: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let cover: URL?
    let banner: URL?
    let synopsis: String
    let episodes: Int
    let availableEpisodes: Int?
    let genres: [String]
    let hasHungarian: Bool
    let status: String
    let score: Double?
    let year: Int?
    let format: String?
    let nextEpisode: Int?
    let nextEpisodeAt: Double?
    init?(json: [String: Any], now: TimeInterval = Date().timeIntervalSince1970) {
        let rawID = json["anilistId"] as? Int ?? json["id"] as? Int ?? Int((json["id"] as? String ?? "").replacingOccurrences(of:"al:",with:""))
        guard let id = rawID, id > 0 else { return nil }; self.id = id
        let names = json["title"] as? [String: Any], images = json["coverImage"] as? [String: Any]
        title = json["title"] as? String ?? names?["english"] as? String ?? names?["romaji"] as? String ?? "Untitled"
        cover = Self.imageURL(json["cover"] as? String ?? json["coverImage"] as? String ?? images?["extraLarge"] as? String ?? images?["large"] as? String)
        banner = Self.imageURL(json["bannerImage"] as? String ?? json["banner"] as? String)
        synopsis = json["synopsis"] as? String ?? json["description"] as? String ?? ""
        status = json["status"] as? String ?? "UNKNOWN"
        episodes = max(0,json["totalPlannedEpisodes"] as? Int ?? json["totalEpisodes"] as? Int ?? json["episodes"] as? Int ?? 0)
        let next = json["nextAiringEpisode"] as? [String: Any]
        let number = next?["episode"] as? Int ?? json["nextEpisode"] as? Int
        let time = (next?["airingAt"] as? NSNumber)?.doubleValue ?? (json["nextEpisodeAt"] as? NSNumber)?.doubleValue
        nextEpisode = number; nextEpisodeAt = time
        let explicit = json["airedEpisodes"] as? Int ?? json["currentEpisodes"] as? Int
        let pastSchedule = ((json["airingSchedule"] as? [String:Any])?["nodes"] as? [[String:Any]] ?? []).filter { (($0["airingAt"] as? NSNumber)?.doubleValue ?? .infinity) <= now }.compactMap { $0["episode"] as? Int }.max()
        var observed = [explicit,pastSchedule].compactMap { $0 }.filter { $0 >= 0 }
        if let number,let time { observed.append(max(0,time > now ? number-1 : number)) }
        if status == "NOT_YET_RELEASED" || status == "CANCELLED" { availableEpisodes = 0 }
        else if status == "FINISHED" && episodes > 0 { availableEpisodes = episodes }
        else if let count = observed.max() { availableEpisodes = min(episodes > 0 ? episodes : Int.max,count) }
        else { availableEpisodes = nil }
        genres = json["genres"] as? [String] ?? []
        hasHungarian = json["hasHungarianSubtitles"] as? Bool ?? json["hasHungarianSub"] as? Bool ?? false
        if let value = (json["averageScore"] as? NSNumber)?.doubleValue, value > 0, value <= 100 { score = value / 10 }
        else { score = (json["score"] as? NSNumber)?.doubleValue }
        year = json["seasonYear"] as? Int ?? json["year"] as? Int; format = json["format"] as? String
    }
    static func imageURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, let url = URL(string: raw, relativeTo: URL(string:"https://cortanime.eu"))?.absoluteURL, url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }; return url
    }
    var plainSynopsis: String { synopsis.replacingOccurrences(of:"<[^>]+>",with:"",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&#039;",with:"'").replacingOccurrences(of:"&quot;",with:"\"") }
    func episodeLimit(language: String) -> Int { availableEpisodes ?? 0 }
    var episodeSummary: String { if let current = availableEpisodes { return episodes > 0 ? "\(current) / \(episodes) episodes" : "\(current) released" }; return "Released count unavailable" }
}

struct SubtitleTrack: Codable, Hashable, Identifiable {
    let file: String, label: String
    var id: String { file }
    var url: URL? { guard let u = URL(string:file),u.scheme == "https",u.host != nil,u.user == nil,u.password == nil else { return nil }; return u }
}
struct StreamInfo: Decodable {
    struct Skip: Decodable { struct Segment: Decodable { let start: Double, end: Double; var valid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start } }; let intro: Segment?, outro: Segment? }
    let found: Bool?
    let streamUrl: String?
    let type: String?
    var tracks: [SubtitleTrack]?
    let downloadAllowed: Bool?
    let downloadUrl: String?
    let skip: Skip?
    let notReleased: Bool?
    let nextEpisode: Int?
    let airingAt: Int?
    // Ephemeral validated bytes are handed directly to playback; never decoded from the API.
    var preparedCaptions: [String:Data] = [:]
    enum CodingKeys: String,CodingKey { case found,streamUrl,type,tracks,downloadAllowed,downloadUrl,skip,notReleased,nextEpisode,airingAt }
    /// The truth about why this episode cannot play, in words a viewer can act on.
    var unavailableReason: String {
        if notReleased == true {
            if let next = nextEpisode,let at = airingAt,at > 0 {
                let date = Date(timeIntervalSince1970:TimeInterval(at))
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier:"en_US_POSIX")
                formatter.dateFormat = "MMM d, HH:mm"
                return "Episode \(next) has not aired yet. It arrives \(formatter.string(from:date))."
            }
            return "This episode has not aired yet."
        }
        if found == false { return "The source is not answering for this episode. Try again in a moment." }
        if type?.lowercased() == "embed" { return "This episode only has an embed source, so it plays in CortexPlayer." }
        return "No playable source was returned for this episode. Try again."
    }
    var playbackURL: URL? { guard found == true,!["embed","iframe","html"].contains(type?.lowercased() ?? ""),let raw = streamUrl,let u = URL(string:raw),u.scheme == "https",u.host != nil,u.user == nil,u.password == nil else { return nil };return u }
    var approvedDownloadURL: URL? { guard downloadAllowed == true,let raw = downloadUrl,let u = URL(string:raw),u.scheme == "https",u.host != nil,u.user == nil,u.password == nil else { return nil };return u }
    func subtitle(language: String) -> SubtitleTrack? { tracks?.first { CaptionPolicy.matches($0,language:language) } }
}

@MainActor final class CatalogModel: ObservableObject {
    @Published var titles: [Anime] = []
    @Published var trending: [Anime] = []
    @Published var seasonal: [Anime] = []
    @Published var results: [Anime] = []
    @Published var error: String?
    @Published var searchError: String?
    @Published var loading = false
    @Published var searching = false
    @Published var updated: Date?
    @Published var metadataSource = "AniList"
    @Published var backupMetadata = false
    @Published var savedData = false
    @Published var networkUnavailable = false
    let api: APIClient
    static let fields = MetadataQueries.fields
    private let cache = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("native-catalog-v1.json")
    private struct Snapshot: Codable { let trending: [Anime], seasonal: [Anime], titles: [Anime], date: Date; let source: String?; let backup: Bool? }
    init(api: APIClient) { self.api = api
        if let data = try? Data(contentsOf:cache),let snapshot = try? JSONDecoder().decode(Snapshot.self,from:data) { trending = snapshot.trending; seasonal = snapshot.seasonal;titles = snapshot.titles;updated = snapshot.date;metadataSource = snapshot.source ?? "AniList";backupMetadata = snapshot.backup ?? false;savedData = true }
    }
    static var fixture: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-fixture")
        #else
        return false
        #endif
    }
    static func fixtureAnime() -> Anime? { guard let url = Bundle.main.url(forResource:"FixtureBleach",withExtension:"json"),let data = try? Data(contentsOf:url),let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],let d = root["data"] as? [String:Any],let m = d["Media"] as? [String:Any] else { return nil };return Anime(json:m,now:1792497600) }
    func load() async {
        guard !loading else { return };loading = true;defer { loading = false }
        networkUnavailable = false
        if Self.fixture,let item = Self.fixtureAnime() { trending = [item]; seasonal = [item];titles = [item];updated = nil;return }
        do {
            if !(await loadHomeEndpoint()) {
            let month = Calendar.current.component(.month,from:Date()),year = Calendar.current.component(.year,from:Date()),season = ["WINTER","SPRING","SUMMER","FALL"][(month-1)/3]
            let data = try await api.graph(MetadataQueries.home,variables:["s":season,"y":year])
            guard let tr = (data["trending"] as? [String:Any])?["media"] as? [[String:Any]],let se = (data["seasonal"] as? [String:Any])?["media"] as? [[String:Any]],!tr.isEmpty else { throw AppFailure.message("No current home data returned.") }
            trending = tr.compactMap { Anime(json:$0) };seasonal = se.compactMap { Anime(json:$0) };updated = Date();metadataSource = api.metadataSource;backupMetadata = api.metadataUsingBackup;savedData = false;error = nil
            }
        } catch { savedData = !trending.isEmpty;guard !(error is CancellationError),!Task.isCancelled else { return };networkUnavailable = Connectivity.isNetworkFailure(error);self.error = error.localizedDescription }
        do { let data = try await api.data("/api/hu-catalog");if let rows = try JSONSerialization.jsonObject(with:data) as? [[String:Any]] { titles = rows.compactMap { Anime(json:$0) } } } catch { if titles.isEmpty,!(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
        if let updated,let data = try? JSONEncoder().encode(Snapshot(trending:trending,seasonal:seasonal,titles:titles,date:updated,source:metadataSource,backup:backupMetadata)) { try? data.write(to:cache,options:.atomic) }
    }
    private func loadHomeEndpoint() async -> Bool {
        do {
            let result = try await api.json("/api/home-live")
            guard let context = MetadataFeedPolicy.context(result),
                  let tr = result["trending"] as? [[String:Any]],let se = result["seasonal"] as? [[String:Any]] else { return false }
            trending = tr.compactMap { Anime(json:$0) };seasonal = se.compactMap { Anime(json:$0) }
            updated = context.date;metadataSource = context.source;backupMetadata = context.backup
            savedData = result["stale"] as? Bool == true || Date().timeIntervalSince(context.date)>300
            error = nil;return !trending.isEmpty
        } catch { return false }
    }
    func detail(_ id: Int,cached: Anime? = nil) async throws -> Anime {
        if Self.fixture,let item = Self.fixtureAnime(),item.id == id { return item }
        let data = try await api.graph(MetadataQueries.detail,variables:["id":id])
        guard var media = data["Media"] as? [String:Any] else { throw AppFailure.message("Anime metadata unavailable.") }
        if let nodes = (data["aired"] as? [String:Any])?["airingSchedules"] as? [[String:Any]] { media["airingSchedule"] = ["nodes":nodes] }
        // A missing AniList planned total must not erase the catalog's explicit planned total.
        // It is never used as a released-episode count.
        if let stored = cached ?? titles.first(where:{ $0.id == id }) {
            if (media["episodes"] as? Int ?? 0) <= 0,stored.episodes > 0 { media["totalPlannedEpisodes"] = stored.episodes }
            if let released = stored.availableEpisodes { media["currentEpisodes"] = released }
            if stored.hasHungarian { media["hasHungarianSubtitles"] = true }
        }
        guard let anime = Anime(json:media) else { throw AppFailure.message("Anime metadata unavailable.") }
        return anime
    }
    func discover(query: String = "",genre: String = "",format: String = "",season: String = "",year: Int? = nil,sort: String = "TRENDING_DESC",page: Int = 1) async throws -> [Anime] {
        if Self.fixture { return [Self.fixtureAnime()].compactMap { $0 } }
        var args = ["type:ANIME","sort:$sort"]
        if !UserDefaults.standard.bool(forKey:"catalog.adult") { args.append("isAdult:false") };var defs = ["$p:Int","$sort:[MediaSort]"];var vars: [String:Any] = ["p":page,"sort":[sort]]
        for (key,value,type) in [("search",query,"String"),("genre",genre,"String"),("format",format,"MediaFormat"),("season",season,"MediaSeason")] where !value.isEmpty { args.append("\(key):$\(key)");defs.append("$\(key):\(type)");vars[key] = value }
        if let year { args.append("seasonYear:$year");defs.append("$year:Int");vars["year"] = year }
        let graph = "query(\(defs.joined(separator:","))){Page(page:$p,perPage:24){media(\(args.joined(separator:","))){\(Self.fields)}}}"
        let data = try await api.graph(graph,variables:vars);return ((data["Page"] as? [String:Any])?["media"] as? [[String:Any]] ?? []).compactMap { Anime(json:$0) }
    }
    func search(_ raw: String) async { searching = true;defer { searching = false };do { try await Task.sleep(for:.milliseconds(350));try Task.checkCancellation();let found = try await discover(query:raw);try Task.checkCancellation();results = found;searchError = nil } catch is CancellationError {} catch { if !Task.isCancelled { searchError = error.localizedDescription } } }
    func resolve(_ anime: Anime,episode: Int,language: String,refresh: Bool = false) async throws -> StreamInfo {
        guard episode > 0 else { throw AppFailure.message("Select an episode.") }
        var query = ["anilistId":String(anime.id),"episode":String(episode),"lang":language];if refresh { query["refresh"] = "1" }
        let bytes = try await api.data("/api/stream/resolve",query:query);try Task.checkCancellation()
        var info = try JSONDecoder().decode(StreamInfo.self,from:bytes)
        guard info.playbackURL != nil else { throw AppFailure.message(info.unavailableReason) }
        let prepared = try await CaptionPolicy.prepare(info.tracks ?? [],language:language)
        info.tracks = prepared.tracks;info.preparedCaptions = prepared.data
        for (raw,data) in prepared.data { if let url = URL(string:raw) { try? SubtitleCache.save(data,source:url) } }
        return info
    }
    func route(for anime: Anime,episode: Int,language: String,info: StreamInfo) throws -> PlaybackRoute {
        guard let url = info.playbackURL else { throw AppFailure.message(info.unavailableReason) }
        var route = PlaybackRoute(title:anime.title,url:url,key:"\(anime.id).\(episode)",subtitleURL:info.subtitle(language:language)?.url)
        route.anime = anime;route.episode = episode;route.language = language;route.info = info;route.episodeLabel = "Episode \(episode)"
        if route.subtitleURL == nil { route.subtitleMessage = "Selected subtitles unavailable. Choose another track in player options." }
        route.reload = { [self] in let fresh = try await resolve(anime,episode:episode,language:language,refresh:true);return try self.route(for:anime,episode:episode,language:language,info:fresh) }
        if episode < anime.episodeLimit(language:language) { route.next = { [self] in let fresh = try await resolve(anime,episode:episode+1,language:language);return try self.route(for:anime,episode:episode+1,language:language,info:fresh) } };return route
    }
}
