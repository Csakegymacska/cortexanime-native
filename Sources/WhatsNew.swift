import SwiftUI

// MARK: - What's New (2.0.0)
//
// A hívási helyek (App, AdaptiveShell, Profile) a `WhatsNew.key` UserDefaults
// jelzőt és a `WhatsNewView(onDone:)`-t várják — ez a fájl azt valósítja meg.
// A kulcs verziónként más, így minden nagyobb kiadás után egyszer magától
// megjelenik; a Profilból újra megnyitható.

enum WhatsNew {
    static let version = "2.0.0"
    /// `true` = már látták ezt a verziót (a hívási helyek így olvassák).
    static let key = "whatsnew.2.0.0.seen"

    /// (szimbólum, cím, leírás) — app-UI-ban nincs emoji, szimbólumok vannak.
    static let items: [(symbol: String, title: String, detail: String)] = [
        ("bubble.left.and.bubble.right.fill", "Chat, rebuilt",
         "The chat now waits for your session to verify before loading — messages appear every time, not just on a lucky attempt."),
        ("magnifyingglass", "Search inside conversations",
         "Find any message in a thread without scrolling back weeks."),
        ("arrowshape.turn.up.left", "Quote replies",
         "Hold a message, tap Reply — the quote travels with your answer and shows as its own card."),
        ("hand.tap", "Heart burst & swipe reply",
         "Double-tap a message for a quick heart burst, or swipe it right to answer it."),
        ("bell.badge", "Badges where they matter",
         "Unread message count on the Messages row, friend request count on the Friends row."),
        ("sparkles", "What's new sheet",
         "This sheet appears once after each update — the same list lives in Profile, and the release notes on the site."),
        ("wrench.and.screwdriver", "Stability fixes",
         "Failed sends stay visible with one-tap retry; the friends list and the new-message sheet load reliably.")
    ]
}

struct WhatsNewView: View {
    var onDone: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version \(WhatsNew.version)").font(.caption.bold()).tracking(1.1)
                            .foregroundStyle(Color.cortexPurple)
                        Text("What's new").font(.system(size: 30, weight: .black))
                    }
                    ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.cortexPurple)
                                .frame(width: 34, height: 34)
                                .background(Color.cortexPurple.opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.subheadline.bold())
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        UserDefaults.standard.set(true, forKey: WhatsNew.key)
                        onDone()
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.cortexBlack)
        }
    }
}
