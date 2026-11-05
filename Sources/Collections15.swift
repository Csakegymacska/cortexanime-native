import SwiftUI

// MARK: - 1.5.0 · Collections+
//
// Lists that belong to you: any number of them, each with titles, a note, a pin
// and an archive flag. On top of that every title can carry tags, a private
// note and a rewatch counter, and can be hidden from the rest of the app.
// Everything is stored as JSON in UserDefaults and can be exported as a file.

struct Collection15Item: Codable, Identifiable, Equatable {
    var id: Int { animeID }
    var animeID: Int
    var title: String
    var cover: String?
    var addedAt: Date = Date()
}

struct Collection15: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var note: String = ""
    var items: [Collection15Item] = []
    var pinned: Bool = false
    var archived: Bool = false
    var createdAt: Date = Date()
}

@MainActor final class Collections15Store: ObservableObject {
    static let shared = Collections15Store()

    @Published private(set) var lists: [Collection15] = []
    @Published private(set) var tags: [Int: [String]] = [:]
    @Published private(set) var notes: [Int: String] = [:]
    @Published private(set) var rewatches: [Int: Int] = [:]
    @Published private(set) var hidden: Set<Int> = []

    private let defaults = UserDefaults.standard

    init() { reload() }

    private func reload() {
        if let data = defaults.data(forKey: "lab15.collections.lists"),
           let decoded = try? JSONDecoder().decode([Collection15].self, from: data) {
            lists = decoded
        } else {
            lists = [Collection15(name: "Watch next"), Collection15(name: "All time favourites")]
        }
        tags = (defaults.dictionary(forKey: "lab15.collections.tags") as? [String: [String]])?.reduce(into: [:]) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        } ?? [:]
        notes = (defaults.dictionary(forKey: "lab15.collections.notes") as? [String: String])?.reduce(into: [:]) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        } ?? [:]
        rewatches = (defaults.dictionary(forKey: "lab15.collections.rewatches") as? [String: Int])?.reduce(into: [:]) { result, pair in
            if let key = Int(pair.key) { result[key] = pair.value }
        } ?? [:]
        hidden = Set(defaults.array(forKey: "lab15.collections.hidden") as? [Int] ?? [])
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(lists) { defaults.set(data, forKey: "lab15.collections.lists") }
        defaults.set(tags.reduce(into: [String: [String]]()) { $0[String($1.key)] = $1.value }, forKey: "lab15.collections.tags")
        defaults.set(notes.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }, forKey: "lab15.collections.notes")
        defaults.set(rewatches.reduce(into: [String: Int]()) { $0[String($1.key)] = $1.value }, forKey: "lab15.collections.rewatches")
        defaults.set(Array(hidden), forKey: "lab15.collections.hidden")
    }

    // MARK: lists

    func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lists.append(Collection15(name: trimmed))
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lists[index].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        lists.removeAll { $0.id == id }
        persist()
    }

    func duplicate(_ id: UUID) {
        guard let original = lists.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = original.name + " copy"
        copy.pinned = false
        lists.append(copy)
        persist()
    }

    func togglePin(_ id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].pinned.toggle()
        persist()
    }

    func toggleArchive(_ id: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].archived.toggle()
        persist()
    }

    func setNote(_ id: UUID, note: String) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].note = note
        persist()
    }

    func move(from source: IndexSet, to destination: Int) {
        lists.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Replaces one list wholesale. Used by the detail screen when it reorders
    /// titles, so the store stays the only writer.
    func replaceList(_ updated: Collection15) {
        guard let index = lists.firstIndex(where: { $0.id == updated.id }) else { return }
        lists[index] = updated
        persist()
    }

    // MARK: items

    func add(animeID: Int, title: String, cover: String?, to listID: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        guard !lists[index].items.contains(where: { $0.animeID == animeID }) else { return }
        lists[index].items.append(Collection15Item(animeID: animeID, title: title, cover: cover))
        persist()
    }

    func remove(animeID: Int, from listID: UUID) {
        guard let index = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[index].items.removeAll { $0.animeID == animeID }
        persist()
    }

    /// Move a title between two lists without losing its tags or note.
    func move(animeID: Int, from source: UUID, to target: UUID) {
        guard let item = lists.first(where: { $0.id == source })?.items.first(where: { $0.animeID == animeID }) else { return }
        add(animeID: item.animeID, title: item.title, cover: item.cover, to: target)
        remove(animeID: animeID, from: source)
    }

    // MARK: per-title data

    func setTags(_ values: [String], for animeID: Int) {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if cleaned.isEmpty { tags.removeValue(forKey: animeID) } else { tags[animeID] = Array(Set(cleaned)).sorted() }
        persist()
    }

    func addTag(_ tag: String, for animeID: Int) {
        setTags((tags[animeID] ?? []) + [tag], for: animeID)
    }

    func removeTag(_ tag: String, for animeID: Int) {
        setTags((tags[animeID] ?? []).filter { $0 != tag }, for: animeID)
    }

    func setNote(_ note: String, for animeID: Int) {
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.removeValue(forKey: animeID) }
        else { notes[animeID] = note }
        persist()
    }

    func bumpRewatch(_ animeID: Int) {
        rewatches[animeID, default: 0] += 1
        persist()
    }

    func resetRewatch(_ animeID: Int) {
        rewatches.removeValue(forKey: animeID)
        persist()
    }

    func toggleHidden(_ animeID: Int) {
        if hidden.contains(animeID) { hidden.remove(animeID) } else { hidden.insert(animeID) }
        persist()
    }

    // MARK: export / import

    struct Payload15: Codable {
        var lists: [Collection15]
        var tags: [String: [String]]
        var notes: [String: String]
        var rewatches: [String: Int]
        var hidden: [Int]
    }

    func exportData() -> String {
        let payload = Payload15(
            lists: lists,
            tags: tags.reduce(into: [:]) { $0[String($1.key)] = $1.value },
            notes: notes.reduce(into: [:]) { $0[String($1.key)] = $1.value },
            rewatches: rewatches.reduce(into: [:]) { $0[String($1.key)] = $1.value },
            hidden: Array(hidden))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    func importData(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload15.self, from: data) else { return false }
        lists = payload.lists
        tags = payload.tags.reduce(into: [:]) { result, pair in if let key = Int(pair.key) { result[key] = pair.value } }
        notes = payload.notes.reduce(into: [:]) { result, pair in if let key = Int(pair.key) { result[key] = pair.value } }
        rewatches = payload.rewatches.reduce(into: [:]) { result, pair in if let key = Int(pair.key) { result[key] = pair.value } }
        hidden = Set(payload.hidden)
        persist()
        return true
    }

    func resetEverything() {
        lists = [Collection15(name: "Watch next")]
        tags = [:]; notes = [:]; rewatches = [:]; hidden = []
        persist()
    }

    var totalItems: Int { lists.reduce(0) { $0 + $1.items.count } }
    var activeLists: [Collection15] { lists.filter { !$0.archived } }
}

struct Collections15View: View {
    @ObservedObject private var store = Collections15Store.shared
    @EnvironmentObject private var catalog: CatalogModel
    @State private var creating = false
    @State private var newName = ""
    @State private var selected: Collection15?
    @State private var importText = ""
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    LabStat(value: "\(store.lists.count)", label: "lists")
                    LabStat(value: "\(store.totalItems)", label: "titles", tint: .cortexMint)
                    LabStat(value: "\(store.hidden.count)", label: "hidden", tint: .orange)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section("Lists") {
                ForEach(store.lists) { list in
                    Button { selected = list } label: {
                        HStack(spacing: 12) {
                            Image(systemName: list.pinned ? "pin.fill" : "square.stack.3d.up")
                                .foregroundStyle(list.pinned ? Color.cortexPurple : .white.opacity(0.35))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name).font(.system(size: 14, weight: .semibold))
                                Text("\(list.items.count) titles\(list.archived ? " · archived" : "")")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.25))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove { store.move(from: $0, to: $1) }
                .onDelete { indexSet in
                    for index in indexSet { store.delete(store.lists[index].id) }
                }
            }

            Section {
                Button { creating = true; newName = "" } label: { Label("New list", systemImage: "plus") }
                Button { importing = true; importText = "" } label: { Label("Import collections", systemImage: "square.and.arrow.down") }
                if let message {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } header: {
                Text("Manage")
            } footer: {
                Text("A list can be duplicated, pinned, archived or deleted from its own screen. Import expects the JSON the export produces.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Collections+")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { list in
            NavigationStack { Collection15Detail(listID: list.id) }
                .environmentObject(catalog)
        }
        .sheet(isPresented: $importing) { importSheet }
        .alert("New list", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") { store.create(name: newName) }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Paste an export below. It replaces every list, tag, note and rewatch count.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
                TextEditor(text: $importText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 12))
                Button {
                    message = store.importData(importText) ? "Collections imported." : "That is not a valid export."
                    importing = false
                } label: {
                    Text("Import").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { importing = false } } }
        }
        .presentationDetents([.large])
    }
}

struct Collection15Detail: View {
    let listID: UUID
    @ObservedObject private var store = Collections15Store.shared
    @EnvironmentObject private var catalog: CatalogModel
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var draftName = ""
    @State private var noteDraft = ""
    @State private var adding = false
    @State private var query = ""

    private var list: Collection15? { store.lists.first { $0.id == listID } }

    var body: some View {
        List {
            if let list {
                Section {
                    TextField("List note", text: $noteDraft, axis: .vertical)
                        .font(.system(size: 13))
                        .onSubmit { store.setNote(listID, note: noteDraft) }
                    HStack {
                        Button("Save note") { store.setNote(listID, note: noteDraft) }
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text("\(list.items.count) titles").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }

                Section {
                    ForEach(list.items) { item in
                        NavigationLink { Collection15Title(animeID: item.animeID, title: item.title) } label: {
                            HStack(spacing: 11) {
                                AnimeArtwork(url: URL(string: item.cover ?? ""))
                                    .frame(width: 38, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                    if let tags = store.tags[item.animeID], !tags.isEmpty {
                                        Text(tags.joined(separator: " · ")).font(.system(size: 10.5)).foregroundStyle(Color.cortexPurple)
                                    }
                                    if let count = store.rewatches[item.animeID], count > 0 {
                                        Text("\(count)× rewatched").font(.system(size: 10.5)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.remove(animeID: item.animeID, from: listID)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                    .onMove { source, destination in
                        guard let index = store.lists.firstIndex(where: { $0.id == listID }) else { return }
                        var items = store.lists[index].items
                        items.move(fromOffsets: source, toOffset: destination)
                        let updated = Collection15(id: listID, name: store.lists[index].name, note: store.lists[index].note,
                                                   items: items, pinned: store.lists[index].pinned,
                                                   archived: store.lists[index].archived, createdAt: store.lists[index].createdAt)
                        store.replaceList(updated)
                    }
                } footer: {
                    if list.items.isEmpty {
                        Text("Empty. Add something from search above.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle(list?.name ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { noteDraft = list?.note ?? "" }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") { draftName = list?.name ?? ""; renaming = true }
                    Button("Add titles") { adding = true; query = "" }
                    Button(list?.pinned == true ? "Unpin" : "Pin") { store.togglePin(listID) }
                    Button(list?.archived == true ? "Unarchive" : "Archive") { store.toggleArchive(listID) }
                    Button("Duplicate") { store.duplicate(listID) }
                    ShareLink(item: store.exportData()) { Label("Export all collections", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button("Delete list", role: .destructive) { store.delete(listID); dismiss() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Rename list", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            Button("Save") { store.rename(listID, to: draftName) }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $adding) { addSheet }
    }

    private var addSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredTitles) { anime in
                    Button {
                        store.add(animeID: anime.id, title: anime.title, cover: anime.cover?.absoluteString, to: listID)
                    } label: {
                        HStack(spacing: 10) {
                            AnimeArtwork(url: anime.cover).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(anime.title).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            if list?.items.contains(where: { $0.animeID == anime.id }) == true {
                                Image(systemName: "checkmark").foregroundStyle(Color.cortexPurple)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search the catalogue")
            .scrollContentBackground(.hidden)
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Add titles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { adding = false } } }
        }
    }

    private var filteredTitles: [Anime] {
        let base = catalog.titles.filter { !store.hidden.contains($0.id) }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(base.prefix(60)) }
        return base.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// Tags, a private note, the rewatch counter and the hide switch for one title.
struct Collection15Title: View {
    let animeID: Int
    let title: String
    @ObservedObject private var store = Collections15Store.shared
    @State private var tagDraft = ""
    @State private var noteDraft = ""

    var body: some View {
        List {
            Section("Tags") {
                ForEach(store.tags[animeID] ?? [], id: \.self) { tag in
                    HStack {
                        Text(tag).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button { store.removeTag(tag, for: animeID) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.3))
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add a tag", text: $tagDraft)
                    Button("Add") {
                        store.addTag(tagDraft, for: animeID)
                        tagDraft = ""
                    }
                    .disabled(tagDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Private note") {
                TextEditor(text: $noteDraft)
                    .frame(minHeight: 110)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                Button("Save note") { store.setNote(noteDraft, for: animeID) }
                    .font(.system(size: 12, weight: .bold))
            }

            Section("Rewatches") {
                HStack {
                    Text("Count").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(store.rewatches[animeID] ?? 0)")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Color.cortexPurple)
                    Button { store.bumpRewatch(animeID) } label: { Image(systemName: "plus.circle.fill") }
                        .buttonStyle(.plain)
                    Button { store.resetRewatch(animeID) } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.4))
                }
            }

            Section {
                Toggle("Hide this title everywhere", isOn: Binding(
                    get: { store.hidden.contains(animeID) },
                    set: { value in
                        if value != store.hidden.contains(animeID) { store.toggleHidden(animeID) }
                    }))
            } footer: {
                Text("Hidden titles disappear from Collection lists, search in Collections+ and the Taste Engine.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            noteDraft = store.notes[animeID] ?? ""
        }
    }
}
