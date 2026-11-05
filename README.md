# CortexAnime Native — isolated full-port candidate

A genuine **SwiftUI** iOS application with an **AVPlayerLayer** video surface and app-owned CortexPlayer controls. No website shell, PWA, WKWebView or provider iframe.

**Full parity is not yet certified.** `PARITY.md` separates implemented code from live, simulated, account and physical-device verification.

## Current device build: 0.4.0 (3), compiled with WidgetKit

On 20 October 2026, Apple's Xcode 26.3 successfully archived the current metadata/navigation/gesture/widget source in private run `39486840314`, source commit `bebee12c4cb8217e69fdce25da29e70442cbcd29`. Both the host and embedded WidgetKit extension are genuine **arm64 physical-iOS Mach-O executables**. The downloaded IPA passed the strict local verifier independently of CI.

- File: `CortexAnimeNative-0.4.0-build3-UNSIGNED.ipa`.
- Size: **1,831,592 bytes**.
- SHA-256: `69b6dbec70e22607d26488ef911420f19ba45dc7e5995fb7882f1febc409565d`.
- Host: `eu.cortex.anime.port`; embedded extension: `eu.cortex.anime.port.widget`; both version `0.4.0`, build `3`, minimum iOS 18.
- **Unsigned, no provisioning profile, not installable before valid signing.** Physical iPhone, ESign compatibility and actual Home Screen widget registration remain untested.
- The original build-2 IPA is preserved separately. Build 2 had the user's real HTTP-400/navigation bugs and contains no widget; re-signing it cannot add these corrections.

The same Mac run also passed the exact-current-source live Swift/Foundation caption probe: Dark Summoner episode 2 EN **196** dialogue cues; episode 3 EN **232**; BLEACH episode 9 HU **308**. Mislabeled storyboard tracks were excluded. This is not iPhone display/playback proof.

**Do not mark that whole Actions run green:** its simulator stage exhausted the bounded time budget during boot/compilation, before XCTest execution; the overall conclusion was cancelled. The bounded continuations used the same production source. **Final result:** 26/26 native Mac/Foundation model/gesture/widget/metadata checks passed, and an iOS18.5 Release simulator app compiled; simulator runtime timed out before any accepted launch/screenshot. Current iOS XCTest/UI cases did not execute successfully. See `BUILD3-STATUS.md`; no pending/failed/skipped case is counted as passed.

## Corrected metadata and single native navigation

The user's installed build 2 exposed an invalid `sort` argument on `Media.airingSchedule`. Current source removes it, uses root `Page.airingSchedules` for latest released data, reads HU `currentEpisodes`, preserves explicit known release/HU data on refresh, and never turns a planned total into playable episodes.

The port uses retained per-tab NavigationStacks with **one black safe-area-integrated bottom bar**, purple active icon/text/marker, 60-point buttons, no system TabView, gray material capsule or duplicate bar. Current native source was Apple-compiled; runtime results must be read separately from this statement.

The previous **11/11** live GraphQL contract checks cover Home, search/browse/season/movies, four details, schedule and extras. These were transport/schema checks, not a substitute for the current native simulator/live tests.

## Both requested 3D/drag interactions

- Bottom navigation: continuous drag-to-select with purple marker, bounded perspective and tap fallback.
- Spotlight: horizontal swipe/tilt, vertical-drag rejection and paused auto-advance during dragging.
- Shelves: native card-aligned scrolling and 3D scroll transitions.
- Reduce Motion: flat/no-spring fallback; shared finite-input/clamping policy.

All of this is in the compiled build-3 source. `Previews/` contains earlier **browser mock-ups**, not native screenshots or embedded app pages. Genuine new simulator captures, if produced, are identified separately in the current report. Physical gesture/performance acceptance is still pending.

## Latest aired episodes widget

Embedded native `CortexEpisodesWidget`, small/medium, shared Foundation feed/query and dedicated privacy manifest. It shows recent non-adult public anime airings, cover/title/episode and native detail links. No account, cookie sharing, App Group or video/HU-availability claim. Failed refreshes use an extension-local cache labeled “Saved”; iOS controls actual timeline scheduling despite the roughly 30-minute refresh request.

The new port registers **`cortexanime-native-port`**, leaving the preserved original app's `cortexanime` scheme alone. `Profile → Home Screen widget` gives manual-add/signing help and checks for extension files, **not certificate validity**. Launch requests a refresh, not automatic Home Screen placement.

The compiled IPA contains `PlugIns/CortexEpisodesWidget.appex`. Sign **both** host and extension with compatible team/profiles/identifiers, preserve PlugIns, launch the host once, then manually add the widget. Read `WIDGET-SIGNING.md`. Device signing/installation/gallery appearance is not certified.

## Isolation and code map

Existing website/Worker, original `cortex_ios`, previous app identifiers and original IPAs remain unchanged. Only an explicitly authorized new private native repository/branch receives allowlisted source. No Agent/model package, API key, PAT, signing key, provisioning profile or production Worker source is uploaded.

- `App.swift`, `Design.swift`, `Home.swift`, `Browse.swift`: native navigation/catalogs/branding.
- `API.swift`, `Catalog.swift`, `MetadataQueries.swift`: transport and metadata/stream contracts.
- `Detail.swift`, `DetailExtras.swift`, `Schedule.swift`: native metadata/episode/detail screens.
- `NativePlayer.swift`, `PlayerControls.swift`, `CaptionPolicy.swift`: own native player and captions.
- `SubtitleCache.swift`: bounded caption cache/export, not unauthorized generic video downloading.
- `Profile.swift`, `Collections.swift`, `Social.swift`, `WatchParty.swift`, `Decorations.swift`, `Explore.swift`: account/library/community/other views.
- `Shared/`, `WidgetExtension/`, `WidgetSetup.swift`: public latest-airing widget and manual setup.

## Reproduce on an existing Mac

Xcode 26+, XcodeGen, iOS 18+ device target:

```sh
xcodegen generate --spec project.yml
bash Build/archive-native.sh
```

The archive script stages a **fresh** IPA and verifies both executables, iOS platform, bundle IDs/versions, extension point, privacy manifests, isolated URL scheme and unsigned state before replacing output.

Run `bash Build/probe-native-models.sh` to reproduce the Mac/Foundation checks separately from UI tests. Run the generated `CortexAnimeNative` scheme for simulator tests. Its test environment sets `CORTEX_LIVE_QA=1`; verify live cases actually execute, not skip. Live tests read Home/detail and play Dark Summoner 2/3. They do not send real login/registration credentials, emails, comments, messages, friend requests or Watch Party mutations.

Recorded BLEACH metadata and the authored H.264/AAC color-bar/tone clip are explicit deterministic debug fixtures. `--ui-fixture` selects recorded UI data; `--player-fixture` additionally opens the authored clip. Normal production launch uses neither.

## Remote safety and historical evidence

The original account's near-exhausted cap and disabled workflow were not changed. The user's separately authorized **already-existing** TibikeYH120 Free account had an independently verified zero-reported-use baseline. A separate ledger checks fresh usage, zero net charges and all five owned repositories' active jobs before any push; at most four attempts, standard Intel Mac, 12 minutes/job and a reserved a final 160 weighted-minute reservation/attempt (earlier attempts reserved 130). No signup, payment or billing-setting change.

Operational helpers, credentials, CI workflows and raw remote diagnostics are intentionally excluded from the delivered source ZIP. Local reproduction scripts and compact evidence are included.

Historical build 2 (`891496b…`, run `39471994485`) archived successfully. The **26 passing** simulator unit/integration tests and one five-tab/email UI test belonged to earlier build 1, not build 2 or 3. They must not be relabeled as current-build passes. Full parity, OAuth handoff, real-account/multi-device flows and physical signing/playback/visual acceptance remain incomplete.
