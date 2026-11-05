import SwiftUI

// MARK: - 1.5.0 · Taste Engine
//
// A recommender you can read. Every pick comes with the reason it was picked,
// and every reason is one of your own settings: a genre weight, a mood, a
// runtime cap, a year window. Nothing is hidden behind a model — if the
// suggestions are wrong you can see exactly which dial to turn.

@MainActor final class Taste15Store: ObservableObject {
    static let shared = Taste15Store()

    @Published var weights: [String: Int] { didSet { persist() } }
    @Published var maxEpisodes: Int { didSet { defaults.set(maxEpisodes, forKey: "lab15.taste.maxEp") } }
    @Published var minScore: Double { didSet { defaults.set(minScore, forKey: "lab15.taste.minScore") } }
    @Published var onlyHungarian: Bool { didSet { defaults.set(onlyHungarian, forKey: "lab15.taste.onlyHu") } }
    @Published var onlyFinished: Bool { didSet { defaults.set(onlyFinished, forKey: "lab15.taste.finished") } }
    @Published var excludeWatched: Bool { didSet { defaults.set(excludeWatched, forKey: "lab15.taste.exclude") } }
    @Published var diversity: Double { didSet { defaults.set(diversity, forKey: "lab15.taste.diversity") } }
    @Published var mood: Taste15Mood { didSet { defaults.set(mood.rawValue, forKey: "lab15.taste.mood") } }

    private let defaults = UserDefaults.standard

    init() {
        let raw = defaults.string(forKey: "lab15.taste.weights")
        let data = raw?.data(using: .utf8)
        weights = (data.flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) }) ?? [:]
        maxEpisodes = defaults.object(forKey: "lab15.taste.maxEp") as? Int ?? 0
        minScore = defaults.object(forKey: "lab15.taste.minScore") as? Double ?? 0
        onlyHungarian = defaults.object(forKey: "lab15.taste.onlyHu") as? Bool ?? false
        onlyFinished = defaults.object(forKey: "lab15.taste.finished") as? Bool ?? false
        excludeWatched = defaults.object(forKey: "lab15.taste.exclude") as? Bool ?? true
        diversity = defaults.object(forKey: "lab15.taste.diversity") as? Double ?? 0.35
        mood = Taste15Mood(rawValue: defaults.string(forKey: "lab15.taste.mood") ?? "") ?? .any
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(weights) {
            defaults.set(String(decoding: data, as: UTF8.self), forKey: "lab15.taste.weights")
        }
    }

    func weight(for genre: String) -> Int { weights[genre] ?? 0 }

    func bump(_ genre: String, by delta: Int) {
        let next = min(3, max(-3, (weights[genre] ?? 0) + delta))
        if next == 0 { weights.removeValue(forKey: genre) } else { weights[genre] = next }
    }

    func resetWeights() { weights = [:] }

    func resetAll() {
        weights = [:]; maxEpisodes = 0; minScore = 0
        onlyHungarian = false; onlyFinished = false
        excludeWatched = true; diversity = 0.35; mood = .any
    }

    /// Saved filter presets — three slots, enough to keep a "short and finished"
    /// and a "long runner" configuration without a naming dialog.
    func savePreset(_ slot: Int) {
        let payload: [String: Any] = [
            "max": maxEpisodes, "score": minScore, "hu": onlyHungarian,
            "finished": onlyFinished, "diversity": diversity, "mood": mood.rawValue,
        ]
        defaults.set(payload, forKey: "lab15.taste.preset.\(slot)")
    }

    func loadPreset(_ slot: Int) -> Bool {
        guard let payload = defaults.dictionary(forKey: "lab15.taste.preset.\(slot)") else { return false }
        maxEpisodes = payload["max"] as? Int ?? 0
        minScore = payload["score"] as? Double ?? 0
        onlyHungarian = payload["hu"] as? Bool ?? false
        onlyFinished = payload["finished"] as? Bool ?? false
        diversity = payload["diversity"] as? Double ?? 0.35
        mood = Taste15Mood(rawValue: payload["mood"] as? String ?? "") ?? .any
        return true
    }

    func hasPreset(_ slot: Int) -> Bool { defaults.dictionary(forKey: "lab15.taste.preset.\(slot)") != nil }
}

enum Taste15Mood: String, CaseIterable, Identifiable {
    case any, chill, hype, dark, romance, funny, brainy, feels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .chill: return "Chill"
        case .hype: return "Hype"
        case .dark: return "Dark"
        case .romance: return "Romance"
        case .funny: return "Funny"
        case .brainy: return "Brainy"
        case .feels: return "Feels"
        }
    }

    var genres: [String] {
        switch self {
        case .any: return []
        case .chill: return ["Slice of Life", "Comedy", "Iyashikei"]
        case .hype: return ["Action", "Adventure", "Sports", "Mecha"]
        case .dark: return ["Thriller", "Horror", "Psychological", "Mystery"]
        case .romance: return ["Romance", "Drama", "Shoujo"]
        case .funny: return ["Comedy", "Parody", "Gag"]
        case .brainy: return ["Mystery", "Sci-Fi", "Psychological", "Supernatural"]
        case .feels: return ["Drama", "Slice of Life", "Music", "Romance"]
        }
    }

    var detail: String {
        switch self {
        case .any: return "No mood filter — your genre weights decide."
        case .chill: return "Slow, warm, low stakes. Nothing bad happens to anyone."
        case .hype: return "Momentum, fights, tournaments, and a soundtrack that shouts."
        case .dark: return "Tension, dread and a plot that keeps secrets from you."
        case .romance: return "Two people, too much time, and one confession too late."
        case .funny: return "Gags first. Plot is welcome but not required."
        case .brainy: return "Puzzles, rules and a mystery that plays fair."
        case .feels: return "The kind of ending that makes you sit still for a minute."
        }
    }
}

/// One scored suggestion with the reason it exists.
struct Taste15Pick: Identifiable {
    var id: Int { anime.id }
    let anime: Anime
    let score: Int
    let reason: String
}

struct TasteEngine15View: View {
    @ObservedObject private var store = Taste15Store.shared
    @EnvironmentObject private var catalog: CatalogModel
    @State private var sort: Taste15Sort = .match
    @State private var showAll = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                LabChips(items: Taste15Mood.allCases, label: { $0.title }, selection: $store.mood)
                Text(store.mood.detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)

                LabCard(title: "Filters", footnote: "Filters remove titles before scoring. Weights only change the order, so a strict filter can still return a long list.") {
                    LabRow(title: "Episode cap", detail: store.maxEpisodes == 0 ? "No cap" : "\(store.maxEpisodes) episodes or fewer", symbol: "number") {
                        Stepper("", value: $store.maxEpisodes, in: 0...200, step: 12).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Minimum score", detail: store.minScore == 0 ? "Any score" : String(format: "%.1f and above", store.minScore), symbol: "star.fill") {
                        Stepper("", value: $store.minScore, in: 0...9, step: 0.5).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Hungarian subtitles", detail: "Only titles with HU subs", symbol: "character.book.closed") {
                        Toggle("", isOn: $store.onlyHungarian).labelsHidden()
                    }
                    LabRow(title: "Finished only", detail: "Nothing that is still airing", symbol: "checkmark.circle") {
                        Toggle("", isOn: $store.onlyFinished).labelsHidden()
                    }
                    LabRow(title: "Skip what I watched", detail: "Uses your watch log", symbol: "eye.slash") {
                        Toggle("", isOn: $store.excludeWatched).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Diversity", detail: String(format: "%.0f%% — how far from your usual it may wander", store.diversity * 100), symbol: "dial.medium") {
                        Slider(value: $store.diversity, in: 0...1).frame(width: 120)
                    }
                }

                genreWeights
                presets
                results
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Taste Engine")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: genre weights

    private var genres: [String] {
        var counts: [String: Int] = [:]
        for title in catalog.titles {
            for genre in title.genres { counts[genre, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.prefix(18).map { $0.key }
    }

    private var genreWeights: some View {
        LabCard(title: "Genre weights", footnote: "+3 always, -3 never. A weight of zero leaves the genre neutral, which is not the same as disliking it.") {
            if genres.isEmpty {
                Text("The catalogue is still loading. Weights appear once it has titles.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).padding(.vertical, 8)
            } else {
                ForEach(genres, id: \.self) { genre in
                    HStack(spacing: 10) {
                        Text(genre).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        Button { store.bump(genre, by: -1) } label: {
                            Image(systemName: "minus.circle").font(.system(size: 17))
                        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
                        Text("\(store.weight(for: genre))")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(width: 22)
                            .foregroundStyle(store.weight(for: genre) == 0 ? .white.opacity(0.35) : Color.cortexPurple)
                        Button { store.bump(genre, by: 1) } label: {
                            Image(systemName: "plus.circle").font(.system(size: 17))
                        }.buttonStyle(.plain).foregroundStyle(Color.cortexPurple)
                    }
                    .padding(.vertical, 5)
                }
                Button("Reset every weight") { store.resetWeights() }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.vertical, 8)
            }
        }
    }

    // MARK: presets

    private var presets: some View {
        LabCard(title: "Presets", footnote: "Three slots. Saving overwrites the slot without asking — the live filters above stay as they are.") {
            ForEach(1...3, id: \.self) { slot in
                HStack {
                    Text("Slot \(slot)").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Load") { _ = store.loadPreset(slot) }
                        .font(.system(size: 12, weight: .bold))
                        .disabled(!store.hasPreset(slot))
                    Button("Save") { store.savePreset(slot) }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.leading, 10)
                }
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: results

    private var results: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeading(title: "Your picks")
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Taste15Sort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Text(sort.title).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cortexPurple)
                }
            }
            Text("\(picks.count) titles match the filters")
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.42))

            if let top = picks.first {
                topPick(top)
            }

            ForEach(Array(picks.dropFirst().prefix(showAll ? 60 : 8))) { pick in
                HStack(alignment: .top, spacing: 11) {
                    AnimeArtwork(url: pick.anime.cover)
                        .frame(width: 52, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pick.anime.title).font(.system(size: 13, weight: .bold)).lineLimit(2)
                        Text(pick.reason).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                        HStack(spacing: 6) {
                            Pill(text: "\(pick.score)", color: .cortexMint)
                            if let score = pick.anime.score { Pill(text: String(format: "%.1f", score), color: .yellow) }
                            if pick.anime.hasHungarian { Pill(text: "HU", color: .cortexPurple) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            if picks.count > 9 {
                Button(showAll ? "Show fewer" : "Show all \(picks.count)") { showAll.toggle() }
                    .font(.system(size: 12, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func topPick(_ pick: Taste15Pick) -> some View {
        HStack(spacing: 13) {
            AnimeArtwork(url: pick.anime.banner ?? pick.anime.cover)
                .frame(width: 108, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("TOP PICK").font(.system(size: 9, weight: .black)).tracking(1.2).foregroundStyle(Color.cortexPurple)
                Text(pick.anime.title).font(.system(size: 14, weight: .black)).lineLimit(2)
                Text(pick.reason).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: scoring

    private var watchedIDs: Set<Int> {
        Set(CreditStore.shared.watchLog.map { $0.animeID })
    }

    private var picks: [Taste15Pick] {
        let watched: Set<Int> = store.excludeWatched ? watchedIDs : []
        var scored: [Taste15Pick] = []
        for anime in catalog.titles {
            if store.onlyHungarian && !anime.hasHungarian { continue }
            if store.onlyFinished && anime.status != "FINISHED" { continue }
            if store.maxEpisodes > 0 && anime.episodes > store.maxEpisodes { continue }
            if store.minScore > 0, let score = anime.score, score < store.minScore { continue }
            if store.minScore > 0, anime.score == nil { continue }
            if watched.contains(anime.id) { continue }
            if let year = anime.year, year < 1980 { continue }

            var score = 10
            var reasons: [String] = []
            for genre in anime.genres {
                let weight = store.weight(for: genre)
                if weight != 0 {
                    score += weight * 6
                    reasons.append("\(genre) \(weight > 0 ? "+\(weight)" : "\(weight)")")
                }
            }
            if store.mood != .any {
                let hits = anime.genres.filter { store.mood.genres.contains($0) }
                if hits.isEmpty { continue }
                score += 8
                reasons.append("\(store.mood.title.lowercased()) mood")
            }
            if let rating = anime.score { score += Int((rating - 6) * 4) }
            if anime.hasHungarian { score += 4; reasons.append("HU subs") }
            if anime.episodes > 0 && anime.episodes <= 13 { score += 3; reasons.append("short run") }
            // Diversity nudges the tail of the list: a random term scaled by the slider
            // so a low setting is stable and a high one reshuffles every visit.
            score += Int(Double.random(in: 0...12) * store.diversity)
            scored.append(Taste15Pick(anime: anime, score: score,
                                      reason: reasons.isEmpty ? "matches your filters" : reasons.prefix(3).joined(separator: " · ")))
        }
        switch sort {
        case .match: scored.sort { $0.score > $1.score }
        case .score: scored.sort { ($0.anime.score ?? 0) > ($1.anime.score ?? 0) }
        case .newest: scored.sort { ($0.anime.year ?? 0) > ($1.anime.year ?? 0) }
        case .shortest: scored.sort { $0.anime.episodes < $1.anime.episodes }
        }
        return scored
    }
}

enum Taste15Sort: String, CaseIterable, Identifiable {
    case match, score, newest, shortest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .match: return "Best match"
        case .score: return "Rating"
        case .newest: return "Newest"
        case .shortest: return "Shortest"
        }
    }
}
