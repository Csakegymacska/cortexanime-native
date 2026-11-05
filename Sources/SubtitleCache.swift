import Foundation
import CryptoKit

/// Caption-only app sandbox cache, not a video/source availability guarantee.
enum SubtitleCache {
    static let folder = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NativeCaptions",isDirectory:true)
    static func file(for source: URL) -> URL { let key = SHA256.hash(data:Data(source.absoluteString.utf8)).map { String(format:"%02x",$0) }.joined();return folder.appendingPathComponent(key+".vtt") }
    static func load(_ source: URL) -> Data? { let target = file(for:source);guard let data = try? Data(contentsOf:target),data.count <= 2_000_000,let text = String(data:data,encoding:.utf8),!WebVTT.parse(text).isEmpty else { return nil };return data }
    @discardableResult static func save(_ data: Data,source: URL) throws -> URL {
        guard data.count <= 2_000_000,let text = String(data:data,encoding:.utf8),!WebVTT.parse(text).isEmpty else { throw AppFailure.message("Only valid caption files up to 2 MB can be saved.") }
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target = file(for:source);try data.write(to:target,options:.atomic)
        let files = (try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.contentModificationDateKey,.fileSizeKey])) ?? []
        let sorted = files.sorted { ((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        var total = sorted.reduce(0) { $0+((try? $1.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0) };var count = sorted.count
        for old in sorted where old != target { if total <= 20_000_000 && count <= 80 { break };total -= (try? old.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0;count -= 1;try? FileManager.default.removeItem(at:old) }
        return target
    }
}
