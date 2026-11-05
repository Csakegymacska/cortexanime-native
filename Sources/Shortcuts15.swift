import SwiftUI
import UIKit

// MARK: - 1.5.0 · Shortcuts
//
// The app already understands cortexanime-native-port://anime/<id>, but nothing
// in the interface ever produced a link. This screen does: it turns the last
// episode you watched and up to three pinned titles into real, openable links,
// plus shareable web links for anyone who does not have the app.

@MainActor final class Shortcuts15Store: ObservableObject {
    static let shared = Shortcuts15Store()

    @Published var pins: [Int] { didSet { defaults.set(pins, forKey: "lab15.shortcuts.pins") } }
    @Published var lastID: Int?

    private let defaults = UserDefaults.standard

    init() {
        pins = defaults.array(forKey: "lab15.shortcuts.pins") as? [Int] ?? []
    }

    func togglePin(_ id: Int) {
        if let index = pins.firstIndex(of: id) { pins.remove(at: index) }
        else { pins.append(id); if pins.count > 3 { pins.removeFirst() } }
    }

    func isPinned(_ id: Int) -> Bool { pins.contains(id) }

    static func appLink(_ id: Int) -> URL? { URL(string: "cortexanime-native-port://anime/\(id)") }
    static func homeLink() -> URL? { URL(string: "cortexanime-native-port://home") }
    static func webLink(_ id: Int) -> URL? { URL(string: "https://cortanime.eu/anime/\(id)") }
    static func watchLink(_ id: Int, episode: Int) -> URL? { URL(string: "https://cortanime.eu/watch/\(id)/\(episode)") }

    @discardableResult
    func open(_ url: URL?) -> Bool {
        guard let url else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

struct Shortcuts15View: View {
    @ObservedObject private var store = Shortcuts15Store.shared
    @ObservedObject private var credits = CreditStore.shared
    @EnvironmentObject private var catalog: CatalogModel
    @State private var picking = false
    @State private var query = ""
    @State private var copied: String?

    private var last: WatchTick? {
        credits.watchLog.last(where: { $0.seconds > 30 }) ?? credits.watchLog.last
    }

    private var pinnedTitles: [Anime] {
        store.pins.compactMap { id in catalog.titles.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                continueCard
                pinsCard
                linksCard
                schemeCard
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) { picker }
    }

    // MARK: continue

    private var continueCard: some View {
        LabCard(title: "Continue", footnote: "Picked from the most recent entry in the watch log. Opening it hands the link back to the app, which jumps straight to the title.") {
            if let last {
                HStack(spacing: 12) {
                    AnimeArtwork(url: catalog.titles.first { $0.id == last.animeID }?.cover)
                        .frame(width: 46, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(last.title).font(.system(size: 14, weight: .bold)).lineLimit(2)
                        Text("Episode \(last.episode)\(last.completed ? " · finished" : "")")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(fmt(last.date)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                Divider().overlay(Color.white.opacity(0.06))
                HStack(spacing: 10) {
                    Button {
                        store.open(Shortcuts15Store.appLink(last.animeID))
                    } label: {
                        Label("Open in app", systemImage: "arrow.up.forward.app.fill")
                            .font(.system(size: 12.5, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 11))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Button {
                        copy(Shortcuts15Store.webLink(last.animeID)?.absoluteString ?? "", tag: "cont")
                    } label: {
                        Label(copied == "cont" ? "Copied" : "Copy link", systemImage: copied == "cont" ? "checkmark" : "link")
                            .font(.system(size: 12.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            } else {
                Text("Nothing watched yet. Start an episode and it will show up here.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.vertical, 14)
            }
        }
    }

    // MARK: pins

    private var pinsCard: some View {
        LabCard(title: "Pinned", footnote: "Three slots, stored on the device. Tap a card to open the title, hold the pin button to unpin it from the picker.") {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { slot in
                    if slot < pinnedTitles.count {
                        let anime = pinnedTitles[slot]
                        Button { store.open(Shortcuts15Store.appLink(anime.id)) } label: {
                            VStack(spacing: 6) {
                                AnimeArtwork(url: anime.cover)
                                    .frame(height: 74)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                Text(anime.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(2)
                                    .frame(height: 26, alignment: .top)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Unpin", role: .destructive) { store.togglePin(anime.id) }
                            Button("Copy link") { copy(Shortcuts15Store.webLink(anime.id)?.absoluteString ?? "", tag: "pin\(anime.id)") }
                        }
                    } else {
                        Button { picking = true; query = "" } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                                    .frame(height: 74).frame(maxWidth: .infinity)
                                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                                Text("Empty").font(.system(size: 10.5)).foregroundStyle(.secondary).frame(height: 26)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 10)
            Divider().overlay(Color.white.opacity(0.06))
            Button { picking = true; query = "" } label: {
                Label(store.pins.isEmpty ? "Pin a title" : "Change pins", systemImage: "pin.fill")
                    .font(.system(size: 12.5, weight: .semibold)).padding(.vertical, 6)
            }
        }
    }

    // MARK: links

    private var linksCard: some View {
        LabCard(title: "Links", footnote: "The web link opens the public page, so it also works for someone who has never installed the app.") {
            if let anime = pinnedTitles.first {
                LabRow(title: "Share \(anime.title)", detail: "Web page + app deep link", symbol: "square.and.arrow.up") {
                    ShareLink(item: shareText(anime)) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold))
                    }
                }
                Divider().overlay(Color.white.opacity(0.06))
                LabRow(title: "Watch page", detail: "Opens in the browser", symbol: "safari.fill") {
                    Button {
                        store.open(Shortcuts15Store.watchLink(anime.id, episode: 1))
                    } label: {
                        Text("Open").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cortexPurple)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Pin a title to unlock sharing.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Go to the home rail", detail: "Uses the app's own URL scheme", symbol: "house.fill") {
                Button { store.open(Shortcuts15Store.homeLink()) } label: {
                    Text("Open").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.cortexPurple)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: scheme

    private var schemeCard: some View {
        LabCard(title: "URL scheme", footnote: "Anything that can open a URL — a Shortcut, a note, a QR code — can drive the app with these.") {
            VStack(alignment: .leading, spacing: 8) {
                code("cortexanime-native-port://anime/21")
                code("cortexanime-native-port://home")
                code("https://cortanime.eu/watch/21/1")
            }
            .padding(.vertical, 10)
            Divider().overlay(Color.white.opacity(0.06))
            Button {
                copy("cortexanime-native-port://anime/<id>", tag: "scheme")
            } label: {
                Label(copied == "scheme" ? "Copied" : "Copy scheme", systemImage: copied == "scheme" ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12.5, weight: .semibold)).padding(.vertical, 6)
            }
            Divider().overlay(Color.white.opacity(0.06))
            Button {
                if let id = pinnedTitles.first?.id { store.open(Shortcuts15Store.appLink(id)) }
            } label: {
                Label("Test the deep link", systemImage: "testtube.2")
                    .font(.system(size: 12.5, weight: .semibold)).padding(.vertical, 6)
            }
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.cortexMint)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func shareText(_ anime: Anime) -> String {
        var parts = [anime.title]
        if let web = Shortcuts15Store.webLink(anime.id) { parts.append(web.absoluteString) }
        if let app = Shortcuts15Store.appLink(anime.id) { parts.append("In the app: \(app.absoluteString)") }
        return parts.joined(separator: "\n")
    }

    private func copy(_ text: String, tag: String) {
        UIPasteboard.general.string = text
        copied = tag
    }

    private func fmt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var picker: some View {
        NavigationStack {
            List {
                ForEach(filtered) { anime in
                    Button {
                        store.togglePin(anime.id)
                    } label: {
                        HStack(spacing: 10) {
                            AnimeArtwork(url: anime.cover).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(anime.title).font(.system(size: 13)).lineLimit(1)
                            Spacer()
                            Image(systemName: store.isPinned(anime.id) ? "pin.fill" : "pin")
                                .foregroundStyle(store.isPinned(anime.id) ? Color.cortexPurple : .white.opacity(0.3))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search the catalogue")
            .scrollContentBackground(.hidden)
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Pin a title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { picking = false } } }
        }
    }

    private var filtered: [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(catalog.titles.prefix(60)) }
        return catalog.titles.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}
