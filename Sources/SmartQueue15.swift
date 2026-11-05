import SwiftUI

// MARK: - 1.5.0 · Smart Queue
//
// A queue that survives a relaunch and is built from what you already watch.
// The Lab can seed it from the watch log ("the next episode of everything I
// started"), then you reorder, pin, skip or clear it. The queue is the only
// thing the player needs to know about, so nothing else changes.

struct Queue15Item: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var animeID: Int
    var title: String
    var episode: Int
    var cover: String?
    var addedAt: Date = Date()
    var pinned: Bool = false
}

@MainActor final class Queue15Store: ObservableObject {
    static let shared = Queue15Store()

    @Published private(set) var items: [Queue15Item] = []
    @Published private(set) var played: Set<String> = []

    private let defaults = UserDefaults.standard
    private let key = "lab15.queue.items"
    private let playedKey = "lab15.queue.played"

    init() { reload() }

    private func reload() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Queue15Item].self, from: data) {
            items = decoded
        }
        played = Set(defaults.array(forKey: playedKey) as? [String] ?? [])
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
        defaults.set(Array(played), forKey: playedKey)
    }

    /// A queue entry is identified by series + episode, never by UUID, so adding
    /// the same episode twice is a no-op instead of a duplicate row.
    func contains(animeID: Int, episode: Int) -> Bool {
        items.contains { $0.animeID == animeID && $0.episode == episode }
    }

    func add(animeID: Int, title: String, episode: Int, cover: String? = nil) {
        guard !contains(animeID: animeID, episode: episode) else { return }
        items.append(Queue15Item(animeID: animeID, title: title, episode: episode, cover: cover))
        persist()
    }

    func addNextEpisodes(from ticks: [WatchTick]) {
        var latest: [Int: (title: String, episode: Int)] = [:]
        for tick in ticks {
            if let existing = latest[tick.animeID] {
                if tick.episode > existing.episode { latest[tick.animeID] = (tick.title, tick.episode) }
            } else {
                latest[tick.animeID] = (tick.title, tick.episode)
            }
        }
        for (animeID, info) in latest {
            add(animeID: animeID, title: info.title, episode: info.episode + 1)
        }
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        persist()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func pin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.pinned.toggle()
        if item.pinned { items.insert(item, at: 0) } else { items.append(item) }
        persist()
    }

    func bump(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
        persist()
    }

    /// Marks the episode played and drops it. The key is series#episode so the
    /// history view can show what the queue actually delivered.
    func markPlayed(id: UUID) {
        guard let item = items.firstIndex(where: { $0.id == id }) else { return }
        played.insert("\(items[item].animeID)#\(items[item].episode)")
        items.remove(at: item)
        persist()
    }

    func shuffleUnpinned() {
        let pinned = items.filter { $0.pinned }
        let rest = items.filter { !$0.pinned }.shuffled()
        items = pinned + rest
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    func clearPlayedHistory() {
        played.removeAll()
        persist()
    }

    var totalMinutes: Int { items.reduce(0) { total, _ in total + 24 } }

    var seriesCount: Int { Set(items.map { $0.animeID }).count }

    var next: Queue15Item? { items.first }
}

struct SmartQueue15View: View {
    @ObservedObject private var store = Queue15Store.shared
    @ObservedObject private var credits = CreditStore.shared
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    LabStat(value: "\(store.items.count)", label: "in queue")
                    LabStat(value: "\(store.seriesCount)", label: "series", tint: .cortexMint)
                    LabStat(value: "\(store.totalMinutes)m", label: "estimated", tint: .orange)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let next = store.next {
                Section("Up next") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(next.title).font(.system(size: 15, weight: .bold))
                        Text("Episode \(next.episode)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.cortexPurple)
                    }
                    .padding(.vertical, 4)
                    Button {
                        store.markPlayed(id: next.id)
                    } label: { Label("Mark as watched", systemImage: "checkmark.circle") }
                    Button {
                        store.bump(id: next.id)
                    } label: { Label("Keep at the top", systemImage: "arrow.up.to.line") }
                }
            }

            Section {
                Button {
                    store.addNextEpisodes(from: credits.watchLog)
                } label: {
                    Label("Seed from my history", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    store.shuffleUnpinned()
                } label: {
                    Label("Shuffle everything unpinned", systemImage: "shuffle")
                }
                Button(role: .destructive) {
                    store.clear()
                } label: {
                    Label("Empty the queue", systemImage: "trash")
                }
            } header: {
                Text("Queue actions")
            } footer: {
                Text("Seeding adds the next episode of every series in your watch log. Episodes already in the queue are skipped.")
            }

            Section {
                ForEach(store.items) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            Text("Episode \(item.episode)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.pinned {
                            Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(Color.cortexPurple)
                        }
                    }
                    .contentShape(Rectangle())
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { store.markPlayed(id: item.id) } label: {
                            Label("Watched", systemImage: "checkmark")
                        }.tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.remove(id: item.id) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button { store.pin(id: item.id) } label: {
                            Label(item.pinned ? "Unpin" : "Pin", systemImage: "pin")
                        }.tint(Color.cortexPurple)
                    }
                }
                .onMove { store.move(from: $0, to: $1) }
                .onDelete { store.remove(at: $0) }
            } header: {
                HStack {
                    Text("Queue")
                    Spacer()
                    Button(editMode == .active ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    }
                    .font(.system(size: 12, weight: .bold))
                }
            } footer: {
                if store.items.isEmpty {
                    Text("The queue is empty. Seed it from your history, then reorder it however you like.")
                }
            }

            if !store.played.isEmpty {
                Section("Delivered") {
                    ForEach(Array(store.played).sorted().prefix(20), id: \.self) { key in
                        Text(key.replacingOccurrences(of: "#", with: " · episode "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) { store.clearPlayedHistory() } label: {
                        Label("Clear delivered list", systemImage: "eraser")
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Smart Queue")
        .navigationBarTitleDisplayMode(.inline)
    }
}
