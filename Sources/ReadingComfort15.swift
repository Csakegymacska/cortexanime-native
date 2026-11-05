import SwiftUI
import UIKit

// MARK: - 1.5.0 · Reading Comfort
//
// A reader for synopses. Anime descriptions are long, translated and often
// pinned into a 12-point caption under a poster — hard to read, worse at night.
// This screen gives them their own page with the typography you choose, a real
// measure, a reading-time estimate and a spoiler switch.

enum Reading15FontDesign: String, CaseIterable, Identifiable {
    case system, serif, rounded, mono
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Default"
        case .serif: return "Serif"
        case .rounded: return "Rounded"
        case .mono: return "Mono"
        }
    }
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .mono: return .monospaced
        }
    }
}

enum Reading15Canvas: String, CaseIterable, Identifiable {
    case black, charcoal, sepia
    var id: String { rawValue }
    var title: String {
        switch self {
        case .black: return "Black"
        case .charcoal: return "Charcoal"
        case .sepia: return "Sepia"
        }
    }
    var background: Color {
        switch self {
        case .black: return .cortexBlack
        case .charcoal: return Color(red: 0.09, green: 0.09, blue: 0.105)
        case .sepia: return Color(red: 0.97, green: 0.93, blue: 0.85)
        }
    }
    var ink: Color {
        switch self {
        case .black, .charcoal: return .white
        case .sepia: return Color(red: 0.16, green: 0.13, blue: 0.1)
        }
    }
    var isLight: Bool { self == .sepia }
}

@MainActor final class Reading15Store: ObservableObject {
    static let shared = Reading15Store()

    @Published var size: Double { didSet { save(size, "size") } }
    @Published var spacing: Double { didSet { save(spacing, "spacing") } }
    @Published var design: Reading15FontDesign { didSet { save(design.rawValue, "design") } }
    @Published var canvas: Reading15Canvas { didSet { save(canvas.rawValue, "canvas") } }
    @Published var narrow: Bool { didSet { save(narrow, "narrow") } }
    @Published var dim: Bool { didSet { save(dim, "dim") } }
    @Published var bold: Bool { didSet { save(bold, "bold") } }
    @Published var blurSpoilers: Bool { didSet { save(blurSpoilers, "blur") } }
    @Published var wpm: Int { didSet { save(wpm, "wpm") } }

    private let defaults = UserDefaults.standard

    init() {
        size = defaults.object(forKey: "lab15.read.size") as? Double ?? 17
        spacing = defaults.object(forKey: "lab15.read.spacing") as? Double ?? 7
        design = Reading15FontDesign(rawValue: defaults.string(forKey: "lab15.read.design") ?? "") ?? .serif
        canvas = Reading15Canvas(rawValue: defaults.string(forKey: "lab15.read.canvas") ?? "") ?? .black
        narrow = defaults.object(forKey: "lab15.read.narrow") as? Bool ?? true
        dim = defaults.object(forKey: "lab15.read.dim") as? Bool ?? false
        bold = defaults.object(forKey: "lab15.read.bold") as? Bool ?? false
        blurSpoilers = defaults.object(forKey: "lab15.read.blur") as? Bool ?? false
        wpm = defaults.object(forKey: "lab15.read.wpm") as? Int ?? 220
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: "lab15.read." + key) }

    var weight: Font.Weight { bold ? .semibold : .regular }

    var ink: Color { canvas.ink.opacity(dim ? 0.62 : 1) }

    func font(points: Double? = nil) -> Font {
        .system(size: points ?? size, weight: weight, design: design.design)
    }

    func readingMinutes(_ text: String) -> Int {
        let words = text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        guard wpm > 0 else { return 0 }
        return max(1, Int((Double(words) / Double(wpm) * 60).rounded() / 60))
    }

    func readingLabel(_ text: String) -> String {
        let words = text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        let minutes = Double(words) / Double(max(1, wpm))
        if minutes < 1 { return "\(words) words · under a minute" }
        return "\(words) words · about \(Int(minutes.rounded(.up))) min"
    }

    func applyPreset(_ preset: Int) {
        switch preset {
        case 0: // Comfort
            size = 17; spacing = 7; design = .serif; canvas = .black; narrow = true; dim = false; bold = false
        case 1: // Compact
            size = 15; spacing = 4; design = .system; canvas = .charcoal; narrow = false; dim = true; bold = false
        default: // Large print
            size = 23; spacing = 11; design = .rounded; canvas = .sepia; narrow = true; dim = false; bold = true
        }
    }

    func reset() { applyPreset(0); blurSpoilers = false; wpm = 220 }
}

struct ReadingComfort15View: View {
    @ObservedObject private var store = Reading15Store.shared
    @EnvironmentObject private var catalog: CatalogModel
    @State private var picking = false
    @State private var query = ""
    @State private var selected: Anime?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                preview
                LabCard(title: "Type", footnote: "The preview above is the real reader: the same values render the full synopsis.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Size \(Int(store.size)) pt").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Slider(value: $store.size, in: 13...26, step: 1).tint(Color.cortexPurple)
                        Text("Line spacing \(String(format: "%.0f", store.spacing)) pt").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Slider(value: $store.spacing, in: 0...16, step: 1).tint(Color.cortexPurple)
                    }
                }
                typography
                canvasCard
                LabCard(title: "Reading") {
                    LabRow(title: "Spoiler blur", detail: "Hides the preview until you tap it", symbol: "eye.slash.fill") {
                        Toggle("", isOn: $store.blurSpoilers).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    LabRow(title: "Reading speed", detail: "\(store.wpm) words per minute", symbol: "speedometer") {
                        Stepper("", value: $store.wpm, in: 120...400, step: 10).labelsHidden()
                    }
                    Divider().overlay(Color.white.opacity(0.06))
                    Button { picking = true; query = "" } label: {
                        Label("Read a real synopsis", systemImage: "book.fill")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Reading Comfort")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) { picker }
        .sheet(item: $selected) { anime in
            Reader15Sheet(anime: anime)
        }
    }

    private var sampleText: String {
        "A quiet town at the edge of a map that nobody has finished drawing. Every summer the same train arrives with one passenger nobody remembers inviting, and every autumn it leaves with someone the town would rather forget. When a girl with a borrowed name steps off the platform carrying a suitcase full of letters, the stationmaster has to decide which of the two stories he has been telling himself is the true one."
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Pill(text: "Preview")
                Spacer()
                Text(store.readingLabel(sampleText))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(store.canvas.background)
                VStack(alignment: .leading, spacing: 8) {
                    Text("The station at the end of the line")
                        .font(.system(size: store.size + 4, weight: .bold, design: store.design.design))
                        .foregroundStyle(store.canvas.ink)
                    Text(sampleText)
                        .font(store.font())
                        .lineSpacing(store.spacing)
                        .foregroundStyle(store.ink)
                        .frame(maxWidth: store.narrow ? 300 : .infinity, alignment: .leading)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .blur(radius: store.blurSpoilers ? 7 : 0)
                if store.blurSpoilers {
                    VStack(spacing: 6) {
                        Image(systemName: "eye.slash.fill").font(.system(size: 18, weight: .bold))
                        Text("Tap to reveal").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(store.canvas.ink.opacity(0.7))
                    .onTapGesture { store.blurSpoilers = false }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(store.canvas.isLight ? 0.05 : 0.08)))
        }
    }

    private var typography: some View {
        LabCard(title: "Typeface", footnote: "Serif reads best for long paragraphs; the system face is the safest for small screens.") {
            HStack(spacing: 8) {
                ForEach(Reading15FontDesign.allCases) { design in
                    Button { store.design = design } label: {
                        Text("Aa")
                            .font(.system(size: 17, weight: .semibold, design: design.design))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(store.design == design ? Color.cortexPurple.opacity(0.24) : Color.white.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(store.design == design ? Color.cortexPurple : .clear))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        store.applyPreset(index)
                    } label: {
                        Text(["Comfort", "Compact", "Large print"][index])
                            .font(.system(size: 11.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.06), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Narrow measure", detail: "Keeps lines under 65 characters", symbol: "text.alignleft") {
                Toggle("", isOn: $store.narrow).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Bold text", detail: "Heavier strokes, same size", symbol: "bold") {
                Toggle("", isOn: $store.bold).labelsHidden()
            }
        }
    }

    private var canvasCard: some View {
        LabCard(title: "Canvas", footnote: "Sepia is the only light theme on purpose — a pure white page is the worst thing to read at 2 a.m.") {
            HStack(spacing: 8) {
                ForEach(Reading15Canvas.allCases) { canvas in
                    Button { store.canvas = canvas } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(canvas.background)
                                .frame(height: 38)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.12)))
                                .overlay(Text("Aa").font(.system(size: 13, weight: .bold)).foregroundStyle(canvas.ink))
                            Text(canvas.title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(store.canvas == canvas ? Color.cortexPurple.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Dim the text", detail: "Lower contrast, easier at night", symbol: "circle.lefthalf.filled") {
                Toggle("", isOn: $store.dim).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            Button { store.reset() } label: {
                Label("Reset reading comfort", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.vertical, 4)
            }
        }
    }

    private var picker: some View {
        NavigationStack {
            List {
                ForEach(filtered) { anime in
                    Button { selected = anime } label: {
                        HStack(spacing: 10) {
                            AnimeArtwork(url: anime.cover).frame(width: 32, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(anime.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                Text(store.readingLabel(anime.synopsis)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search the catalogue")
            .scrollContentBackground(.hidden)
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Read")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { picking = false } } }
        }
    }

    private var filtered: [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(catalog.titles.prefix(50)) }
        return catalog.titles.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// The full synopsis on its own page, at the comfort settings above.
struct Reader15Sheet: View {
    let anime: Anime
    @ObservedObject private var store = Reading15Store.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                store.canvas.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AnimeArtwork(url: anime.cover)
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(anime.title)
                                .font(.system(size: store.size + 7, weight: .bold, design: store.design.design))
                                .foregroundStyle(store.canvas.ink)
                            Text([anime.format, anime.year.map(String.init), "\(anime.episodes) ep"]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(store.canvas.ink.opacity(0.55))
                        }
                        Text(anime.synopsis.isEmpty ? "No synopsis in the catalogue for this title yet." : anime.synopsis)
                            .font(store.font())
                            .lineSpacing(store.spacing)
                            .foregroundStyle(store.ink)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(store.readingLabel(anime.synopsis))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(store.canvas.ink.opacity(0.5))
                    }
                    .frame(maxWidth: store.narrow ? 560 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(18)
                }
            }
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = anime.synopsis
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
    }
}
