import SwiftUI

@main
struct CortexTVApp: App {
    @StateObject private var store = TVStore()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct TVRootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TVHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            TVCatalogView()
                .tabItem { Label("Hungarian", systemImage: "character.book.closed") }
                .tag(1)
            TVSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(2)
        }
    }
}
