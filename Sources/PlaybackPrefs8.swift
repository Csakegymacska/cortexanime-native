import SwiftUI

// MARK: - 8.0 · Playback preferences
//
// Two knobs the player never exposed: the speed a new episode starts at, and
// how far the double-tap jumps. Both are device-local and both are read by the
// player itself, so setting them here changes the real playback.

enum PlaybackRate8: Double, CaseIterable, Identifiable {
    case half = 0.5
    case threeQuarter = 0.75
    case normal = 1.0
    case oneQuarter = 1.25
    case oneHalf = 1.5
    case double = 2.0

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .half: return "0.5×"
        case .threeQuarter: return "0.75×"
        case .normal: return "1×"
        case .oneQuarter: return "1.25×"
        case .oneHalf: return "1.5×"
        case .double: return "2×"
        }
    }

    static func nearest(_ value: Double) -> PlaybackRate8 {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .normal
    }
}

enum SeekStep8: Double, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30

    var id: Double { rawValue }
    var title: String { "\(Int(rawValue)) s" }

    static func nearest(_ value: Double) -> SeekStep8 {
        allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .ten
    }
}

enum PlaybackPrefs8 {
    static let rateKey = "player.defaultRate8"
    static let seekStepKey = "player.seekStep8"

    static var rate: Double {
        let value = UserDefaults.standard.object(forKey: rateKey) as? Double ?? 1.0
        return min(2.0, max(0.5, value))
    }

    static var seekStep: Double {
        let value = UserDefaults.standard.object(forKey: seekStepKey) as? Double ?? 10
        return min(30, max(5, value))
    }
}

struct PlaybackExtras8View: View {
    @AppStorage(PlaybackPrefs8.rateKey) private var rate = 1.0
    @AppStorage(PlaybackPrefs8.seekStepKey) private var step = 10.0

    var body: some View {
        List {
            Section("Default speed") {
                Picker("Every new episode starts at", selection: $rate) {
                    ForEach(PlaybackRate8.allCases) { item in Text(item.title).tag(item.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("playback8.rate")
                Text("The player applies this speed when an episode starts. Nothing is remembered per series yet — that arrives with the watchlist sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Double-tap seek") {
                Picker("Jump length", selection: $step) {
                    ForEach(SeekStep8.allCases) { item in Text(item.title).tag(item.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("playback8.seekStep")
                Text("Double-tap the left or right half of the video to jump back or forward by this much.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Reset to 1× and 10 s") { rate = 1.0; step = 10 }
            }
        }
        .navigationTitle("Playback")
    }
}
