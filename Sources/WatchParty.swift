import SwiftUI

// MARK: - 7.2: Watch Party, rebuilt
//
// The room logic is the same as before (the worker owns the state: /api/watchparty/create, /join,
// /control, /state, /messages, /reaction). What changed is everything people look at: a lobby that
// explains the room, a code you can read out loud, member chips, a real chat with bubbles, and
// quick reactions drawn as symbols instead of text.

struct PartyMessage: Identifiable, Equatable {
    let id: String
    let name: String
    let text: String
}

@MainActor final class WatchPartyModel: ObservableObject {
    @Published var room = ""
    @Published var name = "Guest"
    @Published var subject = ""
    @Published var members: [String] = []
    @Published var chat: [PartyMessage] = []
    @Published var reactions: [String] = []
    @Published var error: String?
    @Published var busy = false
    @Published var lastSync = Date.distantPast

    private let client = UUID().uuidString
    private var lastUpdate = 0.0
    private var task: Task<Void, Never>?
    private weak var playback: Playback?
    private var api: APIClient?

    var isHost: Bool { !room.isEmpty }
    var synced: Bool { Date().timeIntervalSince(lastSync) < 12 && error == nil }

    func configure(api: APIClient, playback: Playback) {
        self.api = api
        self.playback = playback
        if let username = api.user?.username { name = username }
        if let anime = playback.route.anime {
            subject = playback.route.episodeLabel.isEmpty ? anime.title : "\(anime.title) · \(playback.route.episodeLabel)"
        }
    }

    func enter(code: String? = nil) async {
        guard let api, let anime = playback?.route.anime, let episode = playback?.route.episode else {
            error = "A live anime episode is required."
            return
        }
        busy = true
        defer { busy = false }
        do {
            var body: [String: Any] = ["name": String(name.prefix(30))]
            let joining = code?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let joining, !joining.isEmpty { body["roomId"] = joining }
            else {
                body["animeId"] = anime.id
                body["episode"] = episode
            }
            let result = try await api.json(joining?.isEmpty == false ? "/api/watchparty/join" : "/api/watchparty/create",
                                            method: "POST", body: body)
            if let id = result["animeId"] as? Int, id != anime.id { throw AppFailure.message("This room is watching another anime.") }
            if let ep = result["episode"] as? Int, ep != episode { throw AppFailure.message("This room is watching another episode.") }
            guard let returned = result["roomId"] as? String else { throw AppFailure.message("No room code returned.") }
            room = returned
            lastUpdate = 0
            error = nil
            task?.cancel()
            task = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                }
            }
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    func leave() {
        task?.cancel(); task = nil
        room = ""; members = []; chat = []; reactions = []; lastSync = .distantPast
    }

    func control(_ action: String, time: Double) {
        guard !room.isEmpty, let api else { return }
        let target = room
        Task {
            do { _ = try await api.json("/api/watchparty/control", method: "POST",
                                        body: ["roomId": target, "action": action, "time": max(0, time), "clientId": client]) }
            catch { if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    func send(_ text: String) async throws {
        guard !room.isEmpty, let api else { return }
        _ = try await api.json("/api/watchparty/messages", method: "POST",
                               body: ["roomId": room, "name": name, "text": String(text.prefix(300))])
        await poll()
    }

    func react(_ reaction: String) async {
        guard let api, !room.isEmpty else { return }
        do {
            _ = try await api.json("/api/watchparty/reaction", method: "POST",
                                   body: ["roomId": room, "name": name, "emoji": reaction])
            await poll()
        } catch {
            if !(error is CancellationError), !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func poll() async {
        guard let api, !room.isEmpty else { return }
        let active = room
        do {
            let state = try await api.json("/api/watchparty/state", query: ["roomId": active, "name": name])
            try Task.checkCancellation()
            guard active == room else { return }
            members = state["members"] as? [String] ?? []
            reactions = (state["reactions"] as? [[String: Any]] ?? []).suffix(6).map {
                ($0["name"] as? String ?? "Guest") + " · " + ($0["emoji"] as? String ?? "heart")
            }
            let updated = (state["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            if updated > lastUpdate {
                lastUpdate = updated
                if state["lastClient"] as? String != client, let playback {
                    let time = max(0, (state["time"] as? NSNumber)?.doubleValue ?? 0)
                    let action = state["action"] as? String ?? "pause"
                    if action == "seek" || abs(playback.position - time) > 2 { playback.seek(time) }
                    if action == "play" { playback.player.play() }
                    else if action == "pause" { playback.player.pause() }
                    lastSync = Date()
                }
            }
            let chatRow = try await api.json("/api/watchparty/messages", query: ["roomId": active])
            try Task.checkCancellation()
            guard active == room else { return }
            chat = (chatRow["messages"] as? [[String: Any]] ?? []).enumerated().map { index, row in
                PartyMessage(id: "\(index)-\(row["name"] as? String ?? "")-\(row["text"] as? String ?? "")",
                             name: row["name"] as? String ?? "Guest",
                             text: row["text"] as? String ?? "")
            }
            if lastSync == .distantPast { lastSync = Date() }
            error = nil
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

struct NativeWatchParty: View {
    @ObservedObject var party: WatchPartyModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var text = ""
    @State private var flying: (symbol: String, id: UUID)?

    var body: some View {
        NavigationStack {
            ZStack {
                PartyBackdrop()
                ScrollView {
                    VStack(spacing: 18) {
                        if party.room.isEmpty { lobby } else { room }
                    }
                    .padding(18)
                }
                .scrollDismissesKeyboard(.interactively)
                if let flying {
                    Image(systemName: flying.symbol)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.pink, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .pink.opacity(0.5), radius: 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .offset(y: 90)
                        .id(flying.id)
                }
            }
            .navigationTitle(party.room.isEmpty ? "Watch Party" : "Room \(party.room)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: lobby

    private var lobby: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(LinearGradient(colors: [Color.cortexPurple, Color(red: 0.25, green: 0.6, blue: 1)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 84, height: 84)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(.black.opacity(0.8))
                }
                .shadow(color: Color.cortexPurple.opacity(0.5), radius: 24, y: 10)
                Text("Watch together").font(.system(size: 26, weight: .black))
                Text(party.subject.isEmpty ? "Playback is shared: play, pause and seek reach everyone." : party.subject)
                    .font(.footnote).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cortexPurple)
                    TextField("Display name", text: $party.name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task { await party.enter() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 15, weight: .bold))
                        Text("Create a room").font(.system(size: 15, weight: .black))
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(LinearGradient(colors: [Color.cortexPurple, Color(red: 0.36, green: 0.72, blue: 0.98)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(party.busy)
                .accessibilityIdentifier("party.create")
            }
            .padding(14)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

            VStack(spacing: 12) {
                Text("JOIN WITH A CODE").font(.system(size: 9, weight: .black)).tracking(1.6)
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    TextField("ABC123", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                        .tracking(6)
                        .padding(.horizontal, 14).frame(height: 54)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("party.code")
                    Button {
                        Task { await party.enter(code: code) }
                    } label: {
                        Text("Join")
                            .font(.system(size: 14, weight: .black))
                            .padding(.horizontal, 18).frame(height: 54)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(party.busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

            HStack(spacing: 10) {
                step(number: 1, title: "Create", detail: "or join with a code")
                step(number: 2, title: "Share", detail: "send the code")
                step(number: 3, title: "Watch", detail: "play, pause, seek")
            }

            if let error = party.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number)").font(.system(size: 10, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.cortexPurple, in: Circle())
            Text(title).font(.system(size: 12, weight: .bold))
            Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: room

    private var room: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ROOM CODE").font(.system(size: 9, weight: .black)).tracking(1.6)
                            .foregroundStyle(.white.opacity(0.45))
                        Text(party.room)
                            .font(.system(size: 30, weight: .black, design: .monospaced))
                            .tracking(4)
                    }
                    Spacer()
                    ShareLink(item: party.room) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Share room code")
                }

                HStack(spacing: 8) {
                    Circle().fill(party.synced ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(party.synced ? "In sync — play, pause and seek are shared" : "Reconnecting…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(party.members.count) here").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                }

                if !party.members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(party.members, id: \.self) { member in
                                HStack(spacing: 6) {
                                    Text(String(member.prefix(1)).uppercased())
                                        .font(.system(size: 11, weight: .black))
                                        .frame(width: 22, height: 22)
                                        .background(avatarColor(member), in: Circle())
                                        .foregroundStyle(.black)
                                    Text(member).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                }
                                .padding(.horizontal, 8).frame(height: 30)
                                .background(.white.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

            VStack(spacing: 10) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if party.chat.isEmpty {
                                Text("The room chat is empty — say hello.")
                                    .font(.footnote).foregroundStyle(.white.opacity(0.45))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                            }
                            ForEach(party.chat) { message in
                                chatBubble(message, mine: message.name == party.name)
                                    .id(message.id)
                            }
                            Color.clear.frame(height: 1).id("partyBottom")
                        }
                        .padding(.horizontal, 10)
                    }
                    .frame(minHeight: 170, maxHeight: 300)
                    .onChange(of: party.chat.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("partyBottom", anchor: .bottom) }
                    }
                }

                HStack(spacing: 8) {
                    ForEach([("heart.fill", "heart"), ("hand.thumbsup.fill", "like"),
                             ("flame.fill", "fire"), ("face.smiling.fill", "laugh")], id: \.1) { pair in
                        Button {
                            Task { await party.react(pair.1) }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                                flying = (pair.0, UUID())
                            }
                            Task {
                                try? await Task.sleep(for: .milliseconds(900))
                                withAnimation(.easeOut(duration: 0.3)) { flying = nil }
                            }
                        } label: {
                            Image(systemName: pair.0)
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.07), in: Circle())
                                .foregroundStyle(.pink)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Synced \(party.lastSync.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }

                HStack(spacing: 8) {
                    TextField("Message the room", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Button {
                        let body = text
                        text = ""
                        Task {
                            do { try await party.send(body) }
                            catch { if !(error is CancellationError), !Task.isCancelled { party.error = error.localizedDescription } }
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(text.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : Color.cortexPurple)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("party.send")
                }
            }
            .padding(12)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))

            if !party.reactions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(party.reactions, id: \.self) { reaction in
                        Text(reaction).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                party.leave()
            } label: {
                Text("Leave room")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)

            if let error = party.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func chatBubble(_ message: PartyMessage, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(message.name).font(.system(size: 9, weight: .black)).tracking(0.6)
                        .foregroundStyle(.white.opacity(0.45))
                }
                Text(message.text)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Color.cortexPurple.opacity(0.32) : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func avatarColor(_ name: String) -> Color {
        let palette: [Color] = [Color.cortexPurple, .cyan, .mint, .pink, .orange, .yellow]
        return palette[abs(name.hashValue) % palette.count]
    }
}

struct PartyBackdrop: View {
    var body: some View {
        ZStack {
            Color.cortexBlack
            Circle().fill(Color.cortexPurple.opacity(0.38)).frame(width: 300, height: 300)
                .blur(radius: 100).offset(x: -120, y: -240)
            Circle().fill(Color(red: 0.2, green: 0.7, blue: 0.95).opacity(0.25)).frame(width: 260, height: 260)
                .blur(radius: 110).offset(x: 140, y: 260)
        }
        .ignoresSafeArea()
    }
}
