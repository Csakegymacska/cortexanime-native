import SwiftUI

// MARK: - iOS 26 visual layer
//
// 6.0 targets iOS 26 and later, so the app can finally use the new system look instead of
// painting its own opaque panels. Everything here degrades to a plain material on the off
// chance the SDK in use does not expose the glass modifier.

/// Liquid glass surface with a soft tint. Used for the cards the viewer actually touches
/// (quick actions, the notification settings, the subtitle radar rows).
struct CortexGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 26
    var tint: Color = .clear
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 26, tint: Color = .clear, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cortexGlassSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

extension View {
    /// One place for the glass look, so a future SDK change is a single edit.
    @ViewBuilder func cortexGlassSurface(cornerRadius: CGFloat = 26, tint: Color = .clear, stroke: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // A `.glassEffect` szimbólum csak a 26-os SDK-ban létezik: régebbi SDK-val
        // (COMPAT_SDK) kizárólag a tömör anyag fordul, így a virtuális Macen is épül.
        #if !COMPAT_SDK
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay(shape.stroke(stroke ?? Color.white.opacity(0.10), lineWidth: 1))
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(stroke ?? Color.white.opacity(0.10), lineWidth: 1))
        }
        #else
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(stroke ?? Color.white.opacity(0.10), lineWidth: 1))
        #endif
    }
}

/// Animated mesh backdrop used behind the home hero and the settings header. `MeshGradient`
/// is a system view, so it costs no assets and no downloads.
struct CortexMeshBackdrop: View {
    var accent: Color = Color.cortexPurple
    var secondary: Color = Color(red: 0.16, green: 0.72, blue: 0.86)
    /// Animation is opt-in: the home screen keeps a still gradient so the backdrop never
    /// keeps the GPU awake (the same heat rule as the watch guard).
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Explicit types: an inline array of bare numbers leaves `MeshGradient` ambiguous and
    /// the compiler reports it against the enclosing view instead.
    private static func points(wave: Float) -> [SIMD2<Float>] {
        [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0.05), SIMD2<Float>(1, 0),
            SIMD2<Float>(0.05, 0.5), SIMD2<Float>(0.5, 0.35 + 0.25 * wave), SIMD2<Float>(0.95, 0.45),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.55, 0.92), SIMD2<Float>(1, 1),
        ]
    }

    private func gradient(wave: Float) -> some View {
        MeshGradient(width: 3, height: 3, points: Self.points(wave: wave), colors: [
            .cortexBlack, accent.opacity(0.62), .cortexBlack,
            accent.opacity(0.34), secondary.opacity(0.36), accent.opacity(0.26),
            .cortexBlack, accent.opacity(0.46), .cortexBlack,
        ])
        .overlay(LinearGradient(colors: [.clear, Color.cortexBlack.opacity(0.72)], startPoint: .top, endPoint: .bottom))
        .accessibilityHidden(true)
    }

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
                gradient(wave: Float((sin(timeline.date.timeIntervalSince1970 / 6) + 1) / 2))
            }
        } else {
            gradient(wave: 0.45)
        }
    }
}

/// The visible 6.1 entry point on Home: a glass banner with a live mesh backdrop that shows
/// the newest subtitle in either language and leads to the radar and its notification settings.
struct SubtitleRadarBanner: View {
    let drop: SubtitleDrop?
    let counts: (hu: Int, en: Int)
    let settingsSummary: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = MotionSettings.shared

    private var countsLabel: some View {
        Text("\(counts.hu) HU · \(counts.en) EN · 7 days")
            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    @ViewBuilder private func openRadarButton(compact: Bool) -> some View {
        NavigationLink { NativeSubtitleRadar() } label: {
            HStack(spacing: 5) {
                if compact { Image(systemName: "chevron.right.circle").font(.system(size: 12, weight: .black)) }
                if !compact { Text("Open radar").font(.system(size: 11, weight: .black)).lineLimit(1) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.white.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open subtitle radar")
        .accessibilityIdentifier("home.radar.open")
    }

    @ViewBuilder private func alertsButton(compact: Bool) -> some View {
        NavigationLink { NativeNotificationSettings() } label: {
            HStack(spacing: 5) {
                if compact { Image(systemName: settingsSummary == "Alerts on" ? "bell.fill" : "bell.slash").font(.system(size: 12, weight: .black)) }
                if !compact { Text(settingsSummary).font(.system(size: 11, weight: .black)).lineLimit(1) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.white, in: Capsule()).foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settingsSummary)
        .accessibilityIdentifier("home.radar.alerts")
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CortexMeshBackdrop(accent: drop?.language.color ?? Color.cortexPurple)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "captions.bubble.fill").font(.system(size: 11, weight: .black))
                    Text("SUBTITLE RADAR").font(.system(size: 10, weight: .black)).tracking(1.4)
                    Spacer(minLength: 0)
                    if let drop { SubtitleLanguageBadge(language: drop.language) }
                }
                .foregroundStyle(.white.opacity(0.85))
                if let drop {
                    HStack(spacing: 12) {
                        AnimeArtwork(url: drop.cover)
                            .frame(width: 54, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(drop.title).font(.system(size: 15, weight: .black)).lineLimit(2)
                            Text("Episode \(drop.episode) · \(drop.ageText)")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Hungarian and English subtitles in one place.")
                        .font(.system(size: 15, weight: .black)).lineLimit(2)
                }
                // 6.4: on a narrow column (unfolded foldable in a small window, or the wide-phone
                // rail taking 74 pt) the two pills used to wrap into two lines each. ViewThatFits
                // drops the secondary label first, then both labels, instead of breaking the words.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        countsLabel
                        Spacer(minLength: 0)
                        openRadarButton(compact: false)
                        alertsButton(compact: false)
                    }
                    HStack(spacing: 8) {
                        countsLabel
                        Spacer(minLength: 0)
                        openRadarButton(compact: true)
                        alertsButton(compact: true)
                    }
                    HStack(spacing: 8) {
                        openRadarButton(compact: true)
                        alertsButton(compact: true)
                    }
                }
            }
            .padding(16)
        }
        .frame(minHeight: 176)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .foregroundStyle(.white)
        // 6.3: the free-drag tilt on a full-width card read as wobbling, so it is gone. What is left
        // is a depth cue that cannot fight the scroll: the card recedes slightly as it scrolls away.
        .scrollTransition(.interactive, axis: .vertical) { card, phase in
            card
                .scaleEffect((reduceMotion || !motion.cardTilt) ? 1 : 1 - CGFloat(min(1, abs(phase.value))) * 0.035)
                .opacity((reduceMotion || !motion.cardTilt) ? 1 : 1 - min(1, abs(phase.value)) * 0.25)
        }
    }
}

/// Small language badge shared by the shelves, the radar rows and the settings screen.
struct SubtitleLanguageBadge: View {
    let language: SubtitleLanguage
    var verbose: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: language.symbol).font(.system(size: 8, weight: .black))
            Text(verbose ? language.name : language.badge)
                .font(.system(size: 9, weight: .black))
                .tracking(0.4)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(language.color)
        .background(language.color.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(language.color.opacity(0.34), lineWidth: 1))
        .accessibilityLabel(language.name + " subtitle")
    }
}

/// The one row used by the subtitle radar in the app and by its settings preview.
struct SubtitleDropRow: View {
    let drop: SubtitleDrop
    var showsArtwork: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            if showsArtwork {
                AnimeArtwork(url: drop.cover)
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(drop.title).font(.system(size: 13, weight: .bold)).lineLimit(2)
                HStack(spacing: 6) {
                    SubtitleLanguageBadge(language: drop.language)
                    Text(drop.episodeText).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    Text("·").foregroundStyle(.white.opacity(0.3))
                    Text(drop.ageText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("subtitle.row.\(drop.id)")
    }
}

/// Horizontal shelf of the newest drops for the given languages.
struct SubtitleDropShelf: View {
    let title: String
    let drops: [SubtitleDrop]
    var limit: Int = 14
    var trailing: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                SectionHeading(title: title)
                if let trailing { Pill(text: trailing) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(drops.prefix(limit)) { drop in
                        NavigationLink {
                            NativeLinkedDetail(id: drop.animeID)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                AnimeArtwork(url: drop.cover)
                                    .frame(width: 132, height: 186)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(alignment: .topLeading) {
                                        SubtitleLanguageBadge(language: drop.language).padding(7)
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        Text("EP \(drop.episode)")
                                            .font(.system(size: 10, weight: .black))
                                            .padding(.horizontal, 7).padding(.vertical, 4)
                                            .background(.black.opacity(0.55), in: Capsule())
                                            .padding(7)
                                    }
                                Text(drop.title).font(.system(size: 12, weight: .bold)).lineLimit(2).frame(width: 132, alignment: .leading)
                                Text(drop.ageText).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).frame(width: 132, alignment: .leading)
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("subtitle.card.\(drop.id)")
                        .cortexShelfTilt(strength: 14)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}
