import SwiftUI

/// Local demonstration state only. Never a paid entitlement or a StoreKit transaction.
@MainActor final class BetaSubscription: ObservableObject {
    static let shared = BetaSubscription()
    private let key = "cortex.plus.beta.preview.v1"
    @Published private(set) var previewActive: Bool
    init() { previewActive = UserDefaults.standard.bool(forKey:key) }
    func simulate() { previewActive = true;UserDefaults.standard.set(true,forKey:key) }
    func cancelPreview() { previewActive = false;UserDefaults.standard.removeObject(forKey:key) }
}

struct NativeBetaTestCard: Identifiable { let id: String;let brand: String;let last4: String;let month: Int;let year: Int }
struct NativeBetaPurchase: View {
    @ObservedObject private var beta = BetaSubscription.shared
    @Environment(\.dismiss) private var dismiss
    @State private var completed = false
    @EnvironmentObject private var api: APIClient
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var cards: [NativeBetaTestCard] = []
    @State private var cardMessage: String?
    @State private var cardBusy = false
    @State private var confirmTestCard = false
    @State private var confirmRemove = false
    var body: some View {
        VStack(spacing:0) {
            ZStack {
                Text("Beta checkout").font(.headline)
                HStack { Button { dismiss() } label: { Image(systemName:"xmark").font(.title3.bold()).foregroundStyle(.white).frame(width:48,height:48).background(.white.opacity(0.08),in:Circle()) }.accessibilityLabel("Close beta checkout").accessibilityIdentifier("beta.close");Spacer() }
            }.padding(.horizontal,20).padding(.top,18)
            ScrollView {
                VStack(spacing:20) {
                    Image("CortexLogo").resizable().scaledToFit().frame(width:100,height:100).clipShape(RoundedRectangle(cornerRadius:24)).shadow(color:.cortexPurple.opacity(0.35),radius:24,y:7).scaleEffect(appeared ? 1 : 0.88).opacity(appeared ? 1 : 0).padding(.top,28)
                    VStack(spacing:7) {
                        Text("Cortex Plus").font(.title.bold())
                        Text("Monthly subscription preview").foregroundStyle(.secondary)
                        Text("BETA · NO CHARGE").font(.caption.bold()).tracking(1.5).foregroundStyle(Color.cortexPurple).padding(.horizontal,14).padding(.vertical,9).background(Color.cortexPurple.opacity(0.12),in:Capsule()).accessibilityIdentifier("beta.disclosure")
                    }
                    if completed {
                        VStack(spacing:12) {
                            Image(systemName:"checkmark.circle.fill").font(.system(size:44)).foregroundStyle(.green).symbolEffect(.bounce,value:completed)
                            Text("Demo complete").font(.title2.bold()).accessibilityIdentifier("beta.success")
                            Text("No payment was taken. This is not a real subscription.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(24).frame(maxWidth:.infinity).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:22)).transition(.scale(scale:0.92).combined(with:.opacity))
                    }
                    HStack(spacing:14) {
                        Image(systemName:"creditcard.fill").font(.title2).foregroundStyle(Color.cortexPurple).frame(width:46,height:40)
                        VStack(alignment:.leading,spacing:5) {
                            Text(cards.first.map { "\($0.brand.capitalized) ···· \($0.last4)" } ?? "Demo payment method").font(.headline)
                            Text(cards.first.map { "Stripe TEST card · \($0.month)/\($0.year)" } ?? "No card or Apple ID required").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength:0)
                    }.padding(20).frame(maxWidth:.infinity).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:22))
                    VStack(alignment:.leading,spacing:18) {
                        HStack { Text("€15 / month").font(.title3.bold());Spacer();Text("Preview price").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        HStack { Text("Charged today");Spacer();Text("€0.00").font(.headline).foregroundStyle(.green) }.accessibilityIdentifier("beta.zeroCharge")
                        Text("This beta does not take payments and does not renew automatically. You can cancel or repeat the preview at any time.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        Divider()
                        Text("This is a Cortex demo screen, not an Apple Pay or App Store purchase sheet. No Wallet connection, bank authorization or real subscription is created.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }.padding(20).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:22))
                    VStack(alignment:.leading,spacing:10) {
                        Text("Test cards only").font(.caption.bold()).foregroundStyle(Color.cortexPurple).accessibilityIdentifier("beta.testCardsOnly")
                        Text("Card numbers stay on Stripe's protected test page. Do not enter a real bank card. Saving a test card does not subscribe or charge you.").font(.caption).foregroundStyle(.secondary)
                        if api.signedIn {
                            Button("Save a Stripe TEST card") { confirmTestCard = true }.frame(minHeight:44).disabled(cardBusy).accessibilityIdentifier("beta.saveTestCard")
                            HStack { Button("Refresh saved test cards") { Task { await refreshCards() } }.frame(minHeight:44);if !cards.isEmpty { Button("Remove test card",role:.destructive) { confirmRemove = true }.frame(minHeight:44) } }.font(.caption).disabled(cardBusy)
                        } else { Link("Sign in on the website to manage test cards",destination:URL(string:"https://cortanime.eu/plus")!).font(.caption).frame(minHeight:44) }
                        if let cardMessage { Text(cardMessage).font(.caption).foregroundStyle(.secondary) }
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:18))
                    if beta.previewActive && !completed { Text("Demo preview active on this device").font(.caption).foregroundStyle(.green).accessibilityIdentifier("beta.active") }
                }.padding(.horizontal,20).padding(.bottom,24)
            }
            VStack(spacing:10) {
                if completed {
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(.cortexPurple).frame(maxWidth:.infinity,minHeight:48).accessibilityIdentifier("beta.done")
                } else if beta.previewActive {
                    Button("Cancel demo preview",role:.destructive) { beta.cancelPreview() }.frame(maxWidth:.infinity,minHeight:48).accessibilityIdentifier("beta.cancel")
                } else {
                    Button { withAnimation(reduceMotion ? nil : .spring(response:0.48,dampingFraction:0.78)) { beta.simulate();completed = true } } label: { Text("Simulate subscription").font(.headline).frame(maxWidth:.infinity,minHeight:52) }.buttonStyle(.borderedProminent).tint(.cortexPurple).accessibilityIdentifier("beta.simulate")
                }
                Text("Preview only · No payment · No auto-renewal").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.padding(.horizontal,24).padding(.top,12).padding(.bottom,18)
        }.background(Color(red:0.09,green:0.09,blue:0.11)).preferredColorScheme(.dark).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(30)
            .onAppear { withAnimation(reduceMotion ? nil : .spring(response:0.55,dampingFraction:0.8)) { appeared = true } }
            .sensoryFeedback(.success,trigger:completed)
            .task(id:api.user?.id) { await refreshCards() }
            .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await refreshCards() } } }
            .alert("Stripe TEST cards only",isPresented:$confirmTestCard) {
                Button("Continue to Stripe test page") { Task { await saveTestCard() } };Button("Cancel",role:.cancel) {}
            } message: { Text("Use only test number 4242 4242 4242 4242 with a future expiry and test CVC. Never use your real bank card. No subscription or charge is created.") }
            .alert("Remove saved TEST card?",isPresented:$confirmRemove) {
                Button("Remove",role:.destructive) { Task { await removeTestCard() } };Button("Cancel",role:.cancel) {}
            } message: { Text("This removes the selected test card from your Stripe test customer.") }
    }
    private func refreshCards() async {
        guard api.signedIn else { cards = [];return }
        do {
            let row = try await api.json("/api/plus/cards")
            cards = ((row["cards"] as? [[String:Any]]) ?? []).compactMap { c in
                guard let id = c["id"] as? String,let brand = c["brand"] as? String,let last4 = c["last4"] as? String,c["testMode"] as? Bool == true else { return nil }
                return NativeBetaTestCard(id:id,brand:brand,last4:last4,month:c["expMonth"] as? Int ?? 0,year:c["expYear"] as? Int ?? 0)
            };cardMessage = cards.isEmpty ? "No saved Stripe test card." : "Saved test card loaded securely from Stripe."
        } catch { if !(error is CancellationError),!Task.isCancelled { cardMessage = error.localizedDescription } }
    }
    private func saveTestCard() async {
        guard !cardBusy else { return };cardBusy = true;defer { cardBusy = false }
        do {
            let row = try await api.json("/api/plus/cards/setup",method:"POST",body:["testCardOnly":true])
            guard row["testMode"] as? Bool == true,row["mode"] as? String == "setup",let raw = row["url"] as? String,let url = URL(string:raw),url.scheme == "https",url.host == "checkout.stripe.com" else { throw AppFailure.message("The Stripe test-card address is unavailable.") }
            openURL(url)
        } catch { if !(error is CancellationError),!Task.isCancelled { cardMessage = error.localizedDescription } }
    }
    private func removeTestCard() async {
        guard !cardBusy,let card = cards.first else { return };cardBusy = true;defer { cardBusy = false }
        do { _ = try await api.json("/api/plus/cards/remove",method:"POST",body:["id":card.id]);await refreshCards() }
        catch { if !(error is CancellationError),!Task.isCancelled { cardMessage = error.localizedDescription } }
    }
}

#if DEBUG
struct BetaPurchaseQALobby: View {
    @ObservedObject private var beta = BetaSubscription.shared
    @State private var show = false
    var body: some View {
        VStack(spacing:24) {
            Text("Cortex Plus beta").font(.title.bold())
            Text(beta.previewActive ? "Demo preview active" : "Demo preview inactive").accessibilityIdentifier("beta.lobby.status")
            Button("Preview subscription") { show = true }.buttonStyle(.borderedProminent).accessibilityIdentifier("beta.open")
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.cortexBlack).sheet(isPresented:$show) { NativeBetaPurchase() }
    }
}
#endif
