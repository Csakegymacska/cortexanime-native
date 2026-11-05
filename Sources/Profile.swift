import SwiftUI
import PhotosUI

struct NativeProfile: View {
    @EnvironmentObject private var api: APIClient
    @EnvironmentObject private var catalog: CatalogModel
    @ObservedObject private var library = AnimeLibrary.shared
    @ObservedObject private var store = CreditStore.shared
    @State private var login = false
    @State private var showBetaPurchase = false
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var motion = MotionSettings.shared
    @ObservedObject private var layout = LayoutPreferences.shared
    @Environment(\.cortexLayoutMode) private var layoutMode
    @State private var signInPulse = false
    @State private var decorationSheet = false
    @State private var decorationDraft = ""
    @ObservedObject private var studio = Studio8.shared

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                ProfileHeader8(name: api.user?.username ?? "Your Cortex Profile",
                               avatar: api.user?.avatar,
                               banner: api.user?.banner,
                               status: api.user?.status,
                               accent: studio.accentHex.isEmpty ? ProfileAccent.color(api.user?.accent) : studio.accent,
                               level: store.level,
                               progress: store.levelProgress,
                               balance: store.balance,
                               streak: store.streakDays,
                               episodes: store.episodesCompleted,
                               badges: ProfileBadge.all.filter { store.badgesEarned.contains($0.id) },
                               signedIn: api.signedIn,
                               onSignIn: { login = true })
                    .padding(.bottom, 30)

                    if !studio.hideStats {
                        LazyVGrid(columns:[GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10)],spacing:10) {
                            StatCard(icon:"play.circle.fill",value:"\(store.episodesCompleted)",label:"episodes")
                            StatCard(icon:"clock.fill",value:String(format:"%.1f h",store.totalSeconds/3600.0),label:"watch time",color:.cyan)
                            StatCard(icon:"checkmark.seal.fill",value:"\(store.seriesCompleted)",label:"series finished",color:.mint)
                        }
                    }
                }.frame(maxWidth:.infinity).padding(.vertical,6)
            }.listRowBackground(Color.cortexPanel)
            .task { _ = ProfileBadge.evaluate(store:store) }
            .onChange(of: store.equipped) { value in
                guard api.signedIn else { return }
                Task { _ = try? await api.json("/api/user/profile", method: "PATCH", body: ["decoration": value]) }
            }

            Section("Credits & profile") {
                NavigationLink { NativeDecorationShop() } label: {
                    HStack {
                        Label("Credit shop · decorations",systemImage:"star.circle.fill")
                        Spacer()
                        Text("\(CortexDecoration.all.filter { store.isUnlocked($0.id) }.count)/\(CortexDecoration.all.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("profile.shop")
                Button {
                    decorationSheet = true
                } label: {
                    HStack {
                        Label("Avatar decorations", systemImage: "sparkles")
                        Spacer()
                        NativeAvatar(raw: api.user?.avatar, decoration: store.equipped).frame(width: 30, height: 30)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("profile.decorations")
                NavigationLink { NativeStatsView() } label: { Label("Statistics & badges",systemImage:"chart.bar.fill") }
                    .accessibilityIdentifier("profile.stats")
                NavigationLink { Studio8View() } label: { Label("Studio 8 · profile designer",systemImage:"slider.horizontal.3") }
                    .accessibilityIdentifier("profile.studio8")
                NavigationLink { HomeLayout8View() } label: { Label("Home layout",systemImage:"rectangle.3.group") }
                    .accessibilityIdentifier("profile.homelayout")
                NavigationLink { CaptionStudio8View() } label: { Label("Subtitles & captions",systemImage:"textformat.size") }
                    .accessibilityIdentifier("profile.captions")
                NavigationLink { PlaybackExtras8View() } label: { Label("Playback speed & seek",systemImage:"speedometer") }
                    .accessibilityIdentifier("profile.playback")
                NavigationLink { History8View() } label: { Label("Watch history",systemImage:"clock.arrow.circlepath") }
                    .accessibilityIdentifier("profile.history")
                if api.signedIn {
                    NavigationLink { NativeProfileStudio() } label: { Label("Customise profile",systemImage:"paintpalette") }
                        .accessibilityIdentifier("profile.studio")
                    NavigationLink { NativeEditProfile() } label: { Label("Edit profile",systemImage:"person.crop.circle.badge.pencil") }
                }
            }

            Section {
                WeeklyRecapCard(store: store)
                    .listRowInsets(EdgeInsets(top:6, leading:0, bottom:6, trailing:0))
                    .listRowBackground(Color.clear)
            }

            Section("My badges") {
                let earned = ProfileBadge.all.filter { store.badgesEarned.contains($0.id) }
                if earned.isEmpty {
                    Text("You don't have any badges yet — watch an episode and your first one will arrive!").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:10) {
                            ForEach(earned) { badge in
                                VStack(spacing:5) {
                                    Image(systemName:badge.icon).font(.system(size:17,weight:.bold)).foregroundStyle(badge.rarity >= 3 ? .yellow : badge.rarity >= 2 ? Color.cortexPurple : .cyan)
                                    Text(badge.name).font(.system(size:9.5,weight:.black)).lineLimit(1)
                                }
                                .frame(width:76).padding(.vertical,10)
                                .background(Color.cortexPanel,in: RoundedRectangle(cornerRadius:12))
                            }
                        }.padding(.vertical,4)
                    }
                }
            }

            if !studio.hideCollection {
            Section("Showcase · Favorites") {
                let favs = (catalog.titles + catalog.trending + catalog.seasonal + library.history.map(\.anime)).filter { library.favorites.contains($0.id) }
                if favs.isEmpty {
                    Text("Add favorites and they will appear here.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal,showsIndicators:false) {
                        LazyHStack(alignment:.top,spacing:12) {
                            ForEach(Array(favs.prefix(6))) { anime in
                                NavigationLink { NativeLinkedDetail(id:anime.id) } label: {
                                    VStack(spacing:6) {
                                        AnimeArtwork(url:anime.cover).frame(width:88,height:132).clipShape(RoundedRectangle(cornerRadius:12))
                                        Text(anime.title).font(.system(size:10,weight:.bold)).lineLimit(1).frame(width:88)
                                    }
                                }.buttonStyle(.plain)
                                    .cortexShelfTilt(strength:12)
                            }
                        }.scrollTargetLayout().padding(.vertical,4)
                    }.scrollTargetBehavior(.viewAligned)
                }
            }
            }

            Section("Motion") {
                Toggle(isOn: $motion.cardTilt) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("3D card motion")
                        Text("Shelf cards tilt as they scroll and the hero leans with your swipe, artwork only — the text stays still. Turn it off for a completely flat interface.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.card3d")
                Text("The system Reduce Motion setting overrides this switch.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Layout") {
                Toggle(isOn: $layout.forceWide) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Always use the wide layout")
                        Text("For an unfolded foldable iPhone. A 74 pt icon rail on the left and the full width for content, instead of the five bottom tabs. It switches over automatically when the display is wide enough — turn this on only if the unfolded screen stays on the tab layout.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.forceWide")
                Text("Current layout: \(layoutMode.title)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.layoutMode")
            }

            Section("Cortex Plus · Beta") {
                Button { showBetaPurchase = true } label: { Label("Preview subscription · No charge",systemImage:"creditcard") }
                    .frame(minHeight:44)
                    .accessibilityIdentifier("profile.betaPurchase")
                Text("Demo only. No real payment or automatic renewal.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Your library") {
                NavigationLink { NativeRadar() } label: { Label("For You · Cortex Radar",systemImage:"sparkles") }
                NavigationLink { NativeAlerts() } label: {
                    Label { Text("Episode alerts") } icon: { Image(systemName:"bell.badge") }
                }
                NavigationLink { NativeNotificationSettings() } label: {
                    Label { Text("Subtitle notifications") } icon: { Image(systemName:"bell.and.waves.left.and.right") }
                }.accessibilityIdentifier("settings.notifications")
                NavigationLink { NativeSubtitleRadar() } label: {
                    Label { Text("Subtitle radar") } icon: { Image(systemName:"captions.bubble") }
                }.accessibilityIdentifier("settings.subtitleRadar")
                NavigationLink { NativeWatchlist() } label: { Label("Watchlist",systemImage:"bookmark") }
                NavigationLink { NativeHistory() } label: { Label("Continue watching & history",systemImage:"clock.arrow.circlepath") }
                NavigationLink { NativeDownloads() } label: { Label("Downloads",systemImage:"arrow.down.circle") }
            }

            Section("Community") {
                NavigationLink { NativeFriends() } label: {
                    HStack {
                        Label("Friends & user search",systemImage:"person.2")
                        Spacer()
                        FriendRequestBadge()
                    }
                }
                NavigationLink { NativeMessages() } label: {
                    HStack {
                        Label("Messages",systemImage:"bubble.left.and.bubble.right")
                        Spacer()
                        MessagesUnreadBadge()
                    }
                }
                if api.signedIn {
                    NavigationLink { NativeEditProfile() } label: { Label("Edit profile",systemImage:"person.crop.circle.badge.pencil") }
                    NavigationLink { NativeAniList() } label: { Label("AniList link & sync",systemImage:"link") }
                    NavigationLink { NativePublicProfile(id:api.user!.id) } label: { Label("Public profile & activity",systemImage:"person.text.rectangle") }
                }
            }

            Section("Explore") {
                NavigationLink { NativeBrowse(mode:.movies) } label: { Label("Movies",systemImage:"film") }
                NavigationLink { NativeSchedule() } label: { Label("Release schedule",systemImage:"calendar") }
                NavigationLink { NativeManga() } label: { Label("Manga",systemImage:"book") }
            }

            Section("CortexAnime") {
                NavigationLink { Lab15View() } label: {
                    HStack(spacing: 10) {
                        Label("Cortex Lab",systemImage:"flask.fill")
                        Spacer()
                        Text("150")
                            .font(.system(size:10.5,weight:.black))
                            .padding(.horizontal,7).padding(.vertical,3)
                            .background(Color.cortexPurple.opacity(0.22),in:Capsule())
                            .foregroundStyle(Color.cortexPurple)
                    }
                }.accessibilityIdentifier("profile.lab15")
                NavigationLink { NativeSettings() } label: { Label("Settings",systemImage:"gearshape") }
                NavigationLink { NativeReleases() } label: { Label("New in Hungarian",systemImage:"sparkles.tv.fill") }.accessibilityIdentifier("profile.releases")
                Button { UserDefaults.standard.set(false, forKey: WhatsNew.key); notificationShowWhatsNew() } label: { Label("What's new in \(WhatsNew.version)",systemImage:"party.popper") }
                NavigationLink { NativeWidgetSetup() } label: { Label("Home Screen widget",systemImage:"square.grid.2x2") }.accessibilityIdentifier("widgets.setup")
                NavigationLink("FAQ") { NativeInformation(kind:.faq) }
                NavigationLink("Privacy Policy") { NativeInformation(kind:.privacy) }
                NavigationLink("DMCA") { NativeInformation(kind:.dmca) }
                Link("Contact",destination:URL(string:"mailto:cortex@cortexanime.eu")!)
                if api.signedIn {
                    Button("Sign out",role:.destructive) {
                        Task { do { try await api.logout() } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } } }
                    }
                    .frame(minHeight:44)
                    .buttonStyle(.bordered)
                }
                if let error { ErrorNotice(text:error) }
            }

            Section {
                    Text("CortexAnime \(DeviceInfo.version) (\(DeviceInfo.build)) · \(layoutMode.title) layout · SwiftUI + AVPlayer\nUnsigned builds require signing before installation.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.version")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.cortexBlack)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$showBetaPurchase) { NativeBetaPurchase() }
        .sheet(isPresented:$login) { NavigationStack { NativeAuthentication() } }
        // 6.8: the decoration picker opens straight from Profile, resizes properly in a sheet,
        // and equips immediately — the store already holds the choice, so no Save is needed.
        .sheet(isPresented: $decorationSheet) {
            NavigationStack {
                NativeDecorations(selected: $decorationDraft)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { if decorationDraft.isEmpty { decorationDraft = store.equipped } }
        .onChange(of: decorationDraft) { _, value in
            guard !value.isEmpty, value != store.equipped else { return }
            store.equip(value)
            guard api.signedIn else { return }
            // The server stores one id; the local stack keeps both layers.
            let primary = CortexDecoration.list(value).first(where: { $0.slot == .frame })?.id
                ?? CortexDecoration.list(value).first?.id ?? "none"
            Task { _ = try? await api.json("/api/user/profile", method: "PATCH", body: ["decoration": primary]) }
        }
        .overlay {
            if let level = store.pendingLevelUp {
                LevelUpOverlay(level: level) { store.clearLevelUp() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.pendingLevelUp)
    }
}

extension Notification.Name { static let cortexShowWhatsNew = Notification.Name("cortex.showWhatsNew") }
func notificationShowWhatsNew() { NotificationCenter.default.post(name: .cortexShowWhatsNew, object: nil) }

struct NativeAuthentication: View {
    @EnvironmentObject private var api: APIClient
    @Environment(\.dismiss) private var dismiss
    @State private var registering = false
    @State private var verification = false
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @State private var message: String?
    @State private var authPulse = false
    @State private var showingPassword = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        AuthMark()
                        Text(registering ? "Create your account" : "Welcome back")
                            .font(.system(size: 26, weight: .black))
                            .foregroundStyle(.white)
                        Text(registering
                             ? "One account for the watchlist, credits, decorations and messages."
                             : "Sign in to keep your watchlist, credits and decorations in sync.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .padding(.top, 18)

                    AuthModeSwitch(registering: $registering)

                    VStack(spacing: 12) {
                        AuthField(symbol: "envelope.fill", title: "Email") {
                            TextField("you@example.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("auth.email")
                        }
                        if registering {
                            AuthField(symbol: "person.fill", title: "Username") {
                                TextField("cortexfan", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                        AuthField(symbol: "lock.fill", title: "Password") {
                            HStack(spacing: 8) {
                                Group {
                                    if showingPassword {
                                        TextField("At least 8 characters", text: $password)
                                            .textContentType(registering ? .newPassword : .password)
                                    } else {
                                        SecureField("At least 8 characters", text: $password)
                                            .textContentType(registering ? .newPassword : .password)
                                    }
                                }
                                .accessibilityIdentifier("auth.password")
                                Button {
                                    showingPassword.toggle()
                                } label: {
                                    Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.55))
                                        .frame(width: 34, height: 34)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showingPassword ? "Hide password" : "Show password")
                            }
                        }
                        if verification {
                            AuthField(symbol: "checkmark.shield.fill", title: "Verification code") {
                                TextField("123456", text: $code)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                            }
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack(spacing: 9) {
                            if busy { ProgressView().tint(.black) }
                            Text(verification ? "Verify email" : registering ? "Create account" : "Sign in")
                                .font(.system(size: 15, weight: .black))
                            if !busy { Image(systemName: "arrow.right").font(.system(size: 13, weight: .black)) }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(LinearGradient(colors: [Color.cortexPurple, Color(red: 0.36, green: 0.72, blue: 0.98)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || email.isEmpty || (!verification && password.isEmpty))
                    .opacity(busy || email.isEmpty || (!verification && password.isEmpty) ? 0.45 : 1)
                    .accessibilityIdentifier("auth.submit")

                    if verification {
                        Button("Resend code") { Task { await resend() } }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.cortexPurple)
                            .disabled(busy)
                            .frame(minHeight: 44)
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if let message {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text("Email sign-in only: the website's OAuth callbacks open a browser session, which a separate native app cannot reuse securely. AniList linking is available after you sign in.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.cortexBlack)
        .navigationTitle("Cortex Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: registering)
        .animation(.easeInOut(duration: 0.22), value: verification)
    }

    private func submit() async {
        busy = true;error = nil;defer { busy = false }
        do {
            if verification {
                _ = try await api.json("/api/auth/verify-email",method:"POST",body:["email":email,"code":code])
                try api.persistSession();await api.refreshAccount()
                if api.signedIn {
                    password = "";dismiss()
                } else {
                    message = "Email verified. Please sign in.";verification = false;registering = false
                }
                return
            }
            if registering {
                let verificationRequired = try await api.register(username: username, email: email, password: password)
                if verificationRequired {
                    verification = true;message = "Check your email for a verification code."
                } else {
                    dismiss()
                }
            } else {
                try await api.login(email:email,password:password)
                dismiss()
            }
        } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func resend() async {
        busy = true;defer { busy = false }
        do {
            _ = try await api.json("/api/auth/resend-code",method:"POST",body:["email":email])
            message = "A new verification code was requested."
        } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct NativeEditProfile: View {
    @EnvironmentObject private var api: APIClient
    @State private var username = ""
    @State private var bio = ""
    @State private var decoration = "none"
    @State private var avatar = ""
    @State private var banner = ""
    @State private var code = ""
    @State private var image: PhotosPickerItem?
    @State private var bannerImage: PhotosPickerItem?
    @State private var message: String?
    @State private var error: String?
    @State private var busy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savePulse = false

    var body: some View {
        Form {
            // 6.8: a live preview, so the decorated avatar is visible while editing instead of
            // hiding behind a 44 pt row somewhere in the middle of the form.
            Section {
                VStack(spacing: 12) {
                    NativeAvatar(raw: avatar.isEmpty ? nil : avatar, decoration: decoration)
                        .frame(width: 132, height: 132)
                        .frame(maxWidth: .infinity)
                    Text(CortexDecoration.list(decoration).map(\.name).joined(separator: " + ").isEmpty
                         ? "No decoration" : CortexDecoration.list(decoration).map(\.name).joined(separator: " + "))
                        .font(.system(size: 13, weight: .bold))
                    NavigationLink {
                        NativeDecorations(selected: $decoration)
                    } label: {
                        Label("Choose a decoration", systemImage: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.cortexPurple.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.cortexPurple)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.decorations.choose")
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section("Profile") {
                TextField("Username",text:$username).textInputAutocapitalization(.never)
                TextField("Bio (up to 300 characters)",text:$bio,axis:.vertical).lineLimit(3...6)
                Text("\(bio.count)/300").font(.caption).foregroundStyle(.secondary)
                TextField("Avatar HTTPS URL",text:Binding(get:{ avatar.hasPrefix("data:") ? "" : avatar },set:{ avatar = $0 })).textInputAutocapitalization(.never).keyboardType(.URL)
                PhotosPicker("Choose avatar",selection:$image,matching:.images)
                TextField("Banner HTTPS URL",text:Binding(get:{ banner.hasPrefix("data:") ? "" : banner },set:{ banner = $0 })).textInputAutocapitalization(.never).keyboardType(.URL)
                PhotosPicker("Choose banner",selection:$bannerImage,matching:.images)
                NavigationLink {
                    NativeDecorations(selected:$decoration)
                } label: {
                    HStack {
                        NativeAvatar(raw:avatar,decoration:decoration).frame(width:44,height:44)
                        Text("Avatar decorations")
                        Spacer()
                        Text(CortexDecoration.list(decoration).map(\.name).joined(separator: " + ").isEmpty
                             ? "No decoration" : CortexDecoration.list(decoration).map(\.name).joined(separator: " + "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Save profile") {
                    Task { await save() }
                }
                .disabled(busy || bio.count > 300)
                .frame(minHeight:44)
                .buttonStyle(.borderedProminent)
                .scaleEffect(busy ? 0.97 : (savePulse ? 1.02 : 1.0))
                .animation(reduceMotion ? nil : .easeInOut(duration:2.2).repeatForever(autoreverses:true),value:savePulse)
                .onAppear { savePulse = true }
            }

            Section("Verify email") {
                Button("Send verification code") {
                    Task { await action("/api/auth/profile-send-code",body:[:],success:"Verification email requested.") }
                }
                .disabled(busy)
                .frame(minHeight:44)
                TextField("Code",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                Button("Verify code") {
                    Task { await action("/api/auth/profile-verify-code",body:["code":code],success:"Email verified.") }
                }
                .disabled(code.isEmpty || busy)
                .frame(minHeight:44)
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(.green).symbolEffect(.bounce,value:message.count)
                }
            }
            if let error {
                Section {
                    ErrorNotice(text:error)
                }
            }
        }
        .navigationTitle("Edit profile")
        .task {
            username = api.user?.username ?? ""
            bio = api.user?.bio ?? ""
            decoration = api.user?.decoration ?? "none"
            avatar = api.user?.avatar ?? ""
            do {
                let r = try await api.json("/api/user/\(api.user?.id ?? 0)")
                if let u = r["user"] as? [String:Any] {
                    banner = u["banner"] as? String ?? ""
                }
            } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onChange(of:image) { _,value in Task { await select(value,banner:false) } }
        .onChange(of:bannerImage) { _,value in Task { await select(value,banner:true) } }
    }

    private func select(_ item: PhotosPickerItem?,banner: Bool) async {
        do {
            guard let bytes = try await item?.loadTransferable(type:Data.self),let image = UIImage(data:bytes) else { return }
            let maxWidth: CGFloat = banner ? 1280 : 512
            let factor = min(1,maxWidth/image.size.width)
            let size = CGSize(width:image.size.width*factor,height:image.size.height*factor)
            let rendered = UIGraphicsImageRenderer(size:size).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }
            guard let jpg = rendered.jpegData(compressionQuality:0.7) else { return }
            let value = "data:image/jpeg;base64,"+jpg.base64EncodedString()
            guard value.count <= 600000 else { throw AppFailure.message("Choose a smaller image.") }
            if banner { self.banner = value } else { avatar = value }
        } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func save() async {
        busy = true;defer { busy = false }
        do {
            _ = try await api.json("/api/user/profile",method:"PATCH",body:["username":username,"bio":bio,"avatar":avatar,"banner":banner,"decoration":decoration])
            await api.refreshAccount()
            message = "Profile saved."
            error = nil
        } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
    }

    private func action(_ path: String,body: [String:Any],success: String) async {
        busy = true;defer { busy = false }
        do {
            _ = try await api.json(path,method:"POST",body:body)
            message = success;error = nil
        } catch { if !(error is CancellationError),!Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct NativeSettings: View {
    @AppStorage("player.skipIntro") private var skip = true
    @AppStorage("player.skipOutro") private var skipOutro = true
    @AppStorage("catalog.adult") private var adult = false
    @AppStorage("player.autoNext") private var autoNext = false
    @State private var clear = false
    var body: some View {
        Form {
            AppearanceSection()
            Section("CortexPlayer") {
                Toggle("Show intro skip",isOn:$skip)
                Toggle("Show outro skip",isOn:$skipOutro)
                Toggle("Automatically play next episode",isOn:$autoNext)
                Text("Playback stays inside the native CortexPlayer. Sidecar subtitles display inside the app, not in Picture in Picture or AirPlay.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Catalog") {
                Toggle("Include adult catalog metadata (18+)",isOn:$adult)
                Text("Only enable this if you are 18 or older.").font(.caption).foregroundStyle(.secondary)
            }
            StorageSection()
            Section("Local history") {
                Button("Clear watch history",role:.destructive) { clear = true }
                Text("Account watchlists are not deleted.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Build") {
                Text("Genuine native SwiftUI screens. No embedded website or provider iframe.").font(.caption)
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear this app's local watch history?",isPresented:$clear) {
            Button("Clear history",role:.destructive) { AnimeLibrary.shared.clearHistory() }
        }
    }
}
