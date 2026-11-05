# CortexAnime native port — verification matrix

Scope: **all current mobile-site functions**, not a core-only/MVP substitution. English UI; a separate SwiftUI app and AVPlayerLayer renderer. The production Worker, website assets, original native project and old wrapper IPA must remain unchanged.

This matrix distinguishes implementation from verification. Presence of code is **not** proof that a feature works with a real account, provider or physical iPhone.

## Current blocking release status

**Shipped build 2 failed on the user's physical iPhone:** live metadata returned HTTP 400; released count/Watch Now could be unavailable; system and custom bottom bars both appeared. This overrides any impression from earlier fixture-based UI checks that the production metadata path was working.

**Current build3 was genuinely Apple-compiled on 20 October 2026**, including metadata fixes, one black/purple navigation bar, both 3D/drag interactions, audit fixes and the embedded WidgetKit extension. Device archive run `39486840314`, commit `bebee12c4cb8217e69fdce25da29e70442cbcd29`; IPA SHA-256 `69b6dbec70e22607d26488ef911420f19ba45dc7e5995fb7882f1febc409565d`.

Both host and widget are arm64 physical-iOS executables, matching 0.4.0/build3, privacy/extension/URL-scheme checks passed. The IPA is **unsigned**: no ESign/certificate, physical phone, real widget-gallery or on-device gesture acceptance is claimed. Existing build2 is preserved and should not be mistaken for the correction.

The archive run's exact-source Apple Swift/Foundation live caption probe passed Dark208025 episodes2/3 EN and BLEACH185874 episode9 HU (196/232/308 dialogue cues). Its simulator stage timed out before executing XCTest, so the **overall archive run concluded cancelled**, despite successful device artifacts/probe. A separate simulator-only continuation uses identical production app/project source. Final outcome: **26/26 native Mac/Foundation checks passed**, plus iOS18.5 Release simulator compilation; **runtime boot/install timed out, no accepted app launch or screenshots and no current XCTest pass**. The full record is in `BUILD3-STATUS.md`; failed/unexecuted cases are never counted as passes.

Earlier 11/11 live GraphQL HTTP checks and widget20-row HTTP check remain transport evidence, not native runtime proof. Earlier `Previews/` PNG/HTML files remain explicitly **browser mock-ups**, not iOS pictures. Full functional/visual parity remains unaccepted.

| Function | Isolated native implementation | Verification / remaining acceptance |
|---|---|---|
| Home, spotlight rotation, trending, seasonal, genre navigation | SwiftUI cards and dark-purple navigation; current `/api/home-live` with AniList fallback; dated local metadata cache | Final device compile passes; five-tab/email-form UI test passed on build 1. Pixel-identical visual parity not established. |
| Search, genres, format, sort, pagination | Native controls, debounced AniList queries and native grids | Simulator/UI plus live search verification pending. |
| HU catalog | `/api/hu-catalog`, native filtering/grid | Public API read: HTTP 200, 351 rows on 20 Oct 2026. |
| Seasonal/year browse and movies | Native filtered/paginated catalog | Runtime verification pending. |
| Airing schedule | Native list, website's weekly cache then AniList, local-time dates | Runtime verification pending. |
| Detail, synopsis, latest/jump/all released episodes | SwiftUI; future next-airing and past schedule counts; no invented fallback of 12 playable episodes | Recorded real BLEACH metadata unit test passed: 9/10, no invented episode 10. Full detail UI test did not finish. |
| Characters, Japanese voices, relations, recommendations | Native metadata views | Live response/UI verification pending. |
| Trailer | Opens official YouTube trailer via system link | Intentional external player; in-app website-style trailer embedding is not replicated. |
| Player | Own CortexPlayer controls over AVPlayerLayer; seek +/-10, scrub, restart/retry, next/auto-next, speeds, quality ceilings, mute, sleep, intro skip | Build 1: authored fixture and live iOS-simulator AVPlayer Dark Summoner 2/3 plus 65-second seeks passed. Full final-build runtime rerun not done. |
| Subtitles | Native VTT parser, overlapping cue timeline, HU/EN/FR selection; storyboard rejection and missing-language notices | Build 1 fixture displayed captions. Final exact-source native Swift probe: EN Dark 2/3 and HU BLEACH 9 passed; default selection rejects mislabeled storyboards. No physical caption display test. |
| PiP / AirPlay | Native AVPictureInPictureController and AVRoutePickerView | Physical-device routing and background behavior untested. |
| Resume / history | On-device actual playback records and resume points | Persistence and playback tests prepared. |
| Account viewing-progress sync | Uses existing `/api/watchlist/progress`; user-controlled because existing backend can emit linked-account notifications | Real account writes deliberately not executed by this agent's QA. |
| Watchlist | Local favorites plus account GET/POST/DELETE | Transport tests only until a real account test; local/server favorite state reconciliation still requires acceptance testing. |
| Login / register / verify / resend / logout | Native forms, existing auth APIs, scoped cookie persistence in iOS Keychain | No real registration, emails, login credential submission or account mutations performed during QA. |
| Third-party OAuth login | **BLOCKED**, not a fake success or embedded website login | Existing AniList callback issues a browser cookie and returns a website URL. A secure native callback/credential handoff is absent. Website/backend unchanged. |
| Profile / avatar / banner / decorations / email verification | Native editor and photo picker; real site's 652-decoration catalog, native frames and image overlays | Saving and email actions untested with a real account. CSS-specific decoration animations are not pixel-exact native reproductions. |
| Public profiles / activity / friend counts | Native API-backed views | Account/user-content runtime verification pending. |
| Friend search / request / accept / decline / remove | Native list and existing endpoints | No real friend requests or removals sent in QA. |
| Direct messages | Native polling conversation and send action | No real messages sent in QA. |
| Comments / own-comment removal | Native list/composer with server authorization | No real comments posted/deleted in QA. |
| Watch Party / room code / member list / sync / chat / reactions | Native room UI, 3-second polling, create/join/control/messages/reaction endpoints | No live room creation/control/messages in QA. Multi-device synchronization not certified. Reactions use plain native labels/SF Symbols, no UI emoji. |
| Manga | Native MangaDex-backed grid/search/pagination; system link to MangaDex reader | Public API HTTP 200 verified; reader stays external as on website. |
| Offline episodes | AVAssetDownloadURLSession, background persistence, local availability checks and deletion | Only explicit `downloadAllowed` plus dedicated `downloadUrl` enables saving. None of the 12 inspected resolve responses granted it. Do not claim general offline episode availability. |
| Website's offline subtitle behavior | Native player additionally caches valid captions (2 MB/file; 20 MB / 80-file cache bounds), can use the saved copy on network failure and offers native share/export | Caption cache persistence/invalid-file unit tests passed on build 1; full offline-device behavior remains unverified. |
| FAQ / Privacy / DMCA / contact | Native text/disclosure views from unchanged website assets, plus explicit native caveats | 11 original FAQ entries and policy text bundled. Some website FAQ claims are historical and not proof of native capabilities. |
| Deep links | Native `cortexanime-native-port:` URL scheme / anime path handling | HTTPS Universal Links need site association and signing; not claimed. |
| Small-phone / iPad / landscape / accessibility | Adaptive native grids, 44-point primary controls; remaining hit-target acceptance pending, portrait/landscape support and player accessibility IDs | Simulator screenshots/tests pending; no physical-iPhone, 4-GB RAM or battery certification. |

## Historical build1/2 cost controls (separate original account)

- Separate bundle ID: `eu.cortex.anime.port`; does not replace old `eu.cortex.anime.native` or `eu.cortex.anime.web`.
- Private existing repository, a dedicated isolated branch and exactly one native-only workflow. No Agent/model dependencies, signing credentials, Worker source or website assets uploaded.
- GitHub account plan was verified **Free**; current Actions net charge was 0. Conservative weighted usage: Linux 74 + macOS 159×10 + Windows 28×2 = **1,720** of a minimum 2,000 included minutes.
- Single standard `macos-15-intel` job after the ARM runner stayed unassigned, 12-minute timeout; fresh weighted headroom and concurrency checks per attempt. Final correction job was capped at 4 minutes with a 50-weighted-minute reserve; billing lag was bounded using the completed runs' entire wall-clock durations. No billing settings changed.
- Two ARM source pushes were cancelled while queued: each had runner ID 0, zero executed steps, and reported macOS billable time 0 ms. These are not compiler runs. The first actual Intel Apple compile exposed SwiftUI color/type-inference errors; those were corrected before the next bounded run.
- A real unsigned device IPA, if produced, is **not installable until signed** with a valid provisioning arrangement. No Apple membership/Mac purchase; no physical phone or signing test is claimed.

## Public read-only source sampling

See `Build/read-only-source-qa.json`: 12 episode/language requests across 10 different anime, with **11 resolver successes and valid HLS first-manifest bytes**. Dandadan (AniList 171018), episode 1 returned `found:false`. This does not imply 11 successful native plays. No iframe fallback or source-domain/extractor modification was made.

## Completion rule

Do **not** label this a finished full-parity port while OAuth, offline subtitle parity, real-account flows, multi-device party behavior, physical playback and visual acceptance remain unverified or blocked. Report compiler/test outcomes separately from these scope gaps.

## Historical build1/2 evidence and limitations

Final build **0.4.0 (2)** and Mac exact-source caption probe succeeded: commit `891496b80f6a53ec771d8d59f08f8d6d4d1e80ff`, run `39471994485`. The corrected app source and resource fingerprints match that commit.

The **26 passing** iOS simulator unit/integration tests and the one passing five-tab/email UI test were on build 1 (`2e4f7dda77721fedd77093dbd46c5c57e34d443e`), before the final caption correction. The full UI suite timed out; its separate rerun was cancelled to reserve free minutes for correcting a real caption-selection defect. Do not claim those 26 tests were rerun on final build 2, or that portrait/landscape/UI/account acceptance is complete.

Four executed Mac attempts were used (initial compile, archive+tests, interrupted UI-only run, final 4-minute archive/probe), plus two provably unexecuted ARM queue cancellations. No further builds are permitted on that original near-exhausted account: its task workflow was disabled after success. Legacy workflows and billing settings were untouched.

Read the delivered Hungarian status report for the complete scope distinction. Full parity remains **false**, notably OAuth credential handoff, real-account/community/multi-device acceptance, physical iPhone signing/playback and visual acceptance.

## Current existing-account safety

The user explicitly authorized their previously existing TibikeYH120 Free account. A new **private** isolated native repository receives only allowlisted source. All five owned repos and fresh billing are checked; separate ledger, four-attempt maximum, standard Intel Mac, 12-minute jobs, final 160 weighted-minute reservation/attempt (earlier attempts reserved130). No signup, billing change or original-account cap reset. Actual final usage belongs in `BUILD3-STATUS.md`.
