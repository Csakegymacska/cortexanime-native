import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Indexes the Hungarian catalog for on-device Spotlight search.
///
/// Fire-and-forget on purpose: indexing is a nicety, and a failed index must never block
/// the catalog. Items carry a plain cortanime.eu link plus the anime id, which the app
/// turns back into a detail screen when the result is tapped.
enum SpotlightIndex {
    static let domain = "eu.cortex.anime.port.series"
    private static let stampKey = "spotlight.indexedAt"
    private static let prefix = "anime-"
    private static let maximum = 300

    static func animeID(from identifier: String) -> Int? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return Int(identifier.dropFirst(prefix.count))
    }

    /// Re-indexes at most once a day (or when forced) and only when the catalog is known.
    static func refreshIfNeeded(_ titles: [Anime], force: Bool = false) {
        guard !titles.isEmpty else { return }
        let last = UserDefaults.standard.double(forKey: stampKey)
        if !force, last > 0, Date().timeIntervalSince1970 - last < 86_400 { return }

        let items: [CSSearchableItem] = titles.prefix(maximum).map { anime in
            let attributes = CSSearchableItemAttributeSet(contentType: .item)
            attributes.title = anime.title
            attributes.displayName = anime.title
            attributes.contentDescription = anime.hasHungarian
                ? "Hungarian subtitles available · \(anime.episodeSummary)"
                : anime.plainSynopsis.isEmpty ? "Anime" : String(anime.plainSynopsis.prefix(180))
            attributes.keywords = ["anime", "CortexAnime", "magyar felirat", "hungarian subtitles"] + Array(anime.genres.prefix(4))
            attributes.thumbnailURL = anime.cover
            attributes.contentURL = URL(string: "https://cortanime.eu/anime/\(anime.id)")
            return CSSearchableItem(uniqueIdentifier: prefix + String(anime.id),
                                    domainIdentifier: domain,
                                    attributeSet: attributes)
        }
        guard !items.isEmpty else { return }

        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
            }
        }
    }
}
