# CortexAnime iOS 4.0 — frissítési csomag

Verzió: `MARKETING_VERSION 4.0`, `CURRENT_PROJECT_VERSION 29`.
Minden felületi szöveg angol. A csomag a 3.0 (28) tetejére épül.

## 1. Widgetek — teljes újraírás

A 3.0-ig egyetlen widget volt („Latest episodes”), AniList airing adatból, csak kis és
közepes méretben. A 4.0-ban kettő van, négy otthoni mérettel és három zárképernyős
formával.

| Widget | Adatforrás | Mit mutat |
|---|---|---|
| **New in Hungarian** (új) | `GET /api/app/epfeed` + AniList borítók | A legfrissebb, már magyar felirattal rendelkező epizódok. „NEW” jelölés, ha egy sorozat első része jött ki. Kis: egy hero poszter; közepes: két kártya; nagy: négy sor; zárképernyőn: mai darabszám / legújabb cím / egysoros szöveg. |
| **Latest airings** (újratervezve) | AniList `Page.airingSchedules` | Mi ment le nemrég a szezonban. |

Közös újdonságok:

- **Zárképernyős méretek** mindkettőhöz: `accessoryCircular`, `accessoryRectangular`, `accessoryInline`.
- **Extra large** méret (iPad és nagyobb iPhone).
- **Saját cache**: ha nincs hálózat, a widget az utolsó jó listát mutatja, „SAVED” jelöléssel, nem üres kártyát.
- **Borító-szín**: a poszterekből mintavételezett szín adja a kártya tintjét és a háttér gradiensét.
- **Kártya-szintű deep link**: minden kártya a saját anime oldalára visz (`cortexanime-native-port://anime/<id>`).
- **Nincs App Group, nincs fiók, nincs kulcstartó** — ez szándékos: így bármilyen aláíró tanúsítvánnyal működik, és a widget nem látja a nézési előzményt vagy a letöltéseket.
- Frissítés: a „New in Hungarian” 20 percenként, a „Latest airings” 30 percenként kér frissítést (az iOS dönti el, mikor adja meg).

## 2. App-funkciók (4.0)

1. **New in Hungarian képernyő** (`NativeReleases`): a teljes kiadási feed napokra bontva, „All / New series / Today” szűrőkkel, húzásra frissül.
2. **New in Hungarian sor a főoldalon**: a hat legfrissebb kiadás, „See all” a teljes listára.
3. **What’s new 4.0** lap: első indításkor egyszer, utána a Profilból bármikor újranyitható.
4. **Felirat-stílus**: háttér (Box / Outline / None) és függőleges pozíció (Low / Standard / High), élő előnézettel a lejátszó beállításaiban. A választás eszközönként megmarad, a streamelt és a letöltött feliratra is érvényes.
5. **Alap lejátszási sebesség**: beállítható (0.75× – 2×), minden új epizód ezzel indul.
6. **Megosztás**: a sorozat oldalán és a lejátszóban is `cortanime.eu` link (ShareLink).
7. **Spotlight**: a magyar katalógus sorozatai indexelődnek az eszközön (legfeljebb 300 elem, naponta egyszer), az iOS keresésből megnyitva a megfelelő anime oldalára visz.
8. **Widget-útmutató frissítve**: két widget, méretek, zárképernyő, csomag-ellenőrzés (jelzi, ha a widget nélküli IPA-t telepítetted).
9. A widgetek timeline-ja az app indulásakor is frissül (`WidgetCenter.reloadTimelines`).

## 3. Javítások, amik ebben a csomagban maradtak

- Az „Are you still watching?” guard (3.0 build 28) változatlanul benne van.
- Az automatikus következő rész a lejátszó képernyőn megy keresztül, nem a lejátszó modellből.
- A letöltött epizódok a poszterről indíthatók, a letöltéslistában ott a borító.

## 4. Amit ez a csomag nem bizonyít

- Fizikai iPhone-on nem futott; a fordítás a GitHub Actions `xcode-27` futásában történik, utána a `/app` oldalra kerül az IPA.
- A `WatchGuardTests` és a többi teszt a repóban van, de a CI workflow csak archivál. A teszt-target fordítását a következő `xcodebuild test` igazolja.
- A Spotlight-indexelés és a widgetek valódi viselkedése eszközön, telepítés után ellenőrizhető.

## 5. Kiadás — 4.0 build 29

- Commitok: `3540939` (a csomag), `391908d` (widget típusnév-javítás), `b2d6b0b` (What's new kizárása QA-indításból).
- CI: run #13 `40991349378` failure (a widget már fordult, de a UI teszt elhasalt a What's new takarás miatt), run #14 `40991939339` **success** (archív + UI tesztek).
- IPA: `CortexAnime-4.0-b29.ipa`, 6 210 448 byte, sha256 `8f4684d6de3323272a9c0689c8ece7bc86879e9bc17215090a2e2cfd617e24ca`.
- Élőben: `https://cortanime.eu/ios/CortexAnime-latest.ipa` 200, byte-azonos; `/app` a 4.0 · build 29-et hirdeti.
- Variánsok a `/app` oldalon: widget nélkül 6 082 811 B, widget nélkül ad-hoc aláírva 6 110 610 B, widgettel ad-hoc aláírva 6 244 332 B.
- GitHub Release draft: `428596236`, tag `ios-4.0-build29`, csatolmány feltöltve.
- Discord: `1565554632825118802`.
