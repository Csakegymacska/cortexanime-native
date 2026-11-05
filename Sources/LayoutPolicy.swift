import SwiftUI
import UIKit

/// 6.4: which shell the app should show.
///
/// Three surfaces report a *regular* horizontal size class while still being a phone:
/// a landscape iPhone, and the inner display of an unfolding iPhone. Until now every regular
/// width got the iPad shell, so a 430 pt tall phone turned into a sidebar with giant insets.
/// `widePhone` exists for exactly those screens: a slim icon rail plus a full-width detail column.
enum CortexLayoutMode: String, CaseIterable {
    /// Compact phone: five tabs at the bottom.
    case phone
    /// Wide but still a phone (unfolded foldable, landscape iPhone): icon rail, no sidebar insets.
    case widePhone
    /// iPad, Split View and Stage Manager: the existing split shell, unchanged.
    case pad

    var title: String {
        switch self {
        case .phone: return "Phone"
        case .widePhone: return "Wide phone"
        case .pad: return "Pad"
        }
    }
}

enum CortexLayoutPolicy {
    /// QA / screenshot override: `--wide-phone-qa` renders the wide-phone shell on any device,
    /// so the layout can be proven in CI on a normal iPhone simulator.
    static let qaArgument = "--wide-phone-qa"

    static var qaForced: Bool {
        ProcessInfo.processInfo.arguments.contains(qaArgument)
    }

    /// Pure decision function — unit tested, no globals.
    static func mode(idiom: UIUserInterfaceIdiom,
                     horizontal: UserInterfaceSizeClass?,
                     forceWide: Bool = false,
                     qaForced: Bool = qaForced) -> CortexLayoutMode {
        if qaForced { return .widePhone }
        switch idiom {
        case .pad, .mac, .tv, .vision:
            return .pad
        default:
            if horizontal == .regular { return .widePhone }
            // The user can pin the wide layout on a device whose foldable display reports compact.
            return forceWide ? .widePhone : .phone
        }
    }
}

/// Persisted user choice behind Profile → Layout. Default is off: a normal iPhone stays tabbed.
final class LayoutPreferences: ObservableObject {
    static let shared = LayoutPreferences()
    static let forceWideKey = "layout.forceWide.v1"

    @Published var forceWide: Bool {
        didSet { defaults.set(forceWide, forKey: Self.forceWideKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.forceWide = (defaults.object(forKey: Self.forceWideKey) as? Bool) ?? false
    }
}

private struct CortexLayoutModeKey: EnvironmentKey {
    static let defaultValue: CortexLayoutMode = .phone
}

extension EnvironmentValues {
    /// Read by Home (content width, hero height) and by the Profile version row.
    var cortexLayoutMode: CortexLayoutMode {
        get { self[CortexLayoutModeKey.self] }
        set { self[CortexLayoutModeKey.self] = newValue }
    }
}
