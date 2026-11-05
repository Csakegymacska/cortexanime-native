import SwiftUI
import UIKit
import PhotosUI

// MARK: - 7.1: friends, public profiles and a real message screen
//
// The old screen asked for a username before it would show anything, then polled one conversation.
// This version is a conversation: a list of threads with previews and unread counts, a thread with
// day separators, delivery states and delete, and a friend list that can start a chat in one tap.
// The server grew three endpoints for it (threads / read / delete) — see deployment-messages-v2.

struct SocialUser: Identifiable, Hashable {
    let id: Int
    let name: String
    let avatar: String?

    init?(_ r: [String: Any]) {
        guard let id = r["id"] as? Int ?? r["requester_id"] as? Int,
              let name = r["username"] as? String else { return nil }
        self.id = id; self.name = name; avatar = r["avatar"] as? String
    }
}

// MARK: - Friends

struct NativeFriends: View {
    @EnvironmentObject private var api: APIClient
    @State private var friends: [SocialUser] = []
    @State private var requests: [SocialUser] = []
    @State private var found: [SocialUser] = []
    @State private var search = ""
    @State private var error: String?
    @State private var busy = false
    @State private var loading = true

    var body: some View {
        List {
            if !api.signedIn, api.sessionValidated || !api.hasStoredSession {
                NativeEmpty(title: "Sign in to connect",
                            detail: "Friend requests and messages need an account. Create one from Profile.",
                            icon: "person.2")
                    .listRowBackground(Color.clear)
            } else {
                Section("Find people") {
                    HStack(spacing: 8) {
                        TextField("Username", text: $search)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Button("Search") { Task { await find() } }
                            .disabled(search.isEmpty || busy)
                            .frame(minHeight: 44)
                    }
                    ForEach(found) { person in
                        HStack(spacing: 10) {
                            personRow(person)
                            Button("Add") { Task { await command("/api/friends/request", body: ["username": person.name]) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                if !requests.isEmpty {
                    Section("Requests") {
                        ForEach(requests) { person in
                            HStack(spacing: 10) {
                                personRow(person)
                                Button("Accept") { Task { await command("/api/friends/accept", body: ["requesterId": person.id]) } }
                                    .buttonStyle(.borderedProminent)
                                Button("Ignore", role: .destructive) { Task { await remove(person) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                Section("Friends · \(friends.count)") {
                    if friends.isEmpty {
                        Text(loading ? "Loading…" : "No friends yet — search a username above.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(friends) { person in
                        NavigationLink {
                            ChatThreadView(username: person.name)
                        } label: {
                            HStack(spacing: 10) {
                                NativeAvatar(raw: person.avatar).frame(width: 38, height: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name).font(.subheadline.bold())
                                    Text("Tap to open the chat").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 13)).foregroundStyle(Color.cortexPurple)
                            }
                        }
                        .swipeActions { Button("Remove", role: .destructive) { Task { await remove(person) } } }
                    }
                }
                if let error { Section { ErrorNotice(text: error) } }
            }
        }
        .navigationTitle("Friends")
        .task { await load() }
        .refreshable { await load() }
    }

    private func personRow(_ person: SocialUser) -> some View {
        NavigationLink { NativePublicProfile(id: person.id) } label: {
            HStack(spacing: 10) {
                NativeAvatar(raw: person.avatar).frame(width: 38, height: 38)
                Text(person.name).font(.subheadline.bold())
                Spacer()
            }
        }
    }

    private func load() async {
        guard await api.ensureSession() else { loading = false; return }
        do {
            let a = try await api.json("/api/friends")
            let b = try await api.json("/api/friends/requests")
            friends = (a["friends"] as? [[String: Any]] ?? []).compactMap(SocialUser.init)
            requests = (b["requests"] as? [[String: Any]] ?? []).compactMap(SocialUser.init)
            error = nil
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
        loading = false
    }

    private func find() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await api.json("/api/user/search", query: ["q": search])
            found = (r["users"] as? [[String: Any]] ?? []).compactMap(SocialUser.init)
            error = nil
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func command(_ path: String, body: [String: Any]) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await api.json(path, method: "POST", body: body)
            await load()
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func remove(_ user: SocialUser) async {
        do {
            _ = try await api.json("/api/friends/\(user.id)", method: "DELETE")
            await load()
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - Models

struct ChatThread: Identifiable, Hashable {
    let id: Int
    let username: String
    let avatar: String?
    let last: String
    let lastAt: Date?
    let mine: Bool
    let unread: Int

    init?(_ r: [String: Any]) {
        guard let id = r["id"] as? Int, let name = r["username"] as? String else { return nil }
        self.id = id; username = name
        avatar = r["avatar"] as? String
        last = r["last"] as? String ?? ""
        lastAt = (r["last_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        mine = r["mine"] as? Bool ?? false
        unread = r["unread"] as? Int ?? 0
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Delivery: Equatable { case sending, sent, failed }
    let id: Int
    let text: String
    let image: String?
    let mine: Bool
    let at: Date?
    var delivery: Delivery = .sent

    var hasImage: Bool { image?.isEmpty == false }
    var isGIF: Bool { image?.hasPrefix("data:image/gif") == true }
    var isVoice: Bool { image?.hasPrefix("data:audio") == true }

    init?(_ r: [String: Any]) {
        guard let id = r["id"] as? Int else { return nil }
        self.id = id
        text = r["body"] as? String ?? ""
        image = r["image"] as? String
        mine = r["mine"] as? Bool ?? false
        at = (r["created_at"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    init(pending text: String, image: String? = nil) {
        id = -Int(Date().timeIntervalSince1970 * 1000)
        self.text = text
        self.image = image
        mine = true
        at = Date()
        delivery = .sending
    }
}

/// Animated GIF from a data URL. UIImage shows only the first frame, so the bubble needs a
/// UIImageView with `animatedImage`; everything else (PNG/JPEG/WebP) goes through Image.
struct ChatImage: View {
    let dataURL: String
    var maxWidth: CGFloat = 210

    private var payload: Data? {
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...]))
    }

    private var isGIF: Bool { dataURL.hasPrefix("data:image/gif") }

    var body: some View {
        if let payload, let image = UIImage(data: payload) {
            if isGIF {
                AnimatedImage(data: payload)
                    .frame(width: maxWidth, height: maxWidth * (image.size.height / max(image.size.width, 1)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: maxWidth, height: maxWidth * min(1.4, image.size.height / max(image.size.width, 1)))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.cortexPanel)
                .frame(width: maxWidth, height: 120)
                .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.4)))
        }
    }
}

struct AnimatedImage: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.image = UIImage.animatedImage(withGIFData: data) ?? UIImage(data: data)
        return view
    }
    func updateUIView(_ uiView: UIImageView, context: Context) {
        if uiView.image == nil { uiView.image = UIImage.animatedImage(withGIFData: data) ?? UIImage(data: data) }
    }
}

extension UIImage {
    /// Frame-by-frame decode of an animated GIF into a single animated UIImage.
    static func animatedImage(withGIFData data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }
        var frames: [UIImage] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(UIImage(cgImage: frame))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            duration += max(0.02, delay)
        }
        guard frames.count > 1 else { return nil }
        return UIImage.animatedImage(with: frames, duration: duration)
    }
}

// MARK: - Messages (conversation list)

struct NativeMessages: View {
    var initialUsername = ""
    @EnvironmentObject private var api: APIClient
    @State private var threads: [ChatThread] = []
    @State private var loading = true
    @State private var error: String?
    @State private var composing = false

    var body: some View {
        Group {
            if !initialUsername.isEmpty {
                ChatThreadView(username: initialUsername)
            } else if !api.signedIn {
                if api.hasStoredSession, !api.sessionValidated {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NativeEmpty(title: "Sign in to send messages",
                                detail: "Messages are private and only visible to you and the other person.",
                                icon: "bubble.left.and.bubble.right")
                }
            } else {
                list
            }
        }
        .background(Color.cortexBlack)
        .navigationTitle(initialUsername.isEmpty ? "Messages" : initialUsername)
        .navigationBarTitleDisplayMode(initialUsername.isEmpty ? .large : .inline)
        .toolbar {
            if initialUsername.isEmpty && api.signedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New message")
                }
            }
        }
        .sheet(isPresented: $composing) {
            NavigationStack { NewChatSheet { composing = false } }
        }
        .task {
            guard initialUsername.isEmpty else { return }
            // A munkamenet-érvényesítés aszinkron: megvárjuk, mielőtt üresnek
            // jelentenénk ki a listát. Addig pörgünk, amíg nincs döntés.
            while !Task.isCancelled {
                if await api.ensureSession() {
                    await load()
                } else if api.sessionValidated {
                    loading = false
                    return
                }
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
        }
    }

    private var list: some View {
        List {
            if let error {
                Section { ErrorNotice(text: error) }
            }
            if threads.isEmpty && !loading {
                NativeEmpty(title: "No conversations yet",
                            detail: "Open a friend from the list, or start a new message.",
                            icon: "bubble.left.and.bubble.right")
                    .listRowBackground(Color.clear)
            }
            ForEach(threads) { thread in
                NavigationLink { ChatThreadView(username: thread.username) } label: { row(thread) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack)
        .refreshable { await load() }
    }

    private func row(_ thread: ChatThread) -> some View {
        HStack(spacing: 12) {
            NativeAvatar(raw: thread.avatar).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(thread.username).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    if let at = thread.lastAt {
                        Text(relative(at)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text((thread.mine ? "You: " : "") + thread.last)
                        .font(.caption)
                        .foregroundStyle(thread.unread > 0 ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    if thread.unread > 0 {
                        Text("\(thread.unread)")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.cortexPurple, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            let r = try await api.json("/api/messages/threads")
            threads = (r["threads"] as? [[String: Any]] ?? []).compactMap(ChatThread.init)
            error = nil
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
        loading = false
    }
}

private func relative(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
}

// MARK: - New chat

struct NewChatSheet: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    var onClose: () -> Void = {}
    @State private var friends: [SocialUser] = []
    @State private var search = ""
    @State private var found: [SocialUser] = []
    @State private var error: String?

    private var people: [SocialUser] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return friends }
        return found
    }

    var body: some View {
        List {
            Section("To") {
                TextField("Search a username", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ForEach(people) { person in
                    NavigationLink { ChatThreadView(username: person.name) } label: {
                        HStack(spacing: 10) {
                            NativeAvatar(raw: person.avatar).frame(width: 36, height: 36)
                            Text(person.name).font(.subheadline.bold())
                        }
                    }
                }
            }
            Section("Friends") {
                ForEach(friends) { person in
                    NavigationLink { ChatThreadView(username: person.name) } label: {
                        HStack(spacing: 10) {
                            NativeAvatar(raw: person.avatar).frame(width: 36, height: 36)
                            Text(person.name).font(.subheadline.bold())
                        }
                    }
                }
            }
            if let error { Section { ErrorNotice(text: error) } }
        }
        .navigationTitle("New message")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { onClose(); dismiss() } } }
        .task { await loadFriends() }
        .onChange(of: search) { _, value in
            guard value.trimmingCharacters(in: .whitespaces).count >= 2 else { found = []; return }
            Task { await searchPeople(value) }
        }
    }

    private func loadFriends() async {
        guard await api.ensureSession() else { return }
        do {
            let r = try await api.json("/api/friends")
            friends = (r["friends"] as? [[String: Any]] ?? []).compactMap(SocialUser.init)
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func searchPeople(_ text: String) async {
        do {
            let r = try await api.json("/api/user/search", query: ["q": text])
            found = (r["users"] as? [[String: Any]] ?? []).compactMap(SocialUser.init)
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

// MARK: - One conversation

struct ChatThreadView: View {
    let username: String
    @EnvironmentObject private var api: APIClient
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var error: String?
    @State private var loading = true
    @State private var picked: PhotosPickerItem?
    @State private var attaching = false
    /// 7.3: keresés a beszélgetésben + idézetes válasz.
    @State private var search = ""
    @State private var replyTo: ChatMessage?
    /// Megosztások: epizód, party-meghívó, hívás.
    @State private var sharingEpisode = false
    @State private var invitingParty = false
    @State private var calling = false
    @FocusState private var composerFocused: Bool

    private var rows: [ChatRow] {
        ChatRow.build(search.isEmpty ? messages : messages.filter {
            $0.text.localizedCaseInsensitiveContains(search)
        })
    }
    private var canSend: Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 2000
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if loading && messages.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    if messages.isEmpty && !loading {
                        Text("Say hi — this is the start of the conversation.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(rows) { row in
                        switch row {
                        case .day(let date):
                            dayHeader(date)
                        case .message(let message):
                            bubble(message).id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .background(Color.cortexBlack)
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search messages")
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { calling = true } label: { Image(systemName: "phone.fill") }
                    .accessibilityLabel("Voice call")
            }
        }
        .sheet(isPresented: $sharingEpisode) {
            EpisodeSharePicker { anime in
                sendRaw("@ep:\(anime.id)/1#\(anime.title)")
            }
        }
        .sheet(isPresented: $invitingParty) {
            PartyInviteSheet { code in sendRaw("@party:\(code)") }
        }
        .sheet(isPresented: $calling) {
            CallRoomView(username: username)
        }
        .task(id: username) {
            await load(markRead: true)
            loading = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                await load(markRead: true)
            }
        }
    }

    private func dayHeader(_ date: Date) -> some View {
        Text(dayTitle(date))
            .font(.system(size: 10, weight: .black)).tracking(1.2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    @ViewBuilder private func bubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.mine { Spacer(minLength: 50) }
            VStack(alignment: message.mine ? .trailing : .leading, spacing: 3) {
                if let card = ShareCard.parse(message.text) {
                    ShareCardView(card: card, mine: message.mine)
                } else if message.isVoice, let audio = message.image {
                    VoiceNoteBubble(dataURL: audio)
                } else if let image = message.image, !image.isEmpty {
                    ChatImage(dataURL: image)
                        .overlay(alignment: .bottomTrailing) {
                            if message.isGIF {
                                Text("GIF").font(.system(size: 8, weight: .black))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(6)
                            }
                        }
                        .contextMenu {
                            Button { UIPasteboard.general.image = UIImage(data: image.split(separator: ",").last.flatMap { Data(base64Encoded: String($0)) } ?? Data()) } label: {
                                Label("Copy image", systemImage: "doc.on.doc")
                            }
                            if message.mine && message.id > 0 {
                                Button(role: .destructive) { Task { await delete(message) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
                if !message.text.isEmpty {
                    // 7.3: a "> " sorral kezdődő üzenet első sora idézet.
                    let parts = message.text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                    let quote = message.text.hasPrefix("> ") ? String(parts[0].dropFirst(2)) : nil
                    let rest = quote == nil ? message.text : (parts.count > 1 ? String(parts[1]) : "")
                    VStack(alignment: .leading, spacing: 5) {
                        if let quote, !quote.isEmpty {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.cortexPurple).frame(width: 3)
                                Text(quote).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(6)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        if !rest.isEmpty {
                            Text(rest).font(.subheadline).foregroundStyle(.white)
                        }
                    }
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(message.mine ? Color.cortexPurple.opacity(0.30) : Color.cortexPanel,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu {
                        Button { replyTo = message } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
                        Button { UIPasteboard.general.string = message.text } label: { Label("Copy", systemImage: "doc.on.doc") }
                        if message.mine && message.id > 0 {
                            Button(role: .destructive) { Task { await delete(message) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .modifier(HeartBurst())
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                // Jobbra húzás = válasz (a függőleges görgetést nem bántjuk).
                                if value.translation.width > 60,
                                   abs(value.translation.width) > abs(value.translation.height) {
                                    replyTo = message
                                }
                            }
                    )
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(message.mine ? Color.cortexPurple.opacity(0.35) : .white.opacity(0.06), lineWidth: 1))
                        .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                            if message.mine && message.id > 0 {
                                Button(role: .destructive) { Task { await delete(message) } } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                }
                if message.mine {
                    switch message.delivery {
                    case .sending: Text("Sending…").font(.system(size: 9)).foregroundStyle(.secondary)
                    case .failed:
                        Button { Task { await retry(message) } } label: {
                            Text("Not delivered · tap to retry").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    case .sent:
                        if let at = message.at {
                            Text(at.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !message.mine { Spacer(minLength: 50) }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let replyTo {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.cortexPurple).frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Replying").font(.system(size: 9, weight: .black)).foregroundStyle(Color.cortexPurple)
                        Text(replyTo.text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { self.replyTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Cancel reply")
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.white.opacity(0.05))
            }
            if let error {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.top, 6)
            }
            if attaching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Preparing the image…").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { sharingEpisode = true } label: { Label("Share an episode", systemImage: "play.rectangle") }
                    Button { invitingParty = true } label: { Label("Invite to watch party", systemImage: "person.3") }
                    Button { calling = true } label: { Label("Voice call", systemImage: "phone") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.cortexPurple)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .accessibilityLabel("Share or call")
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.cortexPurple)
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .disabled(!api.signedIn)
                .accessibilityLabel("Send a photo or GIF")
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? Color.cortexPurple : Color.white.opacity(0.25))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Send message")
                .disabled(!canSend || !api.signedIn)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            if draft.count > 1600 {
                Text("\(draft.count)/2000").font(.system(size: 9)).foregroundStyle(draft.count > 2000 ? .orange : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16).padding(.bottom, 4)
            }
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        .onChange(of: picked) { _, item in
            Task {
                await sendImage(item)
                picked = nil
            }
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    private func load(markRead: Bool) async {
        guard await api.ensureSession() else { return }
        do {
            let r = try await api.json("/api/messages", query: ["with": username])
            let fresh = (r["messages"] as? [[String: Any]] ?? []).compactMap(ChatMessage.init)
            // Keep a pending bubble alive until the server answers; otherwise it flickers away.
            let pending = messages.filter { $0.id < 0 }
            messages = fresh + pending
            error = nil
            if markRead {
                _ = try? await api.json("/api/messages/read", method: "POST", body: ["with": username])
            }
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// Nyers üzenet küldése (megosztott kártyák, meghívók) — nem rak függő buborékot.
    private func sendRaw(_ text: String) {
        Task {
            _ = try? await api.json("/api/messages", method: "POST", body: ["to": username, "body": text])
            await load(markRead: true)
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return }
        draft = ""
        // 7.3: idézetes válasz — az első sor "> idézet", a szerver tárolja így.
        var outgoing = text
        if let replyTo {
            let quoted = String(replyTo.text.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            outgoing = "> " + quoted + "\n" + text
            self.replyTo = nil
        }
        let pending = ChatMessage(pending: outgoing)
        messages.append(pending)
        do {
            _ = try await api.json("/api/messages", method: "POST", body: ["to": username, "body": outgoing])
            messages.removeAll { $0.id == pending.id }
            await load(markRead: true)
        } catch {
            if let index = messages.firstIndex(where: { $0.id == pending.id }) {
                messages[index].delivery = .failed
            }
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func retry(_ message: ChatMessage) async {
        guard message.id < 0 else { return }
        messages.removeAll { $0.id == message.id }
        draft = message.text
        await send()
    }

    private func sendImage(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        attaching = true
        defer { attaching = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            error = "That file could not be read."
            return
        }
        guard let payload = ChatAttachment.prepare(data) else {
            error = "That image is too large — pick a smaller photo or a GIF under 250 KB."
            return
        }
        let pending = ChatMessage(pending: "", image: payload)
        messages.append(pending)
        do {
            _ = try await api.json("/api/messages", method: "POST", body: ["to": username, "image": payload])
            messages.removeAll { $0.id == pending.id }
            await load(markRead: true)
        } catch {
            if let index = messages.firstIndex(where: { $0.id == pending.id }) {
                messages[index].delivery = .failed
            }
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func delete(_ message: ChatMessage) async {
        do {
            _ = try await api.json("/api/messages/\(message.id)", method: "DELETE")
            messages.removeAll { $0.id == message.id }
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

enum ChatRow: Identifiable {
    case day(Date)
    case message(ChatMessage)

    var id: String {
        switch self {
        case .day(let date): return "day-\(date.timeIntervalSince1970)"
        case .message(let message): return "m-\(message.id)"
        }
    }

    static func build(_ messages: [ChatMessage]) -> [ChatRow] {
        var out: [ChatRow] = []
        var last: Date?
        for message in messages {
            let day = Calendar.current.startOfDay(for: message.at ?? Date())
            if last != day { out.append(.day(day)); last = day }
            out.append(.message(message))
        }
        return out
    }
}

// MARK: - Public profile

struct NativePublicProfile: View {
    let id: Int
    @EnvironmentObject private var api: APIClient
    @State private var user: NativeUser?
    @State private var watchlist: [Anime] = []
    @State private var activity: [String] = []
    @State private var friendStatus = "none"
    @State private var count = 0
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let user {
                    ProfileCard(name: user.username,
                                avatar: user.avatar,
                                banner: user.banner,
                                status: user.status,
                                bio: user.bio,
                                decoration: user.decoration ?? "none",
                                accent: ProfileAccent.color(user.accent),
                                friends: count)
                    if api.signedIn && api.user?.id != id {
                        HStack(spacing: 10) {
                            Button(friendLabel) { Task { await add() } }
                                .buttonStyle(.bordered)
                                .disabled(["friends", "sent"].contains(friendStatus))
                                .frame(minHeight: 44)
                            NavigationLink { NativeMessages(initialUsername: user.username) } label: {
                                Label("Message", systemImage: "bubble.left.fill")
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    if !watchlist.isEmpty { AnimeShelf(title: "Watchlist", items: watchlist) }
                    if !activity.isEmpty {
                        SectionHeading(title: "Recent activity")
                        ForEach(Array(activity.enumerated()), id: \.offset) { _, text in
                            Text(text).font(.caption).padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else if error == nil {
                    ProgressView("Loading profile…").frame(maxWidth: .infinity).padding(.top, 40)
                }
                if let error { NativeError(text: error) { Task { await load() } } }
            }
            .padding(16)
        }
        .background(Color.cortexBlack)
        .navigationTitle(user?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var friendLabel: String {
        switch friendStatus {
        case "incoming": return "Accept request"
        case "friends": return "Friends"
        case "sent": return "Request sent"
        default: return "Add friend"
        }
    }

    private func load() async {
        do {
            let r = try await api.json("/api/user/\(id)")
            user = (r["user"] as? [String: Any]).flatMap(NativeUser.init)
            watchlist = (r["watchlist"] as? [[String: Any]] ?? []).compactMap(watchlistAnime)
            activity = (r["activity"] as? [[String: Any]] ?? []).map {
                "\($0["title"] as? String ?? "Anime") · Episode \($0["episode"] as? Int ?? 1)"
            }
            friendStatus = r["friendStatus"] as? String ?? "none"
            let stats = try await api.json("/api/user/stats", query: ["id": String(id)])
            count = stats["friends"] as? Int ?? 0
            error = nil
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func add() async {
        do {
            if friendStatus == "incoming" {
                _ = try await api.json("/api/friends/accept", method: "POST", body: ["requesterId": id])
            } else {
                _ = try await api.json("/api/friends/request", method: "POST", body: ["username": user?.username ?? ""])
            }
            await load()
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

/// Turns a picked photo (or an animated GIF) into the data URL the worker accepts: 380 000
/// characters maximum, png / jpeg / webp / gif.
enum ChatAttachment {
    static let limit = 380_000

    static func prepare(_ data: Data) -> String? {
        let isGIF = data.count > 6 && (data.prefix(6) == Data("GIF87a".utf8) || data.prefix(6) == Data("GIF89a".utf8))
        if isGIF {
            let payload = "data:image/gif;base64," + data.base64EncodedString()
            return payload.count <= limit ? payload : nil
        }
        guard let image = UIImage(data: data) else { return nil }
        var quality: CGFloat = 0.75
        var maxSide: CGFloat = 1200
        while maxSide >= 400 {
            let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let shrunk = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            if let jpeg = shrunk.jpegData(compressionQuality: quality) {
                let payload = "data:image/jpeg;base64," + jpeg.base64EncodedString()
                if payload.count <= limit { return payload }
            }
            quality = max(0.35, quality - 0.15)
            if quality <= 0.35 { maxSide *= 0.75; quality = 0.6 }
        }
        return nil
    }
}


// MARK: - Unread badge (7.3)

/// Olvasatlan üzenetek száma a Profil Messages során. A saját hálózati hívását
/// csinálja, hogy a Profilt ne kelljen tehermentesíteni; a munkamenetet megvárja.
struct MessagesUnreadBadge: View {
    @EnvironmentObject private var api: APIClient
    @State private var count = 0

    var body: some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.cortexPurple, in: Capsule())
            }
        }
        .task {
            guard await api.ensureSession() else { return }
            guard let row = try? await api.json("/api/messages/threads"),
                  let threads = row["threads"] as? [[String: Any]] else { return }
            count = threads.compactMap { $0["unread"] as? Int }.reduce(0, +)
        }
        .accessibilityLabel(count > 0 ? "\(count) unread messages" : "No unread messages")
    }
}


/// Barátkérések száma a Profil Friends során (7.3/2.0 mintára).
struct FriendRequestBadge: View {
    @EnvironmentObject private var api: APIClient
    @State private var count = 0

    var body: some View {
        Group {
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.cortexPurple, in: Capsule())
            }
        }
        .task {
            guard await api.ensureSession() else { return }
            guard let row = try? await api.json("/api/friends/requests"),
                  let reqs = row["requests"] as? [[String: Any]] else { return }
            count = reqs.count
        }
        .accessibilityLabel(count > 0 ? "\(count) friend requests" : "No friend requests")
    }
}

/// Dupla koppintásra szív-kitörés az üzeneten (helyi visszajelzés, nem küld semmit).
struct HeartBurst: ViewModifier {
    @State private var burst = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if burst {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.cortexPurple)
                        .shadow(color: Color.cortexPurple.opacity(0.7), radius: 12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { burst = true }
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                Task {
                    try? await Task.sleep(for: .seconds(0.65))
                    withAnimation(.easeOut(duration: 0.25)) { burst = false }
                }
            }
    }
}
