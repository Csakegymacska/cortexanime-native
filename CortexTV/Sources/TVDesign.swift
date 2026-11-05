import SwiftUI

// MARK: - Brand

enum TVBrand {
    static let ink = Color(hex: 0x04060B)
    static let inkSoft = Color(hex: 0x0B1019)
    static let text = Color(hex: 0xEDF2F9)
    static let dim = Color(hex: 0x8B95A7)
    static let cyan = Color(hex: 0x5EE7F5)
    static let violet = Color(hex: 0xAE61FA)

    static var aurora: LinearGradient {
        LinearGradient(colors: [violet.opacity(0.55), cyan.opacity(0.35), ink.opacity(0.0)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var title: LinearGradient {
        LinearGradient(colors: [cyan, violet], startPoint: .leading, endPoint: .trailing)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Poster card

struct TVPosterCard: View {
    let media: TVMedia
    var width: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVRemoteImage(address: media.cover)
                .frame(width: width, height: width * 1.42)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if media.hasHungarian {
                        Text("HU")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(TVBrand.cyan.opacity(0.9)))
                            .foregroundStyle(TVBrand.ink)
                            .padding(8)
                    }
                }
            Text(media.title)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(TVBrand.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(TVBrand.dim)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .padding(12)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let total = media.totalEpisodes, total > 0 { parts.append("\(total) episodes") }
        if let status = media.status {
            parts.append(status == "RELEASING" ? "airing" : "finished")
        }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

// MARK: - Remote image

struct TVRemoteImage: View {
    let address: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                TVBrand.inkSoft
                if let address, let url = URL(string: address) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        case .empty:
                            ProgressView().tint(TVBrand.cyan)
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            TVBrand.aurora.opacity(0.5)
            Image(systemName: "sparkles.tv")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TVBrand.dim)
        }
    }
}

// MARK: - Rail

struct TVRail<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(TVBrand.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 18))
                        .foregroundStyle(TVBrand.dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 60)
            content()
        }
    }
}

// MARK: - Small helpers

struct TVPill: View {
    let text: String
    var tint: Color = TVBrand.cyan

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }
}
