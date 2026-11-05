import Foundation

/// Explicit, truthful contracts for the AniList feed and its mapped Kitsu backup.
/// A start-date quarter is not silently presented as an authoritative anime season.
enum MetadataFeedPolicy {
    struct Context {
        let source: String
        let backup: Bool
        let date: Date
    }
    static func canFallback(status: Int) -> Bool {
        status == 403 || status == 408 || status == 429 || (500...599).contains(status)
    }
    static func context(_ result: [String: Any], now: Date = Date()) -> Context? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.component(.month, from: now), year = calendar.component(.year, from: now)
        let season = ["winter","spring","summer","fall"][(month-1)/3]
        guard result["season"] as? String == season, result["year"] as? Int == year,
              let source = result["source"] as? String,
              let tr = result["trending"] as? [[String: Any]], !tr.isEmpty,
              let se = result["seasonal"] as? [[String: Any]],
              let timestamp = result["fetchedAt"] as? String else { return nil }
        let backup = source == "Kitsu"
        if backup {
            guard result["fallback"] as? Bool == true, result["partial"] as? Bool == true,
                  result["identity"] as? String == "ANILIST_MAPPED",
                  result["seasonalScope"] as? String == "START_DATE_QUARTER",
                  result["ranking"] as? String == "POPULARITY_ASC" else { return nil }
        } else {
            guard source == "AniList", result["ranking"] as? String == "TRENDING_DESC", !se.isEmpty else { return nil }
        }
        guard (tr+se).allSatisfy({ row in
            guard let id = row["anilistId"] as? Int, id > 0 else { return false }
            return row["id"] as? String == "al:\(id)"
        }) else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        guard let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else { return nil }
        let age = now.timeIntervalSince(date)
        guard age >= -60, age <= (backup ? 3600 : 86400) else { return nil }
        return Context(source:source,backup:backup,date:date)
    }
}
