import SwiftUI

struct TVPlayRequest: Identifiable {
    let media: TVMedia
    let episode: Int
    var id: String { "\(media.aid)-\(episode)" }
}

struct TVDetailView: View {
    let media: TVMedia

    @EnvironmentObject private var store: TVStore
    @State private var episodes: [TVEpisode] = []
    @State private var loadingEpisodes = true
    @State private var playRequest: TVPlayRequest?
    @State private var detail: TVMedia?

    private var current: TVMedia { detail ?? media }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                artwork
                actions
                if !current.genres.isEmpty { genreRow }
                if let synopsis = current.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.system(size: 22))
                        .foregroundStyle(TVBrand.dim)
                        .lineSpacing(4)
                        .frame(maxWidth: 1180, alignment: .leading)
                        .padding(.horizontal, 60)
                }
                episodeSection
            }
            .padding(.bottom, 70)
        }
        .background(TVBrand.ink.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .task {
            episodes = await store.episodes(for: media.aid)
            detail = await store.media(for: media.aid)
            loadingEpisodes = false
        }
        .fullScreenCover(item: $playRequest) { request in
            TVPlayerView(media: request.media, startEpisode: request.episode)
        }
    }

    // MARK: Artwork

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            TVRemoteImage(address: current.banner ?? current.cover)
                .frame(height: 560)
                .overlay(
                    LinearGradient(colors: [TVBrand.ink.opacity(0.15), TVBrand.ink.opacity(0.75), TVBrand.ink],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    LinearGradient(colors: [TVBrand.ink.opacity(0.8), .clear], startPoint: .leading, endPoint: .center)
                )

            HStack(alignment: .bottom, spacing: 34) {
                TVRemoteImage(address: current.cover)
                    .frame(width: 220, height: 312)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 24, y: 10)

                VStack(alignment: .leading, spacing: 12) {
                    Text(current.title)
                        .font(.system(size: 58, weight: .heavy))
                        .foregroundStyle(TVBrand.text)
                        .lineLimit(2)
                    if let original = current.originalTitle, original != current.title {
                        Text(original)
                            .font(.system(size: 22))
                            .foregroundStyle(TVBrand.dim)
                            .lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        if let total = current.totalEpisodes, total > 0 {
                            TVPill(text: "\(total) episodes", tint: TVBrand.cyan)
                        }
                        if let status = current.status {
                            TVPill(text: status == "RELEASING" ? "Airing" : "Finished", tint: TVBrand.violet)
                        }
                        if current.hasHungarian {
                            TVPill(text: "Hungarian subs", tint: TVBrand.cyan)
                        }
                        if let score = current.score, score > 0 {
                            TVPill(text: String(format: "%.1f", score), tint: TVBrand.violet)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 20) {
            if let first = episodes.first {
                Button {
                    playRequest = TVPlayRequest(media: current, episode: first.number)
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                }
                .buttonStyle(.card)
            } else if loadingEpisodes {
                ProgressView().tint(TVBrand.cyan)
            } else {
                Text("No episodes are available for this title yet.")
                    .font(.system(size: 22))
                    .foregroundStyle(TVBrand.dim)
            }
        }
        .padding(.horizontal, 60)
    }

    private var genreRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(current.genres, id: \.self) { genre in
                    TVPill(text: genre, tint: TVBrand.dim)
                }
            }
            .padding(.horizontal, 60)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Episodes

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Episodes")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(TVBrand.text)
                Spacer()
                if loadingEpisodes { ProgressView().tint(TVBrand.cyan) }
            }
            .padding(.horizontal, 60)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 360), spacing: 24)],
                      alignment: .leading, spacing: 28) {
                ForEach(episodes) { episode in
                    Button {
                        playRequest = TVPlayRequest(media: current, episode: episode.number)
                    } label: {
                        episodeCard(episode)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 60)
        }
    }

    private func episodeCard(_ episode: TVEpisode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                TVRemoteImage(address: episode.thumbnail ?? current.banner ?? current.cover)
                    .frame(height: 178)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Episode \(episode.number)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            Text(episode.title ?? "Episode \(episode.number)")
                .font(.system(size: 17))
                .foregroundStyle(TVBrand.dim)
                .lineLimit(2)
                .frame(height: 42, alignment: .top)
        }
    }
}
