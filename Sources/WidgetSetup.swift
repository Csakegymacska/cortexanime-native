import SwiftUI

/// Widget guide for 4.0. The widgets read public endpoints only — no App Group, no account
/// and no downloads — so they keep working with any signing certificate.
struct NativeWidgetSetup: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let symbol: String
        let summary: String
        let bullet: [String]
    }

    private var packaged: Bool {
        guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("CortexEpisodesWidget.appex"),
              let bundle = Bundle(url: url) else { return false }
        return (bundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String
            == "com.apple.widgetkit-extension"
    }

    private let entries: [Entry] = [
        .init(name: "New in Hungarian", symbol: "sparkles.tv.fill",
              summary: "The newest episodes that already have Hungarian subtitles.",
              bullet: ["Episode number, poster and how long ago it went live.",
                       "“NEW” marks a series whose first episode just landed.",
                       "Lock screen sizes show today's count, the newest title, or a one line summary."]),
        .init(name: "Subtitle radar", symbol: "captions.bubble.fill",
              summary: "Hungarian and English subtitles in one widget.",
              bullet: ["Every row carries the language it landed in: HU or EN.",
                       "Today's count also shows up on the lock screen.",
                       "Use it when you read English subs and only want a nudge when something new is out."]),
        .init(name: "Latest airings", symbol: "tv.fill",
              summary: "What aired recently across the season.",
              bullet: ["Airing data comes from AniList, not from the subtitle pipeline.",
                       "It never promises a stream or a Hungarian track.",
                       "Also available as a lock screen widget."]),
    ]

    var body: some View {
        List {
            Section {
                Text("Three subtitle widgets plus the airing one, four Home Screen sizes each, with lock screen versions. They refresh on their own and keep the last good list when the network is down.")
                    .font(.subheadline)
            }
            ForEach(entries) { entry in
                Section(entry.name) {
                    Label(entry.summary, systemImage: entry.symbol).foregroundStyle(Color.cortexPurple)
                    ForEach(entry.bullet, id: \.self) { line in Text(line).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("How to add one") {
                Text("1. Touch and hold an empty area of the Home Screen.")
                Text("2. Choose Edit → Add Widget, then find CortexAnime.")
                Text("3. Pick a widget, swipe between sizes, then tap Add Widget.")
                Text("4. Lock screen: touch and hold the Lock Screen → Customise → tap under the clock → choose CortexAnime.")
                Text("An app cannot silently place its widget on your Home Screen.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Package check") {
                Label(packaged ? "Widget extension files found" : "Widget extension files missing",
                      systemImage: packaged ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(packaged ? Color.green : Color.orange)
                Text("This checks the embedded files only, not your certificate or iOS widget registration. Your signing tool must keep and sign the .appex extension together with the main app. If you installed the widget-free IPA, this row stays orange and no widget appears — that build has no extension by design.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Widgets never read your account, watch history or downloads.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("widgets.setup")
    }
}
