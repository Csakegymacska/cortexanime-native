import SwiftUI
import UIKit

/// One-line strip under the navigation bar. Only exists while a newer build is published.
struct UpdateBannerView: View {
    @ObservedObject var center: UpdateCenter
    @State private var copied = false

    var body: some View {
        Group {
            if let release = center.availableRelease, !center.bannerHidden {
                Button {
                    center.showSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.cortexPurple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Update available · \(release.shortLine)")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(release.sizeText.isEmpty ? "Tap to download inside the app"
                                 : "Tap to download inside the app · \(release.sizeText)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 6)
                        Text("Update")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.cortexPurple)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.cortexPanel)
                    .overlay(Rectangle().frame(height: 0.5).foregroundStyle(Color.cortexPurple.opacity(0.35)), alignment: .bottom)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Update available, version \(release.version)")
            }
        }
        .animation(.easeInOut(duration: 0.22), value: center.availableRelease)
    }
}

/// The sheet: what changed, how big, and the two honest buttons — download here, or open the
/// signer once the IPA is on the device.
struct UpdateSheetView: View {
    @ObservedObject var center: UpdateCenter
    @Environment(\.dismiss) private var dismiss
    @State private var copiedSource = false

    private var release: AppRelease? { center.availableRelease }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let release, let notes = release.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .top, spacing: 9) {
                                    Circle().fill(Color.cortexPurple).frame(width: 5, height: 5).padding(.top, 6)
                                    Text(note)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cortexPanel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    progress
                    actions
                    handOff
                }
                .padding(20)
            }
            .background(Color.cortexBlack.ignoresSafeArea())
            .navigationTitle("Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.foregroundStyle(Color.cortexPurple)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CortexAnime \(release?.version ?? "")")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
            Text("Installed: \(center.installedVersion) (\(center.installedBuild))"
                 + (release?.sizeText.isEmpty == false ? " · \(release!.sizeText)" : ""))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch center.phase {
        case .downloading(_, let progress, let bytes):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(Color.cortexPurple)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.cortexPurple)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        case .ready(_, let file):
            VStack(alignment: .leading, spacing: 6) {
                Label("Downloaded and verified", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.cortexMint)
                Text(file.lastPathComponent)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.orange)
        case .checking:
            ProgressView().tint(Color.cortexPurple)
        case .upToDate:
            Label("You are on the newest build.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.cortexMint)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            if let file = center.downloadedFile {
                ShareLink(item: file) {
                    actionLabel("Share / save the IPA", symbol: "square.and.arrow.up.fill", filled: true)
                }
                .buttonStyle(.plain)
                Button {
                    center.openSigner()
                } label: {
                    actionLabel("Open the signer", symbol: "arrow.up.forward.app.fill", filled: false)
                }
                .buttonStyle(.plain)
            } else if case .downloading = center.phase {
                actionLabel("Downloading…", symbol: "arrow.down.circle", filled: true)
                    .opacity(0.6)
            } else {
                Button {
                    center.download()
                } label: {
                    actionLabel("Download update", symbol: "arrow.down.circle.fill", filled: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var handOff: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iOS only installs signed builds. Share the downloaded IPA to Files or straight to ESign / SideStore, then sign it there — no second download in Safari.")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                UIPasteboard.general.string = UpdateCenter.sourceAddress
                copiedSource = true
                Task { try? await Task.sleep(nanoseconds: 1_800_000_000); copiedSource = false }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: copiedSource ? "checkmark.circle.fill" : "doc.on.doc")
                    Text(copiedSource ? "Source address copied" : "Copy SideStore / AltStore source")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(copiedSource ? Color.cortexMint : Color.cortexPurple)
            }
            .buttonStyle(.plain)
        }
    }

    private func actionLabel(_ title: String, symbol: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(filled ? Color.white : Color.cortexPurple)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(filled ? Color.cortexPurple : Color.cortexPanel)
        )
    }
}
