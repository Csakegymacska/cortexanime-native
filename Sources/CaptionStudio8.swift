import SwiftUI

// MARK: - 8.0 · Caption studio
//
// The player already had size, plate style and position. 8.0 adds the four
// things people ask for next: colour, weight, plate opacity and line width.
// The same values drive the real overlay and the preview, so what you see in
// the settings sheet is literally what is drawn over the video.

enum CaptionPalette8: String, CaseIterable, Identifiable {
    case white, amber, cyan, lime, rose, ice
    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return "White"
        case .amber: return "Amber"
        case .cyan: return "Cyan"
        case .lime: return "Lime"
        case .rose: return "Rose"
        case .ice: return "Ice"
        }
    }

    var color: Color {
        switch self {
        case .white: return .white
        case .amber: return Color(red: 1.00, green: 0.82, blue: 0.35)
        case .cyan: return Color(red: 0.45, green: 0.90, blue: 1.00)
        case .lime: return Color(red: 0.72, green: 0.96, blue: 0.45)
        case .rose: return Color(red: 1.00, green: 0.62, blue: 0.76)
        case .ice: return Color(red: 0.78, green: 0.88, blue: 1.00)
        }
    }
}

enum CaptionWidth8: String, CaseIterable, Identifiable {
    case narrow, standard, wide
    var id: String { rawValue }

    var title: String {
        switch self {
        case .narrow: return "Narrow"
        case .standard: return "Standard"
        case .wide: return "Wide"
        }
    }

    /// Extra side padding inside the video frame.
    var inset: CGFloat {
        switch self {
        case .narrow: return 54
        case .standard: return 16
        case .wide: return 4
        }
    }
}

enum CaptionPrefs8 {
    static let colorKey = "player.captionColor8"
    static let boldKey = "player.captionBold8"
    static let plateKey = "player.captionPlate8"
    static let widthKey = "player.captionWidth8"

    static func palette(_ raw: String) -> CaptionPalette8 { CaptionPalette8(rawValue: raw) ?? .white }
    static func width(_ raw: String) -> CaptionWidth8 { CaptionWidth8(rawValue: raw) ?? .standard }
}

struct CaptionStudio8View: View {
    @AppStorage(CaptionPrefs8.colorKey) private var color = CaptionPalette8.white.rawValue
    @AppStorage(CaptionPrefs8.boldKey) private var bold = true
    @AppStorage(CaptionPrefs8.plateKey) private var plate = 0.80
    @AppStorage(CaptionPrefs8.widthKey) private var width = CaptionWidth8.standard.rawValue
    @AppStorage("player.captionBackground") private var background = CaptionBackground.box.rawValue
    @AppStorage("player.captionPosition") private var position = CaptionPosition.standard.rawValue
    @AppStorage("player.subtitleSize") private var size = SubtitleSizePolicy.defaultSize

    private var palette: CaptionPalette8 { CaptionPrefs8.palette(color) }
    private var wide: CaptionWidth8 { CaptionPrefs8.width(width) }

    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottom) {
                    LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.16), .black],
                                   startPoint: .top, endPoint: .bottom)
                    Text("Így fog kinézni a felirat.")
                        .font(.system(size: CGFloat(SubtitleSizePolicy.clamped(size)), weight: bold ? .bold : .semibold))
                        .foregroundStyle(palette.color)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, CaptionStyle.background(background) == .box ? 10 : 2)
                        .padding(.vertical, CaptionStyle.background(background) == .box ? 6 : 0)
                        .background {
                            if CaptionStyle.background(background) == .box {
                                RoundedRectangle(cornerRadius: 7).fill(.black.opacity(plate))
                            }
                        }
                        .shadow(color: .black, radius: 2)
                        .padding(.horizontal, wide.inset)
                        .padding(.bottom, 18)
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            Section("Colour") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                    ForEach(CaptionPalette8.allCases) { item in
                        Button { color = item.rawValue } label: {
                            VStack(spacing: 5) {
                                Circle().fill(item.color).frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(.secondary.opacity(color == item.rawValue ? 0.9 : 0.15),
                                                             lineWidth: color == item.rawValue ? 2 : 1))
                                Text(item.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("caption8.color." + item.rawValue)
                    }
                }
                .padding(.vertical, 2)
                Text("Yellow and cyan stay readable on bright scenes; white is the classic look.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Text") {
                Toggle("Bold captions", isOn: $bold)
                    .accessibilityIdentifier("caption8.bold")
                Slider(value: $size, in: SubtitleSizePolicy.minimum...SubtitleSizePolicy.maximum, step: 1) {
                    Text("Size")
                }
                Text("\(Int(SubtitleSizePolicy.clamped(size))) pt").font(.caption).foregroundStyle(.secondary)
                Picker("Line width", selection: $width) {
                    ForEach(CaptionWidth8.allCases) { item in Text(item.title).tag(item.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("caption8.width")
            }

            Section("Plate") {
                Picker("Background", selection: $background) {
                    ForEach(CaptionBackground.allCases) { item in Text(item.title).tag(item.rawValue) }
                }
                .pickerStyle(.segmented)
                if CaptionStyle.background(background) == .box {
                    Slider(value: $plate, in: 0.30...1.0, step: 0.05) { Text("Plate opacity") }
                    Text("Plate \(Int(plate * 100))% opaque").font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("caption8.plate")
                }
                Picker("Position", selection: $position) {
                    ForEach(CaptionPosition.allCases) { item in Text(item.title).tag(item.rawValue) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Reset captions to defaults") {
                    color = CaptionPalette8.white.rawValue
                    bold = true
                    plate = 0.80
                    width = CaptionWidth8.standard.rawValue
                    background = CaptionBackground.box.rawValue
                    position = CaptionPosition.standard.rawValue
                    size = SubtitleSizePolicy.defaultSize
                }
            }
        }
        .navigationTitle("Subtitles")
    }
}
