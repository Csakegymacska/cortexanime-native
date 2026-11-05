import SwiftUI
import WidgetKit
import ActivityKit

private let downloadPurple = Color(red:0.67,green:0.43,blue:1)

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for:DownloadActivityAttributes.self) { context in
            VStack(alignment:.leading,spacing:10) {
                HStack {
                    Label("CortexAnime · Downloads",systemImage:"arrow.down.circle.fill").font(.caption.bold()).foregroundStyle(downloadPurple)
                    Spacer()
                    Text("\(context.state.completed) / \(context.state.total)").font(.caption.monospacedDigit())
                }
                Text(context.state.title).font(.headline).lineLimit(1)
                HStack { Text("Episode \(context.state.episode)");Spacer();Text(context.isStale ? "Open app for current status" : context.state.phase) }.font(.caption).foregroundStyle(.secondary)
                ProgressView(value:context.state.progress).tint(downloadPurple)
                if context.state.failed > 0 { Text("\(context.state.failed) need attention · Open Downloads to retry").font(.caption2).foregroundStyle(.orange) }
            }.padding(16).activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string:"cortexanime-native-port://downloads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("CORTEX",systemImage:"arrow.down.circle.fill").font(.caption.bold()).foregroundStyle(downloadPurple) }
                DynamicIslandExpandedRegion(.trailing) { Text("\(context.state.completed)/\(context.state.total)").font(.caption.bold().monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment:.leading,spacing:7) {
                        Text(context.state.title).font(.subheadline.bold()).lineLimit(1)
                        HStack { Text("EP \(context.state.episode) · \(context.isStale ? "Open app to update" : context.state.phase)").lineLimit(1);Spacer();Text("\(Int(context.state.progress*100))%").monospacedDigit() }.font(.caption)
                        ProgressView(value:context.state.progress).tint(downloadPurple)
                    }.padding(.bottom,5)
                }
            } compactLeading: {
                Image(systemName:context.state.phase == "Complete" ? "checkmark.circle.fill" : "arrow.down.circle.fill").foregroundStyle(downloadPurple)
            } compactTrailing: {
                Text("\(Int(context.state.progress*100))%").font(.caption2.bold().monospacedDigit()).foregroundStyle(downloadPurple)
            } minimal: {
                Gauge(value:context.state.progress) { Image(systemName:"arrow.down") }.gaugeStyle(.accessoryCircularCapacity).tint(downloadPurple)
            }.widgetURL(URL(string:"cortexanime-native-port://downloads")).keylineTint(downloadPurple)
        }
    }
}
