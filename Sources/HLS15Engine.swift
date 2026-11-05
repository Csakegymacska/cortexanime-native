import Foundation
import AVFoundation

// MARK: - 1.5.2 · Offline HLS, downloaded by us
//
// Why this exists: the app used AVAssetDownloadTask for HLS. That API insists on
// recognising the media type from the URL, and every stream CortexAnime serves
// comes from /api/hls-proxy?tk=… — no .m3u8 extension — so the task failed before
// a single byte moved, or produced a .movpkg the player refused to open. The fix
// is not another workaround around AVFoundation: it is to download the playlist
// ourselves, segment by segment, and hand the player a local playlist whose
// segment names are plain file names.
//
// What that buys, beyond actually working:
//   · byte-exact progress instead of time-range guesses,
//   · resume after a cold launch (finished segments are skipped),
//   · a real reason for every failure, with per-segment retries,
//   · no .movpkg, so nothing can be "cleared by the system" behind our back.

enum DownloadQuality15: String, CaseIterable, Identifiable {
    case auto, high, saver

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .high: return "Best"
        case .saver: return "Saver"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Up to 720p — the balance most phones want."
        case .high: return "The highest variant the source offers. Largest files."
        case .saver: return "The smallest variant, roughly a third of the size."
        }
    }

    /// Upper bandwidth bound used when picking a variant.
    var cap: Int? {
        switch self {
        case .auto: return 3_200_000
        case .high: return nil
        case .saver: return 1_000_000
        }
    }

    static var current: DownloadQuality15 {
        DownloadQuality15(rawValue: UserDefaults.standard.string(forKey: "downloads.quality15") ?? "") ?? .auto
    }
}

struct HLS15Variant {
    let bandwidth: Int
    let resolution: String
    let url: URL
}

@MainActor final class HLS15Engine {
    static let shared = HLS15Engine()

    private var cancelled = Set<UUID>()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    // MARK: cancellation

    func begin(_ id: UUID) { cancelled.remove(id) }
    func cancel(_ id: UUID) { cancelled.insert(id) }
    func isCancelled(_ id: UUID) -> Bool { cancelled.contains(id) }

    // MARK: verification used by the player and the library

    /// A folder is ready when it has a playlist with an end marker and at least one segment.
    static func verify(folder: URL) -> Bool {
        let index = folder.appendingPathComponent("index.m3u8")
        guard let text = try? String(contentsOf: index, encoding: .utf8),
              text.hasPrefix("#EXTM3U"),
              text.contains("#EXT-X-ENDLIST") else { return false }
        // Substring nem tudja a Foundation String-metódusokat, ezért előbb String lesz.
        let segments: [String] = text.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !segments.isEmpty else { return false }
        for name in segments {
            guard OfflineStorage.bytes(at: folder.appendingPathComponent(name)) > 0 else { return false }
        }
        return true
    }

    static func planSummary(folder: URL) -> String? {
        let meta = folder.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: meta),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let resolution = row["resolution"] as? String ?? ""
        let segments = row["segments"] as? Int ?? 0
        guard segments > 0 else { return nil }
        return resolution.isEmpty ? "\(segments) segments" : "\(resolution) · \(segments) segments"
    }

    // MARK: download

    /// Downloads every segment into `folder`, then writes `index.m3u8` and returns it.
    /// Safe to call again after a cancellation: segments already on disk are skipped.
    func download(id: UUID,
                  info: StreamInfo,
                  quality: DownloadQuality15,
                  folder: URL,
                  progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        begin(id)
        let source = try OfflineSource.candidate(info)
        let (lines, segments, initURI, detail) = try await prepare(source, quality: quality, id: id)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? OfflineStorage.protect(folder)

        if let initURI {
            let destination = folder.appendingPathComponent("init.mp4")
            if OfflineStorage.bytes(at: destination) == 0 {
                let data = try await fetch(initURI, id: id)
                try data.write(to: destination, options: .atomic)
            }
        }

        var completed = 0
        for (index, segment) in segments.enumerated() {
            if isCancelled(id) { throw CancellationError() }
            // 20 szegmensenként megnézzük a szabad helyet: ne a lemez betöltésénél derüljön ki.
            if index % 20 == 0 {
                let values = try? OfflineFiles.mediaFolder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let free = values?.volumeAvailableCapacityForImportantUsage, free < 200 * 1024 * 1024 {
                    throw AppFailure.message("Less than 200 MB is left on the device. Free some space, then resume this download — it continues where it stopped.")
                }
            }
            let destination = folder.appendingPathComponent(Self.name(for: index))
            if OfflineStorage.bytes(at: destination) > 0 {
                completed += 1
                progress(Double(completed) / Double(max(1, segments.count)))
                continue
            }
            var lastError: Error = AppFailure.message("The stream server stopped answering.")
            var saved = false
            for attempt in 0..<3 {
                if isCancelled(id) { throw CancellationError() }
                do {
                    let data = try await fetch(segment, id: id)
                    if initURI == nil, data.first != 0x47, data.count > 188 {
                        throw AppFailure.message("The segment was truncated.")
                    }
                    try data.write(to: destination, options: .atomic)
                    saved = true
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    lastError = error
                    try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
                }
            }
            guard saved else { throw lastError }
            completed += 1
            progress(Double(completed) / Double(max(1, segments.count)))
        }

        // Local playlist: the same lines, with segment names instead of token URLs.
        var out: [String] = []
        var cursor = 0
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-MAP") {
                out.append("#EXT-X-MAP:URI=\"init.mp4\"")
            } else if line.isEmpty || line.hasPrefix("#") {
                out.append(raw)
            } else {
                out.append(Self.name(for: cursor))
                cursor += 1
            }
        }
        let index = folder.appendingPathComponent("index.m3u8")
        try Data(out.joined(separator: "\n").utf8).write(to: index, options: .atomic)
        try? OfflineStorage.protect(index)

        let meta: [String: Any] = [
            "source": source.absoluteString,
            "quality": quality.rawValue,
            "bandwidth": detail.bandwidth,
            "resolution": detail.resolution,
            "segments": segments.count,
            "bytes": OfflineStorage.bytes(at: folder),
            "savedAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("meta.json"), options: .atomic)
        }
        progress(1)
        return index
    }

    // MARK: playlist preparation

    private struct Detail {
        let bandwidth: Int
        let resolution: String
    }

    private func prepare(_ source: URL,
                         quality: DownloadQuality15,
                         id: UUID) async throws -> (lines: [String], segments: [URL], map: URL?, detail: Detail) {
        let masterText = String(decoding: try await fetch(source, id: id), as: UTF8.self)
        var playlistText = masterText
        var playlistURL = source
        var detail = Detail(bandwidth: 0, resolution: "")

        let variants = Self.parseMaster(masterText, base: source)
        if !variants.isEmpty {
            let chosen = Self.choose(variants, quality: quality)
            playlistURL = chosen.url
            detail = Detail(bandwidth: chosen.bandwidth, resolution: chosen.resolution)
            playlistText = String(decoding: try await fetch(chosen.url, id: id), as: UTF8.self)
        }

        let lines = playlistText.components(separatedBy: .newlines)
        guard playlistText.hasPrefix("#EXTM3U") else {
            throw AppFailure.message("The source did not return an HLS playlist.")
        }
        for line in lines {
            if line.hasPrefix("#EXT-X-KEY"), !line.contains("METHOD=NONE") {
                throw AppFailure.message("This stream is encrypted for playback only, so it cannot be saved offline.")
            }
            if line.hasPrefix("#EXT-X-BYTERANGE") {
                throw AppFailure.message("This stream splits one file into byte ranges, which this downloader does not save. Pick another source.")
            }
        }
        guard playlistText.contains("#EXT-X-ENDLIST") else {
            throw AppFailure.message("This is a live or unfinished stream, so there is nothing complete to save yet.")
        }

        var mapURI: URL?
        var segments: [URL] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-MAP") {
                if let range = trimmed.range(of: "URI=\"") {
                    let rest = trimmed[range.upperBound...]
                    if let end = rest.firstIndex(of: "\"") {
                        let raw = String(rest[..<end])
                        mapURI = URL(string: raw, relativeTo: playlistURL)?.absoluteURL
                    }
                }
            } else if !trimmed.isEmpty, !trimmed.hasPrefix("#") {
                if let url = URL(string: trimmed, relativeTo: playlistURL)?.absoluteURL {
                    segments.append(url)
                }
            }
        }
        guard !segments.isEmpty else {
            throw AppFailure.message("The playlist lists no segments, so this episode cannot be saved.")
        }
        return (lines, segments, mapURI, detail)
    }

    static func parseMaster(_ text: String, base: URL) -> [HLS15Variant] {
        let lines = text.components(separatedBy: .newlines)
        var out: [HLS15Variant] = []
        for (index, raw) in lines.enumerated() where raw.hasPrefix("#EXT-X-STREAM-INF") {
            var bandwidth = 0
            var resolution = ""
            let attributes = raw.replacingOccurrences(of: "#EXT-X-STREAM-INF:", with: "").split(separator: ",").map { String($0) }
            for attribute in attributes {
                let parts = attribute.split(separator: "=", maxSplits: 1).map { String($0) }
                guard parts.count == 2 else { continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].replacingOccurrences(of: "\"", with: "")
                if key == "BANDWIDTH" { bandwidth = Int(value) ?? 0 }
                if key == "RESOLUTION" { resolution = value }
            }
            guard let uri = lines.dropFirst(index + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix("#") }),
                  let url = URL(string: uri.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL else { continue }
            out.append(HLS15Variant(bandwidth: bandwidth, resolution: resolution, url: url))
        }
        return out
    }

    static func choose(_ variants: [HLS15Variant], quality: DownloadQuality15) -> HLS15Variant {
        guard let cap = quality.cap else {
            return variants.max { $0.bandwidth < $1.bandwidth } ?? variants[0]
        }
        let fitting = variants.filter { $0.bandwidth <= cap }
        return fitting.max { $0.bandwidth < $1.bandwidth } ?? variants.min { $0.bandwidth < $1.bandwidth } ?? variants[0]
    }

    static func name(for index: Int) -> String {
        String(format: "seg%05d.ts", index)
    }

    // MARK: one HTTP fetch, with the caller's cancellation respected

    private func fetch(_ url: URL, id: UUID) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if isCancelled(id) { throw CancellationError() }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 403 {
                throw AppFailure.message("The stream link expired before the episode finished. Start the download again to get a fresh link.")
            }
            throw AppFailure.message("The stream server returned HTTP \(http.statusCode).")
        }
        guard !data.isEmpty else { throw AppFailure.message("The stream server returned an empty response.") }
        return data
    }
}
