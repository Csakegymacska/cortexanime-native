import SwiftUI

// MARK: - 8.0 · Studio 8
//
// A profile is a page, not a row of settings. Studio 8 gives the account four
// layouts, four avatar shapes, six rings, six backdrops, a free accent colour,
// tagline, genre chips, social handles, pinned badges and per-field privacy —
// and every one of them is visible in the live preview before it is saved.
//
// Everything here is device-local (UserDefaults), so it works signed out and
// never needs a round trip. The one exception is the accent, which also feeds
// the app-wide tint, so the whole UI follows the chosen colour.

enum ProfileLayout8: String, CaseIterable, Identifiable {
    case classic, poster, compact, cinematic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .poster: return "Poster"
        case .compact: return "Compact"
        case .cinematic: return "Cinematic"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "Banner on top, centred avatar. The layout the app shipped with."
        case .poster: return "Tall banner, the avatar overlaps it like a film poster."
        case .compact: return "No banner. Avatar beside the name, for people who scroll fast."
        case .cinematic: return "Wide banner with the name over the image and the stats underneath."
        }
    }

    var bannerHeight: CGFloat {
        switch self {
        case .classic: return 120
        case .poster: return 178
        case .compact: return 0
        case .cinematic: return 152
        }
    }

    var avatarSize: CGFloat {
        switch self {
        case .classic: return 92
        case .poster: return 108
        case .compact: return 74
        case .cinematic: return 96
        }
    }
}

enum AvatarShape8: String, CaseIterable, Identifiable {
    case circle, squircle, rounded, hexagon
    var id: String { rawValue }

    var title: String {
        switch self {
        case .circle: return "Circle"
        case .squircle: return "Squircle"
        case .rounded: return "Rounded"
        case .hexagon: return "Hexagon"
        }
    }
}

struct AvatarShapeClip8: Shape {
    let shape: AvatarShape8

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .circle:
            return Path(ellipseIn: rect)
        case .squircle:
            return RoundedRectangle(cornerRadius: rect.width * 0.31, style: .continuous).path(in: rect)
        case .rounded:
            return RoundedRectangle(cornerRadius: rect.width * 0.20, style: .continuous).path(in: rect)
        case .hexagon:
            var path = Path()
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            for step in 0..<6 {
                let angle = (Double(step) / 6.0) * 2 * Double.pi - Double.pi / 2
                let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius,
                                    y: centre.y + CGFloat(sin(angle)) * radius)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }
}

enum AvatarRing8: String, CaseIterable, Identifiable {
    case none, pulse, gradient, orbit, neon, frost
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .pulse: return "Pulse"
        case .gradient: return "Gradient"
        case .orbit: return "Orbit"
        case .neon: return "Neon"
        case .frost: return "Frost"
        }
    }
}

enum ProfilePattern8: String, CaseIterable, Identifiable {
    case mesh, grid, dots, waves, stars, solid
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mesh: return "Mesh"
        case .grid: return "Grid"
        case .dots: return "Dots"
        case .waves: return "Waves"
        case .stars: return "Stars"
        case .solid: return "Solid"
        }
    }
}

enum Density8: String, CaseIterable, Identifiable {
    case compact, cosy, roomy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "Compact"
        case .cosy: return "Cosy"
        case .roomy: return "Roomy"
        }
    }
    var spacing: CGFloat {
        switch self {
        case .compact: return 14
        case .cosy: return 20
        case .roomy: return 26
        }
    }
}

/// One place for every 8.0 personalisation value.
@MainActor final class Studio8: ObservableObject {
    static let shared = Studio8()

    @Published var layout: ProfileLayout8 { didSet { save(layout.rawValue, "layout") } }
    @Published var shape: AvatarShape8 { didSet { save(shape.rawValue, "shape") } }
    @Published var ring: AvatarRing8 { didSet { save(ring.rawValue, "ring") } }
    @Published var pattern: ProfilePattern8 { didSet { save(pattern.rawValue, "pattern") } }
    @Published var levelRing: Bool { didSet { save(levelRing, "levelRing") } }
    @Published var accentHex: String { didSet { save(accentHex, "accent") } }
    @Published var tagline: String { didSet { save(tagline, "tagline") } }
    @Published var genres: [String] { didSet { save(genres, "genres") } }
    @Published var discord: String { didSet { save(discord, "discord") } }
    @Published var anilist: String { didSet { save(anilist, "anilist") } }
    @Published var mal: String { didSet { save(mal, "mal") } }
    @Published var pinnedBadges: [String] { didSet { save(pinnedBadges, "badges") } }
    @Published var showPoints: Bool { didSet { save(showPoints, "showPoints") } }
    @Published var showStreak: Bool { didSet { save(showStreak, "showStreak") } }
    @Published var showEpisodes: Bool { didSet { save(showEpisodes, "showEpisodes") } }
    @Published var hideStats: Bool { didSet { save(hideStats, "hideStats") } }
    @Published var hideActivity: Bool { didSet { save(hideActivity, "hideActivity") } }
    @Published var hideCollection: Bool { didSet { save(hideCollection, "hideCollection") } }
    @Published var density: Density8 { didSet { save(density.rawValue, "density") } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = ProfileLayout8(rawValue: defaults.string(forKey: "studio8.layout") ?? "") ?? .classic
        shape = AvatarShape8(rawValue: defaults.string(forKey: "studio8.shape") ?? "") ?? .circle
        ring = AvatarRing8(rawValue: defaults.string(forKey: "studio8.ring") ?? "") ?? .none
        pattern = ProfilePattern8(rawValue: defaults.string(forKey: "studio8.pattern") ?? "") ?? .mesh
        levelRing = defaults.object(forKey: "studio8.levelRing") as? Bool ?? true
        accentHex = defaults.string(forKey: "studio8.accent") ?? ""
        tagline = defaults.string(forKey: "studio8.tagline") ?? ""
        genres = defaults.stringArray(forKey: "studio8.genres") ?? []
        discord = defaults.string(forKey: "studio8.discord") ?? ""
        anilist = defaults.string(forKey: "studio8.anilist") ?? ""
        mal = defaults.string(forKey: "studio8.mal") ?? ""
        pinnedBadges = defaults.stringArray(forKey: "studio8.badges") ?? []
        showPoints = defaults.object(forKey: "studio8.showPoints") as? Bool ?? true
        showStreak = defaults.object(forKey: "studio8.showStreak") as? Bool ?? true
        showEpisodes = defaults.object(forKey: "studio8.showEpisodes") as? Bool ?? true
        hideStats = defaults.object(forKey: "studio8.hideStats") as? Bool ?? false
        hideActivity = defaults.object(forKey: "studio8.hideActivity") as? Bool ?? false
        hideCollection = defaults.object(forKey: "studio8.hideCollection") as? Bool ?? false
        density = Density8(rawValue: defaults.string(forKey: "studio8.density") ?? "") ?? .cosy
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: "studio8." + key)
    }

    /// The chosen accent, or the theme's own colour when the user has not picked one.
    var accent: Color {
        accentHex.isEmpty ? ProfileAccent.color(nil) : ProfileAccent.color(accentHex)
    }

    func toggleGenre(_ genre: String) {
        if let index = genres.firstIndex(of: genre) {
            genres.remove(at: index)
        } else if genres.count < 3 {
            genres.append(genre)
        }
    }

    func toggleBadge(_ id: String) {
        if let index = pinnedBadges.firstIndex(of: id) {
            pinnedBadges.remove(at: index)
        } else if pinnedBadges.count < 4 {
            pinnedBadges.append(id)
        }
    }
}

// MARK: - Backdrop

struct ProfilePatternView8: View {
    let pattern: ProfilePattern8
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            switch pattern {
            case .mesh:
                LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.12), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .solid:
                Color.clear
            case .grid:
                Canvas { context, size in
                    let step: CGFloat = 18
                    var path = Path()
                    var x: CGFloat = 0
                    while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
                    var y: CGFloat = 0
                    while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
                    context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.7)
                }
            case .dots:
                Canvas { context, size in
                    let step: CGFloat = 16
                    var y: CGFloat = 8
                    while y < size.height {
                        var x: CGFloat = 8
                        while x < size.width {
                            let rect = CGRect(x: x, y: y, width: 2, height: 2)
                            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.18)))
                            x += step
                        }
                        y += step
                    }
                }
            case .waves:
                Canvas { context, size in
                    for lane in 0..<4 {
                        var path = Path()
                        let base = size.height * (0.25 + Double(lane) * 0.18)
                        path.move(to: CGPoint(x: 0, y: base))
                        var x: CGFloat = 0
                        while x <= size.width {
                            let y = base + CGFloat(sin(Double(x) / 34 + Double(lane))) * 7
                            path.addLine(to: CGPoint(x: x, y: y))
                            x += 6
                        }
                        context.stroke(path, with: .color(.white.opacity(0.13)), lineWidth: 1.2)
                    }
                }
            case .stars:
                Canvas { context, size in
                    for index in 0..<46 {
                        let fx = CGFloat((index * 73) % 97) / 97
                        let fy = CGFloat((index * 41) % 89) / 89
                        let radius = CGFloat(1 + (index % 3)) * 0.7
                        let rect = CGRect(x: fx * size.width, y: fy * size.height, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(index % 4 == 0 ? 0.55 : 0.22)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Avatar + ring

struct AvatarRing8View: View {
    let ring: AvatarRing8
    let accent: Color
    let size: CGFloat
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch ring {
            case .none:
                EmptyView()
            case .pulse:
                Circle()
                    .stroke(accent.opacity(0.55), lineWidth: 2)
                    .frame(width: size + 12, height: size + 12)
                    .scaleEffect(spin ? 1.06 : 0.96)
                    .opacity(spin ? 0.25 : 0.8)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: spin)
            case .gradient:
                Circle()
                    .stroke(AngularGradient(colors: [accent, accent.opacity(0.25), .white.opacity(0.85), accent],
                                            center: .center), lineWidth: 4)
                    .frame(width: size + 10, height: size + 10)
            case .orbit:
                ZStack {
                    Circle().stroke(accent.opacity(0.28), lineWidth: 1.5)
                        .frame(width: size + 14, height: size + 14)
                    Circle().fill(accent).frame(width: 7, height: 7)
                        .offset(y: -(size + 14) / 2)
                }
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: 7).repeatForever(autoreverses: false), value: spin)
            case .neon:
                Circle().stroke(accent, lineWidth: 3)
                    .frame(width: size + 8, height: size + 8)
                    .shadow(color: accent, radius: 9)
                    .shadow(color: accent.opacity(0.7), radius: 3)
            case .frost:
                Circle().stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .frame(width: size + 11, height: size + 11)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 24).repeatForever(autoreverses: false), value: spin)
            }
        }
        .onAppear { spin = true }
    }
}

struct Studio8Avatar: View {
    let raw: String?
    let decoration: String
    let shape: AvatarShape8
    let ring: AvatarRing8
    let levelRing: Bool
    let progress: Double
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            ZStack {
                NativeAvatar(raw: raw, decoration: decoration)
                    .frame(width: size, height: size)
                    .clipShape(AvatarShapeClip8(shape: shape))
                if levelRing {
                    AvatarShapeClip8(shape: shape)
                        .stroke(accent.opacity(0.9), lineWidth: 3)
                        .frame(width: size, height: size)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, progress)))
                        .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: size + 8, height: size + 8)
                }
            }
            AvatarRing8View(ring: ring, accent: accent, size: size)
        }
        .frame(width: size + 20, height: size + 20)
    }
}

// MARK: - Header

struct ProfileLink8: Identifiable, Hashable {
    var id: String { text }
    let icon: String
    let text: String
}

/// The header NativeProfile renders. Every personalisation value lands here,
/// which is why the studio preview and the real profile can never drift apart.
struct ProfileHeader8: View {
    let name: String
    let avatar: String?
    let banner: String?
    let status: String?
    let accent: Color
    let level: Int
    let progress: Double
    let balance: Int
    let streak: Int
    let episodes: Int
    let badges: [ProfileBadge]
    let signedIn: Bool
    var onSignIn: () -> Void = {}

    @ObservedObject private var studio = Studio8.shared
    @ObservedObject private var store = CreditStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinned: [ProfileBadge] {
        studio.pinnedBadges.compactMap { id in badges.first { $0.id == id } }
    }

    private var links: [ProfileLink8] {
        var rows: [ProfileLink8] = []
        if !studio.discord.isEmpty {
            rows.append(ProfileLink8(icon: "bubble.left.and.bubble.right.fill", text: studio.discord))
        }
        if !studio.anilist.isEmpty {
            rows.append(ProfileLink8(icon: "a.circle.fill", text: "AniList · " + studio.anilist))
        }
        if !studio.mal.isEmpty {
            rows.append(ProfileLink8(icon: "m.circle.fill", text: "MAL · " + studio.mal))
        }
        return rows
    }

    var body: some View {
        Group {
            if studio.layout == .compact {
                compactHeader
            } else {
                bannerHeader
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: studio.layout)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: studio.shape)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: studio.ring)
    }

    // MARK: banner layouts

    private var bannerHeader: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                ZStack {
                    ProfileBanner(raw: banner, height: studio.layout.bannerHeight)
                    ProfilePatternView8(pattern: studio.pattern, accent: accent)
                }
                .frame(height: studio.layout.bannerHeight)
                .clipped()
                .overlay(LinearGradient(colors: [.clear, Color.cortexPanel.opacity(0.92)],
                                        startPoint: .center, endPoint: .bottom))

                if studio.layout == .cinematic {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name).font(.title2.bold()).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if !studio.tagline.isEmpty {
                            Text(studio.tagline).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, studio.layout.bannerHeight * 0.16)
                }

                Studio8Avatar(raw: avatar, decoration: store.equipped == "none" ? "none" : store.equipped,
                              shape: studio.shape, ring: studio.ring, levelRing: studio.levelRing,
                              progress: progress, accent: accent, size: studio.layout.avatarSize)
                    .overlay(alignment: .bottomTrailing) {
                        Text("Level \(level)")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(LinearGradient(colors: [accent, .cyan], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 4, y: 4)
                    }
                    .offset(y: studio.layout.bannerHeight * 0.42)
            }
            .padding(.bottom, studio.layout == .poster ? 58 : 42)

            if studio.layout != .cinematic {
                Text(name).font(.title2.bold())
                if !studio.tagline.isEmpty {
                    Text(studio.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            statusRow
            chips
            statRow
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: compact layout

    private var compactHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Studio8Avatar(raw: avatar, decoration: store.equipped == "none" ? "none" : store.equipped,
                              shape: studio.shape, ring: studio.ring, levelRing: studio.levelRing,
                              progress: progress, accent: accent, size: studio.layout.avatarSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.75)
                    if !studio.tagline.isEmpty {
                        Text(studio.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let status, !status.isEmpty {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 6, height: 6)
                            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            chips
            statRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: pieces

    @ViewBuilder private var statusRow: some View {
        if let status, !status.isEmpty {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var chips: some View {
        if !studio.genres.isEmpty || !links.isEmpty {
            VStack(spacing: 6) {
                if !studio.genres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(studio.genres, id: \.self) { genre in
                            Text(genre.uppercased())
                                .font(.system(size: 9, weight: .black)).tracking(0.8)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(accent.opacity(0.16), in: Capsule())
                                .foregroundStyle(accent)
                        }
                    }
                }
                if !links.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(links) { link in
                            Label(link.text, systemImage: link.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white.opacity(0.07), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var statRow: some View {
        if !studio.hideStats {
            HStack(spacing: 8) {
                if studio.showPoints {
                    Label("\(balance)", systemImage: "star.circle.fill")
                        .font(.system(size: 12, weight: .black))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Color.yellow.opacity(0.18), in: Capsule())
                        .foregroundStyle(.yellow)
                }
                if studio.showStreak && streak > 0 {
                    Label("\(streak) day streak", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .black))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Color.orange.opacity(0.16), in: Capsule())
                        .foregroundStyle(.orange)
                }
                if studio.showEpisodes {
                    Pill(text: "Watched: \(episodes) eps")
                }
            }
        }
        if !pinned.isEmpty {
            HStack(spacing: 8) {
                ForEach(pinned) { badge in
                    Image(systemName: badge.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(accent.opacity(0.14), in: Circle())
                        .accessibilityLabel(badge.name)
                }
            }
        }
        if !signedIn {
            Button("Sign in / Create account") { onSignIn() }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 48)
        }
    }
}

// MARK: - Studio screen

struct Studio8View: View {
    @EnvironmentObject private var api: APIClient
    @ObservedObject private var studio = Studio8.shared
    @ObservedObject private var store = CreditStore.shared
    @Environment(\.dismiss) private var dismiss

    private let genreChoices = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Romance",
                               "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Mystery", "Mecha"]

    private var accent: Color { studio.accent }

    var body: some View {
        List {
            Section {
                ProfileHeader8(name: api.user?.username ?? "Your Cortex Profile",
                               avatar: api.user?.avatar,
                               banner: api.user?.banner,
                               status: api.user?.status,
                               accent: accent,
                               level: store.level,
                               progress: store.levelProgress,
                               balance: store.balance,
                               streak: store.streakDays,
                               episodes: store.episodesCompleted,
                               badges: ProfileBadge.all.filter { store.badgesEarned.contains($0.id) },
                               signedIn: api.signedIn)
                    .padding(.vertical, 6)
            }
            .listRowBackground(Color.cortexPanel)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))

            Section("Layout") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(ProfileLayout8.allCases) { item in
                        Button {
                            studio.layout = item
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [accent.opacity(0.55), Color.cortexPanel],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 46)
                                    .overlay(alignment: item == .compact ? .leading : .center) {
                                        Circle().fill(accent)
                                            .frame(width: item == .compact ? 20 : 26, height: item == .compact ? 20 : 26)
                                            .padding(item == .compact ? 8 : 0)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(studio.layout == item ? accent : .white.opacity(0.10),
                                                lineWidth: studio.layout == item ? 2 : 1))
                                Text(item.title).font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(studio.layout == item ? accent : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studio8.layout." + item.rawValue)
                    }
                }
                .padding(.vertical, 4)
                Text(studio.layout.detail).font(.caption).foregroundStyle(.secondary)
            }

            Section("Avatar") {
                Picker("Shape", selection: $studio.shape) {
                    ForEach(AvatarShape8.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("studio8.shape")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 10) {
                    ForEach(AvatarRing8.allCases) { item in
                        Button { studio.ring = item } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().fill(Color.white.opacity(0.06)).frame(width: 46, height: 46)
                                    AvatarRing8View(ring: item, accent: accent, size: 38)
                                }
                                .frame(width: 58, height: 58)
                                Text(item.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    .foregroundStyle(studio.ring == item ? accent : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studio8.ring." + item.rawValue)
                    }
                }
                Toggle("Level progress ring", isOn: $studio.levelRing)
                    .accessibilityIdentifier("studio8.levelRing")
            }

            Section("Backdrop") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(ProfilePattern8.allCases) { item in
                        Button { studio.pattern = item } label: {
                            VStack(spacing: 5) {
                                ZStack {
                                    LinearGradient(colors: [Color(white: 0.10), Color(white: 0.06)],
                                                   startPoint: .top, endPoint: .bottom)
                                    ProfilePatternView8(pattern: item, accent: accent)
                                }
                                .frame(height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(studio.pattern == item ? accent : .white.opacity(0.10),
                                            lineWidth: studio.pattern == item ? 2 : 1))
                                Text(item.title).font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(studio.pattern == item ? accent : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studio8.pattern." + item.rawValue)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Accent") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                    ForEach(Array(ProfileAccent.all.enumerated()), id: \.offset) { entry in
                        let item = entry.element
                        Button {
                            studio.accentHex = item.hex
                        } label: {
                            Circle()
                                .fill(ProfileAccent.color(item.hex))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: studio.accentHex == item.hex ? 2.5 : 0))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                    }
                }
                TextField("#AE61FA", text: $studio.accentHex)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier("studio8.accentHex")
                Button("Follow the theme colour") { studio.accentHex = "" }
                    .disabled(studio.accentHex.isEmpty)
                Text("An empty field keeps the colour of the current theme. Any hex value tints the whole app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Identity") {
                TextField("Tagline (60 characters)", text: $studio.tagline)
                    .onChange(of: studio.tagline) { value in
                        if value.count > 60 { studio.tagline = String(value.prefix(60)) }
                    }
                    .accessibilityIdentifier("studio8.tagline")
                Text("\(studio.tagline.count)/60").font(.caption2).foregroundStyle(.secondary)

                Text("Favourite genres · up to three").font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(genreChoices, id: \.self) { genre in
                        let on = studio.genres.contains(genre)
                        Button { studio.toggleGenre(genre) } label: {
                            Text(genre).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(on ? accent.opacity(0.20) : Color.white.opacity(0.06), in: Capsule())
                                .foregroundStyle(on ? accent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studio8.genre." + genre)
                    }
                }
            }

            Section("Links") {
                TextField("Discord handle", text: $studio.discord).autocorrectionDisabled()
                TextField("AniList username", text: $studio.anilist).autocorrectionDisabled()
                TextField("MyAnimeList username", text: $studio.mal).autocorrectionDisabled()
                Text("Shown as chips on your header. Nothing is sent anywhere — the app only displays them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pinned badges") {
                let earned = ProfileBadge.all.filter { store.badgesEarned.contains($0.id) }
                if earned.isEmpty {
                    Text("Earn a badge first — then pin up to four here.").font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(earned) { badge in
                            let on = studio.pinnedBadges.contains(badge.id)
                            Button { studio.toggleBadge(badge.id) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: badge.icon).font(.system(size: 11, weight: .bold))
                                    Text(badge.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(on ? accent.opacity(0.20) : Color.white.opacity(0.06), in: Capsule())
                                .foregroundStyle(on ? accent : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("studio8.badge." + badge.id)
                        }
                    }
                }
                Text("\(studio.pinnedBadges.count)/4 pinned").font(.caption2).foregroundStyle(.secondary)
            }

            Section("Stats & privacy") {
                Toggle("Show credits", isOn: $studio.showPoints)
                Toggle("Show streak", isOn: $studio.showStreak)
                Toggle("Show episode count", isOn: $studio.showEpisodes)
                Toggle("Hide the stat cards", isOn: $studio.hideStats)
                Toggle("Hide watch activity", isOn: $studio.hideActivity)
                Toggle("Hide my collection", isOn: $studio.hideCollection)
                Text("Hidden fields stay on this device — nothing is uploaded, so they simply stop being drawn.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Studio8PresetsSection()

            Section("Density") {
                Picker("Card density", selection: $studio.density) {
                    ForEach(Density8.allCases) { item in Text(item.title).tag(item) }
                }
                .pickerStyle(.segmented)
                Text("Compact fits more rows, Roomy adds air between the cards.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Studio 8")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - Presets

/// A saved look: one tap restores layout, shape, ring, backdrop, accent,
/// tagline, genres and density. Three of them are enough for "work", "anime
/// night" and "minimal".
struct StudioPreset8: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var layout: String
    var shape: String
    var ring: String
    var pattern: String
    var accent: String
    var tagline: String
    var genres: [String]
    var density: String
}

@MainActor final class StudioPresetStore8: ObservableObject {
    static let shared = StudioPresetStore8()
    @Published private(set) var presets: [StudioPreset8]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        presets = (defaults.data(forKey: "studio8.presets").flatMap {
            try? JSONDecoder().decode([StudioPreset8].self, from: $0)
        }) ?? []
    }

    func save(named name: String) {
        let studio = Studio8.shared
        let preset = StudioPreset8(name: name.isEmpty ? "Preset \(presets.count + 1)" : name,
                                   layout: studio.layout.rawValue,
                                   shape: studio.shape.rawValue,
                                   ring: studio.ring.rawValue,
                                   pattern: studio.pattern.rawValue,
                                   accent: studio.accentHex,
                                   tagline: studio.tagline,
                                   genres: studio.genres,
                                   density: studio.density.rawValue)
        presets.append(preset)
        persist()
    }

    func apply(_ preset: StudioPreset8) {
        let studio = Studio8.shared
        studio.layout = ProfileLayout8(rawValue: preset.layout) ?? .classic
        studio.shape = AvatarShape8(rawValue: preset.shape) ?? .circle
        studio.ring = AvatarRing8(rawValue: preset.ring) ?? .none
        studio.pattern = ProfilePattern8(rawValue: preset.pattern) ?? .mesh
        studio.accentHex = preset.accent
        studio.tagline = preset.tagline
        studio.genres = preset.genres
        studio.density = Density8(rawValue: preset.density) ?? .cosy
    }

    func delete(_ preset: StudioPreset8) {
        presets.removeAll { $0.id == preset.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: "studio8.presets") }
    }
}

struct Studio8PresetsSection: View {
    @ObservedObject private var store = StudioPresetStore8.shared
    @State private var name = ""

    var body: some View {
        Section("Presets") {
            HStack(spacing: 8) {
                TextField("Preset name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { store.save(named: name); name = "" }
                    .buttonStyle(.bordered)
                    .disabled(store.presets.count >= 6)
            }
            ForEach(store.presets) { preset in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name).font(.subheadline.weight(.semibold))
                        Text("\(preset.layout) · \(preset.shape) · \(preset.ring)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Apply") { store.apply(preset) }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) { store.delete(preset) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(minHeight: 40)
            }
            Text("\(store.presets.count)/6 saved looks. Everything in a preset is stored on this device.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
