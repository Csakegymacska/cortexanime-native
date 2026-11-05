import SwiftUI

/// 4.0 "New in Hungarian" screen. Everything here comes from the live release feed,
/// so it never promises an episode that does not exist yet.
struct NativeReleases: View {
    @StateObject private var feed = ReleaseFeed.shared
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, newSeries, today
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .newSeries: return "New series"
            case .today: return "Today"
            }
        }
    }

    private var visible: [CortexRelease] {
        switch filter {
        case .all: return feed.items
        case .newSeries: return feed.items.filter(\.isNewSeries)
        case .today: return feed.items.filter { Calendar.current.isDateInToday($0.airedAt) }
        }
    }

    private struct DaySection: Identifiable {
        let id: String
        let items: [CortexRelease]
    }

    private var sections: [DaySection] {
        var order: [String] = []
        var bucket: [String: [CortexRelease]] = [:]
        for item in visible {
            let key = item.dayLabel
            if bucket[key] == nil { order.append(key) }
            bucket[key, default: []].append(item)
        }
        return order.map { DaySection(id: $0, items: bucket[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                filters
                if feed.items.isEmpty && feed.loading {
                    HStack(spacing: 10) { ProgressView(); Text("Loading the release feed…").font(.subheadline) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 30)
                } else if feed.items.isEmpty {
                    emptyState
                } else if visible.isEmpty {
                    Text("Nothing in this filter yet.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.55)).padding(.vertical, 20)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeading(title: section.id)
                            ForEach(section.items) { item in NavigationLink { NativeLinkedDetail(id: item.animeID) } label: { row(item) }.buttonStyle(.plain) }
                        }
                    }
                }
                if let error = feed.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Text("The feed lists episodes that already have Hungarian subtitles. Times are when the subtitle went live, not the Japanese broadcast.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Color.cortexBlack)
        .navigationTitle("New in Hungarian")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await feed.load(force: true) }
        .task { await feed.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await feed.load(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh releases")
                .accessibilityIdentifier("releases.refresh")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.tv.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Color.cortexPurple)
                Text("\(feed.items.count) published episodes").font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
                if feed.fromCache { Pill(text: "Saved copy", color: .orange) }
            }
            Text("Every entry already has a Hungarian subtitle track in the player.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            if let updated = feed.updated {
                Text("Updated " + updated.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.white.opacity(0.35))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.cortexPurple.opacity(0.25), lineWidth: 1))
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(Filter.allCases) { item in
                    Button { filter = item } label: {
                        Text(item.title)
                            .font(.caption.bold())
                            .padding(.horizontal, 14).frame(minHeight: 38)
                            .background(filter == item ? Color.cortexPurple.opacity(0.25) : Color.white.opacity(0.05), in: Capsule())
                            .overlay(Capsule().stroke(filter == item ? Color.cortexPurple : Color.white.opacity(0.08), lineWidth: 1))
                            .foregroundStyle(filter == item ? Color.cortexPurple : Color.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("releases.filter." + item.rawValue)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(Color.cortexPurple)
            Text("The release feed could not be loaded.").font(.headline)
            Text("Check your connection and try again. Saved episodes still play from Downloads.")
                .font(.caption).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            Button("Try again") { Task { await feed.load(force: true) } }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func row(_ item: CortexRelease) -> some View {
        HStack(spacing: 12) {
            AnimeArtwork(url: item.cover)
                .frame(width: 52, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.cortexPurple.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Pill(text: "EP \(item.episode)")
                    if item.isNewSeries { Pill(text: "NEW SERIES", color: .green) }
                }
                Text(item.cleanTitle).font(.system(size: 14, weight: .bold)).lineLimit(2)
                Text(item.ageText).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.35))
        }
        .padding(10)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.cleanTitle), episode \(item.episode), \(item.ageText)")
    }
}

/// Home shelf for the three newest releases with a shortcut to the full list.
struct ReleaseShelf: View {
    let items: [CortexRelease]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "New in Hungarian")
                Spacer(minLength: 0)
                NavigationLink { NativeReleases() } label: {
                    Text("See all").font(.caption.bold()).foregroundStyle(Color.cortexPurple)
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("home.releases.seeAll")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                // 6.2: lazy + aligned, so the shared 3D tilt has a real scroll phase to follow.
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items.prefix(6)) { item in
                        NavigationLink { NativeLinkedDetail(id: item.animeID) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                AnimeArtwork(url: item.cover)
                                    .frame(width: 116, height: 164)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .topLeading) {
                                        Pill(text: "EP \(item.episode)").padding(6)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                Text(item.cleanTitle).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                                    .frame(width: 116, alignment: .leading)
                                Text(item.ageText).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.cleanTitle), episode \(item.episode)")
                        .cortexShelfTilt(strength: 13)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}
