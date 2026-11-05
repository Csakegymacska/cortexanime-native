import SwiftUI

/// 4.0 subtitle presentation options. Device-local, applied to every caption track.
enum CaptionBackground: String, CaseIterable, Identifiable {
    case box, outline, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .box: return "Box"
        case .outline: return "Outline"
        case .none: return "None"
        }
    }
    var detail: String {
        switch self {
        case .box: return "Solid dark plate behind the text. Easiest to read."
        case .outline: return "Text with a heavy shadow, no plate."
        case .none: return "Plain white text."
        }
    }
}

enum CaptionPosition: String, CaseIterable, Identifiable {
    case low, standard, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "Low"
        case .standard: return "Standard"
        case .high: return "High"
        }
    }
    /// Extra distance from the bottom edge, in points, before the playback controls.
    var extraBottomPadding: CGFloat {
        switch self {
        case .low: return 0
        case .standard: return 26
        case .high: return 78
        }
    }
}

enum CaptionStyle {
    static let backgroundKey = "player.captionBackground"
    static let positionKey = "player.captionPosition"

    static func background(_ raw: String) -> CaptionBackground { CaptionBackground(rawValue: raw) ?? .box }
    static func position(_ raw: String) -> CaptionPosition { CaptionPosition(rawValue: raw) ?? .standard }
}

/// Small live preview used in the player settings sheet.
struct CaptionStylePreview: View {
    let background: CaptionBackground
    let position: CaptionPosition
    let size: Double

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color.cortexPanel, Color.black], startPoint: .top, endPoint: .bottom)
            VStack {
                Spacer(minLength: 0)
                StyledCaptionText(text: AppLanguage.text(en: "This is how the caption will look.", hu: "Így fog kinézni a felirat."), background: background, fontSize: size)
                    .padding(.bottom, 10 + min(46, position.extraBottomPadding))
            }
            VStack {
                Spacer(minLength: 0)
                HStack { Image(systemName: "gobackward.10"); Spacer(); Image(systemName: "pause.fill"); Spacer(); Image(systemName: "goforward.10") }
                    .font(.footnote).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 26).padding(.bottom, 8)
            }
        }
        .frame(height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subtitle preview: \(background.title) background, \(position.title) position")
    }
}

/// The single rendering rule shared by the preview and the real player overlay.
struct StyledCaptionText: View {
    let text: String
    let background: CaptionBackground
    var fontSize: Double = SubtitleSizePolicy.defaultSize

    var body: some View {
        Text(text)
            .font(.system(size: CGFloat(SubtitleSizePolicy.clamped(fontSize)), weight: .semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, background == .box ? 10 : 2)
            .padding(.vertical, background == .box ? 6 : 0)
            .background {
                switch background {
                case .box: RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.8))
                case .outline, .none: Color.clear
                }
            }
            .shadow(color: background == .none ? .black.opacity(0.55) : .black, radius: background == .outline ? 3 : 2)
    }
}
