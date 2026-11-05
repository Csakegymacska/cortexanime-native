import Foundation
import SwiftUI

/// Device-local rules for the "Are you still watching?" guard.
///
/// The guard watches two signals: how many episodes played back to back without a
/// tap, and how long one item kept playing without a tap. When a limit is crossed
/// it asks before the next episode starts, and if nobody answers the countdown it
/// hands the decision to the player screen, which pauses and closes so the phone
/// can lock the screen.
enum WatchGuardPolicy {
    static let enabledKey = "player.watchGuard.enabled"
    static let episodeKey = "player.watchGuard.episodes"
    static let minutesKey = "player.watchGuard.minutes"
    static let minimumEpisodes = 2
    static let defaultEpisodes = 4
    static let maximumEpisodes = 8
    static let episodeChoices = [2, 3, 4, 5, 6, 8]
    static let countdownSeconds = 30
    static let defaultMinutes = 150.0
    static let minuteChoices: [Double] = [60, 90, 120, 150, 180, 240]

    static func clampedEpisodes(_ raw: Int) -> Int { min(max(raw, minimumEpisodes), maximumEpisodes) }

    /// Returns 0 for "off", otherwise a usable minute limit between 30 and 600.
    static func normalizedMinutes(_ raw: Double) -> Double {
        guard raw.isFinite, raw > 0 else { return 0 }
        return min(max(raw, 30), 600)
    }

    static func askBeforeNextEpisode(enabled: Bool, threshold: Int, finished: Int) -> Bool {
        guard enabled, finished > 0 else { return false }
        return finished >= clampedEpisodes(threshold)
    }

    static func askDuringPlayback(enabled: Bool, minutesLimit: Double, minutesPlayed: Double) -> Bool {
        let limit = normalizedMinutes(minutesLimit)
        guard enabled, limit > 0, minutesPlayed.isFinite else { return false }
        return minutesPlayed >= limit
    }

    static func countdownText(_ remaining: Int) -> String {
        remaining > 0 ? "Pausing in \(remaining) s" : "Pausing"
    }

    static func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(max(1, minutes)) minutes" }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours) h \(rest) min"
    }
}

@MainActor final class WatchGuard: ObservableObject {
    enum Reason: Equatable {
        case episodes(Int)
        case longPlayback(Int)

        var title: String { "Are you still watching?" }

        var detail: String {
            switch self {
            case .episodes(let count):
                return "\(count) episodes played in a row without a tap. If nobody answers, CortexPlayer pauses and closes so the screen can lock."
            case .longPlayback(let minutes):
                return "This has been playing for \(WatchGuardPolicy.durationText(minutes)) without a tap. If nobody answers, CortexPlayer pauses and closes so the screen can lock."
            }
        }
    }

    @Published private(set) var episodesFinished = 0
    @Published private(set) var asking: Reason?
    @Published private(set) var remaining = WatchGuardPolicy.countdownSeconds

    /// Called on the main actor when the countdown runs out without an answer.
    var onTimeout: ((Reason) -> Void)?

    private var playedSeconds = 0.0
    private var countdownTask: Task<Void, Never>?

    deinit { countdownTask?.cancel() }

    var enabled: Bool {
        guard UserDefaults.standard.object(forKey: WatchGuardPolicy.enabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: WatchGuardPolicy.enabledKey)
    }

    var episodeThreshold: Int {
        let stored = UserDefaults.standard.object(forKey: WatchGuardPolicy.episodeKey) as? Int ?? WatchGuardPolicy.defaultEpisodes
        return WatchGuardPolicy.clampedEpisodes(stored)
    }

    var minuteThreshold: Double {
        let stored = UserDefaults.standard.object(forKey: WatchGuardPolicy.minutesKey) as? Double ?? WatchGuardPolicy.defaultMinutes
        return WatchGuardPolicy.normalizedMinutes(stored)
    }

    /// Any deliberate action in the player: a tap, a seek, a settings change.
    func noteInteraction() {
        episodesFinished = 0
        playedSeconds = 0
        if asking != nil { dismissPrompt() }
    }

    /// The episode reached its end without the viewer touching anything.
    func noteEpisodeFinished() {
        episodesFinished += 1
        playedSeconds = 0
    }

    /// Accumulates playing time so one long item cannot run all night.
    func tick(playing: Bool, seconds: Double = 5) {
        guard asking == nil else { return }
        guard playing, seconds.isFinite, seconds > 0 else { return }
        playedSeconds += seconds
        let limit = minuteThreshold
        guard WatchGuardPolicy.askDuringPlayback(enabled: enabled, minutesLimit: limit, minutesPlayed: playedSeconds / 60) else { return }
        playedSeconds = 0
        present(.longPlayback(Int(limit.rounded())))
    }

    /// Called at the end of an episode, before the next one would auto-start.
    /// Returns true when the guard took over and the caller must not continue.
    func shouldHoldBeforeNextEpisode() -> Bool {
        guard asking == nil else { return true }
        guard WatchGuardPolicy.askBeforeNextEpisode(enabled: enabled, threshold: episodeThreshold, finished: episodesFinished) else { return false }
        present(.episodes(episodesFinished))
        return true
    }

    /// "I'm still watching": the chain restarts from zero.
    func acknowledge() {
        dismissPrompt()
        episodesFinished = 0
        playedSeconds = 0
    }

    func dismissPrompt() {
        countdownTask?.cancel()
        countdownTask = nil
        asking = nil
        remaining = WatchGuardPolicy.countdownSeconds
    }

    private func present(_ reason: Reason) {
        asking = reason
        remaining = WatchGuardPolicy.countdownSeconds
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.asking != nil else { return }
                if self.remaining > 1 {
                    self.remaining -= 1
                } else {
                    self.remaining = 0
                    let answered = self.asking
                    self.dismissPrompt()
                    if let answered { self.onTimeout?(answered) }
                    return
                }
            }
        }
    }
}

struct WatchGuardPrompt: View {
    let reason: WatchGuard.Reason
    let remaining: Int
    let continueWatching: () -> Void
    let stopWatching: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "moon.zzz.fill").font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.cortexPurple)
                Text(reason.title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                Text(reason.detail).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    ProgressView(value: Double(WatchGuardPolicy.countdownSeconds - remaining),
                                 total: Double(WatchGuardPolicy.countdownSeconds))
                        .tint(Color.cortexPurple).frame(maxWidth: 240)
                    Text(WatchGuardPolicy.countdownText(remaining)).font(.footnote).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.top, 4)
                VStack(spacing: 10) {
                    Button(action: continueWatching) {
                        Text("Yes, I'm still watching").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.cortexPurple)
                    .accessibilityIdentifier("player.watchGuardContinue")
                    Button(action: stopWatching) {
                        Text("Stop here").frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("player.watchGuardStop")
                }
                .frame(maxWidth: 320)
                .padding(.top, 6)
            }
            .padding(24)
        }
        .transition(.opacity)
        .accessibilityIdentifier("player.watchGuard")
        .accessibilityAddTraits(.isModal)
    }
}
