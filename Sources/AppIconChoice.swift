import SwiftUI
import UIKit

/// 6.7: the app icon is part of the appearance.
///
/// iOS only swaps whole icon files (`UIApplication.setAlternateIconName`), so each theme has its
/// own 1024 px artwork under `Assets.xcassets/AppIcon*.appiconset`, listed in Info.plist as
/// `CFBundleAlternateIcons`. The choice is remembered in the app group and re-applied on launch,
/// because an unsigned/re-signed install keeps the bundle icon but drops the alternate selection.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case primary, midnight, aurora, ember, sakura, graphite, noir, daylight

    var id: String { rawValue }

    /// `nil` means the bundle's own icon (AppIcon.appiconset).
    var alternateName: String? { self == .primary ? nil : "AppIcon" + rawValue.capitalized }

    var title: String {
        switch self {
        case .primary: return "Cosmic"
        case .midnight: return "Midnight"
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .sakura: return "Sakura"
        case .graphite: return "Graphite"
        case .noir: return "Noir"
        case .daylight: return "Daylight"
        }
    }

    var asset: String { self == .primary ? "AppIcon" : "AppIcon" + rawValue.capitalized }
}

final class AppIconStore: ObservableObject {
    static let shared = AppIconStore()
    static let key = "appearance.icon.v1"

    @Published private(set) var current: AppIconChoice
    @Published private(set) var message: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = AppIconChoice(rawValue: defaults.string(forKey: Self.key) ?? "primary") ?? .primary
    }

    /// Called once at launch: makes the system icon match the saved choice.
    @MainActor func reconcile() {
        let installed = UIApplication.shared.alternateIconName
        let wanted = current.alternateName
        guard installed != wanted, UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(wanted) { _ in }
    }

    @MainActor func select(_ choice: AppIconChoice) async {
        guard choice != current else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            message = "This build does not allow changing the icon."
            return
        }
        do {
            try await UIApplication.shared.setAlternateIconName(choice.alternateName)
            current = choice
            defaults.set(choice.rawValue, forKey: Self.key)
            message = "Home screen icon: \(choice.title)"
        } catch {
            message = "The icon could not be changed: \(error.localizedDescription)"
        }
    }

    /// Follows the theme only while the user has never picked an icon by hand.
    @MainActor func followTheme(_ theme: CortexTheme) async {
        guard defaults.bool(forKey: "appearance.icon.followTheme") else { return }
        if let choice = AppIconChoice(rawValue: theme.suggestedIcon) { await select(choice) }
    }
}

/// The picker: the artwork itself, eight across in two rows, with the active one ringed.
struct AppIconSection: View {
    @ObservedObject private var store = AppIconStore.shared
    @AppStorage("appearance.icon.followTheme") private var followTheme = true

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AppIconChoice.allCases) { choice in
                    Button {
                        Task { await store.select(choice) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(choice.asset)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(store.current == choice ? Color.cortexPurple : .secondary.opacity(0.18), lineWidth: store.current == choice ? 2.5 : 1))
                                .overlay(alignment: .bottomTrailing) {
                                    if store.current == choice {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white, Color.cortexPurple)
                                            .offset(x: 3, y: 3)
                                    }
                                }
                            Text(choice.title).font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
                                .foregroundStyle(store.current == choice ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(choice.title) icon")
                    .accessibilityIdentifier("appicon." + choice.rawValue)
                }
            }
            Toggle("Follow the theme", isOn: $followTheme)
                .accessibilityIdentifier("appicon.followTheme")
            Text(store.message ?? "Switching replaces the Home screen icon. If the icon was signed before, the new one appears after the next launch.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
