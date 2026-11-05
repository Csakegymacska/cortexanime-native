import SwiftUI

// MARK: - 7.2: the sign-in screen, rebuilt
//
// The old screen was a Form with a segmented control: correct, but it read like a settings page.
// This is the same flow (email → optional username → password → verification code) drawn as a
// single surface: a lit backdrop, one mark, two modes and glass fields.

struct AuthBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        ZStack {
            Color.cortexBlack
            Circle()
                .fill(Color.cortexPurple.opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: drift ? -110 : -140, y: drift ? -260 : -220)
            Circle()
                .fill(Color(red: 0.20, green: 0.72, blue: 0.95).opacity(0.38))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: drift ? 150 : 120, y: drift ? 240 : 280)
            Circle()
                .fill(Color(red: 1.0, green: 0.45, blue: 0.62).opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 110)
                .offset(x: drift ? -160 : -130, y: drift ? 300 : 260)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

struct AuthMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.cortexPurple, Color(red: 0.35, green: 0.75, blue: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 76, height: 76)
                .shadow(color: Color.cortexPurple.opacity(0.45), radius: 22, y: 8)
            Image(systemName: "play.fill")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.black.opacity(0.82))
                .offset(x: 2)
            Circle()
                .fill(.white)
                .frame(width: 9, height: 9)
                .offset(x: 24, y: -24)
        }
        .accessibilityHidden(true)
    }
}

struct AuthModeSwitch: View {
    @Binding var registering: Bool

    var body: some View {
        HStack(spacing: 4) {
            segment("Sign in", active: !registering) { registering = false }
            segment("Create account", active: registering) { registering = true }
        }
        .padding(4)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.09), lineWidth: 1))
    }

    private func segment(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: active ? .black : .semibold))
                .foregroundStyle(active ? .black : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(active ? Color.white : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

struct AuthField<Content: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.cortexPurple.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.cortexPurple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.42))
                content()
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}
