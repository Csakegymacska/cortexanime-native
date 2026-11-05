import Foundation
import ActivityKit
import UIKit

@MainActor final class DownloadLiveStatus {
    private var lastUpdate = Date.distantPast
    private var lastPhase = ""
    private var pending: Task<Void,Never>?
    private var revision = 0
    private var lastRequestedBatch: String?
    func refresh(_ items: [DownloadItem]) {
        let relevant = items.filter { $0.batchID != nil }
        if relevant.isEmpty {
            pending?.cancel();revision += 1;lastRequestedBatch = nil
            let old = Activity<DownloadActivityAttributes>.activities
            Task { for activity in old { await activity.end(nil,dismissalPolicy:.immediate) } };return
        }
        guard let batch = relevant.first(where:{ DownloadQueuePolicy.activeStates.contains($0.state) || $0.state == "queued" })?.batchID ?? relevant.last?.batchID else { return }
        let rows = relevant.filter { $0.batchID == batch }
        let current = rows.first(where:{ DownloadQueuePolicy.activeStates.contains($0.state) }) ?? rows.first(where:{ $0.state == "queued" }) ?? rows.first(where:{ $0.state == "paused" }) ?? rows.first!
        // iOS 27 supplies its own aggregated HLS download Live Activity.
        // Do not show a second branded activity next to that system-owned one.
        if #available(iOS 27.0,*),current.mediaKind == "hls",DownloadQueuePolicy.activeStates.contains(current.state) {
            pending?.cancel();lastRequestedBatch = nil
            Task { for activity in Activity<DownloadActivityAttributes>.activities { await activity.end(nil,dismissalPolicy:.immediate) } };return
        }
        let completed = rows.filter { $0.state == "downloaded" }.count,failed = rows.filter { $0.state == "failed" }.count
        let ongoing = rows.contains { DownloadQueuePolicy.activeStates.contains($0.state) || $0.state == "queued" || $0.state == "paused" }
        let phase = !ongoing ? (failed == 0 ? "Complete" : "Finished with errors") : current.statusLabel
        let progress = rows.reduce(0.0) { $0+($1.state == "downloaded" ? 1 : min(1,max(0,$1.progress))) }/Double(max(1,rows.count))
        let state = DownloadActivityAttributes.ContentState(title:String(current.title.prefix(180)),episode:current.episode,completed:completed,total:rows.count,failed:failed,progress:progress,phase:phase)
        guard phase != lastPhase || Date().timeIntervalSince(lastUpdate) >= 4 || !ongoing else { return }
        lastPhase = phase;lastUpdate = Date();revision += 1;let version = revision
        pending?.cancel()
        pending = Task { @MainActor in
            guard version == self.revision,!Task.isCancelled else { return }
            let content = ActivityContent(state:state,staleDate:Date().addingTimeInterval(90))
            var activity = Activity<DownloadActivityAttributes>.activities.first
            if activity == nil,ongoing,UIApplication.shared.applicationState == .active,ActivityAuthorizationInfo().areActivitiesEnabled,self.lastRequestedBatch != batch {
                do { activity = try Activity.request(attributes:DownloadActivityAttributes(identifier:"offline-downloads"),content:content,pushType:nil);self.lastRequestedBatch = batch } catch { return }
            }
            guard let activity else { return }
            if ongoing { await activity.update(content) }
            else { await activity.end(content,dismissalPolicy:.after(Date().addingTimeInterval(60))) }
        }
    }
}
