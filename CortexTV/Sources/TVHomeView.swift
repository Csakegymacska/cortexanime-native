import SwiftUI

struct TVHomeView: View {
    @EnvironmentObject private var store: TVStore
    @State private var selection: TVMedia?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 46) {
                    hero
                    if let error = store.loadError {
                        TVErrorCard(message: error) {
                            Task { await store.reload() }
                        }
                    }
                    if !store.hungarian.isEmpty {
                        TVRail(title: "With Hungarian subtitles", subtitle: "\(store.hungarian.count) series") {
                            horizontal(store.hungarian)
                        }
                    }
                    if !store.trending.isEmpty {
                        TVRail(title: "Felkapott most", subtitle: "AniList") {
                            horizontal(store.trending)
                        }
                    }
                    if !store.seasonal.isEmpty {
                        TVRail(title: "Ebben a szezonban") {
                            horizontal(store.seasonal)
                        }
                    }
                }
                .padding(.vertical, 40)
            }
            .background(TVBrand.ink.ignoresSafeArea())
            .scrollIndicators(.hidden)
            .navigationDestination(item: $selection) { media in
                TVDetailView(media: media)
            }
        }
        .task { await store.loadIfNeeded() }
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        let featured = store.trending.first ?? store.hungarian.first
        ZStack(alignment: .bottomLeading) {
            TVRemoteImage(address: featured?.banner ?? featured?.cover)
                .frame(height: 620)
                .overlay(
                    LinearGradient(colors: [TVBrand.ink.opacity(0.0), TVBrand.ink.opacity(0.65), TVBrand.ink],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    LinearGradient(colors: [TVBrand.ink.opacity(0.85), .clear],
                                   startPoint: .leading, endPoint: .center)
                )

            VStack(alignment: .leading, spacing: 18) {
                Text("CORTEXANIME")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(TVBrand.title)

                Text(featured?.title ?? "CortexAnime")
                    .font(.system(size: 68, weight: .heavy))
                    .foregroundStyle(TVBrand.text)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 6)

                if let synopsis = featured?.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.system(size: 24))
                        .foregroundStyle(TVBrand.dim)
                        .lineLimit(3)
                        .frame(maxWidth: 900, alignment: .leading)
                }

                HStack(spacing: 22) {
                    if let featured {
                        Button {
                            selection = featured
                        } label: {
                            Label("Watch", systemImage: "play.fill")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .buttonStyle(.card)
                    }
                    if store.loading {
                        ProgressView().tint(TVBrand.cyan)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func horizontal(_ items: [TVMedia]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(items) { item in
                    Button {
                        selection = item
                    } label: {
                        TVPosterCard(media: item)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
        }
        .scrollIndicators(.hidden)
    }
}

struct TVErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Could not load")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(TVBrand.text)
            Text(message)
                .font(.system(size: 20))
                .foregroundStyle(TVBrand.dim)
            Button("Try again", action: retry)
                .buttonStyle(.card)
        }
        .padding(28)
        .frame(maxWidth: 900, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(TVBrand.inkSoft))
        .padding(.horizontal, 60)
    }
}
