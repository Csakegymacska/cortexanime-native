import SwiftUI
import UIKit
import MediaPlayer

// Volume access for the vertical swipe: the system slider inside a hidden MPVolumeView.
@MainActor final class SystemVolumeController {
    static let shared = SystemVolumeController()
    private var volumeView: MPVolumeView?
    private var slider: UISlider?
    func attach(to host: UIView) {
        guard volumeView == nil else { return }
        let view = MPVolumeView(frame: CGRect(x: -2, y: -2, width: 1, height: 1))
        view.alpha = 0.01
        host.addSubview(view)
        volumeView = view
        slider = view.subviews.compactMap { $0 as? UISlider }.first
    }
    var value: Float {
        get { slider?.value ?? AVAudioSession.sharedInstance().outputVolume }
        set { slider?.value = max(0, min(1, newValue)) }
    }
}

enum PlayerHUDKind: Equatable {
    case seek(String)
    case volume(Double)
    case brightness(Double)
}

struct PlayerHUD: View {
    let kind: PlayerHUDKind
    var body: some View {
        HStack(spacing: 10) {
            switch kind {
            case .seek(let text):
                Image(systemName: "forward.fill").font(.title3)
                Text(text).font(.system(size: 17, weight: .bold, design: .monospaced))
            case .volume(let v):
                Image(systemName: v <= 0.01 ? "speaker.slash.fill" : "speaker.wave.3.fill").font(.title3)
                bar(Double(v))
            case .brightness(let v):
                Image(systemName: "sun.max.fill").font(.title3)
                bar(v)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 13)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: 220)
        .transition(.opacity)
    }
    private func bar(_ v: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(.white).frame(width: max(4, geo.size.width * min(1, max(0, v))))
            }
        }
        .frame(height: 6)
    }
}

struct SeekFlash: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
            .transition(.scale.combined(with: .opacity))
    }
}

// UIKit recognizers: single tap, double tap (left/right half = -10s / +10s),
// horizontal pan = scrub, vertical pan = brightness (left) / volume (right).
struct PlayerGestureView: UIViewRepresentable {
    var toggleChrome: () -> Void
    var seekBy: (Double) -> Void
    var scrubStart: () -> Void
    var scrubTo: (Double) -> Void
    var scrubEnd: () -> Void
    var hud: (PlayerHUDKind) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        SystemVolumeController.shared.attach(to: view)
        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor final class Coordinator: NSObject {
        var parent: PlayerGestureView
        weak var hostView: UIView?
        private var mode: Mode = .none
        private var seekAnchor = 0.0
        private var scrubValue = 0.0
        private var brightnessAnchor: CGFloat = 0
        private var volumeAnchor: Float = 0
        private var hudWork: DispatchWorkItem?

        enum Mode { case none, scrub, brightness, volume }

        init(_ parent: PlayerGestureView) { self.parent = parent }

        @objc func handleSingleTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended else { return }
            parent.toggleChrome()
        }

        @objc func handleDoubleTap(_ gr: UITapGestureRecognizer) {
            guard gr.state == .ended, let view = gr.view else { return }
            let left = gr.location(in: view).x < view.bounds.midX
            let step = PlaybackPrefs8.seekStep
            parent.seekBy(left ? -step : step)
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view = gr.view else { return }
            let translation = gr.translation(in: view)
            switch gr.state {
            case .began:
                let horizontal = abs(translation.x) >= abs(translation.y)
                if horizontal {
                    mode = .scrub
                    seekAnchor = 0
                    parent.scrubStart()
                } else {
                    let left = gr.location(in: view).x < view.bounds.midX
                    mode = left ? .brightness : .volume
                    brightnessAnchor = UIScreen.main.brightness
                    volumeAnchor = SystemVolumeController.shared.value
                }
            case .changed:
                switch mode {
                case .scrub:
                    let seconds = Double(translation.x) / 12.0
                    parent.scrubTo(seconds)
                case .brightness:
                    let delta = Double(-translation.y) / 320.0
                    let value = min(1, max(0, Double(brightnessAnchor) + delta))
                    UIScreen.main.brightness = CGFloat(value)
                    parent.hud(.brightness(value))
                case .volume:
                    let delta = Float(-translation.y) / 320.0
                    let value = min(1, max(0, Double(volumeAnchor) + Double(delta)))
                    SystemVolumeController.shared.value = Float(value)
                    parent.hud(.volume(value))
                case .none:
                    break
                }
            case .ended, .cancelled, .failed:
                if mode == .scrub { parent.scrubEnd() }
                mode = .none
            default:
                break
            }
        }
    }
}
