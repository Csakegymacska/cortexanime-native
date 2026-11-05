import SwiftUI
import UIKit
import UserNotifications

// MARK: - Notifications screen
//
// 6.0 is where subtitle alerts became something the viewer configures instead of a side
// effect of following a series: a master switch, one switch per language, and the choice
// between followed series only or the whole catalogue. Everything is checked on-device
// against the public feed, so there is no account and no server-side subscription.

struct NativeNotificationSettings: View {
    @ObservedObject private var settings = SubtitleAlertSettings.shared
    @ObservedObject private var alerts = AlertCenter.shared
    @ObservedObject private var feed = SubtitleFeed.shared
    @State private var busy = false
    @State private var resultLine: String?
    @State private var showPermissionHint = false

    private var authorizationText: String {
        switch alerts.authorization {
        case .authorized: return "Notifications are allowed"
        case .provisional: return "Quiet delivery is allowed"
        case .denied: return "Blocked in iOS Settings"
        case .ephemeral: return "Temporary permission"
        case .notDetermined: return "Not requested yet"
        @unknown default: return "Unknown"
        }
    }

    private var authorized: Bool {
        alerts.authorization == .authorized || alerts.authorization == .provisional
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                permissionCard
                masterCard
                languageCard
                scopeCard
                actionCard
                recentCard
                explainer
            }
            .padding(16)
            .padding(.bottom, 28)
        }
        .background(Color.cortexBlack)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.cortexBlack, for: .navigationBar)
        .task {
            await alerts.loadAuthorization()
            if feed.drops.isEmpty { await feed.load(force: true) }
        }
        .accessibilityIdentifier("settings.notifications")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Subtitle alerts")
                .font(.system(size: 30, weight: .black))
                .accessibilityIdentifier("notify.title")
            Text("Pick the languages you read and CortexAnime tells you the moment a new subtitle lands — Hungarian, English, or both.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 6) {
                SubtitleLanguageBadge(language: .hungarian, verbose: true)
                SubtitleLanguageBadge(language: .english, verbose: true)
                Spacer(minLength: 0)
            }
        }
    }

    private var permissionCard: some View {
        CortexGlassCard(tint: authorized ? SubtitleLanguage.hungarian.color.opacity(0.18) : Color.orange.opacity(0.18)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: authorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(authorized ? SubtitleLanguage.hungarian.color : .orange)
                    Text(authorizationText).font(.subheadline.bold())
                    Spacer(minLength: 0)
                }
                Text(authorized
                     ? "iOS lets CortexAnime show banners, sounds and the notification list."
                     : "Without permission the app can still track what is new, but iOS will not show the banner. You can allow it in iOS Settings → CortexAnime → Notifications.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                HStack(spacing: 10) {
                    if !authorized {
                        Button {
                            Task {
                                busy = true
                                let granted = await alerts.requestAuthorization()
                                showPermissionHint = !granted
                                busy = false
                            }
                        } label: {
                            Label("Allow notifications", systemImage: "bell.badge.fill")
                                .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("notify.allow")
                        Button("iOS Settings") { openSystemSettings() }
                            .font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.white.opacity(0.08), in: Capsule())
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("notify.systemSettings")
                    }
                    Spacer(minLength: 0)
                    if busy { ProgressView().controlSize(.small) }
                }
                if showPermissionHint {
                    Text("iOS refused the request. Open iOS Settings → CortexAnime → Notifications and turn on Allow Notifications.")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .accessibilityIdentifier("notify.status")
    }

    private var masterCard: some View {
        CortexGlassCard(tint: settings.enabled ? Color.cortexPurple.opacity(0.20) : .clear) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { settings.enabled }, set: { settings.enabled = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Subtitle alerts").font(.subheadline.bold())
                        Text(settings.preferences.summary).font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .tint(Color.cortexPurple)
                .accessibilityIdentifier("notify.master")
                Divider().overlay(Color.white.opacity(0.10))
                Text("A banner arrives at most once per series per language, and only for the newest missing episode — a series that catches up three episodes at once is still one notification.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var languageCard: some View {
        CortexGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Languages").font(.system(size: 11, weight: .black)).tracking(1).foregroundStyle(.white.opacity(0.45))
                languageRow(.hungarian, count: feed.count(language: .hungarian))
                languageRow(.english, count: feed.count(language: .english))
            }
        }
        .disabled(!settings.enabled)
        .opacity(settings.enabled ? 1 : 0.55)
    }

    private func languageRow(_ language: SubtitleLanguage, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: language.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(language.color)
                .frame(width: 28, height: 28)
                .background(language.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(language.name).font(.subheadline.bold())
                Text(count == 1 ? "1 new drop in the last 7 days" : "\(count) new drops in the last 7 days")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { settings.isOn(language) }, set: { settings.setLanguage(language, on: $0) }))
                .labelsHidden()
                .tint(language.color)
                .accessibilityIdentifier("notify.lang.\(language.rawValue)")
                .accessibilityLabel(language.name + " subtitle alerts")
        }
    }

    private var scopeCard: some View {
        CortexGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { settings.followedOnly }, set: { settings.followedOnly = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only series I follow").font(.subheadline.bold())
                        Text("Off: every series in the catalog can alert you.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .tint(Color.cortexPurple)
                .accessibilityIdentifier("notify.followedOnly")
                HStack(spacing: 8) {
                    Image(systemName: "heart.text.square").font(.caption).foregroundStyle(.white.opacity(0.5))
                    Text(alerts.follows.isEmpty ? "You are not following any series yet." : "Following \(alerts.follows.count) series.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    Spacer(minLength: 0)
                    NavigationLink("Manage") { NativeAlerts() }.font(.caption2.bold()).foregroundStyle(Color.cortexPurple)
                }
            }
        }
        .disabled(!settings.enabled)
        .opacity(settings.enabled ? 1 : 0.55)
    }

    private var actionCard: some View {
        CortexGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        Task { await runCheck() }
                    } label: {
                        Label("Check now", systemImage: "arrow.clockwise")
                            .font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Color.cortexPurple.opacity(0.22), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityIdentifier("notify.check")
                    Button {
                        Task { await alerts.sendTestNotification() }
                    } label: {
                        Label("Test banner", systemImage: "bell.and.waves.left.and.right")
                            .font(.caption.bold()).padding(.horizontal, 14).padding(.vertical, 9)
                            .background(.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("notify.test")
                    Spacer(minLength: 0)
                    if busy { ProgressView().controlSize(.small) }
                }
                if let resultLine {
                    Text(resultLine).font(.caption2).foregroundStyle(SubtitleLanguage.hungarian.color)
                        .accessibilityIdentifier("notify.result")
                }
                Text(lastCheckLine).font(.caption2).foregroundStyle(.white.opacity(0.45))
                Button(role: .destructive) { settings.resetWatermarks(); resultLine = "History cleared — the next check starts fresh." } label: {
                    Text("Forget what I have seen").font(.caption2.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityIdentifier("notify.reset")
            }
        }
    }

    private var lastCheckLine: String {
        guard let date = settings.lastCheck else { return "No check has run on this device yet." }
        return "Last check: " + date.formatted(date: .abbreviated, time: .shortened)
            + (feed.updated.map { " · feed updated " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
    }

    private var recentCard: some View {
        let recent = feed.recent(days: 14, languages: Set(settings.preferences.languages), limit: 6)
        return CortexGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Latest drops").font(.system(size: 11, weight: .black)).tracking(1).foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength: 0)
                    NavigationLink("All") { NativeSubtitleRadar() }.font(.caption2.bold()).foregroundStyle(Color.cortexPurple)
                }
                if recent.isEmpty {
                    Text("Nothing published in the selected languages in the last two weeks.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(recent) { drop in
                        SubtitleDropRow(drop: drop, showsArtwork: false)
                    }
                }
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the check works").font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
            Text("The app reads the public subtitle feed (cortexanime.eu/api/app/subfeed), compares it with what this device already saw, and posts a local notification. iOS decides when a background refresh actually runs — opening the app always checks immediately. No account, no push server, nothing to unsubscribe from.")
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 4)
    }

    private func runCheck() async {
        busy = true
        defer { busy = false }
        let hits = await alerts.checkSubtitles(notify: true)
        await alerts.loadAuthorization()
        if hits.isEmpty {
            resultLine = authorized
                ? "Nothing new since the last check."
                : "Nothing new — but iOS will not show banners until notifications are allowed."
        } else {
            resultLine = hits.count == 1 ? "1 new subtitle found." : "\(hits.count) new subtitles found."
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Subtitle radar screen

struct NativeSubtitleRadar: View {
    @ObservedObject private var feed = SubtitleFeed.shared
    @State private var filter: SubtitleLanguage? = nil
    @State private var window = 14

    private var visible: [SubtitleDrop] {
        let languages: Set<SubtitleLanguage> = filter.map { [$0] } ?? Set(SubtitleLanguage.allCases)
        return feed.recent(days: window, languages: languages, limit: 120)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    chip(nil, label: "Everything")
                    chip(.hungarian, label: "Hungarian")
                    chip(.english, label: "English")
                    Spacer(minLength: 0)
                }
                Picker("Window", selection: $window) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("radar.window")
                if visible.isEmpty {
                    ContentUnavailableView("No subtitle drops yet",
                                           systemImage: "captions.bubble",
                                           description: Text("Nothing has been published in this window and language."))
                        .padding(.top, 40)
                } else {
                    ForEach(visible) { drop in
                        NavigationLink { NativeLinkedDetail(id: drop.animeID) } label: {
                            CortexGlassCard(cornerRadius: 20, tint: drop.language.color.opacity(0.12), padding: 12) {
                                SubtitleDropRow(drop: drop)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.cortexBlack)
        .navigationTitle("Subtitle radar")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await feed.load(force: true) }
        .task { if feed.drops.isEmpty { await feed.load(force: true) } }
        .accessibilityIdentifier("subtitle.radar")
    }

    private func chip(_ language: SubtitleLanguage?, label: String) -> some View {
        let selected = filter == language
        return Button { filter = language } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(selected ? Color.cortexBlack : .white)
                .background(selected ? (language?.color ?? Color.cortexPurple) : Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("radar.filter.\(language?.rawValue ?? "all")")
    }
}
