import SwiftUI

extension Color {
    static let cortexBlack = Color(red:0.025,green:0.035,blue:0.055)
    static let cortexPurple = Color(red:0.68,green:0.38,blue:0.98)
    static let cortexPanel = Color(red:0.065,green:0.075,blue:0.10)
    static let cortexMint = Color(red:0.35,green:0.90,blue:0.72)
}
struct AnimeArtwork: View {
    let url: URL?
    var body: some View {
        GeometryReader { geo in
            AsyncImage(url:url) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Rectangle().fill(LinearGradient(colors:[.purple.opacity(0.22),Color.cortexPanel],startPoint:.topLeading,endPoint:.bottomTrailing)).overlay { Image(systemName:"play.rectangle").foregroundStyle(.white.opacity(0.25)) } }
            }.frame(width:geo.size.width,height:geo.size.height).clipped()
        }.accessibilityHidden(true)
    }
}
struct CortexHeader: View {
    var body: some View {
        HStack(spacing:8) {
            Image("CortexLogo").resizable().scaledToFit().frame(width:32,height:32).clipShape(Circle())
            Text("CORTEX").font(.system(size:16,weight:.black)) + Text(" ANIME").font(.system(size:16,weight:.black)).foregroundColor(Color.cortexPurple)
            Text("CHARITY").font(.system(size:8,weight:.black)).tracking(1).foregroundStyle(.pink).padding(5).background(.pink.opacity(0.1),in:Capsule())
            Spacer()
            Image(systemName:"sparkle").foregroundStyle(Color.cortexPurple)
        }.padding(.vertical,8)
    }
}
struct Pill: View { let text: String;var color: Color = Color.cortexPurple
    var body: some View { Text(text).font(.system(size:10,weight:.bold)).padding(.horizontal,9).padding(.vertical,5).foregroundStyle(color).background(color.opacity(0.13),in:Capsule()).overlay(Capsule().stroke(color.opacity(0.25),lineWidth:1)) }
}
struct SectionHeading: View { let title: String
    var body: some View { HStack(spacing:10) { Capsule().fill(Color.cortexPurple).frame(width:4,height:18);Text(title).font(.system(size:19,weight:.black));Spacer() }.padding(.top,4) }
}
struct AnimeTile: View {
    let anime: Anime
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            AnimeArtwork(url:anime.cover).aspectRatio(0.68,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:16)).overlay(alignment:.topLeading) { if let score = anime.score { Pill(text:String(format:"%.1f",score),color:.yellow).padding(7) } }
            Text(anime.title).font(.system(size:12,weight:.bold))
                .lineLimit(3)
                .fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity,alignment:.topLeading)
            Text(anime.format ?? "Anime").font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
        }.foregroundStyle(.white).accessibilityElement(children:.combine)
    }
}
struct AnimeGrid: View {
    let items: [Anime]
    var body: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:140),spacing:14)],spacing:20) {
            ForEach(items) { anime in NavigationLink { NativeDetail(seed:anime) } label: { AnimeTile(anime:anime) }.buttonStyle(.plain).accessibilityIdentifier("anime.card.\(anime.id)") }
        }
    }
}
/// One shared 3D treatment for every card that lives in a horizontal shelf.
/// Previously it was inlined in `AnimeShelf` only, so every shelf added after 5.0
/// (releases, subtitle drops, on-device picks) scrolled flat. 6.2 applies it everywhere
/// through this modifier, so a new shelf can never miss it again.
struct CortexCard3D: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = MotionSettings.shared
    /// Tilt in degrees at the edge of the screen; the small cards use a gentler value.
    var strength: Double = 14

    func body(content: Content) -> some View {
        // One chained expression on purpose: the scroll-transition closure returns a visual effect,
        // so a multi-statement body would need an explicit type the generic cannot name.
        content.scrollTransition(.interactive, axis: .horizontal) { card, phase in
            card
                .rotation3DEffect(.degrees(-Double((reduceMotion || !motion.cardTilt) ? 0 : phase.value) * strength),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                .scaleEffect((reduceMotion || !motion.cardTilt) ? 1 : 1 - CGFloat(min(1, abs(phase.value))) * 0.06)
                .opacity((reduceMotion || !motion.cardTilt) ? 1 : 1 - min(1, abs(phase.value)) * 0.12)
        }
    }
}

/// The tap counterpart: a card that leans towards the finger and settles back.
struct CortexPress3D: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A ButtonStyle is not a DynamicProperty container, so the switch is read straight from the
    /// shared object; a value change re-renders the button anyway because its parent re-renders.
    private var motionEnabled: Bool { MotionSettings.shared.cardTilt }
    var strength: Double = 6

    func makeBody(configuration: Configuration) -> some View {
        let still = reduceMotion || !motionEnabled
        return configuration.label
            .rotation3DEffect(.degrees(configuration.isPressed && !still ? strength : 0),
                              axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .scaleEffect(configuration.isPressed && !still ? 0.97 : 1)
            .animation(still ? nil : .spring(response: 0.26, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension View {
    /// Cards inside a horizontal shelf get the tilt while they scroll past the edge.
    func cortexShelfTilt(strength: Double = 14) -> some View { modifier(CortexCard3D(strength: strength)) }
    /// Tappable cards lean towards the finger.
    func cortexPress3D(strength: Double = 6) -> some View { buttonStyle(CortexPress3D(strength: strength)) }
}

struct AnimeShelf: View {
    let title: String
    let items: [Anime]
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            SectionHeading(title:title)
            ScrollView(.horizontal,showsIndicators:false) {
                LazyHStack(alignment:.top,spacing:12) {
                    ForEach(items) { item in
                        NavigationLink { NativeDetail(seed:item) } label: { AnimeTile(anime:item).frame(width:136) }
                            .buttonStyle(.plain)
                            .cortexShelfTilt()
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
        }
    }
}
struct NativeEmpty: View { let title: String;var detail = "";var icon = "rectangle.stack"
    var body: some View { VStack(spacing:14) { Image(systemName:icon).font(.largeTitle).foregroundStyle(Color.cortexPurple);Text(title).font(.headline);if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) } }.frame(maxWidth:.infinity).padding(30) }
}
struct NativeError: View { let text: String;let retry: () -> Void
    var body: some View { VStack(alignment:.leading,spacing:12) { ErrorNotice(text:text);Button("Retry",action:retry).frame(minHeight:44) }.padding().frame(maxWidth:.infinity,alignment:.leading).background(Color.cortexPanel,in:RoundedRectangle(cornerRadius:16)) }
}
struct PrimaryButton: View { let title: String;var icon = "play.fill";let action: () -> Void
    var body: some View { Button(action:action) { Label(title,systemImage:icon).font(.system(size:16,weight:.black)).frame(maxWidth:.infinity,minHeight:52).foregroundStyle(.black).background(.white,in:RoundedRectangle(cornerRadius:18)) }.buttonStyle(.plain) }
}
