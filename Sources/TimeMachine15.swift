import SwiftUI

// MARK: - 1.5.0 · Time Machine
//
// Your own watching, measured properly: a heatmap of the last twelve weeks,
// a month-by-month ledger, streaks, the cost of each habit, and a shareable
// card. Everything is computed from the rolling watch log the credit system
// already keeps, so there is no new tracking here.

struct TimeMachine15View: View {
    @ObservedObject private var store = CreditStore.shared
    @AppStorage("lab15.time.targetHours") private var targetHours: Int = 10

    private var ticks: [WatchTick] { store.watchLog }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                headline
                heatmap
                ledger
                habits
                shareCard
            }
            .padding(16)
        }
        .background(Color.cortexBlack.ignoresSafeArea())
        .navigationTitle("Time Machine")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LabStat(value: LabFormat.hours(store.totalSeconds), label: "total watched")
                LabStat(value: "\(store.episodesCompleted)", label: "episodes done", tint: .cortexMint)
                LabStat(value: "\(store.seriesCompleted)", label: "series finished", tint: .orange)
            }
            HStack(spacing: 10) {
                LabStat(value: "\(ticks.count)", label: "sessions logged")
                LabStat(value: "\(store.streakDays)d", label: "current streak")
                LabStat(value: "Lv \(store.level)", label: "level")
            }
        }
    }

    // MARK: heatmap — 12 weeks, seven rows

    private var heatmap: some View {
        let days = lastTwelveWeeks()
        let peak = days.flatMap { $0.slots }.max() ?? 1
        return LabCard(title: "Last twelve weeks", footnote: "Each square is one day. Darker means more minutes. Days with no watch time stay empty instead of guessing.") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(days) { day in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { slot in
                                let entry = day.slots[slot]
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(colour(for: entry, peak: peak))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func colour(for seconds: Double, peak: Double) -> Color {
        guard seconds > 0 else { return Color.white.opacity(0.05) }
        let ratio = min(1, seconds / max(peak, 1))
        return Color.cortexPurple.opacity(0.28 + ratio * 0.72)
    }

    private struct HeatDay: Identifiable {
        let id: Int
        var slots: [Double]
    }

    private func lastTwelveWeeks() -> [HeatDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var buckets: [Date: Double] = [:]
        for tick in ticks {
            let day = calendar.startOfDay(for: tick.date)
            buckets[day, default: 0] += tick.seconds
        }
        var out: [HeatDay] = []
        for week in stride(from: 11, through: 0, by: -1) {
            var slots = [Double](repeating: 0, count: 7)
            for slot in 0..<7 {
                let offset = -(week * 7) - (6 - slot)
                if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                    slots[slot] = buckets[calendar.startOfDay(for: day)] ?? 0
                }
            }
            out.append(HeatDay(id: week, slots: slots))
        }
        return out
    }

    // MARK: month ledger

    private var ledger: some View {
        let months = monthBuckets()
        return LabCard(title: "Month by month", footnote: "A month with no entries is listed too — an empty month is information.") {
            if months.isEmpty {
                Text("Nothing logged yet. Watch an episode and this fills in.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).padding(.vertical, 10)
            } else {
                ForEach(months) { month in
                    LabRow(title: month.name, detail: "\(month.episodes) episodes · \(month.days) active days", symbol: "calendar") {
                        Text(LabFormat.hours(month.seconds))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    if month.id != months.last?.id { Divider().overlay(Color.white.opacity(0.06)) }
                }
            }
        }
    }

    private struct Month15: Identifiable {
        let id: String
        let name: String
        let seconds: Double
        let episodes: Int
        let days: Int
    }

    private func monthBuckets() -> [Month15] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        var order: [String] = []
        var seconds: [String: Double] = [:]
        var episodes: [String: Set<String>] = [:]
        var days: [String: Set<Date>] = [:]
        for tick in ticks {
            let components = calendar.dateComponents([.year, .month], from: tick.date)
            let key = "\(components.year ?? 0)-\(components.month ?? 0)"
            if seconds[key] == nil { order.append(key) }
            seconds[key, default: 0] += tick.seconds
            if tick.completed { episodes[key, default: []].insert("\(tick.animeID)#\(tick.episode)") }
            days[key, default: []].insert(calendar.startOfDay(for: tick.date))
        }
        guard let firstTick = ticks.map({ $0.date }).min() else { return [] }
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: firstTick)) ?? firstTick
        let end = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        var keys: [String] = []
        while cursor <= end {
            let components = calendar.dateComponents([.year, .month], from: cursor)
            keys.append("\(components.year ?? 0)-\(components.month ?? 0)")
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys.reversed().map { key in
            let parts = key.split(separator: "-")
            let year = Int(parts.first ?? "0") ?? 0
            let month = Int(parts.last ?? "1") ?? 1
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            let date = calendar.date(from: components) ?? Date()
            return Month15(id: key, name: formatter.string(from: date), seconds: seconds[key] ?? 0,
                           episodes: episodes[key]?.count ?? 0, days: days[key]?.count ?? 0)
        }
    }

    // MARK: habits

    private var habits: some View {
        LabCard(title: "Habits", footnote: "Burn rate assumes 24 minutes an episode. The goal is yours, not ours.") {
            LabRow(title: "Average session", detail: "How long one sitting usually lasts", symbol: "timer") {
                Text(averageSession).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Busiest day", detail: busiestDay.isEmpty ? "No data yet" : busiestDay, symbol: "flame.fill") {
                Text(busiestDaySeconds).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "Weekly goal", detail: "\(targetHours) hours a week", symbol: "target") {
                Stepper("", value: $targetHours, in: 1...60).labelsHidden()
            }
            Divider().overlay(Color.white.opacity(0.06))
            LabRow(title: "This week", detail: weekProgress.detail, symbol: "chart.bar.fill") {
                Text(weekProgress.value).font(.system(size: 12, weight: .bold)).foregroundStyle(weekProgress.done ? Color.cortexMint : .white.opacity(0.6))
            }
        }
    }

    private var averageSession: String {
        guard !ticks.isEmpty else { return "–" }
        return LabFormat.hours(ticks.reduce(0) { $0 + $1.seconds } / Double(ticks.count))
    }

    private var busiestDay: String {
        ticks.max(by: { $0.seconds < $1.seconds })?.date.formatted(.dateTime.weekday(.wide)) ?? ""
    }

    private var busiestDaySeconds: String {
        guard let top = ticks.max(by: { $0.seconds < $1.seconds }) else { return "–" }
        return LabFormat.hours(top.seconds)
    }

    private var weekProgress: (value: String, detail: String, done: Bool) {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else {
            return ("–", "No data", false)
        }
        let seconds = ticks.filter { $0.date >= weekStart }.reduce(0) { $0 + $1.seconds }
        let target = Double(targetHours) * 3600
        return (LabFormat.hours(seconds), seconds >= target ? "Goal reached" : "\(LabFormat.hours(max(0, target - seconds))) to go", seconds >= target)
    }

    // MARK: shareable card

    private var shareCard: some View {
        VStack(spacing: 12) {
            LabCard(title: "Share card") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CORTEXANIME").font(.system(size: 10, weight: .black)).tracking(2).foregroundStyle(Color.cortexPurple)
                    Text("I have watched \(LabFormat.hours(store.totalSeconds)) of anime")
                        .font(.system(size: 18, weight: .black))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(store.episodesCompleted) episodes · \(store.seriesCompleted) series · level \(store.level)")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                .padding(.vertical, 8)
            }
            ShareLink(item: shareText) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share the summary").font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
        }
    }

    private var shareText: String {
        "CortexAnime: \(LabFormat.hours(store.totalSeconds)) watched · \(store.episodesCompleted) episodes · \(store.seriesCompleted) series · level \(store.level). cortanime.eu"
    }
}
