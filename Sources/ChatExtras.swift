import AVFoundation
import PhotosUI
import SwiftUI

// MARK: - Chat extras (1.6-os csomag)
//
// Megosztott epizód-, party- és hívás-kártyák, hangjegyzet-buborék és a
// „Cortex Call" hívás-képernyő. A hang szállítása a meglévő üzenet-csatornán
// történik (az `image` mezőben `data:audio/...` fájl), így szerveroldali
// változás nem kell hozzá.

/// Folyadék-nyomás: a gomb nyomásra finoman megnyúlik (iOS 26-os interakciós nyelv).
struct LiquidPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Megosztott tartalom felismerése az üzenet szövegéből.
enum ShareCard: Equatable {
    case episode(aid: Int, ep: Int, title: String)
    case party(code: String)
    case call(code: String)

    static func parse(_ text: String) -> ShareCard? {
        if text.hasPrefix("@ep:") {
            let rest = String(text.dropFirst(4))
            let parts = rest.split(separator: "#", maxSplits: 1)
            let idEp = parts.first.map(String.init) ?? ""
            let title = parts.count > 1 ? String(parts[1]) : "Episode"
            let nums = idEp.split(separator: "/")
            guard nums.count == 2, let aid = Int(nums[0]), let ep = Int(nums[1]) else { return nil }
            return .episode(aid: aid, ep: ep, title: title)
        }
        if text.hasPrefix("@party:") {
            return .party(code: String(text.dropFirst(7)).uppercased())
        }
        if text.hasPrefix("@call:") {
            return .call(code: String(text.dropFirst(6)).uppercased())
        }
        return nil
    }
}

// MARK: - Megosztott kártyák

struct ShareCardView: View {
    let card: ShareCard
    var mine: Bool

    var body: some View {
        switch card {
        case let .episode(aid, ep, title):
            NavigationLink { NativeLinkedDetail(id: aid) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.cortexPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.bold()).lineLimit(1)
                        Text("Episode \(ep) · tap to open").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        case let .party(code):
            NavigationLink { NativeWatchParty(party: WatchPartyModel()) } label: {
                HStack(spacing: 11) {
                    Image(systemName: "person.3.fill").font(.system(size: 20))
                        .foregroundStyle(Color.cortexPurple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch party invite").font(.subheadline.bold())
                        Text("Code \(code) · tap to join").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        case let .call(code):
            HStack(spacing: 11) {
                Image(systemName: "phone.fill").font(.system(size: 20)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Call started").font(.subheadline.bold())
                    Text("Code \(code) · tap the phone icon to talk").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Hangjegyzet-buborék

struct VoiceNoteBubble: View {
    let dataURL: String
    @State private var playing = false
    @State private var player: AVAudioPlayer?

    private var bytes: Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if playing {
                    player?.stop(); playing = false
                } else {
                    guard let bytes else { return }
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                    if let p = try? AVAudioPlayer(data: bytes) {
                        player = p; p.play(); playing = true
                        Task { try? await Task.sleep(for: .seconds(p.duration + 0.2)); playing = false }
                    }
                }
            } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.cortexPurple, in: Circle())
            }
            .buttonStyle(LiquidPress())
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cortexPurple.opacity(playing ? 0.85 : 0.4))
                        .frame(width: 3, height: 8 + CGFloat((i * 7) % 16))
                }
            }
            Text("Voice").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Epizód-megosztó lap

struct EpisodeSharePicker: View {
    @EnvironmentObject private var catalog: CatalogModel
    @Environment(\.dismiss) private var dismiss
    var onPick: (Anime) -> Void
    @State private var query = ""

    private var rows: [Anime] {
        query.isEmpty ? Array(catalog.titles.prefix(40))
            : catalog.titles.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(rows) { anime in
                Button {
                    onPick(anime); dismiss()
                } label: {
                    HStack(spacing: 10) {
                        AsyncImage(url: anime.cover) { phase in
                            if case .success(let img) = phase { img.resizable().scaledToFill() }
                            else { Color.cortexPanel }
                        }
                        .frame(width: 44, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(anime.title).font(.subheadline.bold()).lineLimit(2)
                            Text("\(anime.episodes) episodes").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.cortexBlack)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.cortexBlack)
            .searchable(text: $query, prompt: "Search anime")
            .navigationTitle("Share an episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
    }
}

// MARK: - Party meghívó lap

struct PartyInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSend: (String) -> Void
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Watch party code") {
                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Send invite") {
                        let clean = code.trimmingCharacters(in: .whitespaces).uppercased()
                        guard !clean.isEmpty else { return }
                        onSend(clean); dismiss()
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Invite to watch party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Cortex Call — hívás-képernyő (walkie-talkie)

/// A hang a meglévő üzenet-csatornán utazik (`data:audio` az üzenetben), így a
/// hívás 1:1-ben azonnal működik: nyomd a gombot és beszélj. Némítás és süketítés
/// helyben; kép a kamerából ugyanúgy megy, mint csevegésben.
struct CallRoomView: View {
    let username: String
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss

    @State private var muted = false
    @State private var deafened = false
    @State private var recording = false
    @State private var elapsed = 0
    @State private var recorder: AVAudioRecorder?
    @State private var player: AVAudioPlayer?
    @State private var lastPlayedID = 0
    @State private var cameraItem: PhotosPickerItem?

    private let url = FileManager.default.temporaryDirectory.appendingPathComponent("cx-call.m4a")

    var body: some View {
        ZStack {
            Color.cortexBlack.ignoresSafeArea()
            VStack(spacing: 26) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.cortexPurple.opacity(0.18)).frame(width: 118, height: 118)
                        Circle().strokeBorder(Color.cortexPurple.opacity(recording ? 0.9 : 0.35), lineWidth: 2)
                            .frame(width: 118, height: 118)
                            .scaleEffect(recording ? 1.06 : 1)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: recording)
                        Image(systemName: "person.fill").font(.system(size: 42)).foregroundStyle(Color.cortexPurple)
                    }
                    Text(username).font(.title3.bold())
                    Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Nyomd és beszélj
                Text(muted ? "Muted — the button is off" : (recording ? "Release to send" : "Hold to talk"))
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    if recording { stopAndSend() } else { startRecording() }
                } label: {
                    Image(systemName: muted ? "mic.slash.fill" : (recording ? "waveform" : "mic.fill"))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 108, height: 108)
                        .background(recording ? Color.red : Color.cortexPurple, in: Circle())
                        .shadow(color: (recording ? Color.red : Color.cortexPurple).opacity(0.55), radius: 18)
                }
                .buttonStyle(LiquidPress())
                .disabled(muted)

                HStack(spacing: 14) {
                    callToggle("mic.slash", "Mute", isOn: $muted)
                    callToggle("speaker.slash", "Deafen", isOn: $deafened)
                    PhotosPicker(selection: $cameraItem, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill").font(.system(size: 19))
                                .frame(width: 54, height: 54)
                                .background(Color.cortexPanel, in: Circle())
                            Text("Camera").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    stopAndSend(); dismiss()
                } label: {
                    Label("Hang up", systemImage: "phone.down.fill")
                        .font(.headline).foregroundStyle(.white)
                        .padding(.horizontal, 30).padding(.vertical, 13)
                        .background(Color.red, in: Capsule())
                }
                .buttonStyle(LiquidPress())
            }
            .padding(24)
        }
        .task {
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
            try? AVAudioSession.sharedInstance().setActive(true)
            let clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsed += 1 }
            while !Task.isCancelled {
                await pollVoices()
                try? await Task.sleep(for: .seconds(3))
            }
            clock.invalidate()
        }
        .onChange(of: cameraItem) { _, item in
            Task {
                if let item, let data = try? await item.loadTransferable(type: Data.self) {
                    _ = try? await api.json("/api/messages", method: "POST",
                                            body: ["to": username, "body": "",
                                                   "image": "data:image/jpeg;base64," + data.base64EncodedString()])
                }
                cameraItem = nil
            }
        }
    }

    private func callToggle(_ symbol: String, _ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 19))
                    .frame(width: 54, height: 54)
                    .background(isOn.wrappedValue ? Color.cortexPurple : Color.cortexPanel, in: Circle())
                Text(label).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? Color.cortexPurple : Color.secondary)
            }
        }
        .buttonStyle(LiquidPress())
    }

    private func startRecording() {
        guard !muted else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        recording = true
    }

    private func stopAndSend() {
        guard recording else { return }
        recorder?.stop()
        recording = false
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        Task {
            _ = try? await api.json("/api/messages", method: "POST",
                                    body: ["to": username, "body": "",
                                           "image": "data:audio/mp4;base64," + data.base64EncodedString()])
        }
    }

    /// Bejövő hangok lejátszása (ha nem süket).
    private func pollVoices() async {
        guard !deafened, let row = try? await api.json("/api/messages", query: ["with": username]),
              let msgs = row["messages"] as? [[String: Any]] else { return }
        for m in msgs {
            guard let id = m["id"] as? Int, id > lastPlayedID,
                  let img = m["image"] as? String, img.hasPrefix("data:audio"),
                  let mine = m["mine"] as? Bool, !mine,
                  let comma = img.firstIndex(of: ","),
                  let bytes = Data(base64Encoded: String(img[img.index(after: comma)...])),
                  let p = try? AVAudioPlayer(data: bytes) else { continue }
            lastPlayedID = id
            player = p
            p.play()
        }
        if lastPlayedID == 0, let last = msgs.last?["id"] as? Int { lastPlayedID = last }
    }
}
