import Foundation

/// Durable app data, not URLCache. Old download indexes remain decodable.
enum OfflineStorage {
    static func protect(_ url: URL) throws {
        var target = url
        var values = URLResourceValues();values.isExcludedFromBackup = true
        try target.setResourceValues(values)
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:url.path)
    }
    static func ensureFolder(_ url: URL) throws {
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        try protect(url)
    }
    static func captions(_ data: Data) -> Bool {
        guard data.count <= 2_000_000,let text = String(data:data,encoding:.utf8) else { return false }
        return !WebVTT.parse(text).isEmpty
    }
    static func bytes(at url: URL) -> Int64 {
        if (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) != true {
            return ((try? FileManager.default.attributesOfItem(atPath:url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        }
        let enumerator = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey])
        var total:Int64 = 0
        while let child = enumerator?.nextObject() as? URL {
            if let values = try? child.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]),values.isRegularFile == true,values.isSymbolicLink != true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    // Local media is ready when a plain file is non-empty, or an HLS .movpkg package
    // contains a playlist. This runs independently of assetCache, which is unreliable
    // for local packages.
    static func localMediaReady(_ url: URL) -> Bool {
        let isDirectory = (try? url.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true
        guard bytes(at:url) > 0 else { return false }
        if !isDirectory { return true }
        let enumerator = FileManager.default.enumerator(at:url,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles])
        while let child = enumerator?.nextObject() as? URL {
            if child.pathExtension.lowercased() == "m3u8" { return true }
        }
        return false
    }
    static func requireSpace(_ bytes: Int64 = 0) throws {
        let values = try? OfflineFiles.mediaFolder.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage,available < max(0,bytes)+64*1024*1024 {
            throw AppFailure.message("Not enough device storage. Free some space before saving this episode.")
        }
    }
}

struct OfflineIndex {
    let url: URL
    var backup: URL { url.appendingPathExtension("previous") }
    func load() throws -> [DownloadItem] {
        if !FileManager.default.fileExists(atPath:url.path) && !FileManager.default.fileExists(atPath:backup.path) { return [] }
        for candidate in [url,backup] {
            if let data = try? Data(contentsOf:candidate),let items = try? JSONDecoder().decode([DownloadItem].self,from:data) { return items }
        }
        throw AppFailure.message("The offline library index could not be read. Existing media files have been kept.")
    }
    func save(_ items: [DownloadItem]) throws {
        let data = try JSONEncoder().encode(items)
        if let previous = try? Data(contentsOf:url), (try? JSONDecoder().decode([DownloadItem].self,from:previous)) != nil {
            try previous.write(to:backup,options:.atomic);try OfflineStorage.protect(backup)
        }
        try data.write(to:url,options:.atomic);try OfflineStorage.protect(url)
    }
}
