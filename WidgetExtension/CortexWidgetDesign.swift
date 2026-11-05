import SwiftUI
import UIKit
import ImageIO

// Visual language for every CortexAnime widget: one brand mark, one chip, one card,
// one empty state. Everything is drawn from real data pulled by CortexWidgetClient.

enum CxWidget {
    static let black = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let panel = Color(red: 0.075, green: 0.085, blue: 0.12)
    static let purple = Color(red: 0.68, green: 0.38, blue: 0.98)
    static let indigo = Color(red: 0.32, green: 0.28, blue: 0.86)
    static let mint = Color(red: 0.35, green: 0.92, blue: 0.72)

    static func tint(_ rgb: Int?) -> Color {
        guard let rgb else { return purple }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255,
                     green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }

    static func onTint(_ rgb: Int?) -> Color {
        guard let rgb else { return .white }
        let luma = 0.2126 * Double((rgb >> 16) & 0xFF) + 0.7152 * Double((rgb >> 8) & 0xFF) + 0.0722 * Double(rgb & 0xFF)
        return luma > 168 ? Color(red: 0.05, green: 0.06, blue: 0.10) : .white
    }

    /// Average poster colour with a gentle lift so gradients stay lively on dark glass.
    static func dominantRGB(_ bytes: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 18,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var red = 0, green = 0, blue = 0
        for index in 0..<(width * height) {
            red += Int(pixels[index * 4]); green += Int(pixels[index * 4 + 1]); blue += Int(pixels[index * 4 + 2])
        }
        let count = max(1, width * height)
        var r = Double(red / count) / 255, g = Double(green / count) / 255, b = Double(blue / count) / 255
        let high = max(r, max(g, b)), low = min(r, min(g, b))
        if high > 0 {
            let saturation = (high - low) / high
            if saturation < 0.28 {
                r = r * 0.35 + 0.68 * 0.65; g = g * 0.35 + 0.38 * 0.65; b = b * 0.35 + 0.98 * 0.65
            } else if high < 0.55 {
                let lift = 0.55 / high
                r = min(1, r * lift); g = min(1, g * lift); b = min(1, b * lift)
            }
        }
        return (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }
}

struct CxBrandMark: View {
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image("CortexLogo").resizable().scaledToFit().frame(width: 15, height: 15)
                .accessibilityHidden(true)
            Text("CORTEX").font(.system(size: 9.5, weight: .black)).tracking(0.4)
            Text("ANIME").font(.system(size: 9.5, weight: .black)).tracking(0.4).foregroundStyle(CxWidget.purple)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct CxEpisodeChip: View {
    let episode: Int
    var rgb: Int? = nil
    var body: some View {
        Text("EP \(episode)")
            .font(.system(size: 9, weight: .heavy)).monospacedDigit()
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Capsule().fill(CxWidget.tint(rgb)))
            .foregroundStyle(CxWidget.onTint(rgb))
            .accessibilityLabel("Episode \(episode)")
    }
}

struct CxInfoChip: View {
    let text: String
    var color: Color = CxWidget.purple
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .heavy)).tracking(0.3)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Poster with a colour-tinted scrim. Falls back to a branded gradient when artwork is missing.
struct CxArtwork: View {
    let data: Data?
    var rgb: Int? = nil
    var cornerRadius: CGFloat = 13
    var symbol: String = "sparkles.tv"
    var body: some View {
        ZStack {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [CxWidget.tint(rgb ?? 0x442288), CxWidget.indigo, Color.black.opacity(0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Image(systemName: symbol).font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.22))
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

/// Small family: one full-bleed hero.
struct CxHeroCard: View {
    let title: String
    let episode: Int
    let caption: String
    let artwork: Data?
    let rgb: Int?
    var badge: String? = nil
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CxArtwork(data: artwork, rgb: rgb, cornerRadius: 0, symbol: "play.rectangle")
                .overlay {
                    LinearGradient(colors: [CxWidget.tint(rgb ?? 0x442288).opacity(0.35), .clear, .clear, .black.opacity(0.90)],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    CxEpisodeChip(episode: episode, rgb: rgb)
                    if let badge { CxInfoChip(text: badge, color: CxWidget.mint) }
                }
                Text(title).font(.system(size: 13, weight: .heavy)).lineLimit(2)
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                Text(caption).font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), episode \(episode), \(caption)")
    }
}

/// Medium family: two poster cards side by side.
struct CxPosterCard: View {
    let title: String
    let episode: Int
    let caption: String
    let artwork: Data?
    let rgb: Int?
    var badge: String? = nil
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CxArtwork(data: artwork, rgb: rgb, cornerRadius: 13)
            LinearGradient(colors: [.clear, .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    CxEpisodeChip(episode: episode, rgb: rgb)
                    if let badge { CxInfoChip(text: badge, color: CxWidget.mint) }
                }
                Text(title).font(.system(size: 11.5, weight: .heavy)).lineLimit(2)
                    .foregroundStyle(.white).shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            .padding(8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), episode \(episode), \(caption)")
    }
}

/// Large family: compact rows with a poster thumbnail.
struct CxRow: View {
    let title: String
    let episode: Int
    let caption: String
    let artwork: Data?
    let rgb: Int?
    var badge: String? = nil
    var body: some View {
        HStack(spacing: 9) {
            CxArtwork(data: artwork, rgb: rgb, cornerRadius: 9)
                .frame(width: 34, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11.5, weight: .bold)).lineLimit(2)
                HStack(spacing: 5) {
                    CxEpisodeChip(episode: episode, rgb: rgb)
                    if let badge { CxInfoChip(text: badge, color: CxWidget.mint) }
                    Text(caption).font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), episode \(episode), \(caption)")
    }
}

struct CxEmptyState: View {
    var headline: String
    var detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image("CortexLogo").resizable().scaledToFit().frame(width: 17, height: 17)
                Text("CORTEX").font(.system(size: 10, weight: .black))
                Text("ANIME").font(.system(size: 10, weight: .black)).foregroundStyle(CxWidget.purple)
            }
            Text(headline).font(.system(size: 13, weight: .heavy))
            Text(detail).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.72)).lineLimit(3)
            Spacer(minLength: 0)
            Text("Open CortexAnime").font(.system(size: 9, weight: .bold)).foregroundStyle(CxWidget.purple)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Branded background shared by every family.
struct CxBackground: View {
    var accent: Color = CxWidget.purple
    var body: some View {
        ZStack {
            CxWidget.black
            LinearGradient(colors: [accent.opacity(0.22), .clear, CxWidget.black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct CxLockedChip: View {
    let episode: Int
    var body: some View {
        Text("EP \(episode)").font(.system(size: 9, weight: .heavy)).monospacedDigit()
    }
}

/// 7.2: full-bleed hero with the episode number as a watermark, used by the release and airing
/// widgets. Bigger artwork, stronger scrim, one clear call to action.
struct CxHeroBanner: View {
    let title: String
    let episode: Int
    let caption: String
    let artwork: Data?
    let rgb: Int?
    var badge: String? = nil
    var showsAction: Bool = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CxArtwork(data: artwork, rgb: rgb, cornerRadius: 0, symbol: "play.rectangle")
            LinearGradient(colors: [.black.opacity(0.10), .clear, .black.opacity(0.35), .black.opacity(0.94)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [CxWidget.tint(rgb).opacity(0.45), .clear],
                           startPoint: .bottomTrailing, endPoint: .center)
            Text("\(episode)")
                .font(.system(size: 78, weight: .black))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.13))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, -10).padding(.trailing, 6)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    CxEpisodeChip(episode: episode, rgb: rgb)
                    if let badge { CxInfoChip(text: badge, color: CxWidget.mint) }
                    Spacer(minLength: 0)
                    Text(caption).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(.black.opacity(0.32), in: Capsule())
                }
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                if showsAction {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill").font(.system(size: 7, weight: .black))
                        Text("WATCH").font(.system(size: 8.5, weight: .black)).tracking(0.6)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    .foregroundStyle(.black)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), episode \(episode), \(caption)")
    }
}

/// One-line row with a wide thumbnail, used in the medium and large families.
struct CxMiniRow: View {
    let title: String
    let episode: Int
    let caption: String
    let artwork: Data?
    let rgb: Int?
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            CxArtwork(data: artwork, rgb: rgb, cornerRadius: 8)
                .frame(width: 30, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10.5, weight: .bold)).lineLimit(1)
                HStack(spacing: 4) {
                    Text("EP \(episode)").font(.system(size: 8, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(CxWidget.tint(rgb))
                    if let badge { CxInfoChip(text: badge, color: CxWidget.mint) }
                    Text(caption).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.25))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), episode \(episode), \(caption)")
    }
}
