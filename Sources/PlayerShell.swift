import SwiftUI

/// 6.7: CortexPlayer chrome, rebuilt.
///
/// The old player stacked eight equal-weight buttons in one row under the scrubber, and the
/// settings lived in a stock Form — it read as a utility screen, not as the app. This file keeps
/// the playback engine (`Playback`) and the gestures untouched and replaces only the surround:
///
///  - a glass highlight capsule at the top of the scrubber instead of a system slider
///  - a centred row where play is the only big control, ±10 s flank it, and the rest is quiet
///  - a bottom sheet with three tabs (episode · subtitles · playback) instead of a long Form
///  - the "up next" and end cards use the same glass, inside safe-area padding
struct PlayerGlass: ViewModifier {
    var radius: CGFloat = 20
    var stroke: Double = 0.10
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(stroke), lineWidth: 1))
    }
}

extension View {
    func playerGlass(radius: CGFloat = 20, stroke: Double = 0.10) -> some View {
        modifier(PlayerGlass(radius: radius, stroke: stroke))
    }
}

/// The scrubber: a thin track, a bright played segment, chapter notches and a knob that grows
/// while dragging. It replaces the `Slider`, which on dark video looked like a settings row.
struct PlayerScrubber: View {
    @Binding var value: Double
    let duration: Double
    let chapters: [Double]
    var onEditingChanged: (Bool) -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progress = duration > 0 ? min(1, max(0, value / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18)).frame(height: dragging ? 8 : 5)
                Capsule()
                    .fill(LinearGradient(colors: [Color.cortexPurple, Color.cortexPurple.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: progress * width, height: dragging ? 8 : 5)
                ForEach(chapters, id: \.self) { start in
                    if duration > 0, start > 0, start < duration {
                        Capsule().fill(.white.opacity(0.55))
                            .frame(width: 2, height: 9)
                            .offset(x: min(width - 2, max(0, width * start / duration)))
                    }
                }
                Circle()
                    .fill(.white)
                    .frame(width: dragging ? 18 : 13, height: dragging ? 18 : 13)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: min(max(0, progress * width - (dragging ? 9 : 6.5)), max(0, width - (dragging ? 18 : 13))))
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true; onEditingChanged(true) }
                        let ratio = min(1, max(0, gesture.location.x / width))
                        value = ratio * max(1, duration)
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: dragging)
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(clock(value)) of \(clock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(duration, value + 15)
            case .decrement: value = max(0, value - 15)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }

    private func clock(_ raw: Double) -> String {
        let safe = raw.isFinite ? max(0, Int(raw)) : 0
        return safe >= 3600
            ? String(format: "%d:%02d:%02d", safe / 3600, (safe / 60) % 60, safe % 60)
            : String(format: "%02d:%02d", safe / 60, safe % 60)
    }
}

/// Small glass circle used for every secondary control, so they all read as one family.
struct PlayerCircleButton: View {
    let systemImage: String
    var size: CGFloat = 42
    var disabled = false
    var label: String
    var identifier: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(.white.opacity(disabled ? 0.3 : 0.95))
                .background(.white.opacity(disabled ? 0.04 : 0.10), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .modifier(OptionalIdentifier(identifier))
    }
}

/// The big white play/pause, 68 pt, with the purple glow behind it.
struct PlayerPlayButton: View {
    let playing: Bool
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.cortexPurple.opacity(0.35)).frame(width: 86, height: 86).blur(radius: 14)
                Circle().fill(.white).frame(width: 68, height: 68)
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.black)
                    .offset(x: playing ? 0 : 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(playing ? "Pause playback" : "Resume playback")
        .accessibilityIdentifier("player.togglePlayback")
    }
}

/// One row of the bottom sheet.
struct PlayerSheetRow<Trailing: View>: View {
    let title: String
    var systemImage: String? = nil
    var detail: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .foregroundStyle(.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

/// Episode queue card: the current episode plus the next one, so "what am I watching" is
/// answered without opening settings.
struct PlayerQueueCard: View {
    let title: String
    let episodeLabel: String
    let nextLabel: String?
    let hasNext: Bool
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(episodeLabel.isEmpty ? "Now playing" : episodeLabel)
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.cortexPurple)
                    .lineLimit(1)
                if let nextLabel {
                    Text("Next · \(nextLabel)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            PlayerCircleButton(systemImage: "forward.end.fill", size: 38, disabled: !hasNext, label: "Next episode", identifier: "player.nextEpisode") { onNext() }
        }
        .padding(12)
        .playerGlass(radius: 18, stroke: 0.08)
    }
}

/// Applies an accessibility identifier only when one was given, so an empty string never
/// wipes out the label-based lookup the UI tests use.
struct OptionalIdentifier: ViewModifier {
    let value: String?
    init(_ value: String?) { self.value = value }
    func body(content: Content) -> some View {
        if let value { content.accessibilityIdentifier(value) } else { content }
    }
}
