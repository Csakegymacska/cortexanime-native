import Foundation
import Combine

/// 6.3: the card motion is the user's call.
///
/// The hero tilt is deliberately small (about four degrees at full swipe) and only the artwork
/// moves, but a full-width card on a big screen can still feel like too much. This switch removes
/// every rotation, parallax and press lean in the app at once — the system Reduce Motion setting
/// does the same from the other side, and both are honoured everywhere.
final class MotionSettings: ObservableObject {
    static let shared = MotionSettings()
    static let key = "motion.card3d.v1"

    @Published var cardTilt: Bool {
        didSet { defaults.set(cardTilt, forKey: Self.key) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cardTilt = (defaults.object(forKey: Self.key) as? Bool) ?? true
    }
}
