import SwiftUI
import PhotosUI
import UIKit

// MARK: - 7.1: the profile, made personal
//
// Two things were missing from the profile compared to Discord: a background that belongs to you
// and a line that says what you are doing right now. Both are stored on the server (the `banner`
// field already existed, `status` and `accent` were added with this build), so friends see the
// same card.

/// Ready-made banner backgrounds. A preset is stored as `preset:<id>` in the `banner` field, so it
/// travels through the same column as an uploaded image and needs no extra endpoint.
struct BannerPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [Color]
    var animation: BannerAnimation? = nil
    var isAnimated: Bool { animation != nil }

    static let all: [BannerPreset] = [
        BannerPreset(id: "cosmic", name: "Cosmic", colors: [Color(red: 0.42, green: 0.20, blue: 0.78), Color(red: 0.10, green: 0.12, blue: 0.30)]),
        BannerPreset(id: "aurora", name: "Aurora", colors: [Color(red: 0.15, green: 0.85, blue: 0.72), Color(red: 0.32, green: 0.24, blue: 0.80)]),
        BannerPreset(id: "ember", name: "Ember", colors: [Color(red: 1.00, green: 0.48, blue: 0.28), Color(red: 0.42, green: 0.06, blue: 0.16)]),
        BannerPreset(id: "sakura", name: "Sakura", colors: [Color(red: 1.00, green: 0.48, blue: 0.71), Color(red: 0.35, green: 0.16, blue: 0.52)]),
        BannerPreset(id: "midnight", name: "Midnight", colors: [Color(red: 0.13, green: 0.26, blue: 0.62), Color(red: 0.03, green: 0.05, blue: 0.16)]),
        BannerPreset(id: "mint", name: "Mint", colors: [Color(red: 0.36, green: 0.94, blue: 0.68), Color(red: 0.05, green: 0.32, blue: 0.34)]),
        BannerPreset(id: "sunset", name: "Sunset", colors: [Color(red: 1.00, green: 0.62, blue: 0.32), Color(red: 0.72, green: 0.18, blue: 0.44)]),
        BannerPreset(id: "noir", name: "Noir", colors: [Color(white: 0.30), Color(white: 0.05)]),
        // 7.3: banners that move. Same `preset:<id>` column, no server change.
        BannerPreset(id: "stars", name: "Starfield", colors: [Color(red: 0.05, green: 0.07, blue: 0.20), Color(red: 0.02, green: 0.02, blue: 0.06)], animation: .stars),
        BannerPreset(id: "flow", name: "Aurora Flow", colors: [Color(red: 0.10, green: 0.55, blue: 0.55), Color(red: 0.28, green: 0.16, blue: 0.62)], animation: .aurora),
        BannerPreset(id: "drift", name: "Sakura Drift", colors: [Color(red: 0.62, green: 0.24, blue: 0.44), Color(red: 0.24, green: 0.10, blue: 0.32)], animation: .petals),
        BannerPreset(id: "tide", name: "Tide", colors: [Color(red: 0.05, green: 0.34, blue: 0.48), Color(red: 0.02, green: 0.10, blue: 0.22)], animation: .waves),
        BannerPreset(id: "emberwave", name: "Ember Wave", colors: [Color(red: 0.45, green: 0.12, blue: 0.06), Color(red: 0.14, green: 0.03, blue: 0.05)], animation: .embers),
        BannerPreset(id: "grid", name: "Neon Grid", colors: [Color(red: 0.24, green: 0.05, blue: 0.34), Color(red: 0.02, green: 0.16, blue: 0.24)], animation: .neon),
        BannerPreset(id: "comet", name: "Comet", colors: [Color(red: 0.10, green: 0.12, blue: 0.36), Color(red: 0.02, green: 0.03, blue: 0.10)], animation: .comet),
        BannerPreset(id: "frost", name: "Frost", colors: [Color(red: 0.30, green: 0.45, blue: 0.62), Color(red: 0.08, green: 0.14, blue: 0.24)], animation: .frost),
    ]

    static func named(_ raw: String?) -> BannerPreset? {
        guard let raw, raw.hasPrefix("preset:") else { return nil }
        let id = String(raw.dropFirst("preset:".count))
        return all.first { $0.id == id }
    }
}

/// Banner rendering shared by the profile, the public profile and the studio preview.
struct ProfileBanner: View {
    let raw: String?
    var height: CGFloat = 130

    var body: some View {
        Group {
            if let preset = BannerPreset.named(raw) {
                if preset.isAnimated {
                    AnimatedBanner(preset: preset)
                } else {
                    LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(alignment: .topTrailing) { sparkleField }
                }
            } else if let url = Anime.imageURL(raw) {
                AnimeArtwork(url: url)
            } else {
                LinearGradient(colors: [Color.cortexPurple.opacity(0.55), Color.cortexPanel],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .topTrailing) { sparkleField }
            }
        }
        .frame(height: height)
        .clipped()
    }

    private var sparkleField: some View {
        GeometryReader { geo in
            ForEach(0..<12, id: \.self) { i in
                Circle().fill(.white.opacity(0.12))
                    .frame(width: CGFloat(4 + (i * 5) % 18))
                    .offset(x: geo.size.width * CGFloat((i * 31) % 100) / 100.0 - 20,
                            y: geo.size.height * CGFloat((i * 47) % 100) / 100.0)
            }
        }
    }
}

enum ProfileAccent {
    static let all: [(name: String, hex: String)] = [
        ("Purple", "#AE61FA"), ("Cyan", "#4CD6F5"), ("Mint", "#4CE7A8"), ("Rose", "#FF7AB6"),
        ("Amber", "#FFC45C"), ("Ice", "#9BD1FF"), ("Lime", "#B8F55C"), ("Coral", "#FF8A6A"),
    ]

    static func color(_ hex: String?) -> Color {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            return Color.cortexPurple
        }
        return Color(red: Double((value >> 16) & 0xFF) / 255.0,
                     green: Double((value >> 8) & 0xFF) / 255.0,
                     blue: Double(value & 0xFF) / 255.0)
    }
}

/// The card as friends see it — the studio edits a live copy of this.
struct ProfileCard: View {
    let name: String
    let avatar: String?
    let banner: String?
    let status: String?
    let bio: String?
    let decoration: String
    let accent: Color
    var friends: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileBanner(raw: banner, height: 108)
                .overlay(alignment: .bottomLeading) {
                    NativeAvatar(raw: avatar, decoration: decoration)
                        .frame(width: 74, height: 74)
                        .padding(.leading, 14)
                        .offset(y: 34)
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(name).font(.title3.bold()).foregroundStyle(.white)
                    if let friends { Pill(text: "\(friends) friends", color: accent) }
                    Spacer()
                }
                if let status, !status.isEmpty {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 7, height: 7)
                        Text(status).font(.caption).foregroundStyle(.white.opacity(0.82)).lineLimit(2)
                    }
                }
                if let bio, !bio.isEmpty {
                    Text(bio).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 42)
            .padding(.bottom, 14)
        }
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(accent.opacity(0.35), lineWidth: 1))
    }
}

/// Profile → Customise. Everything on one screen, with the card updating as you type.
struct NativeProfileStudio: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var bio = ""
    @State private var status = ""
    @State private var banner = ""
    @State private var accent = "#AE61FA"
    @State private var decoration = "none"
    @State private var picked: PhotosPickerItem?
    @State private var decorationSheet = false
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?

    private var accentColor: Color { ProfileAccent.color(accent) }

    private var trimmedStatus: String { String(status.prefix(80)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileCard(name: name.isEmpty ? "Your name" : name,
                            avatar: api.user?.avatar,
                            banner: banner,
                            status: trimmedStatus,
                            bio: bio,
                            decoration: decoration,
                            accent: accentColor)

                section("Status") {
                    TextField("What are you up to?", text: $status, axis: .vertical)
                        .lineLimit(1...2)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        ForEach(["Watching anime", "Looking for recs", "Rewatching a favourite"], id: \.self) { line in
                            Button(line) { status = line }
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10).frame(minHeight: 30)
                                .background(accentColor.opacity(0.16), in: Capsule())
                                .foregroundStyle(accentColor)
                                .buttonStyle(.plain)
                        }
                    }
                    Text("\(trimmedStatus.count)/80").font(.caption2).foregroundStyle(.secondary)
                }

                section("Banner") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                        ForEach(BannerPreset.all) { preset in
                            let selected = banner == "preset:\(preset.id)"
                            Button {
                                banner = "preset:\(preset.id)"
                            } label: {
                                VStack(spacing: 5) {
                                    Group {
                                        if preset.isAnimated {
                                            AnimatedBanner(preset: preset)
                                        } else {
                                            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                        }
                                    }
                                    .frame(height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(selected ? Color.white : .white.opacity(0.12), lineWidth: selected ? 2 : 1))
                                    .overlay(alignment: .topTrailing) {
                                        if preset.isAnimated {
                                            Text("LIVE")
                                                .font(.system(size: 7, weight: .black)).tracking(0.6)
                                                .padding(.horizontal, 4).padding(.vertical, 2)
                                                .background(Color.cortexPurple, in: Capsule())
                                                .foregroundStyle(.black)
                                                .padding(3)
                                        }
                                    }
                                    Text(preset.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("studio.banner." + preset.id)
                        }
                    }
                    HStack(spacing: 10) {
                        PhotosPicker("Choose a photo", selection: $picked, matching: .images)
                            .font(.system(size: 13, weight: .semibold))
                        if !banner.isEmpty && !banner.hasPrefix("preset:") {
                            Button("Remove photo", role: .destructive) { banner = "" }
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .frame(minHeight: 40)
                }

                section("Accent") {
                    HStack(spacing: 10) {
                        ForEach(ProfileAccent.all, id: \.hex) { item in
                            Button {
                                accent = item.hex
                            } label: {
                                Circle().fill(ProfileAccent.color(item.hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(.white, lineWidth: accent == item.hex ? 2 : 0))
                                    .overlay(alignment: .center) {
                                        if accent == item.hex {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(.black.opacity(0.7))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                        }
                        Spacer()
                    }
                }

                section("About me") {
                    TextField("A line about your taste (up to 300 characters)", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    Text("\(bio.count)/300").font(.caption2).foregroundStyle(.secondary)
                }

                section("Avatar decoration") {
                    Button { decorationSheet = true } label: {
                        HStack(spacing: 12) {
                            NativeAvatar(raw: nil, decoration: decoration, animated: false)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(decoration == "none" ? "No decoration" : "Decorated").font(.subheadline.bold())
                                Text("Free and paid picks, two layers").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let error { ErrorNotice(text: error) }
                if let message {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                }

                Button {
                    Task { await save() }
                } label: {
                    HStack { Spacer(); Text(busy ? "Saving…" : "Save profile").font(.subheadline.bold()); Spacer() }
                        .frame(minHeight: 48)
                        .background(accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(busy || bio.count > 300)
                .accessibilityIdentifier("studio.save")
            }
            .padding(16)
        }
        .background(Color.cortexBlack)
        .navigationTitle("Customise profile")
        .sheet(isPresented: $decorationSheet) {
            NavigationStack { NativeDecorations(selected: $decoration) }
        }
        .task {
            name = api.user?.username ?? ""
            bio = api.user?.bio ?? ""
            status = api.user?.status ?? ""
            banner = api.user?.banner ?? ""
            accent = api.user?.accent ?? "#AE61FA"
            decoration = api.user?.decoration ?? CreditStore.shared.equipped
        }
        .onChange(of: picked) { _, item in
            Task { await loadBanner(item) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 10, weight: .black)).tracking(1.6).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadBanner(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let width: CGFloat = 1280
        let scale = min(1, width / max(image.size.width, 1))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let shrunk = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard var payload = shrunk.jpegData(compressionQuality: 0.7) else { return }
        var quality: CGFloat = 0.7
        while payload.count > 520_000, quality > 0.25 {
            quality -= 0.15
            guard let smaller = shrunk.jpegData(compressionQuality: quality) else { break }
            payload = smaller
        }
        banner = "data:image/jpeg;base64," + payload.base64EncodedString()
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.json("/api/user/profile", method: "PATCH", body: [
                "username": name.trimmingCharacters(in: .whitespacesAndNewlines),
                "bio": bio,
                "banner": banner,
                "decoration": decoration,
                "status": trimmedStatus,
                "accent": accent,
            ])
            CreditStore.shared.equip(decoration)
            await api.refreshAccount()
            message = "Profile saved."
            error = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - 7.3: animated banners
//
// A banner used to be either a still gradient or a photo. These presets draw themselves: stars
// drift, petals fall, waves roll. Everything is a Canvas on a 24 fps clock, so it costs one small
// layer, keeps working offline, and stops dead when Reduce Motion is on (the still gradient stays).

enum BannerAnimation: String, Hashable {
    case stars, aurora, petals, waves, embers, neon, comet, frost
}

struct AnimatedBanner: View {
    let preset: BannerPreset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var still: Bool { reduceMotion }

    var body: some View {
        ZStack {
            LinearGradient(colors: preset.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if still {
                Canvas { context, size in paint(&context, size: size, t: 12) }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in paint(&context, size: size, t: t) }
                }
            }
        }
        .clipped()
        .accessibilityLabel(preset.name + " animated banner")
    }

    /// All eight effects share one canvas: a handful of primitives, no images.
    private func paint(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let w = Double(size.width), h = Double(size.height)
        guard w > 1, h > 1, let kind = preset.animation else { return }
        switch kind {
        case .stars:
            for i in 0..<42 {
                let seed = Double(i)
                let x = (seed * 37.0).truncatingRemainder(dividingBy: 100) / 100 * w
                let drift = (seed * 53.0).truncatingRemainder(dividingBy: 100) / 100 * h
                let speed = 3 + (seed * 7.0).truncatingRemainder(dividingBy: 9)
                let y = (drift + t * speed).truncatingRemainder(dividingBy: h)
                let alpha = 0.20 + 0.55 * abs(sin(t * 0.7 + seed))
                let r = 0.8 + (seed * 3.0).truncatingRemainder(dividingBy: 3) * 0.7
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
            }
        case .aurora:
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 26))
                for i in 0..<3 {
                    let phase = t * (0.18 + 0.09 * Double(i)) + Double(i) * 2.1
                    let cx = w * (0.28 + 0.22 * sin(phase))
                    let cy = h * (0.38 + 0.26 * cos(phase * 1.3))
                    let rect = CGRect(x: cx - w * 0.45, y: cy - h * 0.45, width: w * 0.9, height: h * 0.9)
                    layer.fill(Path(ellipseIn: rect),
                               with: .color((i == 1 ? Color.mint : Color.cortexPurple).opacity(0.35)))
                }
            }
        case .petals:
            for i in 0..<16 {
                let seed = Double(i)
                let x = ((seed * 61.0).truncatingRemainder(dividingBy: 100) / 100 * w + sin(t * 0.6 + seed) * 14)
                let y = ((seed * 29.0).truncatingRemainder(dividingBy: 100) / 100 * h + t * (9 + seed.truncatingRemainder(dividingBy: 5))) .truncatingRemainder(dividingBy: h)
                let size = 3.2 + seed.truncatingRemainder(dividingBy: 3) * 1.6
                context.drawLayer { layer in
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(t * 40 + seed * 24))
                    layer.fill(Path(ellipseIn: CGRect(x: -size / 2, y: -size / 3, width: size, height: size * 0.66)),
                               with: .color(Color(red: 1, green: 0.72, blue: 0.85).opacity(0.75)))
                }
            }
        case .waves:
            for i in 0..<4 {
                var path = Path()
                let amp = h * (0.05 + 0.02 * Double(i))
                let base = h * (0.55 + 0.13 * Double(i))
                let speed = 0.5 + 0.18 * Double(i)
                path.move(to: CGPoint(x: 0, y: base))
                var x: Double = 0
                while x <= w {
                    let y = base + sin(x / w * 6.0 + t * speed + Double(i)) * amp
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 4
                }
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
                context.fill(path, with: .color(Color.cyan.opacity(0.10 + 0.05 * Double(i))))
            }
        case .embers:
            for i in 0..<24 {
                let seed = Double(i)
                let x = (seed * 43.0).truncatingRemainder(dividingBy: 100) / 100 * w
                let rise = ((seed * 17.0).truncatingRemainder(dividingBy: 100) / 100 * h + t * (7 + seed.truncatingRemainder(dividingBy: 6)))
                let y = h - rise.truncatingRemainder(dividingBy: h)
                let r = 1.2 + seed.truncatingRemainder(dividingBy: 3) * 0.9
                let alpha = 0.35 + 0.4 * abs(sin(t * 1.4 + seed))
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                             with: .color(Color.orange.opacity(alpha)))
            }
        case .neon:
            let step = 26.0
            let slideX = (t * 14).truncatingRemainder(dividingBy: step)
            let slideY = (t * 9).truncatingRemainder(dividingBy: step)
            var x = -step + slideX
            while x < w { context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: h)) },
                                         with: .color(Color(red: 1, green: 0.36, blue: 0.86).opacity(0.16)), lineWidth: 1); x += step }
            var y = -step + slideY
            while y < h { context.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: w, y: y)) },
                                         with: .color(Color.cyan.opacity(0.14)), lineWidth: 1); y += step }
        case .comet:
            let cycle = 4.0
            let progress = (t.truncatingRemainder(dividingBy: cycle)) / cycle
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 1.6))
                for i in 0..<14 {
                    let lag = Double(i) * 0.022
                    let p = progress - lag
                    guard p > 0, p < 1 else { continue }
                    let x = p * (w + 120) - 60
                    let y = h * 0.22 + p * h * 0.42
                    let r = 2.6 - Double(i) * 0.14
                    guard r > 0 else { continue }
                    layer.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                               with: .color(.white.opacity(0.55 - Double(i) * 0.03)))
                }
            }
        case .frost:
            for i in 0..<20 {
                let seed = Double(i)
                let x = (seed * 71.0).truncatingRemainder(dividingBy: 100) / 100 * w
                let y = (seed * 31.0).truncatingRemainder(dividingBy: 100) / 100 * h
                let s = 2.5 + seed.truncatingRemainder(dividingBy: 4) * 1.4
                let alpha = 0.18 + 0.42 * abs(sin(t * 0.9 + seed * 0.7))
                context.drawLayer { layer in
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(45))
                    layer.fill(Path(CGRect(x: -s / 2, y: -s / 2, width: s, height: s)),
                               with: .color(.white.opacity(alpha)))
                }
            }
        }
    }
}
