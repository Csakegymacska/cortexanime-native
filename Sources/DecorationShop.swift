import SwiftUI

// MARK: - Decoration shop (2.0) — profile decorations unlocked with credits

struct ShopItem: Identifiable, Hashable {
    let id: String
    let name: String
    let kind: String   // "glow" | "frame" | "badge"
    let price: Int
    let rarity: Int    // 0 common, 1 rare, 2 epic, 3 legendary
    let tint: String   // NativeAvatar színkulcshoz

    var rarityName: String {
        ["Gyakori", "Ritka", "Epikus", "Legendary"][min(rarity, 3)]
    }
    var rarityColor: Color {
        switch rarity {
        case 1: return .cyan
        case 2: return Color.cortexPurple
        case 3: return .yellow
        default: return .gray
        }
    }
}

enum ShopCatalog {
    /// 6.8: a shop and the picker now share one catalogue, so a decoration can never be
    /// listed in one place and missing from the other.
    static var all: [ShopItem] {
        CortexDecoration.all.map { item in
            ShopItem(id: item.id, name: item.name,
                     kind: item.category == .frame ? "frame" : item.category.rawValue,
                     price: item.price, rarity: item.rarity, tint: "")
        }
    }

    static func items(kind: String) -> [ShopItem] { all.filter { $0.kind == kind } }

    static func decorations(kind: String) -> [CortexDecoration] {
        CortexDecoration.all.filter { ($0.category == .frame ? "frame" : $0.category.rawValue) == kind }
    }
}

struct ShopRow: View {
    let item: ShopItem
    @ObservedObject var store: CreditStore
    @State private var justBought = false

    private var decoration: CortexDecoration? { CortexDecoration.named(item.id) }

    var body: some View {
        HStack(spacing: 13) {
            NativeAvatar(raw: nil, decoration: item.id, animated: false)
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.system(size: 14, weight: .bold))
                HStack(spacing: 6) {
                    Text(item.rarityName).font(.system(size: 10.5, weight: .black)).foregroundStyle(item.rarityColor)
                    if (decoration?.category != nil) {
                        Text(decoration?.category.title ?? "").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            Spacer()
            if store.isUnlocked(item.id) {
                Button(store.isWearing(item.id) ? "Viselve" : "Felveszem") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { store.equip(item.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(store.isWearing(item.id) ? Color.cortexPurple : .gray)
                .font(.system(size: 12, weight: .bold))
                .frame(minHeight: 40)
            } else {
                Button {
                    if store.buy(item) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { justBought = true }
                        store.equip(item.id)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "star.circle.fill").font(.system(size: 11))
                        Text("\(item.price)").font(.system(size: 13, weight: .black))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(store.balance >= item.price ? item.rarityColor.opacity(0.22) : Color.gray.opacity(0.15), in: Capsule())
                    .foregroundStyle(store.balance >= item.price ? item.rarityColor : .gray)
                    .scaleEffect(justBought ? 1.12 : 1.0)
                }
                .disabled(store.balance < item.price)
                .frame(minHeight: 40)
            }
        }
        .padding(12)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(item.rarityColor.opacity(store.isUnlocked(item.id) && store.isWearing(item.id) ? 0.55 : 0.08), lineWidth: 1.5)
        )
    }
}

struct NativeDecorationShop: View {
    @ObservedObject private var store = CreditStore.shared
    @EnvironmentObject private var api: APIClient
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var balancePulse = false
    // 1.0.0: a catalogue this large needs its own controls.
    @State private var onlyOwned = false
    @State private var onlyAffordable = false
    @State private var rarityFilter: Int? = nil
    @State private var sortMode: ShopSortMode = .category
    // 1.0.1: kredit-kód beváltása közvetlenül a boltból.
    @State private var redeemSheet = false
    @State private var redeemCode = ""
    @State private var redeemBusy = false
    @State private var redeemMessage: String?
    @State private var redeemSuccess = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:18) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Your credit balance").font(.system(size:13,weight:.bold)).foregroundStyle(.secondary)
                        HStack(spacing:8) {
                            Image(systemName:"star.circle.fill").foregroundStyle(.yellow)
                            Text("\(store.balance)").font(.system(size:32,weight:.black))
                                .scaleEffect(balancePulse ? 1.08 : 1.0)
                                .animation(reduceMotion ? nil : .easeInOut(duration:2.0).repeatForever(autoreverses:true), value: balancePulse)
                        }
                        Text("Lifetime: \(store.lifetime) credits · Level \(store.level)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth:.infinity,alignment:.leading)
                .background(Color.cortexPanel,in: RoundedRectangle(cornerRadius:18))

                Button {
                    redeemCode = ""; redeemMessage = nil; redeemSuccess = false; redeemSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "ticket.fill").foregroundStyle(.yellow)
                        Text("Redeem a credit code").font(.system(size: 13, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Text("You own \(ownedCount) of \(CortexDecoration.all.count) decorations — \(freeCount) of them are free.")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)

                featured

                filters

                if sortMode == .category {
                    ForEach(DecorationCategory.allCases) { category in
                        let kind = category == .frame ? "frame" : category.rawValue
                        shopSection(category.title, items: filtered(ShopCatalog.decorations(kind: kind)))
                    }
                } else {
                    shopSection(sortMode.title, items: filtered(CortexDecoration.all))
                }

                Text("You earn credits by watching, daily open, and badges. Decorations appear on your profile.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Color(red:0.043,green:0.059,blue:0.102).ignoresSafeArea())
        .navigationTitle("Credit Shop")
        .onAppear { balancePulse = true }
        .sheet(isPresented: $redeemSheet) { redeemView }
    }

    /// 1.0.1: a kódot a szerver váltja be (egyszer használatos, fiókhoz kötött).
    private var redeemView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter the code you received. Codes are single-use and tied to your account.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("CORTEX-XXXX", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .padding(14)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 12))
                if let redeemMessage {
                    Label(redeemMessage, systemImage: redeemSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(redeemSuccess ? Color.green : Color.orange)
                }
                Button {
                    Task { await redeem() }
                } label: {
                    HStack {
                        if redeemBusy { ProgressView().tint(.white) }
                        Text(redeemBusy ? "Redeeming…" : "Redeem")
                            .font(.system(size: 15, weight: .black))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.cortexPurple, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .disabled(redeemBusy || redeemCode.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
            }
            .padding(18)
            .background(Color(red:0.043,green:0.059,blue:0.102).ignoresSafeArea())
            .navigationTitle("Redeem code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { redeemSheet = false } } }
        }
        .presentationDetents([.height(320)])
    }

    private func redeem() async {
        let code = redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        redeemBusy = true
        defer { redeemBusy = false }
        do {
            let result = try await api.redeemCreditCode(code)
            if result.balance >= store.balance {
                store.syncAccount(result.balance)          // a szerver az igazság: a kód benne van
            } else if result.amount > 0 {
                store.add(result.amount, note: "Code \(code)")   // helyi többlet: csak a kód összege jön
            }
            redeemSuccess = true
            redeemMessage = "+\(result.amount) credits added — balance \(store.balance)."
            redeemCode = ""
        } catch {
            redeemSuccess = false
            redeemMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var ownedCount: Int { CortexDecoration.all.filter { store.isUnlocked($0.id) }.count }

    /// One piece is in the window each day — deterministic, so everyone sees the same one.
    private var featuredItem: CortexDecoration? {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1
        let pool = CortexDecoration.all.filter { !$0.isFree }
        guard !pool.isEmpty else { return nil }
        return pool[abs(day * 7 + 3) % pool.count]
    }

    @ViewBuilder private var featured: some View {
        if let item = featuredItem {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(item.rarityColor)
                    Text("TODAY'S WINDOW").font(.system(size: 9.5, weight: .black)).tracking(1.4)
                        .foregroundStyle(item.rarityColor)
                    Spacer()
                    Text(item.rarityName).font(.system(size: 9.5, weight: .black)).foregroundStyle(item.rarityColor)
                }
                HStack(spacing: 14) {
                    DecorationArt(decoration: item, size: 76)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).font(.system(size: 15, weight: .bold))
                        Text(item.category.title).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(item.isFree ? "Free" : "\(item.price) credits")
                            .font(.system(size: 12, weight: .black)).foregroundStyle(item.rarityColor)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .background(LinearGradient(colors: [item.rarityColor.opacity(0.16), Color.cortexPanel],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(item.rarityColor.opacity(0.35), lineWidth: 1))
            .accessibilityIdentifier("shop.featured")
        }
    }
    private var freeCount: Int { CortexDecoration.all.filter { $0.isFree }.count }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip("All rarities", active: rarityFilter == nil) { rarityFilter = nil }
                ForEach(0..<4, id: \.self) { level in
                    chip(["Common", "Rare", "Epic", "Legendary"][level], active: rarityFilter == level) { rarityFilter = level }
                }
            }
            HStack(spacing: 8) {
                chip("Owned", active: onlyOwned) { onlyOwned.toggle() }
                chip("Affordable", active: onlyAffordable) { onlyAffordable.toggle() }
                Spacer(minLength: 0)
                Menu {
                    ForEach(ShopSortMode.allCases) { mode in
                        Button(mode.title) { sortMode = mode }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortMode.title).lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 11).frame(minHeight: 30)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 11).frame(minHeight: 30)
                .background(active ? Color.cortexPurple.opacity(0.25) : Color.white.opacity(0.07), in: Capsule())
                .foregroundStyle(active ? Color.cortexPurple : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shop.chip." + title)
    }

    private func filtered(_ items: [CortexDecoration]) -> [CortexDecoration] {
        var rows = items
        if let rarityFilter { rows = rows.filter { $0.rarity == rarityFilter } }
        if onlyOwned { rows = rows.filter { store.isUnlocked($0.id) } }
        if onlyAffordable { rows = rows.filter { $0.isFree || store.balance >= $0.price } }
        switch sortMode {
        case .category: break
        case .price: rows.sort { ($0.isFree ? 0 : $0.price) < ($1.isFree ? 0 : $1.price) }
        case .rarity: rows.sort { $0.rarity > $1.rarity }
        case .name: rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return rows
    }

    @ViewBuilder private func shopSection(_ title: String, items: [CortexDecoration]) -> some View {
        if !items.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: title)
            ForEach(items) { item in
                ShopRow(item: ShopItem(id: item.id, name: item.name,
                                       kind: item.category == .frame ? "frame" : item.category.rawValue,
                                       price: item.price, rarity: item.rarity, tint: ""),
                        store: store)
            }
        }
        }
    }
}

enum ShopSortMode: String, CaseIterable, Identifiable {
    case category, price, rarity, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .category: return "By category"
        case .price: return "Cheapest first"
        case .rarity: return "Rarest first"
        case .name: return "A–Z"
        }
    }
}

// MARK: - Statistics és jelvények

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = Color.cortexPurple
    var body: some View {
        VStack(spacing:8) {
            Image(systemName:icon).font(.system(size:22,weight:.bold)).foregroundStyle(color)
            Text(value).font(.system(size:20,weight:.black))
            Text(label).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth:.infinity).padding(.vertical,16)
        .background(Color.cortexPanel,in: RoundedRectangle(cornerRadius:16))
    }
}

struct NativeStatsView: View {
    @ObservedObject private var store = CreditStore.shared
    @ObservedObject private var library = AnimeLibrary.shared

    private var hours: String {
        String(format:"%.1f", store.totalSeconds / 3600.0)
    }

    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                LazyVGrid(columns:[GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)],spacing:12) {
                    StatCard(icon:"play.circle.fill", value:"\(store.episodesCompleted)", label:"episodes completed")
                    StatCard(icon:"clock.fill", value:"\(hours) h", label:"watch time", color:.cyan)
                    StatCard(icon:"checkmark.seal.fill", value:"\(store.seriesCompleted)", label:"series finished", color:.mint)
                    StatCard(icon:"flame.fill", value:"\(store.streakDays)", label:"day streak", color:.orange)
                    StatCard(icon:"star.circle.fill", value:"\(store.lifetime)", label:"credits earned", color:.yellow)
                    StatCard(icon:"arrow.up.circle.fill", value:"Level \(store.level)", label:"\(store.xpToNext) XP to next level")
                }

                WeeklyRecapCard(store: store)

                TopSeriesCard(library: library, store: store)

                ShareStatsButton(store: store)

                SectionHeading(title:"Level progress")
                VStack(alignment:.leading,spacing:8) {
                    GeometryReader { geo in
                        ZStack(alignment:.leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(height:14)
                            Capsule().fill(LinearGradient(colors:[Color.cortexPurple,.cyan],startPoint:.leading,endPoint:.trailing))
                                .frame(width:max(14,geo.size.width*store.levelProgress),height:14)
                        }
                    }.frame(height:14)
                    Text("Level \(store.level) · \(Int(store.levelProgress*100))% to the next level").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.cortexPanel,in: RoundedRectangle(cornerRadius:16))

                SectionHeading(title:"Badges")
                // Locked badges now show how far away they are instead of a flat grey card.
                let earnedBadges = ProfileBadge.all.filter { store.badgesEarned.contains($0.id) }
                let lockedBadges = ProfileBadge.all.filter { !store.badgesEarned.contains($0.id) }
                if !earnedBadges.isEmpty {
                    Text("Earned").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(earnedBadges) { badge in
                        BadgeProgressRow(badge: badge, store: store)
                    }
                }
                if !lockedBadges.isEmpty {
                    Text("In progress").font(.caption.bold()).foregroundStyle(.secondary).padding(.top,4)
                    ForEach(lockedBadges) { badge in
                        BadgeProgressRow(badge: badge, store: store)
                    }
                }

                SectionHeading(title:"Credit history")
                VStack(spacing:8) {
                    ForEach(store.transactions.prefix(20)) { tx in
                        HStack {
                            Image(systemName:tx.amount >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                                .foregroundStyle(tx.amount >= 0 ? .mint : .orange)
                            Text(tx.note).font(.system(size:12.5)).lineLimit(1)
                            Spacer()
                            Text(tx.amount >= 0 ? "+\(tx.amount)" : "\(tx.amount)")
                                .font(.system(size:13,weight:.black))
                                .foregroundStyle(tx.amount >= 0 ? .mint : .orange)
                        }
                        .padding(11)
                        .background(Color.cortexPanel,in: RoundedRectangle(cornerRadius:12))
                    }
                }
            }
            .padding(16)
        }
        .background(Color(red:0.043,green:0.059,blue:0.102).ignoresSafeArea())
        .navigationTitle("Statistics")
        .task { _ = ProfileBadge.evaluate(store:store) }
    }

    private func badgeColor(_ rarity: Int) -> Color {
        switch rarity {
        case 1: return .cyan
        case 2: return Color.cortexPurple
        case 3: return .yellow
        default: return .mint
        }
    }
}
