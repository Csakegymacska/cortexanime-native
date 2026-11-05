# CortexAnime iOS 3.0 — frissítési csomag

Verzió: `MARKETING_VERSION 3.0`, `CURRENT_PROJECT_VERSION 26` (`project.yml`).
Az összes felhasználói felületi szöveg angol; a magyar szövegmaradványok ellenőrzése üres.

Állapot: **kész és lefordítva.** A GitHub Actions 9-es futása (Xcode 27.1) sikeresen
learchiválta az appot és a widgetet, a keletkezett IPA verziója 3.0 (26).
Részletek a 4–5. pontban.

---

## 1. Hibajavítások

| # | Hiba | Hol | Javítás |
|---|------|-----|---------|
| 1 | A nézési idő felfújva: a lejátszó 10 másodpercenként az **abszolút** pozíciót küldte "nézett másodpercként", így egy 24 perces rész ~250-szeres időt írt jóvá. | `NativePlayer.swift` 106, 132, 335–339 | Új `accountedPosition`; a `recordHistory` már csak a **deltát** adja át (`position - accountedPosition`), lejátszás-indításkor nullázódik. |
| 2 | Befejezés dupla számolás: újranézéskor minden alkalommal nőtt az `episodesCompleted` és a `seriesCompleted`, a bátrak pedig újra kifizetődtek. | `Points.swift` `noteWatch` | Új `completedEpisodes` / `completedSeries` halmazok; a jutalom és a számláló epizódonként **egyszer** fut. |
| 3 | A már eltárolt, felfújt össznézési idő megmaradt volna. | `Points.swift` init | Egyszeri javítás (`credits.secondsRepaired`), plafon: `max(3600, elkezdett részek × 1800 mp)`. |
| 4 | Versenyhelyzet a részfeloldásnál: gyors koppintásnál két resolve futhatott párhuzamosan. | `Detail.swift` `play` | `resolveTask?.cancel()` az új feladat elindítása előtt. |
| 5 | Magyar szövegmaradványok az angol felületen. | lásd 2. pont lent | "befejezve" → "series finished", "Vitrin · Kedvencek" → "Showcase · Favorites", "Szint N" → "Level N", "N nap" → "N day streak", "Kredit & profil" → "Credits & profile", "megszerzett kredit" → "credits earned", + 11 tvOS szöveg, "10 mp" → "10 sec". |

## 2. Nyelvváltás (HU → EN)

- A korábbi kör 94 szöveg- és 8 kommentcseréje után egy második, szigorúbb pásztázás **16 további** magyar szöveget talált: 8 az iOS Sources-ban, 8 a tvOS appban (tab "Magyar", "Fut/Befejezett", "Magyar felirat be/ki", "Felirat", "Vissza", "N sorozat", "Magyar felirattal").
- Mind angolra írva. A teszt-fixture-ök `label:"Magyar"` értékei szándékosan maradtak: azok a szolgáltatói feliratneveket utánozzák, nem felületi szövegek.
- `CFBundleDevelopmentRegion` a tvOS projektben is `en`.
- Ellenőrzés: magyar ékezetes string, illetve magyar gyakori szavakra illeszkedő string nem maradt (a futtatott szkript 0 találatot ad a felületi fájlokon).

## 3. Új funkciók (11)

1. **Szintlépési kreditujutalom + ünneplő overlay** — szintenként `50 + 25 × (szint − 1)` kredit, minden átlépett szint után egyszer; a `pendingLevelUp` a profil fölött jelenik meg (`LevelUpOverlay`, `levelup.overlay`).
2. **Heti visszatekintő kártya** — 7 napos oszlopdiagram, perc és befejezett részek (`WeeklyRecapCard`, `profile.weeklyRecap`), a Profilon és a Statisztika oldalon.
3. **Jelvény-folyamatjelzők** — a szürke "zárolt" rács helyett valódi százalékos sáv, "Earned" / "In progress" listákkal (`BadgeProgressRow`, `badge.row.<id>`).
4. **Felirat-időzítés állítás** — ±5 s, 0,05 s lépés, perzisztens (`player.subtitleDelay`), a lejátszó "Subtitle timing" szekciójában; a cue-keresés `position - subtitleDelay`-jel dolgozik, azonnali újrarajzolással.
5. **Befejezett részek pipái** — a sorozatoldal epizódrácsán a már megnézett részek pipát és halványított címet kapnak.
6. **"Continue: EP n" gomb** — az első be nem fejezett részre visz, nem a legújabbra (`detail.continue`, `nextUnwatched(upTo:)`).
7. **Continue watching folyamatjelző** — a főoldali folytatósoron a rész hányada csíkban.
8. **Tárhely-riport a Beállításokban** — gyorsítótárazott feliratok darabszám/méret, letöltött részek mérete, "Clear cached subtitles" gomb (`StorageSection`, `StorageReport`).
9. **Legutóbbi keresések** — max. 8 kifejezés, chip-sor a keresőmező alatt, törölhető, koppintásra újratölt (`RecentSearches`, `RecentSearchChips`, `search.recent.<term>`).
10. **Legtöbbet nézett sorozatok** — top 3 a watch log alapján, borítóval, perccel, a sorozatra ugrik (`TopSeriesCard`).
11. **Statisztika megosztása** — `ShareLink` egy összegző sorral: szint, részek, órák, befejezett sorozatok (`profile.shareStats`).

Új `UserDefaults` kulcsok: `credits.completed`, `credits.completedSeries`, `credits.watchLog`, `credits.secondsRepaired`, `player.subtitleDelay`, `search.recents`.
Új fájl: `Sources/Experience.swift` (331 sor, az app target automatikusan felveszi).

## 4. Fordítás és ellenőrzés (GitHub Actions, 9. futás)

- `xcodegen generate` — lefutott, az `Experience.swift` bekerült az app targetbe.
- `bash Build/archive-native.sh` → `xcodebuild ... -sdk iphoneos archive` **sikeres**.
  A fordítás a teljes `Sources/` + widget célokat érintette, tehát a 11 új funkció és az
  összes javítás átment a fordítón.
- Figyelmeztetések: csak a korábban is meglévők (`Design.swift` reduceMotion, `Downloads.swift`
  self capture, `Points.swift` nem használt `evaluate` visszatérés, `Profile.swift` elavult
  `onChange`, widget `result`), **az új kódhoz egy sem**.
- `Build/beta-purchase-qa.py` (szimulátoros béta-vásárlás és visszavonás) — sikeres.
- IPA: `eu.cortex.anime.port`, `CFBundleShortVersionString 3.0`, `CFBundleVersion 26`,
  `CFBundleDevelopmentRegion en`, MinimumOSVersion 18.0, arm64, aláíratlan (a szokásos
  sideload-lánc írja alá).
  sha256: `362564492475240c05e47f21649c0d3ce0fa0bc81cc34d38ee7fe3e659f1b78e`
  (6 061 175 byte). Helyi másolat: `artifacts/CortexAnimeNative-3.0-26-UNSIGNED.ipa`.

Amit ez nem bizonyít: fizikai iPhone-on nem futott, és a szimulátoros QA a béta-vásárlásra
korlátozódik. A kézi füstteszt továbbra is ajánlott:

- rész közben állítsd a feliratot ±0,5 s-mal → azonnal mozdul, kilépés után is megmarad;
- fejezz be egy részt, majd nézd újra → a statisztika nem nő kétszer;
- a Profil stats oldalán jelenjen meg a heti kártya és a top 3 sorozat;
- Beállítások → Storage: számok és a törlés gomb működik;
- keresés: írj be valamit, lépj ki, a chip ott legyen és koppintásra keressen.

## 5. GitHub push — kész

- Repó: `CortexAnime/cortexanime-ios` (privát), ág: `native-iphone-widget-20261020`.
- Feltolt commitok: `74919f7` (igaz hibaüzenetek + újrapróbálás), `a22af46` (build 25 emelés),
  `d8b72ce` (a 3.0 csomag).
- A push elindította a `CortexAnime 2.0 (24)` workflow-t; a 3.0 commit futása
  (run #40961393557, job `metadata`) **success**, a fenti IPA ebből származik.
- Az Actions artifact 1 napig elérhető; utána csak a repóbeli commit marad.

A build szám 26 / 3.0. Ha a 25-ös build számot akarod használni ehhez a kódhoz, a
`project.yml` egy sorát kell visszaállítani, és újra kell indítani a workflow-t.
