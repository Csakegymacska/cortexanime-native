import Foundation

/// One subtitle line. Timings are exactly the ones in the VTT file —
/// the pipeline never shifts them, so the player must not either.
struct TVSubtitleCue: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

enum TVVTT {
    /// Parses WebVTT. Ignores NOTE/STYLE blocks, cue settings and the cue identifier line.
    static func parse(_ source: String) -> [TVSubtitleCue] {
        let normalised = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [TVSubtitleCue] = []
        let blocks = normalised.components(separatedBy: "\n\n")
        var identifier = 0

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0) }
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard !lines.isEmpty else { continue }
            if let first = lines.first,
               first.hasPrefix("WEBVTT") || first.hasPrefix("NOTE") || first.hasPrefix("STYLE") || first.hasPrefix("REGION") {
                continue
            }
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let parts = timing.components(separatedBy: "-->")
            guard parts.count >= 2 else { continue }
            guard let start = seconds(parts[0]), let end = seconds(parts[1]) else { continue }
            guard timingIndex + 1 < lines.count else { continue }
            let text = lines[(timingIndex + 1)...]
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, end > start else { continue }
            identifier += 1
            cues.append(TVSubtitleCue(id: identifier, start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "00:01:23.456", "01:23.456" or "0:01:23,456" -> seconds.
    static func seconds(_ raw: String) -> Double? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ").first ?? ""
        let normalised = cleaned.replacingOccurrences(of: ",", with: ".")
        let pieces = normalised.split(separator: ":")
        var total: Double = 0
        for piece in pieces {
            guard let value = Double(piece) else { return nil }
            total = total * 60 + value
        }
        return total.isFinite ? total : nil
    }
}

/// Finds the cue covering a playback position. Cues may overlap, so it returns
/// every cue that covers the moment and joins them like the website does.
struct TVSubtitleTimeline {
    let cues: [TVSubtitleCue]

    init(cues: [TVSubtitleCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    func text(at time: Double) -> String? {
        guard !cues.isEmpty else { return nil }
        var matched: [String] = []
        for cue in cues {
            if cue.start > time { break }
            if time >= cue.start && time <= cue.end {
                matched.append(cue.text)
            }
        }
        guard !matched.isEmpty else { return nil }
        return matched.joined(separator: "\n")
    }

    var isEmpty: Bool { cues.isEmpty }
}
