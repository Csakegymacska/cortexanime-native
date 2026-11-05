import SwiftUI

// MARK: - Credit & XP system (3.0)
// Watching earns credits, and credits unlock profile decorations.

/// One bar of the weekly recap.
struct WatchDay: Identifiable {
    var id: Date { day }
    let day: Date
    let label: String
    let seconds: Double
}

/// One entry of the rolling watch log (used by the weekly recap).
struct WatchTick: Codable, Identifiable {
    var id: String { "\(animeID)#\(episode)#\(date.timeIntervalSince1970)" }
    var date: Date
    var seconds: Double
    var completed: Bool
    var animeID: Int
    var episode: Int
    var title: String
}

struct CreditTx: Codable, Identifiable {
    let id: UUID
    let amount: Int
    let note: String
    let date: Date
}

enum CreditEvent {
    case episodeStarted
    case episodeCompleted
    case seriesCompleted
    case dailyOpen
    case badgeEarned

    var amount: Int {
        switch self {
        case .episodeStarted: return 5
        case .episodeCompleted: return 20
        case .seriesCompleted: return 120
        case .dailyOpen: return 25
        case .badgeEarned: return 40
        }
    }
    var note: String {
        switch self {
        case .episodeStarted: return "Episode started"
        case .episodeCompleted: return "Episode completed"
        case .seriesCompleted: return "Series completed"
        case .dailyOpen: return "Daily open"
        case .badgeEarned: return "Badge earned"
        }
    }
}

@MainActor final class CreditStore: ObservableObject {
    static let shared = CreditStore()
    private let defaults = UserDefaults.standard

    @Published private(set) var balance: Int
    @Published private(set) var lifetime: Int
    @Published private(set) var xp: Int
    @Published private(set) var unlocked: Set<String>
    @Published private(set) var equipped: String
    @Published private(set) var transactions: [CreditTx]

    // lifetime statistics (the basis of the credit and level system)
    @Published private(set) var episodesCompleted: Int
    @Published private(set) var episodesStarted: Int
    @Published private(set) var seriesCompleted: Int
    @Published private(set) var totalSeconds: Double
    @Published private(set) var streakDays: Int
    @Published private(set) var lastOpenDay: String
    @Published private(set) var badgesEarned: Set<String>

    /// Series-level completion tracking, so a re-watch never inflates the counters.
    @Published private(set) var completedEpisodes: Set<String>
    @Published private(set) var completedSeries: Set<String>
    /// Rolling watch log (last 400 ticks) that powers the weekly recap.
    @Published private(set) var watchLog: [WatchTick]
    /// Set when the stored XP crosses a level. The UI shows a celebration and clears it.
    @Published var pendingLevelUp: Int?

    private var rewardedEpisodes: Set<String>

    init() {
        balance = defaults.integer(forKey: "credits.balance")
        lifetime = defaults.integer(forKey: "credits.lifetime")
        xp = defaults.integer(forKey: "credits.xp")
        unlocked = Set(defaults.array(forKey: "credits.unlocked") as? [String] ?? [])
        equipped = defaults.string(forKey: "credits.equipped") ?? "none"
        transactions = (defaults.data(forKey: "credits.tx").flatMap { try? JSONDecoder().decode([CreditTx].self, from: $0) }) ?? []
        episodesCompleted = defaults.integer(forKey: "credits.epsCompleted")
        episodesStarted = defaults.integer(forKey: "credits.epsStarted")
        seriesCompleted = defaults.integer(forKey: "credits.seriesCompleted")
        totalSeconds = defaults.double(forKey: "credits.seconds")
        streakDays = defaults.integer(forKey: "credits.streak")
        lastOpenDay = defaults.string(forKey: "credits.lastDay") ?? ""
        badgesEarned = Set(defaults.array(forKey: "credits.badges") as? [String] ?? [])
        rewardedEpisodes = Set(defaults.array(forKey: "credits.rewarded") as? [String] ?? [])
        watchLog = (defaults.data(forKey: "credits.watchLog").flatMap { try? JSONDecoder().decode([WatchTick].self, from: $0) }) ?? []
        // Migration: before 3.0 only the counters existed. Anything already rewarded is
        // treated as completed, so the first launch after the update cannot double count.
        if let stored = defaults.array(forKey: "credits.completed") as? [String] {
            completedEpisodes = Set(stored)
        } else {
            completedEpisodes = rewardedEpisodes
        }
        completedSeries = Set(defaults.array(forKey: "credits.completedSeries") as? [String] ?? [])
        pendingLevelUp = nil
        // One-time repair. Until 3.0 the player reported its absolute position every ten
        // seconds as "watched time", so stored totals could be hundreds of hours too high.
        if !defaults.bool(forKey: "credits.secondsRepaired") {
            let ceiling = max(3600, Double(max(episodesStarted, 1)) * 1800)
            if totalSeconds > ceiling { totalSeconds = ceiling }
            defaults.set(true, forKey: "credits.secondsRepaired")
        }
    }

    // ---- level ----
    var level: Int { xp / 500 + 1 }
    var levelProgress: Double { Double(xp % 500) / 500.0 }
    var xpToNext: Int { 500 - (xp % 500) }

    // ---- awarding ----
    func award(_ event: CreditEvent) {
        add(event.amount, note: event.note)
        addXP(event.amount * 2)
        persist()
    }

    /// Adds XP and pays the level bonus exactly once per reached level.
    func addXP(_ amount: Int) {
        guard amount > 0 else { return }
        let before = level
        xp += amount
        let after = level
        guard after > before else { return }
        // Level reward: 50 credits plus 25 per level, paid for every level crossed.
        var bonus = 0
        for reached in (before + 1)...after { bonus += 50 + (reached - 1) * 25 }
        balance += bonus
        lifetime += bonus
        transactions.insert(CreditTx(id: UUID(), amount: bonus, note: "Level \(after) reward", date: Date()), at: 0)
        transactions = Array(transactions.prefix(60))
        pendingLevelUp = after
        persist()
    }

    func clearLevelUp() { pendingLevelUp = nil }

    /// 1.0.1: a fiók-egyenleg követése. Ha a szerveren több kredit van, mint a készüléken
    /// (például jóváírás történt), a különbözet jóváíródik. Soha nem von le semmit.
    func syncAccount(_ serverBalance: Int) {
        guard serverBalance > balance else { return }
        add(serverBalance - balance, note: "Account balance sync")
    }

    func add(_ n: Int, note: String) {
        guard n != 0 else { return }
        balance += n
        if n > 0 { lifetime += n }
        transactions.insert(CreditTx(id: UUID(), amount: n, note: note, date: Date()), at: 0)
        transactions = Array(transactions.prefix(60))
        persist()
    }

    /// Daily open + epizódfigyelés kezelése (a lejátszó hívja).
    func noteWatch(animeID: Int, animeTitle: String, episode: Int, completed: Bool, seconds: Double, duration: Double) {
        totalSeconds += max(0, seconds)
        // napi belépés
        let day = Self.dayFormatter.string(from: Date())
        if day != lastOpenDay {
            let yesterday = Self.dayFormatter.string(from: Date().addingTimeInterval(-86400))
            streakDays = (lastOpenDay == yesterday) ? streakDays + 1 : 1
            lastOpenDay = day
            award(.dailyOpen)
        }
        // Episode rewards happen once per anime + episode.
        let key = "\(animeID)#\(episode)"
        let finished = completed || (duration > 0 && seconds >= duration * 0.85)
        if !rewardedEpisodes.contains(key) {
            rewardedEpisodes.insert(key)
            episodesStarted += 1
            award(.episodeStarted)
        }
        // Completion is counted once per episode. Re-watching used to add to this counter
        // every single time, which inflated the profile statistics.
        if finished, !completedEpisodes.contains(key) {
            completedEpisodes.insert(key)
            episodesCompleted += 1
            award(.episodeCompleted)
            if let rec = AnimeLibrary.shared.history.first(where: { $0.anime.id == animeID }),
               rec.anime.episodes > 0, episode >= rec.anime.episodes,
               !completedSeries.contains(String(animeID)) {
                completedSeries.insert(String(animeID))
                seriesCompleted += 1
                award(.seriesCompleted)
            }
        }
        if rewardedEpisodes.count > 800 { rewardedEpisodes = Set(rewardedEpisodes.suffix(500)) }
        if completedEpisodes.count > 1200 { completedEpisodes = Set(completedEpisodes.suffix(800)) }
        recordTick(seconds: seconds, completed: finished, aniID: animeID, episode: episode, title: animeTitle)
        ProfileBadge.evaluate(store: self)
        persist()
    }

    // ---- watch log (weekly recap) ----
    private func recordTick(seconds: Double, completed: Bool, aniID: Int, episode: Int, title: String) {
        let last = watchLog.last
        let sameSession = last.map { Date().timeIntervalSince($0.date) < 600 } ?? false
        if sameSession, let last, last.animeID == aniID, last.episode == episode {
            // Merge short progress ticks into a single session entry.
            var merged = last
            merged.seconds += max(0, seconds)
            merged.completed = merged.completed || completed
            merged.date = Date()
            watchLog[watchLog.count - 1] = merged
        } else {
            watchLog.append(WatchTick(date: Date(), seconds: max(0, seconds), completed: completed,
                                      animeID: aniID, episode: episode, title: title))
        }
        if watchLog.count > 400 { watchLog = Array(watchLog.suffix(300)) }
    }

    func seconds(inLast days: Int) -> Double {
        let edge = Date().addingTimeInterval(-Double(days) * 86400)
        return watchLog.filter { $0.date >= edge }.reduce(0) { $0 + $1.seconds }
    }

    func episodes(inLast days: Int) -> Int {
        let edge = Date().addingTimeInterval(-Double(days) * 86400)
        return watchLog.filter { $0.date >= edge && $0.completed }.count
    }

    /// Daily watch seconds for the last seven days, oldest first.
    func weeklyBuckets() -> [WatchDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let total = watchLog.filter { $0.date >= day && $0.date < next }.reduce(0) { $0 + $1.seconds }
            return WatchDay(day: day, label: day.formatted(.dateTime.weekday(.narrow)), seconds: total)
        }
    }

    func hasCompleted(animeID: Int, episode: Int) -> Bool {
        completedEpisodes.contains("\(animeID)#\(episode)")
    }

    // ---- bolt ----
    /// A decoration is owned when it was bought, or when it is free in the catalogue.
    func isUnlocked(_ id: String) -> Bool {
        if id == "none" { return true }
        if unlocked.contains(id) { return true }
        return CortexDecoration.all.first(where: { $0.id == id })?.isFree ?? false
    }
    func buy(_ item: ShopItem) -> Bool {
        guard !isUnlocked(item.id), balance >= item.price else { return false }
        balance -= item.price
        unlocked.insert(item.id)
        transactions.insert(CreditTx(id: UUID(), amount: -item.price, note: "Purchased: \(item.name)", date: Date()), at: 0)
        persist()
        return true
    }
    /// True when the id is part of the worn stack (a frame + an aura can be worn together).
    func isWearing(_ id: String) -> Bool {
        if equipped == id { return true }
        return CortexDecoration.list(equipped).contains { $0.id == id }
    }

    func equip(_ id: String) {
        equipped = id
        persist()
    }

    // ---- jelvények ----
    func earnBadge(_ id: String) {
        guard !badgesEarned.contains(id) else { return }
        badgesEarned.insert(id)
        award(.badgeEarned)
        persist()
    }

    private func persist() {
        defaults.set(balance, forKey: "credits.balance")
        defaults.set(lifetime, forKey: "credits.lifetime")
        defaults.set(xp, forKey: "credits.xp")
        defaults.set(Array(unlocked), forKey: "credits.unlocked")
        defaults.set(equipped, forKey: "credits.equipped")
        defaults.set(episodesCompleted, forKey: "credits.epsCompleted")
        defaults.set(episodesStarted, forKey: "credits.epsStarted")
        defaults.set(seriesCompleted, forKey: "credits.seriesCompleted")
        defaults.set(totalSeconds, forKey: "credits.seconds")
        defaults.set(streakDays, forKey: "credits.streak")
        defaults.set(lastOpenDay, forKey: "credits.lastDay")
        defaults.set(Array(badgesEarned), forKey: "credits.badges")
        defaults.set(Array(rewardedEpisodes), forKey: "credits.rewarded")
        defaults.set(Array(completedEpisodes), forKey: "credits.completed")
        defaults.set(Array(completedSeries), forKey: "credits.completedSeries")
        if let log = try? JSONEncoder().encode(watchLog) { defaults.set(log, forKey: "credits.watchLog") }
        if let data = try? JSONEncoder().encode(transactions) { defaults.set(data, forKey: "credits.tx") }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Jelvények (achievementek)

struct ProfileBadge: Identifiable {
    let id: String
    let name: String
    let detail: String
    let icon: String
    let rarity: Int // 0 common, 1 rare, 2 epic, 3 legendary

    static let all: [ProfileBadge] = [
        ProfileBadge(id: "first", name: "First Steps", detail: "Watch your first episode", icon: "sparkles", rarity: 0),
        ProfileBadge(id: "ep10", name: "Warm Up", detail: "Watch 10 episodes", icon: "flame", rarity: 0),
        ProfileBadge(id: "ep50", name: "Maraton", detail: "Watch 50 episodes", icon: "bolt.fill", rarity: 1),
        ProfileBadge(id: "ep100", name: "Centurion", detail: "Watch 100 episodes", icon: "trophy.fill", rarity: 2),
        ProfileBadge(id: "series1", name: "Finisher", detail: "Complete your first series", icon: "checkmark.seal.fill", rarity: 1),
        ProfileBadge(id: "series5", name: "Librarian", detail: "Complete 5 series", icon: "books.vertical.fill", rarity: 2),
        ProfileBadge(id: "streak7", name: "Loyal", detail: "Keep a 7-day watch streak", icon: "calendar.badge.checkmark", rarity: 2),
        ProfileBadge(id: "level5", name: "Rising Star", detail: "Reach level 5", icon: "arrow.up.circle.fill", rarity: 1),
        ProfileBadge(id: "level10", name: "Veteran", detail: "Reach level 10", icon: "crown.fill", rarity: 3),
        ProfileBadge(id: "collector", name: "Collector", detail: "Unlock 3 decorations", icon: "paintpalette.fill", rarity: 1),
        ProfileBadge(id: "decor8", name: "Style Icon", detail: "Unlock 8 decorations", icon: "wand.and.stars", rarity: 3),
        ProfileBadge(id: "hours24", name: "All Day", detail: "Watch 24 hours in total", icon: "clock.fill", rarity: 2),
        ProfileBadge(id: "wardrobe", name: "Wardrobe", detail: "Unlock 20 decorations", icon: "bag.fill", rarity: 2),
        ProfileBadge(id: "legendary", name: "Legendary Owner", detail: "Unlock a legendary decoration", icon: "crown.fill", rarity: 3),
        ProfileBadge(id: "devoted", name: "Devoted", detail: "Watch 100 hours in total", icon: "hourglass", rarity: 3)
    ]

    /// Current value and goal behind a badge, so the UI can show real progress.
    @MainActor func progress(store: CreditStore) -> (value: Double, goal: Double) {
        switch id {
        case "first": return (Double(store.episodesCompleted), 1)
        case "ep10": return (Double(store.episodesCompleted), 10)
        case "ep50": return (Double(store.episodesCompleted), 50)
        case "ep100": return (Double(store.episodesCompleted), 100)
        case "series1": return (Double(store.seriesCompleted), 1)
        case "series5": return (Double(store.seriesCompleted), 5)
        case "streak7": return (Double(store.streakDays), 7)
        case "level5": return (Double(store.level), 5)
        case "level10": return (Double(store.level), 10)
        case "collector": return (Double(store.unlocked.count), 3)
        case "decor8": return (Double(store.unlocked.count), 8)
        case "hours24": return (store.totalSeconds / 3600, 24)
        case "wardrobe": return (Double(store.unlocked.count), 20)
        case "legendary": return (CortexDecoration.all.contains { $0.rarity == 3 && store.isUnlocked($0.id) } ? 1 : 0, 1)
        case "devoted": return (store.totalSeconds / 3600, 100)
        default: return (0, 1)
        }
    }

    @MainActor func fraction(store: CreditStore) -> Double {
        let p = progress(store: store)
        guard p.goal > 0 else { return 1 }
        return min(1, max(0, p.value / p.goal))
    }

    @MainActor static func evaluate(store: CreditStore) -> [ProfileBadge] {
        for b in all {
            let earned: Bool
            switch b.id {
            case "first": earned = store.episodesCompleted >= 1
            case "ep10": earned = store.episodesCompleted >= 10
            case "ep50": earned = store.episodesCompleted >= 50
            case "ep100": earned = store.episodesCompleted >= 100
            case "series1": earned = store.seriesCompleted >= 1
            case "series5": earned = store.seriesCompleted >= 5
            case "streak7": earned = store.streakDays >= 7
            case "level5": earned = store.level >= 5
            case "level10": earned = store.level >= 10
            case "collector": earned = store.unlocked.count >= 3
            case "decor8": earned = store.unlocked.count >= 8
            case "hours24": earned = store.totalSeconds >= 86400
            case "wardrobe": earned = store.unlocked.count >= 20
            case "legendary":
                earned = CortexDecoration.all.contains { $0.rarity == 3 && store.isUnlocked($0.id) }
            case "devoted": earned = store.totalSeconds >= 360000
            default: earned = false
            }
            if earned { store.earnBadge(b.id) }
        }
        return all
    }
}
