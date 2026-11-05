import Foundation
import ActivityKit

struct DownloadActivityAttributes: ActivityAttributes {
    struct ContentState: Codable,Hashable {
        var title: String
        var episode: Int
        var completed: Int
        var total: Int
        var failed: Int
        var progress: Double
        var phase: String
    }
    var identifier: String
}
