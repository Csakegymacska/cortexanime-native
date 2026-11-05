import SwiftUI

// MARK: - 8.0 · Home layout, surprise pick, history
//
// Three small things that make the app feel personal without a backend:
// you can reorder or hide the home shelves, jump to a random series from the
// home screen, and search a full watch-history list instead of only being able
// to wipe it.

enum HomeSection8: String, CaseIterable, Identifiable {
    case continueWatching, releases, subtitles, trending, seasonal, radar, hungarian, quick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .continueWatching: return "Continue watching"
        case .releases: return "New episodes"
        case .subtitles: return "Subtitle radar"
        case .trending: return "Trending now"
        case .seasonal: return "This season"
        case .radar: return "For you"
        case .hungarian: return "Hungarian subtitles"
        case .quick: return "Quick actions"
        }
    }
}

@MainActor final class HomeLayout8: ObservableObject {
    static let shared = HomeLayout8()

    @Published var order: [HomeSection8] { didSet { persist() } }
    @Published var hidden: Set<HomeSection8> { didSet { persist() } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = (defaults.array(forKey: "home8.order") as? [String]) ?? []
        let parsed = saved.compactMap { HomeSection8(rawValue: $0) }
        let missing = HomeSection8.allCases.filter { !parsed.contains($0) }
        order = parsed + missing
        hidden = Set((defaults.array(forKey: "home8.hidden") as? [String] ?? []).compactMap { HomeSection8(rawValue: $0) })
    }

    func shows(_ section: HomeSection8) -> Bool { !hidden.contains(section) }

    func move(_ section: HomeSection8, up: Bool) {
        guard let index = order.firstIndex(of: section) else { return }
        let target = up ? index - 1 : index + 1
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    func reset() {
        order = HomeSection8.allCases
        hidden = []
    }

    private func persist() {
        defaults.set(order.map(\.rawValue), forKey: "home8.order")
        defaults.set(hidden.map(\.rawValue), forKey: "home8.hidden")
    }
}

struct HomeLayout8View: View {
    @ObservedObject private var layout = HomeLayout8.shared

    var body: some View {
        List {
            Section("Sections") {
                ForEach(layout.order) { section in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title).font(.subheadline.weight(.semibold))
                            Text(layout.shows(section) ? "Visible" : "Hidden")
                                .font(.caption2).foregroundStyle(layout.shows(section) ? .secondary : Color.orange)
                        }
                        Spacer()
                        Button {
                            layout.move(section, up: true)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(layout.order.first == section)
                        Button {
                            layout.move(section, up: false)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(layout.order.last == section)
                        Toggle("", isOn: Binding(
                            get: { layout.shows(section) },
                            set: { on in
                                if on { layout.hidden.remove(section) } else { layout.hidden.insert(section) }
                            }))
                            .labelsHidden()
                    }
                    .frame(minHeight: 44)
                }
            }
            Section {
                Button("Reset the home screen") { layout.reset() }
                Text("The hero banner, the quick tiles and the footer always stay — everything else can be reordered or hidden.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Home layout")
    }
}

/// "Surprise me" — a random title from the loaded catalog, opened like any other.
struct RandomPick8: View {
    @EnvironmentObject private var catalog: CatalogModel
    @State private var pick: Anime?

    var body: some View {
        Group {
            if let pick {
                NativeDetail(seed: pick)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Picking something for you…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.cortexBlack)
                .task {
                    let pool = catalog.titles.isEmpty ? catalog.trending : catalog.titles
                    pick = pool.randomElement()
                }
            }
        }
        .navigationTitle("Surprise me")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SurpriseMe8Button: View {
    var body: some View {
        NavigationLink { RandomPick8() } label: {
            HStack(spacing: 10) {
                Image(systemName: "dice")
                    .font(.system(size: 16, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Surprise me").font(.system(size: 13, weight: .bold))
                    Text("A random series, one tap").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(12)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home8.surprise")
    }
}

/// Searchable history with per-row delete. The old flow only had "clear everything".
struct History8View: View {
    @ObservedObject private var library = AnimeLibrary.shared
    @State private var query = ""
    @State private var confirmClear = false

    private var rows: [WatchRecord] {
        let base = library.history
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.filter { $0.anime.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if rows.isEmpty {
                Section {
                    Text(query.isEmpty ? "Nothing watched yet." : "No match for “\(query)”.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(rows) { record in
                NavigationLink {
                    NativeDetail(seed: record.anime, resumeEpisode: record.episode)
                } label: {
                    HStack(spacing: 12) {
                        AnimeArtwork(url: record.anime.cover)
                            .frame(width: 40, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.anime.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("Episode \(record.episode) · \(Int(record.seconds) / 60) min · \(record.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        library.removeHistory([record.id])
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .searchable(text: $query, prompt: "Search history")
        .navigationTitle("Watch history")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) { confirmClear = true }
                    .disabled(library.history.isEmpty)
            }
        }
        .confirmationDialog("Clear the whole watch history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { library.clearHistory() }
        }
    }
}
