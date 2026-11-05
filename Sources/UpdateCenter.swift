import CryptoKit
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One platform block of `https://cortanime.eu/api/app/version`.
struct AppRelease: Decodable, Hashable {
    let version: String
    let build: Int
    let minOS: String?
    let url: String
    let size: Int64?
    let sha256: String?
    let releasedAt: String?
    let notes: [String]?

    var sizeText: String {
        guard let size, size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        return formatter.string(fromByteCount: size)
    }

    var shortLine: String { "\(version) (\(build))" }
}

struct AppManifestFile: Decodable {
    let ios: AppRelease?
    let generatedAt: String?
}

/// Checks the published manifest, downloads the unsigned IPA inside the app and hands it to the
/// signer. iOS never lets an app install itself, so the last step is always a visible hand-off
/// instead of a silent update: the same tap you would do in Safari, only with the file already here.
@MainActor
final class UpdateCenter: ObservableObject {
    static let shared = UpdateCenter()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease, progress: Double, bytes: Int64)
        case ready(AppRelease, file: URL)
        case failed(String)
    }

    static let manifestURL = URL(string: "https://cortanime.eu/api/app/version")!
    static let sourceAddress = "https://cortanime.eu/api/app/source.json"
    static let signerURL = URL(string: "https://applejr.net/#signer")!
    static let installPage = URL(string: "https://cortanime.eu/letoltes")!

    private static let lastCheckKey = "cortex.update.lastCheck"
    private static let seenVersionKey = "cortex.update.seenVersion"

    @Published private(set) var phase: Phase = .idle
    @Published var showSheet = false
    @Published var bannerHidden = false

    private var downloader: UpdateDownloader?

    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var installedBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    var availableRelease: AppRelease? {
        switch phase {
        case .available(let release), .downloading(let release, _, _), .ready(let release, _): return release
        case .checking, .idle, .upToDate, .failed: return nil
        }
    }

    var downloadedFile: URL? {
        if case .ready(_, let file) = phase { return file }
        return nil
    }

    /// Launch-time check, at most once every six hours unless `force` is set.
    func checkIfNeeded(force: Bool = false) async {
        let last = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        if !force, last > 0, Date().timeIntervalSince1970 - last < 6 * 3600 { return }
        await check(force: force)
    }

    func check(force: Bool = false) async {
        if case .downloading = phase { return }
        phase = .checking
        var request = URLRequest(url: Self.manifestURL)
        request.timeoutInterval = 15
        request.setValue("CortexAnime-iOS/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                phase = .failed(AppLanguage.text(en: "The update server did not answer.", hu: "A frissítés-szerver nem válaszolt."))
                return
            }
            let manifest = try JSONDecoder().decode(AppManifestFile.self, from: data)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            guard let release = manifest.ios else {
                phase = .upToDate
                return
            }
            guard release.build > installedBuild else {
                phase = .upToDate
                return
            }
            phase = .available(release)
            let seen = UserDefaults.standard.integer(forKey: Self.seenVersionKey)
            if seen != release.build {
                UserDefaults.standard.set(release.build, forKey: Self.seenVersionKey)
                bannerHidden = false
                try? await Task.sleep(nanoseconds: 900_000_000)
                if case .available = phase { showSheet = true }
            }
        } catch {
            phase = .failed(AppLanguage.text(en: "The update server could not be reached.", hu: "Nem sikerült elérni a frissítés-szervert."))
        }
    }

    func download() {
        guard let release = availableRelease else { return }
        bannerHidden = true
        let target = Self.updatesFolder.appendingPathComponent("CortexAnime-\(release.version)-\(release.build).ipa")
        phase = .downloading(release, progress: 0, bytes: 0)
        let downloader = UpdateDownloader(
            release: release,
            target: target,
            onProgress: { [weak self] progress, bytes in
                Task { @MainActor in
                    guard let self, case .downloading(let current, _, _) = self.phase else { return }
                    self.phase = .downloading(current, progress: progress, bytes: bytes)
                }
            },
            onFinish: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    switch result {
                    case .success(let file):
                        self.phase = .ready(release, file: file)
                    case .failure(let error):
                        self.phase = .failed(error.message)
                    }
                    self.downloader = nil
                }
            }
        )
        self.downloader = downloader
        downloader.start()
    }

    func openSigner() {
        UIApplication.shared.open(Self.signerURL)
    }

    func openInstallPage() {
        UIApplication.shared.open(Self.installPage)
    }

    func reset() {
        if case .failed = phase { phase = .available(availableRelease ?? AppRelease.placeholder) }
    }

    static var updatesFolder: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Updates", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func revealInFiles(_ file: URL) {
        UIApplication.shared.open(file)
    }
}

extension AppRelease {
    static let placeholder = AppRelease(version: "-", build: 0, minOS: nil, url: "", size: nil,
                                        sha256: nil, releasedAt: nil, notes: nil)
}

struct UpdateFailure: Error {
    let message: String
}

/// Plain URLSession download task with progress and a SHA-256 check before the file is offered
/// to the signer.
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let release: AppRelease
    private let target: URL
    private let onProgress: (Double, Int64) -> Void
    private let onFinish: (Result<URL, UpdateFailure>) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var lastReport: TimeInterval = 0

    init(release: AppRelease, target: URL,
         onProgress: @escaping (Double, Int64) -> Void,
         onFinish: @escaping (Result<URL, UpdateFailure>) -> Void) {
        self.release = release
        self.target = target
        self.onProgress = onProgress
        self.onFinish = onFinish
    }

    func start() {
        guard let url = URL(string: release.url) else {
            onFinish(.failure(UpdateFailure(message: AppLanguage.text(en: "The download address is invalid.", hu: "Hibás letöltési cím."))))
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("CortexAnime-iOS", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.task = task
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (release.size ?? 0)
        let progress = expected > 0 ? min(1, Double(totalBytesWritten) / Double(expected)) : 0
        let now = Date().timeIntervalSince1970
        if now - lastReport > 0.12 || progress >= 1 {
            lastReport = now
            onProgress(progress, totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: location, to: target)
            if let expected = release.sha256, !expected.isEmpty {
                let data = try Data(contentsOf: target, options: .mappedIfSafe)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard digest == expected.lowercased() else {
                    try? FileManager.default.removeItem(at: target)
                    onFinish(.failure(UpdateFailure(message: AppLanguage.text(en: "The checksum does not match — the download is damaged.", hu: "Az ellenőrzőösszeg nem egyezik, a letöltés sérült."))))
                    return
                }
            }
            onFinish(.success(target))
        } catch {
            onFinish(.failure(UpdateFailure(message: AppLanguage.text(en: "The file could not be saved: \(error.localizedDescription)", hu: "A fájl mentése nem sikerült: \(error.localizedDescription)"))))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        onFinish(.failure(UpdateFailure(message: AppLanguage.text(en: "The download stopped: \(error.localizedDescription)", hu: "A letöltés megszakadt: \(error.localizedDescription)"))))
    }
}
