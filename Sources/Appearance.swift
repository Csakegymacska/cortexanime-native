import SwiftUI

/// 6.7: the appearance grew from five themes to eight, and the app icon is now part of it.
///
/// Every theme carries three things: the accent, the background and whether the surface is light.
/// The icon choice is separate (see `AppIconChoice`), because iOS only allows whole-icon swaps —
/// so the theme picks a *suggested* icon, and the user can override it any time.
enum CortexTheme: String, CaseIterable, Identifiable {
    case cosmic, midnight, aurora, graphite, daylight, ember, sakura, noir, jade, copper, ice, violet
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cosmic: return "Dark Cosmic"
        case .midnight: return "Midnight Blue"
        case .aurora: return "Aurora"
        case .graphite: return "Graphite"
        case .daylight: return "Solar Light"
        case .ember: return "Ember"
        case .sakura: return "Sakura"
        case .noir: return "Noir"
        case .jade: return "Jade"
        case .copper: return "Copper"
        case .ice: return "Ice"
        case .violet: return "Violet"
        }
    }

    var accent: Color {
        switch self {
        case .cosmic: return Color(red: 0.65, green: 0.51, blue: 1)
        case .midnight: return .blue
        case .aurora: return .mint
        case .graphite: return .orange
        case .daylight: return .indigo
        case .ember: return Color(red: 1.0, green: 0.48, blue: 0.30)
        case .sakura: return Color(red: 1.0, green: 0.48, blue: 0.71)
        case .noir: return Color(white: 0.86)
        case .jade: return Color(red: 0.20, green: 0.83, blue: 0.60)
        case .copper: return Color(red: 0.88, green: 0.54, blue: 0.29)
        case .ice: return Color(red: 0.49, green: 0.83, blue: 0.99)
        case .violet: return Color(red: 0.65, green: 0.55, blue: 0.98)
        }
    }

    var accentDeep: Color {
        switch self {
        case .cosmic: return Color(red: 0.40, green: 0.22, blue: 0.80)
        case .midnight: return Color(red: 0.10, green: 0.30, blue: 0.72)
        case .aurora: return Color(red: 0.10, green: 0.55, blue: 0.48)
        case .graphite: return Color(red: 0.62, green: 0.34, blue: 0.05)
        case .daylight: return Color(red: 0.30, green: 0.28, blue: 0.72)
        case .ember: return Color(red: 0.72, green: 0.22, blue: 0.10)
        case .sakura: return Color(red: 0.72, green: 0.18, blue: 0.44)
        case .noir: return Color(white: 0.38)
        case .jade: return Color(red: 0.05, green: 0.48, blue: 0.38)
        case .copper: return Color(red: 0.54, green: 0.25, blue: 0.07)
        case .ice: return Color(red: 0.10, green: 0.37, blue: 0.55)
        case .violet: return Color(red: 0.36, green: 0.13, blue: 0.71)
        }
    }

    var background: Color {
        switch self {
        case .cosmic: return Color(red: 0.035, green: 0.025, blue: 0.09)
        case .midnight: return Color(red: 0.025, green: 0.055, blue: 0.11)
        case .aurora: return Color(red: 0.02, green: 0.07, blue: 0.065)
        case .graphite: return Color(red: 0.07, green: 0.07, blue: 0.075)
        case .daylight: return Color(red: 0.97, green: 0.96, blue: 0.93)
        case .ember: return Color(red: 0.08, green: 0.035, blue: 0.03)
        case .sakura: return Color(red: 0.08, green: 0.03, blue: 0.06)
        case .noir: return Color(red: 0.045, green: 0.045, blue: 0.05)
        case .jade: return Color(red: 0.02, green: 0.07, blue: 0.055)
        case .copper: return Color(red: 0.075, green: 0.035, blue: 0.02)
        case .ice: return Color(red: 0.02, green: 0.045, blue: 0.07)
        case .violet: return Color(red: 0.04, green: 0.02, blue: 0.08)
        }
    }

    var secondary: Color {
        switch self {
        case .cosmic: return .pink
        case .midnight: return .cyan
        case .aurora: return .teal
        case .graphite: return .yellow
        case .daylight: return .pink
        case .ember: return Color(red: 1.0, green: 0.78, blue: 0.35)
        case .sakura: return Color(red: 0.62, green: 0.72, blue: 1.0)
        case .noir: return Color(white: 0.55)
        case .jade: return Color(red: 0.64, green: 0.90, blue: 0.21)
        case .copper: return Color(red: 1.00, green: 0.82, blue: 0.60)
        case .ice: return Color(red: 0.78, green: 0.91, blue: 1.00)
        case .violet: return Color(red: 0.94, green: 0.67, blue: 0.99)
        }
    }

    var light: Bool { self == .daylight }

    /// Which icon ships with this theme when the user has not picked one.
    var suggestedIcon: String {
        switch self {
        case .cosmic: return "primary"
        case .midnight: return "midnight"
        case .aurora: return "aurora"
        case .graphite: return "graphite"
        case .daylight: return "daylight"
        case .ember: return "ember"
        case .sakura: return "sakura"
        case .noir: return "noir"
        case .jade: return "aurora"
        case .copper: return "ember"
        case .ice: return "midnight"
        case .violet: return "primary"
        }
    }
}

/// The three mesh stops used behind the app. Kept here so the backdrop and the
/// theme picker swatches show the same colours.
extension CortexTheme {
    var mesh: [Color] { [background, accent.opacity(0.55), secondary.opacity(0.35), background] }
    var swatch: LinearGradient {
        LinearGradient(colors: [accent, secondary.opacity(0.85), background], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case theme, system, dark, light
    var id: String { rawValue }
    var name: String { switch self { case .theme: return "Match theme"; case .system: return "System"; case .dark: return "Dark"; case .light: return "Light" } }
}

/// The live mesh background (iOS 18+). Below that the gradient fallback is used, which is
/// why the app still looks right on older devices.
struct CortexMesh: View {
    @AppStorage("appearance.theme") private var theme = CortexTheme.cosmic.rawValue
    @AppStorage("motion.reduce.v1") private var reduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduce
    @Environment(\.colorScheme) private var scheme

    private var selected: CortexTheme { CortexTheme(rawValue: theme) ?? .cosmic }
    private var still: Bool { reduceMotion || systemReduce }

    var body: some View {
        GeometryReader { geo in
            let base = scheme == .light ? Color(.systemBackground) : selected.background
            ZStack {
                base
                if #available(iOS 18.0, *), !still {
                    TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: false)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        MeshGradient(
                            width: 3, height: 3,
                            points: meshPoints(t),
                            colors: [selected.mesh[0], selected.mesh[1].opacity(scheme == .light ? 0.35 : 0.55), selected.mesh[0],
                                     selected.mesh[2].opacity(scheme == .light ? 0.25 : 0.40), selected.mesh[0], selected.mesh[3],
                                     selected.mesh[0], selected.mesh[1].opacity(scheme == .light ? 0.20 : 0.30), selected.mesh[0]]
                        )
                        .animation(.linear(duration: 0.2), value: t)
                    }
                } else {
                    LinearGradient(colors: [selected.accent.opacity(scheme == .light ? 0.10 : 0.20), base, base],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }

    private func meshPoints(_ t: TimeInterval) -> [SIMD2<Float>] {
        let a = Float(sin(t / 9.0)) * 0.08, b = Float(cos(t / 11.0)) * 0.08, c = Float(sin(t / 7.0)) * 0.06
        return [SIMD2(0, 0), SIMD2(0.5 + a, 0), SIMD2(1, 0),
                SIMD2(0, 0.5 + b), SIMD2(0.5, 0.5 + c), SIMD2(1, 0.5 - b),
                SIMD2(0, 1), SIMD2(0.5 - a, 1), SIMD2(1, 1)]
    }
}

struct CortexAppearance: ViewModifier {
    @AppStorage("appearance.theme") private var theme = CortexTheme.cosmic.rawValue
    @AppStorage("appearance.mode") private var mode = DisplayMode.theme.rawValue
    private var selected: CortexTheme { CortexTheme(rawValue: theme) ?? .cosmic }
    private var chosenMode: DisplayMode { DisplayMode(rawValue: mode) ?? .theme }

    func body(content: Content) -> some View {
        content
            .tint(selected.accent)
            .preferredColorScheme(chosenMode == .system ? nil : chosenMode == .light ? .light : chosenMode == .dark ? .dark : selected.light ? .light : .dark)
            .background { CortexMesh() }
    }
}

/// Profile → appearance. Eight swatches in two rows, the display mode, the icon picker
/// and the motion switches, all in one card so nothing hides under another screen.
struct AppearanceSection: View {
    @AppStorage("appearance.theme") private var theme = CortexTheme.cosmic.rawValue
    @AppStorage("appearance.mode") private var mode = DisplayMode.theme.rawValue
    @AppStorage("motion.reduce.v1") private var reduceMotion = false
    @ObservedObject private var motion = MotionSettings.shared
    @Environment(\.accessibilityReduceMotion) private var systemReduce

    private var selected: CortexTheme { CortexTheme(rawValue: theme) ?? .cosmic }

    var body: some View {
        Section("Appearance") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(CortexTheme.allCases) { item in
                    Button {
                        theme = item.rawValue
                        mode = DisplayMode.theme.rawValue
                        Task { await AppIconStore.shared.followTheme(item) }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(item.swatch)
                                .frame(height: 46)
                                .overlay(alignment: .topTrailing) {
                                    if theme == item.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(.white, item.accent)
                                            .padding(4)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme == item.rawValue ? item.accent : .secondary.opacity(0.18), lineWidth: theme == item.rawValue ? 2 : 1))
                            Text(item.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                .foregroundStyle(theme == item.rawValue ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityIdentifier("theme.swatch." + item.rawValue)
                }
            }.padding(.vertical, 4)

            Picker("Display mode", selection: $mode) {
                ForEach(DisplayMode.allCases) { Text($0.name).tag($0.rawValue) }
            }
            .accessibilityIdentifier("appearance.mode")

            Toggle("Reduce motion", isOn: $reduceMotion)
                .accessibilityIdentifier("appearance.reduceMotion")
            Toggle("Card tilt on press", isOn: Binding(get: { motion.cardTilt }, set: { motion.cardTilt = $0 }))
                .accessibilityIdentifier("appearance.cardTilt")
            Text(systemReduce ? "The system Reduce Motion setting is on, so every animation is already still." :
                    "Reduce motion stops the background mesh, the spotlight drift and the card tilt at once.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section("App icon") {
            AppIconSection()
        }
    }
}

/// The fallback backdrop used by older screens that want a plain gradient.
struct CortexBackdrop: View {
    @AppStorage("appearance.theme") private var theme = CortexTheme.cosmic.rawValue
    @Environment(\.colorScheme) private var scheme
    private var selected: CortexTheme { CortexTheme(rawValue: theme) ?? .cosmic }
    var body: some View {
        ZStack {
            scheme == .light ? Color(.systemBackground) : selected == .daylight ? CortexTheme.midnight.background : selected.background
            LinearGradient(colors: [selected.accent.opacity(scheme == .light ? 0.06 : 0.13), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }.ignoresSafeArea()
    }
}
