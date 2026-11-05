import Foundation
import Combine

// Device-local preference shared by streamed and downloaded sidecar captions.
enum SubtitleSizePolicy {
    static let defaultSize = 20.0
    static let minimum = 14.0
    static let maximum = 40.0
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSize }
        return min(maximum, max(minimum, value))
    }
}

// A cancellable, one-shot timer. Playback ticks must NOT reset this timer.
@MainActor final class PlayerChromeState: ObservableObject {
    @Published private(set) var visible = true
    private var eligible = false
    private var timer: Task<Void, Never>?
    private let delay: Duration
    init(delay: Duration = .seconds(3)) { self.delay = delay }
    deinit { timer?.cancel() }

    func update(playing: Bool, scrubbing: Bool = false, settingsOpen: Bool = false,
                partyOpen: Bool = false, voiceOver: Bool = false, active: Bool = true) {
        eligible = playing && !scrubbing && !settingsOpen && !partyOpen && !voiceOver && active
        interacted()
    }
    func interacted() {
        visible = true
        arm()
    }
    func toggleFromVideo() {
        if visible && eligible { visible = false; cancel() }
        else { interacted() }
    }
    func cancel() { timer?.cancel(); timer = nil }
    private func arm() {
        cancel()
        guard eligible, visible else { return }
        let delay = delay
        timer = Task { [weak self] in
            do { try await Task.sleep(for: delay); try Task.checkCancellation() }
            catch { return }
            guard let self, self.eligible else { return }
            self.visible = false
            self.timer = nil
        }
    }
}
