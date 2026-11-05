import Foundation
import Network
import Combine

@MainActor final class Connectivity: ObservableObject {
    static let shared = Connectivity()
    @Published private(set) var isOffline = false
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label:"eu.cortex.anime.port.connectivity")
    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--offline-qa") { isOffline = true;return }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in self?.isOffline = offline }
        }
        monitor.start(queue:queue)
    }
    static func isNetworkFailure(_ error: Error) -> Bool {
        guard let failure = error as? URLError else { return false }
        return [.notConnectedToInternet,.networkConnectionLost,.timedOut,.cannotConnectToHost,.cannotFindHost,.dnsLookupFailed,.internationalRoamingOff,.dataNotAllowed].contains(failure.code)
    }
}

enum OfflineFiles {
    static var root: URL { URL(fileURLWithPath:NSHomeDirectory(),isDirectory:true).resolvingSymlinksInPath() }
    static var mediaFolder: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("OfflineMedia",isDirectory:true) }
    // /private/var and /var are the same path on iOS, so normalize before comparing
    // prefixes; otherwise download locations handed over by the system (for example
    // AVAssetDownload .movpkg) look "outside the container" and the package is dropped.
    private static func normalized(_ path: String) -> String {
        if path.hasPrefix("/private/") { return String(path.dropFirst("/private".count)) }
        return path
    }
    static func relative(_ url: URL) -> String? {
        let path = normalized(url.standardizedFileURL.resolvingSymlinksInPath().path)
        let prefix = normalized(root.path)+"/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
    static func resolve(_ relative: String?) -> URL? {
        guard let relative,!relative.isEmpty,!relative.hasPrefix("/") else { return nil }
        let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard normalized(url.path).hasPrefix(normalized(root.path)+"/"),FileManager.default.fileExists(atPath:url.path) else { return nil }
        return url
    }
}
