import Foundation
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Categories

/// The action row under a banner. Without a registered category iOS only draws the
/// text, which is exactly why the old alerts felt flat: no cover, no buttons, nothing
/// to tap except the whole banner.
enum AlertCategory {
    static let episode = "CORTEX_EPISODE"
    static let subtitle = "CORTEX_SUBTITLE"

    static let playAction = "CORTEX_PLAY"
    static let laterAction = "CORTEX_LATER"
    static let muteAction = "CORTEX_MUTE"

    static func register(center: UNUserNotificationCenter = .current()) {
        let play = UNNotificationAction(identifier: playAction,
                                        title: "Play episode",
                                        options: [.foreground])
        let later = UNNotificationAction(identifier: laterAction,
                                         title: "Remind me in 1 hour",
                                         options: [])
        let mute = UNNotificationAction(identifier: muteAction,
                                        title: "Mute this series",
                                        options: [.destructive])

        let episodes = UNNotificationCategory(identifier: episode,
                                              actions: [play, later, mute],
                                              intentIdentifiers: [],
                                              options: [])
        let subtitles = UNNotificationCategory(identifier: subtitle,
                                               actions: [play, later],
                                               intentIdentifiers: [],
                                               options: [])
        center.setNotificationCategories([episodes, subtitles])
    }
}

// MARK: - Cover art

/// Banners carry the series cover. It is downloaded once, kept in Caches, and handed
/// to the notification centre as a file attachment.
enum AlertArtwork {
    private static let maxBytes = 4_000_000

    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("alert-art", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The cached copy for a series, fetched on first use. Never throws: a banner
    /// without art is still a working banner.
    static func cachedFile(animeID: Int, remote: URL?) async -> URL? {
        guard animeID > 0, let folder else { return nil }
        let file = folder.appendingPathComponent("\(animeID).jpg")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
           let size = attributes[.size] as? Int, size > 2_048 {
            return file
        }
        guard let remote, remote.scheme == "https" else { return nil }
        var request = URLRequest(url: remote)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count > 2_048, data.count <= maxBytes, data.looksLikeArtwork else { return nil }
        try? data.write(to: file, options: .atomic)
        return file
    }

    /// The system moves the attachment into its own store, so every banner gets a
    /// private copy of the cached file instead of sharing one path.
    static func attachment(animeID: Int, remote: URL?) async -> UNNotificationAttachment? {
        guard let source = await cachedFile(animeID: animeID, remote: remote) else { return nil }
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("cortex-alert-\(UUID().uuidString).jpg")
        guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(
            identifier: "cover-\(animeID)",
            url: copy,
            options: [UNNotificationAttachmentOptionsTypeHintKey: UTType.jpeg.identifier]
        )
    }
}

private extension Data {
    /// AniList serves JPEG and PNG; anything else would fail to attach silently.
    var looksLikeArtwork: Bool {
        guard count > 4 else { return false }
        let first = self[startIndex]
        let second = self[startIndex + 1]
        return (first == 0xFF && second == 0xD8) || (first == 0x89 && second == 0x50)
    }
}

// MARK: - Content

/// One banner, fully dressed: cover image, a context line, an action row and a
/// grouped thread. Every notification in the app is built here so they all look
/// the same and none of them is a bare sentence.
struct RichAlert {
    var animeID: Int
    var title: String
    var episode: Int?
    var kicker: String?
    var body: String
    var deepLink: URL?
    var cover: URL?
    var category: String
    var identifier: String
    var badge: Int?

    func content() async -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        if let kicker, !kicker.isEmpty { content.subtitle = kicker }
        content.body = body
        content.threadIdentifier = "cortex-anime-\(animeID)"
        content.categoryIdentifier = category
        content.relevanceScore = 1
        // A missing sound file must never make a banner silent: fall back to the system tone.
        if Bundle.main.url(forResource: "cortex-alert", withExtension: "wav") != nil {
            content.sound = UNNotificationSound(named: UNNotificationSoundName("cortex-alert.wav"))
        } else {
            content.sound = .default
        }
        content.targetContentIdentifier = deepLink?.absoluteString
        var info: [String: Any] = ["aid": animeID]
        if let episode { info["ep"] = episode }
        if let link = deepLink?.absoluteString { info["url"] = link }
        content.userInfo = info
        if let badge { content.badge = NSNumber(value: badge) }
        if let attachment = await AlertArtwork.attachment(animeID: animeID, remote: cover) {
            content.attachments = [attachment]
        }
        return content
    }
}
