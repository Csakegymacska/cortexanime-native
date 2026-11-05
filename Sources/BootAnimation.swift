import SwiftUI

/// Decides whether the boot animation may run. QA/fixture/test launches skip it so
/// screenshots and UI tests never wait behind the intro. (Nonisolated on purpose:
/// CatalogModel.fixture is MainActor-bound; all fixture/QA paths pass `--` arguments.)
enum CortexBootGate {
    static let shouldPlay: Bool = {
        let args = ProcessInfo.processInfo.arguments
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            && !args.contains { $0.hasPrefix("--") }
    }()
}

/// Short brand boot animation (~1.2s): logo spring-in, wordmark tracking-in, gradient
/// sweep. Tap to skip. Respect Reduce Motion (instant frame + quick fade). Decorative
/// only — content loads behind it and never waits on it.
struct CortexBootAnimation: View {
    var onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0.0
    @State private var finished = false
    var body: some View {
        ZStack {
            Color.cortexBlack.ignoresSafeArea()
            RadialGradient(colors:[Color.cortexPurple.opacity(0.24),Color.cyan.opacity(0.06),.clear],center:.center,startRadius:0,endRadius:430)
                .ignoresSafeArea()
            VStack(spacing:22) {
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors:[Color.cortexPurple.opacity(0.85),Color.cyan.opacity(0.45)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:2)
                        .frame(width:128,height:128)
                        .scaleEffect(0.92+phase*0.08)
                        .opacity(phase)
                    Image("CortexLogo").resizable().scaledToFit()
                        .frame(width:96,height:96)
                        .clipShape(RoundedRectangle(cornerRadius:22,style:.continuous))
                        .scaleEffect(0.82+phase*0.18)
                        .opacity(phase)
                        .shadow(color:Color.cortexPurple.opacity(0.5*phase),radius:24,y:6)
                }
                HStack(spacing:2) {
                    Text("CORTEX").font(.system(size:24,weight:.black)).foregroundStyle(.white)
                    Text(" ANIME").font(.system(size:24,weight:.black)).foregroundStyle(Color.cortexPurple)
                }
                .tracking(2+3*(1-phase))
                .opacity(max(0,min(1,(phase-0.12)/0.88)))
                Capsule()
                    .fill(LinearGradient(colors:[.clear,Color.cortexPurple,Color.cyan,.clear],startPoint:.leading,endPoint:.trailing))
                    .frame(width:max(1,190*phase),height:2.5)
                    .opacity(phase > 0.35 ? 1 : 0)
            }
            .padding(.bottom,26)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityHidden(true)
        .task {
            guard !finished else { return }
            if reduceMotion {
                phase = 1
                try? await Task.sleep(for:.milliseconds(120))
                finish(); return
            }
            withAnimation(.spring(response:0.55,dampingFraction:0.78)) { phase = 1 }
            try? await Task.sleep(for:.milliseconds(1150))
            finish()
        }
    }
    private func finish() {
        guard !finished else { return }
        finished = true
        onDone()
    }
}
