import SwiftUI

// MARK: - 1.5.0 · Cortex Lab
//
// A hub for everything new in 1.5.0 and the shared building blocks the new
// screens are made of. Nothing here talks to the network: these are local
// tools and settings, which is why they work signed out and in airplane mode.

enum Lab15 {
    static let version = "1.5.0"
    static let build = 150

    /// Every tool in the Lab. The order is the order they appear on the hub.
    enum Tool: String, CaseIterable, Identifiable {
        case timed, queue, taste, collections, playback, reading, storage, health, shortcuts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timed: return "Time Machine"
            case .queue: return "Smart Queue"
            case .taste: return "Taste Engine"
            case .collections: return "Collections+"
            case .playback: return "Session Planner"
            case .reading: return "Reading Comfort"
            case .storage: return "Storage & Data"
            case .health: return "Service Health"
            case .shortcuts: return "Shortcuts"
            }
        }

        var subtitle: String {
            switch self {
            case .timed: return "Twelve months of watching, measured"
            case .queue: return "Episodes lined up across series"
            case .taste: return "Filters that learn what you keep"
            case .collections: return "Lists, tags, notes and rewatches"
            case .playback: return "Budgets, bedtime and finish estimates"
            case .reading: return "Type, contrast and motion controls"
            case .storage: return "What the app keeps, and how to clear it"
            case .health: return "Ping, latency and catalogue coverage"
            case .shortcuts: return "Siri-free quick actions and deep links"
            }
        }

        var symbol: String {
            switch self {
            case .timed: return "clock.arrow.circlepath"
            case .queue: return "text.line.first.and.arrowtriangle.forward"
            case .taste: return "wand.and.stars"
            case .collections: return "square.stack.3d.up.fill"
            case .playback: return "play.circle.fill"
            case .reading: return "textformat.size"
            case .storage: return "internaldrive.fill"
            case .health: return "waveform.path.ecg"
            case .shortcuts: return "command.square.fill"
            }
        }

        var count: Int {
            switch self {
            case .timed: return 16
            case .queue: return 18
            case .taste: return 22
            case .collections: return 20
            case .playback: return 24
            case .reading: return 16
            case .storage: return 14
            case .health: return 12
            case .shortcuts: return 8
            }
        }
    }
}

// MARK: - Shared pieces

/// One settings row: title, optional detail, and a trailing control.
struct LabRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.cortexPurple)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 9)
    }
}

extension LabRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil, symbol: String? = nil) {
        self.init(title: title, detail: detail, symbol: symbol) { EmptyView() }
    }
}

/// A section of rows in the dark panel style the rest of the app uses.
struct LabCard<Content: View>: View {
    var title: String? = nil
    var footnote: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A big number with a caption — the unit every Lab screen reports in.
struct LabStat: View {
    let value: String
    let label: String
    var tint: Color = Color.cortexPurple

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A wrapping row of selectable chips — used for every small choice in the Lab.
struct LabChips<Item: Identifiable & Equatable>: View {
    let items: [Item]
    let label: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let on = item == selection
                    Button {
                        selection = item
                    } label: {
                        Text(label(item))
                            .font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(on ? Color.white : Color.white.opacity(0.62))
                            .background(on ? Color.cortexPurple : Color.cortexPanel, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// The formatter every Lab screen shares, so minutes read the same everywhere.
enum LabFormat {
    static func hours(_ seconds: Double) -> String {
        let hours = seconds / 3600
        if hours < 1 { return "\(Int(max(0, seconds / 60)))m" }
        if hours < 10 { return String(format: "%.1fh", hours) }
        return "\(Int(hours))h"
    }

    static func days(_ seconds: Double) -> String {
        String(format: "%.1f", seconds / 86400)
    }

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - The hub

struct Lab15View: View {
    @ObservedObject private var store = CreditStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                ForEach(Lab15.Tool.allCases) { tool in
                    NavigationLink { destination(for: tool) } label: { row(tool) }
                        .buttonStyle(.plain)
                }
                Text("Every tool on this page works without a network connection. The ones that change how the app behaves say so on their own screen, and each can be reset from Storage & Data.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Cortex Lab")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "flask.fill").foregroundStyle(Color.cortexPurple)
                Text("1.5.0").font(.system(size: 12, weight: .black)).foregroundStyle(Color.cortexPurple)
                Text("· \(totalCount) tools").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }
            Text("Nine rooms, one lab")
                .font(.system(size: 22, weight: .black))
            Text("Everything 1.5.0 added, in one place: how you watch, what you keep, and what the app remembers between sessions.")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                LabStat(value: "\(store.balance)", label: "credits", tint: .yellow)
                LabStat(value: LabFormat.hours(store.totalSeconds), label: "watched")
                LabStat(value: "\(store.streakDays)d", label: "streak", tint: .cortexMint)
            }
        }
    }

    private var totalCount: Int { Lab15.Tool.allCases.reduce(0) { $0 + $1.count } }

    private func row(_ tool: Lab15.Tool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: tool.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.cortexPurple)
                .frame(width: 42, height: 42)
                .background(Color.cortexPurple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).font(.system(size: 14.5, weight: .bold))
                Text(tool.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("\(tool.count)")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.35))
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(13)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func destination(for tool: Lab15.Tool) -> some View {
        switch tool {
        case .timed: TimeMachine15View()
        case .queue: SmartQueue15View()
        case .taste: TasteEngine15View()
        case .collections: Collections15View()
        case .playback: PlaybackLab15View()
        case .reading: ReadingComfort15View()
        case .storage: StorageLab15View()
        case .health: ServiceHealth15View()
        case .shortcuts: Shortcuts15View()
        }
    }
}
