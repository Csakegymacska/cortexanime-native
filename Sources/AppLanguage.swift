import Foundation

/// 7.4 — a global build.
///
/// The app is English-first: every screen, the player, the studio, chat and the widgets are
/// written in English. This helper only decides the handful of sentences that still have a
/// Hungarian twin (update-centre failures, the caption preview, the release marker). A device set
/// to Hungarian gets Hungarian, everything else gets English — no setting to hunt for, and no
/// mixed language on a non-Hungarian phone.
enum AppLanguage {
    /// True when the phone's first preferred language is Hungarian.
    static var isHungarian: Bool {
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return code.hasPrefix("hu")
    }

    /// Two-way text. Keep the English variant first so a missing translation can never leak.
    static func text(en: String, hu: String) -> String {
        isHungarian ? hu : en
    }

    /// A short label for the current language, used by Settings → About.
    static var displayName: String { isHungarian ? "Magyar" : "English" }
}
