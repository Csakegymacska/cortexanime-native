# CortexTV — Apple TV (tvOS) app

Native tvOS client for cortanime.eu. Separate Xcode project (`project-tv.yml`), so the
iPhone/iPad targets in `project.yml` are untouched and build 25 stays exactly as it is.

## What it does

| Screen | Content |
|---|---|
| Kezdőlap | Hero banner, "Magyar felirattal" rail, trending and this-season rails from `/api/home-live` |
| Magyar | Full Hungarian catalogue from `/api/hu-catalog` (377 titles) |
| Keresés | `/api/anilist/search?q=` plus local catalogue matches |
| Rész | Banner, genres, synopsis, episode grid from `/api/episodes?anilistId=` |
| Lejátszó | `/api/stream/resolve` → AVPlayer, Hungarian subtitles from `/api/hu-subs/{id}/{ep}.vtt` |

Built for the couch: `.card` button style (native focus lift), 10-foot typography,
remote-friendly controls (`Play/Pause` toggles, `Menu` closes, ±10 s buttons),
subtitles drawn as a native overlay so timings stay exactly as shipped.

Errors say the truth: not-yet-aired episodes show the real airing date, a dead source
says the source is not answering, never a raw server payload.

## Build

```bash
brew install xcodegen          # once
cd cortex_anime_native
bash Build/archive-tv.sh simulator   # quick compile check
bash Build/archive-tv.sh device      # archive + export
```

`Build/archive-tv.sh` runs `xcodegen generate --spec project-tv.yml`, then `xcodebuild`
against `generic/platform=tvOS`. Archive output: `build/CortexTV.xcarchive`.

## Installing on a real Apple TV — the honest part

There is **no sideloading equivalent to ESign on tvOS**. An unsigned `.app`/`.ipa` cannot be
installed on an Apple TV. The options are:

1. **Free Apple ID + Xcode on a Mac** (no cost): connect the Apple TV to the Mac (same
   network, Developer Mode on), select the device as the run destination, set your personal
   team in Signing, press Run. The app works for **7 days**, then it must be re-signed.
   Region/account limits apply as with iOS free provisioning.
2. **Apple Developer Program (99 USD/year)**: TestFlight and year-long profiles. Not used
   here — the project rule is no paid services.
3. **App Store**: requires the paid program and review. Deliberately out of scope (beta-only).

So the code and the archive can be produced now; putting it on the TV needs either a Mac
with Xcode and a free Apple ID, or a paid developer account.

## Status

- Source: complete for the screens above (1,4xx lines, nine files).
- Compiled: **not yet** — the sandbox has no Swift toolchain and the GitHub Actions minute
  budget is exhausted until 2026-11-01. First compile happens then.
- Once the compiler runs, expect small fixes; nothing here is claimed as verified.
