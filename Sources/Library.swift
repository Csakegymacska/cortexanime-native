import SwiftUI

struct WatchRecord: Codable, Identifiable {
    let anime: Anime
    var episode: Int
    var language: String
    var seconds: Double
    var duration: Double
    var completed: Bool
    var updatedAt: Date
    var id: Int { anime.id }
}
@MainActor final class AnimeLibrary: ObservableObject {
    static let shared = AnimeLibrary()
    @Published private(set) var favorites: Set<Int>
    @Published private(set) var history: [WatchRecord]
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Set(defaults.array(forKey: "library.favorites") as? [Int] ?? [])
        history = (defaults.data(forKey: "library.history").flatMap { try? JSONDecoder().decode([WatchRecord].self, from: $0) }) ?? []
    }
    func mergeFavorites(_ ids: Set<Int>) { favorites.formUnion(ids); defaults.set(Array(favorites), forKey:"library.favorites") }
    func toggle(_ id: Int) { if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }; defaults.set(Array(favorites), forKey: "library.favorites") }
    func record(anime: Anime, episode: Int, language: String, seconds: Double, duration: Double, completed: Bool = false) {
        guard seconds.isFinite, seconds >= 0, episode > 0 else { return }
        history.removeAll { $0.id == anime.id }
        history.insert(WatchRecord(anime: anime, episode: episode, language: language, seconds: seconds, duration: duration.isFinite ? max(0, duration) : 0, completed: completed, updatedAt: Date()), at: 0)
        history = Array(history.prefix(40))
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "library.history") }
    }
    func removeHistory(_ ids: Set<Int>) { history.removeAll { ids.contains($0.id) }; if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "library.history") } }
    func clearHistory() { history = []; defaults.removeObject(forKey: "library.history") }
}
