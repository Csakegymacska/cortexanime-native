import Foundation

// MARK: - Media

/// One title, decoded from any of the site's payload shapes:
/// `/api/home-live` (id is "al:212888"), `/api/hu-catalog` (id is 269)
/// and the GraphQL proxy (`/api/metadata/graphql`, AniList shape).
struct TVMedia: Identifiable, Decodable, Hashable {
    let aid: Int
    let title: String
    let originalTitle: String?
    let cover: String?
    let banner: String?
    let synopsis: String?
    let totalEpisodes: Int?
    let releasedEpisodes: Int?
    let status: String?
    let genres: [String]
    let score: Double?
    let hasHungarian: Bool

    var id: Int { aid }

    enum CodingKeys: String, CodingKey {
        case anilistId, id, title, hungarianTitle, titleEnglish, titleRomaji
        case cover, coverImage, banner, bannerImage, synopsis
        case episodes, currentEpisodes, totalEpisodes, status, genres, score
        case hasHungarianSubtitles, hasHungarianSub
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        var resolved: Int? = (try? c.decodeIfPresent(Int.self, forKey: .anilistId)) ?? nil
        if resolved == nil { resolved = (try? c.decodeIfPresent(Int.self, forKey: .id)) ?? nil }
        if resolved == nil, let raw = try? c.decodeIfPresent(String.self, forKey: .id), let text = raw {
            resolved = Int(text.replacingOccurrences(of: "al:", with: ""))
        }
        guard let resolvedAid = resolved else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "missing anilist id"))
        }
        aid = resolvedAid

        let hungarian = (try? c.decodeIfPresent(String.self, forKey: .hungarianTitle)) ?? nil
        let plain = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        let english = (try? c.decodeIfPresent(String.self, forKey: .titleEnglish)) ?? nil
        let romaji = (try? c.decodeIfPresent(String.self, forKey: .titleRomaji)) ?? nil
        title = hungarian ?? plain ?? english ?? romaji ?? "Untitled"
        originalTitle = [romaji, english, plain].compactMap { $0 }.first { $0 != title }

        let coverA = (try? c.decodeIfPresent(String.self, forKey: .cover)) ?? nil
        let coverB = (try? c.decodeIfPresent(String.self, forKey: .coverImage)) ?? nil
        cover = coverA ?? coverB
        let bannerA = (try? c.decodeIfPresent(String.self, forKey: .banner)) ?? nil
        let bannerB = (try? c.decodeIfPresent(String.self, forKey: .bannerImage)) ?? nil
        banner = bannerA ?? bannerB

        synopsis = (try? c.decodeIfPresent(String.self, forKey: .synopsis)) ?? nil
        totalEpisodes = ((try? c.decodeIfPresent(Int.self, forKey: .totalEpisodes)) ?? nil)
            ?? ((try? c.decodeIfPresent(Int.self, forKey: .episodes)) ?? nil)
        releasedEpisodes = (try? c.decodeIfPresent(Int.self, forKey: .currentEpisodes)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        genres = ((try? c.decodeIfPresent([String].self, forKey: .genres)) ?? nil) ?? []
        score = (try? c.decodeIfPresent(Double.self, forKey: .score)) ?? nil

        let flagA = (try? c.decodeIfPresent(Bool.self, forKey: .hasHungarianSubtitles)) ?? nil
        let flagB = (try? c.decodeIfPresent(Bool.self, forKey: .hasHungarianSub)) ?? nil
        hasHungarian = flagA ?? flagB ?? false
    }

    init(aid: Int, title: String, originalTitle: String?, cover: String?, banner: String?,
         synopsis: String?, totalEpisodes: Int?, releasedEpisodes: Int?, status: String?,
         genres: [String], score: Double?, hasHungarian: Bool) {
        self.aid = aid
        self.title = title
        self.originalTitle = originalTitle
        self.cover = cover
        self.banner = banner
        self.synopsis = synopsis
        self.totalEpisodes = totalEpisodes
        self.releasedEpisodes = releasedEpisodes
        self.status = status
        self.genres = genres
        self.score = score
        self.hasHungarian = hasHungarian
    }
}

// MARK: - Home

struct TVHomePayload: Decodable {
    let trending: [TVMedia]
    let seasonal: [TVMedia]

    enum CodingKeys: String, CodingKey { case trending, seasonal, airing }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trending = ((try? c.decodeIfPresent([TVMedia].self, forKey: .trending)) ?? nil) ?? []
        seasonal = ((try? c.decodeIfPresent([TVMedia].self, forKey: .seasonal)) ?? nil) ?? []
    }
}

// MARK: - Episodes

struct TVEpisode: Identifiable, Decodable, Hashable {
    let number: Int
    let title: String?
    let thumbnail: String?

    var id: Int { number }

    enum CodingKeys: String, CodingKey { case episode, title, thumbnail }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number = (try? c.decode(Int.self, forKey: .episode)) ?? 1
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil
        thumbnail = (try? c.decodeIfPresent(String.self, forKey: .thumbnail)) ?? nil
    }

    init(number: Int, title: String?, thumbnail: String?) {
        self.number = number
        self.title = title
        self.thumbnail = thumbnail
    }
}

struct TVEpisodesPayload: Decodable {
    let episodes: [TVEpisode]
    let totalEpisodes: Int?
    let currentEpisodes: Int?
}

// MARK: - Stream resolve

struct TVTrack: Decodable, Hashable {
    let file: String?
    let label: String?
    let isDefault: Bool?

    enum CodingKeys: String, CodingKey { case file, label, `default` }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = (try? c.decodeIfPresent(String.self, forKey: .file)) ?? nil
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? nil
        isDefault = (try? c.decodeIfPresent(Bool.self, forKey: .default)) ?? nil
    }
}

struct TVResolve: Decodable {
    let found: Bool?
    let streamUrl: String?
    let embedUrl: String?
    let type: String?
    let server: String?
    let notReleased: Bool?
    let nextEpisode: Int?
    let airingAt: Int?
    let error: String?
    let tracks: [TVTrack]

    enum CodingKeys: String, CodingKey {
        case found, streamUrl, embedUrl, type, server, notReleased, nextEpisode, airingAt, error, tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        found = (try? c.decodeIfPresent(Bool.self, forKey: .found)) ?? nil
        streamUrl = (try? c.decodeIfPresent(String.self, forKey: .streamUrl)) ?? nil
        embedUrl = (try? c.decodeIfPresent(String.self, forKey: .embedUrl)) ?? nil
        type = (try? c.decodeIfPresent(String.self, forKey: .type)) ?? nil
        server = (try? c.decodeIfPresent(String.self, forKey: .server)) ?? nil
        notReleased = (try? c.decodeIfPresent(Bool.self, forKey: .notReleased)) ?? nil
        nextEpisode = (try? c.decodeIfPresent(Int.self, forKey: .nextEpisode)) ?? nil
        airingAt = (try? c.decodeIfPresent(Int.self, forKey: .airingAt)) ?? nil
        error = (try? c.decodeIfPresent(String.self, forKey: .error)) ?? nil
        tracks = ((try? c.decodeIfPresent([TVTrack].self, forKey: .tracks)) ?? nil) ?? []
    }

    var playableURL: URL? {
        guard let text = streamUrl, let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }

    /// Human readable reason, never a raw server payload.
    var failureText: String {
        if notReleased == true {
            if let next = nextEpisode, let at = airingAt, at > 0 {
                let date = Date(timeIntervalSince1970: TimeInterval(at))
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "hu_HU")
                formatter.dateFormat = "MMMM d., HH:mm"
                return "Episode \(next) has not aired yet. Expected: \(formatter.string(from: date))."
            }
            return "This episode has not aired yet."
        }
        switch error {
        case "no-raw-source": return "The source is not serving this episode right now. Try again later."
        case "native_source_unavailable": return "The source did not respond for this episode. Try again in a moment."
        default: return "No playable source was returned. Try again."
        }
    }
}

// MARK: - GraphQL search result

struct TVGraphPayload: Decodable {
    let data: TVGraphData?
}

struct TVGraphData: Decodable {
    let Page: TVGraphPage?
}

/// `/api/metadata/graphql` with a single `Media(id:)` query answers `data.Media`.
struct TVSingleMediaPayload: Decodable {
    let data: TVSingleMediaData?
}

struct TVSingleMediaData: Decodable {
    let Media: TVGraphMedia?
}

struct TVGraphPage: Decodable {
    let media: [TVGraphMedia]
}

struct TVGraphMedia: Decodable {
    let id: Int
    let episodes: Int?
    let status: String?
    let genres: [String]?
    let title: TVGraphTitle?
    let coverImage: TVGraphCover?
    let bannerImage: String?

    struct TVGraphTitle: Decodable {
        let romaji: String?
        let english: String?
    }

    struct TVGraphCover: Decodable {
        let large: String?
    }

    var asMedia: TVMedia {
        TVMedia(aid: id,
                title: title?.english ?? title?.romaji ?? "Untitled",
                originalTitle: title?.romaji,
                cover: coverImage?.large,
                banner: bannerImage,
                synopsis: nil,
                totalEpisodes: episodes,
                releasedEpisodes: nil,
                status: status,
                genres: genres ?? [],
                score: nil,
                hasHungarian: false)
    }
}
