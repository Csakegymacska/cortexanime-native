import SwiftUI
import UIKit

// MARK: - 1.5.0 · Session Planner
//
// Watching is a budget, not a score. This screen turns the watch log into
// numbers you can plan with: how many episodes fit before bedtime, how long
// until a series is finished, whether today already went over the cap, and how
// many of the last thirty days stayed under it.

@MainActor final class Session15Store: ObservableObject {
    static let shared = Session15Store()

    @Published var dailyCap: Int { didSet { defaults.set(dailyCap, forKey: "lab15.session.dailyCap") } }
    @Published var weeklyCap: Int { didSet { defaults.set(weeklyCap, forKey: "lab15.session.weeklyCap") } }
    @Published var episodeMinutes: Int { didSet { defaults.set(episodeMinutes, forKey: "lab15.session.episodeMinutes") } }
    @Published var bedtimeHour: Int { didSet { defaults.set(bedtimeHour, forKey: "lab15.session.bedHour") } }
    @Published var bedtimeMinute: Int { didSet { defaults.set(bedtimeMinute, forKey: "lab15.session.bedMinute") } }
    @Published var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: "lab15.session.keepAwake")
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
    }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "lab15.session.haptics") } }

    private let defaults = UserDefaults.standard

    init() {
        dailyCap = defaults.object(forKey: "lab15.session.dailyCap") as? Int ?? 4
        weeklyCap = defaults.object(forKey: "lab15.session.weeklyCap") as? Int ?? 20
        episodeMinutes = defaults.object(forKey: "lab15.session.episodeMinutes") as? Int ?? 24
        bedtimeHour = defaults.object(forKey: "lab15.session.bedHour") as? Int ?? 23
        bedtimeMinute = defaults.object(forKey: "lab15.session.bedMinute") as? Int ?? 0
        keepAwake = defaults.object(forKey: "lab15.session.keepAwake") as? Bool ?? false
        haptics = defaults.object(forKey: "lab15.session.haptics") as? Bool ?? true
    }

    func tap() {
        guard haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Episodes watched on a given day, counted from completed ticks only.
    func episodes(on day: Date, log: [WatchTick]) -> Int {
        let calendar = Calendar.current
        return log.filter { calendar.isDate($0.date, inSameDayAs: day) && $0.completed }.count
    }

    func episodesThisWeek(log: [WatchTick]) -> Int {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return log.filter { $0.date >= start && $0.completed }.count
    }

    func daysUnderBudget(log: [WatchTick], window: Int = 30) -> Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<window {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            if episodes(on: day, log: log) <= dailyCap { count += 1 }
        }
        return count
    }

    /// Minutes from now until the bedtime setting; negative when it has passed.
    var minutesUntilBedtime: Int {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = bedtimeHour
        components.minute = bedtimeMinute
        guard let bed = calendar.date(from: components) else { return 0 }
        let target = bed > now ? bed : (calendar.date(byAdding: .day, value: 1, to: bed) ?? bed)
        return Int(target.timeIntervalSince(now) / 60)
    }

    var episodesBeforeBedtime: Int {
        guard episodeMinutes > 0 else { return 0 }
        return max(0, minutesUntilBedtime / episodeMinutes)
    }

    /// Finishing time if one episode starts right now.
    func finishTime(episodes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let end = Date().addingTimeInterval(Double(episodes * episodeMinutes) * 60)
        return formatter.string(from: end)
    }

    var bedtimeLabel: String {
        String(format: "%02d:%02d", bedtimeHour, bedtimeMinute)
    }
}

struct PlaybackLab15View: View {
    @ObservedObject private var store = Session15Store.shared
    @ObservedObject private var credits = CreditStore.shared

    private var todayCount: Int { store.episodes(on: Date(), log: credits.watchLog) }
    private var weekCount: Int { store.episodesThisWeek(log: credits.watchLog) }
    private var overToday: Bool { todayCount > store.dailyCap }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                today
                budget
                bedtime
                finish
                device
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Session Planner")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: today

    private var today: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LabStat(value: "\(todayCount)/\(store.dailyCap)",
                        label: overToday ? "today · over cap" : "today",
                        tint: overToday ? .orange : .cortexMint)
                LabStat(value: "\(weekCount)/\(store.weeklyCap)", label: "this week",
                        tint: weekCount > store.weeklyCap ? .orange : .cortexPurple)
                LabStat(value: "\(store.daysUnderBudget(log: credits.watchLog))/30", label: "days under cap")
            }
            if overToday {
                Label("Today already went over the daily cap. Tomorrow starts from zero — the budget never carries debt.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: budget

    private var budget: some View {
        LabCard(title: "Budget", footnote: "A completed episode counts. Starting one and stopping does not, so the counter cannot be inflated by browsing.") {
            LabRow(title: "Daily cap", detail: "\(store.dailyCap) episodes a day", symbol: "calendar.badge.clock") {
                Stepper("", value: $store.dailyCap, in: 1...20).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Weekly cap", detail: "\(store.weeklyCap) episodes a week", symbol: "calendar") {
                Stepper("", value: $store.weeklyCap, in: 1...100, step: 5).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Episode length", detail: "Used for every estimate on this screen", symbol: "clock") {
                Stepper("\(store.episodeMinutes) min", value: $store.episodeMinutes, in: 5...90, step: 1).labelsHidden()
            }
        }
    }

    // MARK: bedtime

    private var bedtime: some View {
        LabCard(title: "Bedtime", footnote: "The window is measured from now to your bedtime; after it passes, the next day's bedtime is used.") {
            LabRow(title: "Bedtime", detail: store.bedtimeLabel, symbol: "moon.zzz.fill") {
                Stepper("", value: $store.bedtimeHour, in: 0...23).labelsHidden()
            }
            LabRow(title: "Minute", detail: "\(store.bedtimeMinute)", symbol: "clock.badge") {
                Stepper("", value: $store.bedtimeMinute, in: 0...55, step: 5).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fits before bed").font(.system(size: 14, weight: .semibold))
                    Text("\(store.minutesUntilBedtime) minutes left in the window")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.episodesBeforeBedtime)")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Color.cortexPurple)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: finish estimate

    private var finish: some View {
        LabCard(title: "If you start now", footnote: "A straight-line estimate at one episode after another, using the episode length above.") {
            ForEach([1, 2, 3, 5, 7], id: \.self) { count in
                LabRow(title: "\(count) episode\(count == 1 ? "" : "s")",
                       detail: "\(count * store.episodeMinutes) minutes", symbol: "play.fill") {
                    Text(store.finishTime(episodes: count))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
    }

    // MARK: device

    private var device: some View {
        LabCard(title: "Device", footnote: "Keep awake is applied the moment you flip it and is released when the app closes; it never survives a relaunch unless the switch is on.") {
            LabRow(title: "Keep the screen awake", detail: "While the app is in front", symbol: "sun.max.fill") {
                Toggle("", isOn: $store.keepAwake).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Haptics", detail: "A light tap on every Lab action", symbol: "hand.tap.fill") {
                Toggle("", isOn: $store.haptics).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            Button {
                store.tap()
            } label: {
                Label("Test the haptic", systemImage: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 8)
            }
        }
    }
}
