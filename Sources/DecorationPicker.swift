import SwiftUI

// MARK: - The decoration picker (7.0)
//
// Two layers instead of one: a frame hugs the avatar's edge, an aura floats around it, and the
// two can be worn together. The stored value stays a single string ("frame_galaxy|glow_fireflies"),
// so the profile field, the shop and older saved values keep working.
//
// Every cell is a plain `Button` with a `ButtonStyle` — no `DragGesture` anywhere, because that is
// what used to swallow the scroll and the taps.

struct DecorationTileStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (selected ? 1.02 : 1))
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: selected)
    }
}

/// Favourites live on the device — a decoration you like is not a server concept.
final class DecorationFavourites: ObservableObject {
    static let shared = DecorationFavourites()
    static let key = "decorations.favourites.v1"
    @Published private(set) var ids: Set<String>

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ids = Set(defaults.array(forKey: Self.key) as? [String] ?? [])
    }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(Array(ids), forKey: Self.key)
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }
}

struct DecorationTile: View {
    let decoration: CortexDecoration
    let selected: Bool
    let owned: Bool
    let favourite: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.10 : 0.05))
                NativeAvatar(raw: nil, decoration: decoration.id, animated: false)
                    .frame(width: 62, height: 62)
                    .padding(6)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white, Color.cortexPurple)
                        .padding(4)
                } else if !owned {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                        Text("\(decoration.price)").font(.system(size: 9, weight: .black))
                    }
                    .foregroundStyle(decoration.rarityColor)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(4)
                } else if decoration.isFree {
                    Text("FREE")
                        .font(.system(size: 8, weight: .black)).tracking(0.6)
                        .foregroundStyle(Color.mint)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(4)
                }
                if favourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: 74)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.cortexPurple : decoration.rarityColor.opacity(owned ? 0.25 : 0.12),
                            lineWidth: selected ? 2 : 1)
            )
            Text(decoration.name)
                .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .frame(height: 26, alignment: .top)
                .foregroundStyle(selected ? .white : .white.opacity(0.75))
        }
        .contentShape(Rectangle())
    }
}

struct NativeDecorations: View {
    @Binding var selected: String
    @ObservedObject private var store = CreditStore.shared
    @ObservedObject private var favourites = DecorationFavourites.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var slot: DecorationSlot = .frame
    @State private var category: DecorationCategory?
    @State private var search = ""
    @State private var highlight: String?
    @State private var message: String?
    @State private var bounce = false
    @State private var onlyOwned = false
    @State private var onlyFavourites = false
    @State private var onlyFree = false

    // ---- the stack ----

    private var current: (frame: String?, aura: String?) {
        var frame: String?
        var aura: String?
        for item in CortexDecoration.list(selected) {
            if item.slot == .frame { frame = item.id } else { aura = item.id }
        }
        return (frame, aura)
    }

    private func id(in target: DecorationSlot) -> String? {
        target == .frame ? current.frame : current.aura
    }

    private func set(_ id: String?, in target: DecorationSlot) {
        var frame = current.frame
        var aura = current.aura
        if target == .frame { frame = id } else { aura = id }
        selected = CortexDecoration.encode(frame: frame, aura: aura)
    }

    private var items: [CortexDecoration] {
        var base = CortexDecoration.matching(category).filter { $0.slot == slot }
        if onlyOwned { base = base.filter { store.isUnlocked($0.id) } }
        if onlyFavourites { base = base.filter { favourites.contains($0.id) } }
        if onlyFree { base = base.filter { $0.isFree } }
        guard !search.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    private var previewID: String { highlight ?? selected }

    /// 1.0.0: two shortcuts for a catalogue this big — a random look you own, or an
    /// aura that shares the frame's palette.
    private var luckRow: some View {
        HStack(spacing: 9) {
            Button {
                randomize()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "dice")
                    Text("Surprise look")
                }
                .font(.system(size: 11.5, weight: .bold))
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(Color.cortexPurple.opacity(0.22), in: Capsule())
                .foregroundStyle(Color.cortexPurple)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("decoration.randomize")

            Button {
                matchPair()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("Match the pair")
                }
                .font(.system(size: 11.5, weight: .bold))
                .padding(.horizontal, 12).frame(minHeight: 34)
                .background(.white.opacity(0.07), in: Capsule())
                .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("decoration.match")

            Spacer(minLength: 0)
            Text("\(ownedCount)/\(CortexDecoration.all.count)")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func randomize() {
        let ownedFrames = CortexDecoration.all.filter { $0.slot == .frame && store.isUnlocked($0.id) }
        let ownedAuras = CortexDecoration.all.filter { $0.slot == .aura && store.isUnlocked($0.id) }
        var frame = current.frame
        var aura = current.aura
        if let pick = ownedFrames.randomElement() { frame = pick.id }
        if let pick = ownedAuras.randomElement() { aura = pick.id }
        selected = CortexDecoration.encode(frame: frame, aura: aura)
        message = "A random pair you already own."
    }

    private func matchPair() {
        guard let frameID = current.frame,
              let frame = CortexDecoration.named(frameID) else {
            message = "Pick a frame first, then match an aura to it."
            return
        }
        let candidates = CortexDecoration.all.filter { item in
            item.slot == .aura && store.isUnlocked(item.id) && item.colors.contains(where: { color in
                color == frame.primary || color == frame.secondary
            })
        }
        guard let aura = candidates.randomElement() else {
            message = "No owned aura shares this frame's colours yet."
            return
        }
        selected = CortexDecoration.encode(frame: frameID, aura: aura.id)
        message = "\(aura.name) matches \(frame.name)."
    }

    private var ownedCount: Int { CortexDecoration.all.filter { store.isUnlocked($0.id) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewCard
                slotPicker
                NativeSearchField(text: $search, prompt: "Search decorations")
                categoryChips
                filterRow
                luckRow
                if items.isEmpty {
                    Text("Nothing matches here yet.")
                        .font(.callout).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 14) {
                        Button {
                            set(nil, in: slot)
                            message = "\(slot.title) layer cleared."
                        } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.04))
                                    Image(systemName: "slash.circle")
                                        .font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.5))
                                }
                                .frame(height: 74)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(id(in: slot) == nil ? Color.cortexPurple : .white.opacity(0.10),
                                            lineWidth: id(in: slot) == nil ? 2 : 1))
                                Text("None").font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7)).frame(height: 26, alignment: .top)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(DecorationTileStyle(selected: id(in: slot) == nil))
                        .accessibilityIdentifier("decoration.none")

                        ForEach(items) { item in
                            Button {
                                tapped(item)
                            } label: {
                                DecorationTile(decoration: item,
                                               selected: id(in: slot) == item.id,
                                               owned: store.isUnlocked(item.id),
                                               favourite: favourites.contains(item.id))
                            }
                            .buttonStyle(DecorationTileStyle(selected: id(in: slot) == item.id))
                            .contextMenu {
                                Button {
                                    favourites.toggle(item.id)
                                } label: { Label(favourites.contains(item.id) ? "Remove favourite" : "Favourite", systemImage: "star") }
                            }
                            .accessibilityLabel("\(item.name) decoration")
                            .accessibilityIdentifier("decoration." + item.id)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.visible)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Avatar decorations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.bold() }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    // ---- pieces ----

    private var previewCard: some View {
        let frame = CortexDecoration.named(current.frame ?? "")
        let aura = CortexDecoration.named(current.aura ?? "")
        let tint = frame?.primary ?? aura?.primary ?? Color.cortexPurple
        return VStack(spacing: 10) {
            HStack(spacing: 14) {
                NativeAvatar(raw: nil, decoration: previewID)
                    .frame(width: 112, height: 112)
                    .scaleEffect(bounce ? 1.04 : 1)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55), value: bounce)
                VStack(alignment: .leading, spacing: 6) {
                    Text(frame?.name ?? aura?.name ?? "No decoration")
                        .font(.system(size: 17, weight: .black)).lineLimit(1)
                    Text("\(ownedCount) / \(CortexDecoration.all.count) in your collection")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(tint)
                    HStack(spacing: 6) {
                        slotBadge("Frame", frame?.name, .frame)
                        slotBadge("Aura", aura?.name, .aura)
                    }
                    if let message {
                        Text(message).font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.orange).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08)).frame(height: 6)
                    Capsule().fill(LinearGradient(colors: [Color.cortexPurple, tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(ownedCount) / CGFloat(max(1, CortexDecoration.all.count))), height: 6)
                }
            }.frame(height: 6)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.22), Color.cortexPanel], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.35), lineWidth: 1))
    }

    private func slotBadge(_ title: String, _ value: String?, _ target: DecorationSlot) -> some View {
        Button {
            slot = target
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.45))
                Text(value ?? "None").font(.system(size: 10.5, weight: .bold)).lineLimit(1)
                    .foregroundStyle(slot == target ? .white : .white.opacity(0.7))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .frame(minWidth: 74, alignment: .leading)
            .background(slot == target ? Color.cortexPurple.opacity(0.22) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(slot == target ? Color.cortexPurple.opacity(0.6) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var slotPicker: some View {
        Picker("Layer", selection: $slot) {
            ForEach(DecorationSlot.allCases) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: slot) { _, _ in highlight = nil }
        .accessibilityIdentifier("decoration.slot")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", symbol: "square.grid.2x2.fill", active: category == nil) { category = nil }
                ForEach(DecorationCategory.allCases) { item in
                    chip(title: item.title, symbol: item.symbol, active: category == item) { category = item }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(title).font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 12).frame(minHeight: 34)
            .foregroundStyle(active ? .black : .white.opacity(0.8))
            .background(active ? Color.white : .white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("decoration.category." + title)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            toggleChip("Free", systemImage: "gift.fill", active: $onlyFree)
            toggleChip("Owned", systemImage: "checkmark.seal.fill", active: $onlyOwned)
            toggleChip("Favourites", systemImage: "star.fill", active: $onlyFavourites)
            Spacer()
            Button {
                surprise()
            } label: {
                Label("Surprise me", systemImage: "dice.fill")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).frame(minHeight: 34)
                    .background(Color.cortexPurple.opacity(0.20), in: Capsule())
                    .foregroundStyle(Color.cortexPurple)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("decoration.surprise")
        }
    }

    private func toggleChip(_ title: String, systemImage: String, active: Binding<Bool>) -> some View {
        Button {
            active.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 10).frame(minHeight: 34)
            .foregroundStyle(active.wrappedValue ? .black : .white.opacity(0.7))
            .background(active.wrappedValue ? Color.white : .white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        let locked = CortexDecoration.named(highlight ?? "")
        return HStack(spacing: 12) {
            if let locked, !store.isUnlocked(locked.id) {
                Button {
                    buy(locked)
                } label: {
                    Label("\(locked.price) credits", systemImage: "star.circle.fill")
                        .font(.system(size: 13, weight: .black))
                        .padding(.horizontal, 14).frame(minHeight: 42)
                        .background(store.balance >= locked.price ? Color.white : .white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(store.balance >= locked.price ? .black : .white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(store.balance < locked.price)
                .accessibilityIdentifier("decoration.buy")
                Spacer()
            }
            let worn = !selected.isEmpty && selected != "none"
            Text(worn ? "\(CortexDecoration.list(selected).count) layer\(CortexDecoration.list(selected).count == 1 ? "" : "s") on" : "Nothing worn")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
            if locked == nil { Spacer() }
            Button {
                set(nil, in: .frame); set(nil, in: .aura)
                message = "Decoration removed."
            } label: {
                Text("Take off").font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 14).frame(minHeight: 42)
                    .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Button {
                dismiss()
            } label: {
                Label("Keep", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .black))
                    .padding(.horizontal, 18).frame(minHeight: 42)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("decoration.keep")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    // ---- actions ----

    private func tapped(_ item: CortexDecoration) {
        highlight = nil
        message = nil
        if store.isUnlocked(item.id) {
            wear(item)
        } else {
            highlight = item.id
            message = item.isFree ? "\(item.name) · free." : "\(item.name) · \(item.price) credits."
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func wear(_ item: CortexDecoration) {
        set(item.id, in: item.slot)
        // The credit store keeps the newest pick so the rest of the app (and the server field)
        // stays in sync; the full stack lives in `selected`.
        store.equip(item.id)
        bounce = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            bounce = false
        }
    }

    private func buy(_ item: CortexDecoration) {
        let shopItem = ShopItem(id: item.id, name: item.name,
                                kind: item.slot == .frame ? "frame" : "glow",
                                price: item.price, rarity: item.rarity, tint: "")
        if store.buy(shopItem) {
            highlight = nil
            wear(item)
            message = "Bought and equipped."
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            message = "Not enough credits — watch an episode and more arrive."
        }
    }

    private func surprise() {
        let pool = CortexDecoration.all.filter { store.isUnlocked($0.id) }
        guard !pool.isEmpty else { return }
        let frames = pool.filter { $0.slot == .frame }
        let auras = pool.filter { $0.slot == .aura }
        if let frame = frames.randomElement(), let aura = auras.randomElement() {
            selected = CortexDecoration.encode(frame: frame.id, aura: aura.id)
            store.equip(frame.id)
            slot = .frame
            category = nil
            onlyOwned = true
            onlyFavourites = false
            message = "\(frame.name) + \(aura.name)"
            bounce = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                bounce = false
            }
        }
    }
}
