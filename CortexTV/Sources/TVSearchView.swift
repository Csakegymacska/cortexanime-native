import SwiftUI

struct TVSearchView: View {
    @EnvironmentObject private var store: TVStore
    @State private var query = ""
    @State private var results: [TVMedia] = []
    @State private var searching = false
    @State private var selection: TVMedia?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 18) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(TVBrand.cyan)
                    TextField("Search series", text: $query)
                        .font(.system(size: 30))
                        .textFieldStyle(.plain)
                        .foregroundStyle(TVBrand.text)
                        .frame(maxWidth: 900)
                        .onSubmit { Task { await runSearch() } }
                    Spacer()
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                if searching {
                    ProgressView().tint(TVBrand.cyan).padding(.horizontal, 60)
                }

                if results.isEmpty && !searching {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(query.isEmpty ? "Type part of a title, then choose Search." :
                                "No results for: \(query)")
                            .font(.system(size: 22))
                            .foregroundStyle(TVBrand.dim)
                        Button("Search") { Task { await runSearch() } }
                            .buttonStyle(.card)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 60)
                    .padding(.top, 10)
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 22)],
                              alignment: .leading, spacing: 28) {
                        ForEach(results) { item in
                            Button {
                                selection = item
                            } label: {
                                TVPosterCard(media: item, width: 240)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 20)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TVBrand.ink.ignoresSafeArea())
            .navigationDestination(item: $selection) { media in
                TVDetailView(media: media)
            }
        }
    }

    private func runSearch() async {
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
        searching = true
        results = await store.search(query)
        searching = false
    }
}

struct TVCatalogView: View {
    @EnvironmentObject private var store: TVStore
    @State private var selection: TVMedia?

    private var items: [TVMedia] { store.hungarian }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(TVBrand.violet)
                    Text("With Hungarian subtitles")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(TVBrand.text)
                    Spacer()
                    Text("\(items.count) series")
                        .font(.system(size: 20))
                        .foregroundStyle(TVBrand.dim)
                }
                .padding(.horizontal, 60)
                .padding(.top, 40)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 22)],
                              alignment: .leading, spacing: 28) {
                        ForEach(items) { item in
                            Button {
                                selection = item
                            } label: {
                                TVPosterCard(media: item, width: 240)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.hidden)
            }
            .background(TVBrand.ink.ignoresSafeArea())
            .navigationDestination(item: $selection) { media in
                TVDetailView(media: media)
            }
            .task { await store.loadIfNeeded() }
        }
    }
}
