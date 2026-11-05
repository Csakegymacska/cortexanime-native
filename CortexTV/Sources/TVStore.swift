import Foundation
import SwiftUI

@MainActor
final class TVStore: ObservableObject {
    @Published private(set) var trending: [TVMedia] = []
    @Published private(set) var seasonal: [TVMedia] = []
    @Published private(set) var hungarian: [TVMedia] = []
    @Published private(set) var loading = true
    @Published private(set) var loadError: String?

    private let base = URL(string: "https://cortanime.eu")!
    private let session: URLSession
    private var mediaCache: [Int: TVMedia] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard loading || (trending.isEmpty && hungarian.isEmpty) else { return }
        await reload()
    }

    func reload() async {
        loading = true
        loadError = nil
        async let homePayload: TVHomePayload? = fetchHome()
        async let catalog: [TVMedia] = fetchHungarianCatalog()
        let home = await homePayload
        let catalogue = await catalog
        if let home {
            trending = home.trending
            seasonal = home.seasonal
        }
        hungarian = catalogue
        for item in trending + seasonal + catalogue { mediaCache[item.aid] = item }
        if trending.isEmpty && catalogue.isEmpty {
            loadError = "No data arrived from the server. Check your connection, then choose Try again."
        }
        loading = false
    }

    private func fetchHome() async -> TVHomePayload? {
        await decode(TVHomePayload.self, from: try? url("/api/home-live"))
    }

    private func fetchHungarianCatalog() async -> [TVMedia] {
        await decode([TVMedia].self, from: try? url("/api/hu-catalog")) ?? []
    }

    // MARK: - Detail

    func media(for aid: Int) async -> TVMedia? {
        if let cached = mediaCache[aid] { return cached }
        let payload = await decode(TVSingleMediaPayload.self, from: try? url("/api/metadata/graphql"), method: "POST", body: [
            "query": "query($id:Int){Media(id:$id,type:ANIME){id episodes status genres title{romaji english} coverImage{large} bannerImage}}",
            "variables": ["id": aid]
        ])
        guard let media = payload?.data?.Media?.asMedia else { return nil }
        mediaCache[aid] = media
        return media
    }

    func episodes(for aid: Int) async -> [TVEpisode] {
        let payload = await decode(TVEpisodesPayload.self, from: try? url("/api/episodes", query: ["anilistId": String(aid)]))
        return (payload?.episodes ?? []).sorted { $0.number < $1.number }
    }

    // MARK: - Search

    func search(_ text: String) async -> [TVMedia] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let local = hungarian.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
        if local.count >= 8 { return Array(local.prefix(40)) }

        let payload = await decode(TVGraphPayload.self, from: try? url("/api/anilist/search", query: ["q": trimmed]))
        var seen = Set<Int>()
        var results: [TVMedia] = []
        for media in local + (payload?.data?.Page?.media.map(\.asMedia) ?? []) where seen.insert(media.aid).inserted {
            results.append(media)
        }
        return results
    }

    // MARK: - Playback

    func resolve(aid: Int, episode: Int, language: String = "hun") async throws -> TVResolve {
        guard let requestURL = try? url("/api/stream/resolve", query: [
            "anilistId": String(aid), "episode": String(episode), "lang": language
        ]) else { throw TVStoreError.message("Invalid request.") }
        var request = URLRequest(url: requestURL)
        request.setValue("CortexTV/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TVStoreError.message("The server did not respond.") }
        guard (200..<300).contains(http.statusCode) else {
            throw TVStoreError.message("The server returned an error (\(http.statusCode)). Try again.")
        }
        return try JSONDecoder().decode(TVResolve.self, from: data)
    }

    func subtitles(aid: Int, episode: Int, language: String = "hu") async -> [TVSubtitleCue] {
        guard let requestURL = try? url("/api/\(language == "hu" ? "hu" : "en")-subs/\(aid)/\(episode).vtt") else { return [] }
        var request = URLRequest(url: requestURL)
        request.setValue("CortexTV/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return TVVTT.parse(text)
    }

    // MARK: - Plumbing

    private func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard path.hasPrefix("/"), var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw TVStoreError.message("Invalid path.")
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let result = components.url else { throw TVStoreError.message("Invalid address.") }
        return result
    }

    private func decode<T: Decodable>(_ type: T.Type, from address: URL?, method: String = "GET", body: [String: Any]? = nil) async -> T? {
        guard let address else { return nil }
        var request = URLRequest(url: address)
        request.setValue("CortexTV/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            request.httpMethod = method
        }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum TVStoreError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}
