import SwiftUI

struct DownloadTransferBanner: View {
    let item: DownloadItem
    let count: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action:action) {
            HStack(spacing:10) {
                AnimeArtwork(url:item.anime?.cover).frame(width:26,height:36).clipShape(RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(.white.opacity(0.1),lineWidth:1))
                ZStack { Circle().stroke(Color.cortexPurple.opacity(0.18),lineWidth:3);Circle().trim(from:0,to:max(0,min(1,item.progress))).stroke(Color.cortexPurple,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90));Image(systemName:"arrow.down").font(.caption.bold()) }.frame(width:31,height:31)
                VStack(alignment:.leading,spacing:3) { Text(item.title).font(.caption.bold()).lineLimit(1);Text("EP \(item.episode) · \(item.statusLabel) · \(count) pending").font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(minLength:0)
                Text("\(Int(item.progress*100))%").font(.caption.bold().monospacedDigit()).contentTransition(.numericText()).foregroundStyle(Color.cortexPurple)
            }.padding(.horizontal,17).padding(.vertical,10).background(Color.cortexPanel)
                .animation(reduceMotion ? nil : .easeInOut(duration:0.35),value:item.progress)
        }.buttonStyle(.plain).accessibilityIdentifier("downloads.liveBanner")
    }
}
