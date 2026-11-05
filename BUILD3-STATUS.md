# CortexAnime Native — 0.4.0 (3): valódi Apple-build widgettel

**2026. október 20. — Elkészült az új, valódi arm64-es iOS IPA. A widget is le van fordítva és be van ágyazva. Az IPA aláíratlan; a teljes szimulátoros és fizikai átvétel nem sikeresként lezárt.**

## Az átadott fájl

**`CortexAnimeNative-0.4.0-build3-UNSIGNED.ipa`**

| Tulajdonság | Ellenőrzött érték |
|---|---|
| Méret | 1 831 592 bájt |
| SHA-256 | `69b6dbec70e22607d26488ef911420f19ba45dc7e5995fb7882f1febc409565d` |
| Verzió / build | 0.4.0 / **3** |
| Főapp | `eu.cortex.anime.port` |
| Beágyazott widget | `eu.cortex.anime.port.widget` |
| Widgetfájl | `Payload/CortexAnimeNative.app/PlugIns/CortexEpisodesWidget.appex` |
| Mindkét futtatható állomány | Valódi Mach-O `MH_EXECUTE`, **arm64**, fizikai iOS platform 2 |
| Minimum rendszer | iOS 18 |
| Apple device-fordító | Xcode 26.3, iOS 26.2 SDK |
| Aláírás / provisioning | **Nincs**; telepítéshez érvényes aláírás szükséges |

Az új fájl nem a régi IPA átnevezése vagy újracsomagolt makett. Apple-fordításból származó külön bináris; a szigorú IPA-ellenőrző a letöltés után helyben is sikeresen ellenőrizte a főappot és a widgetet. A régi build 2 megmaradt változatlanul, de nincs benne widget, és nem ajánlott a korábban jelzett hibák miatt.

Device-archívum: privát run **39486840314**, forráscommit **`bebee12c4cb8217e69fdce25da29e70442cbcd29`**. Az archiváláshoz eredetileg feltöltött **50 fájl** Git- és SHA-256-azonossága külön ellenőrizve a helyi forrással. A későbbi futások a QA-workflow-t és egy külön Mac-próbaállományt módosítottak, nem az IPA alapjául szolgáló app-/widgetforrást vagy projektet.

## Mit tartalmaz ez az új bináris?

- A hibás AniList-argumentum javítása, legutóbbi megjelent epizódadatok helyes lekérdezése; nincs kitalált 12 lejátszható rész.
- Explicit megjelent darabszám és HU-jelölés megőrzése hiányos frissítéskor.
- **Egyetlen**, fekete/lila, saját natív alsó navigáció; nincs rendszer-TabView és szürke lebegő kapszula.
- A kért **mindkét** interakció: húzással váltható 3D alsó navigáció és húzható/3D animekártyák, Reduce Motion-fallbackkel.
- Natív **Legújabb megjelent részek** WidgetKit-bővítmény, kis/közepes méretre, publikus cím/borító/epizódszám és natív adatlaplink; bejelentkezés és App Group nélkül.
- Elkülönített `cortexanime-native-port` URL-séma; a régi app `cortexanime` sémája nem módosult.
- Új widget-/külsőlinkenként friss navigációs állapot; címlista-változásnál indexkorlátozás.
- Friss ideiglenes IPA-staging és új ZIP, hogy eltávolított régi fájl ne maradjon benne.
- A meglévő teljes natív forráskör: SwiftUI, saját CortexPlayer-vezérlők/AVPlayer, katalógusok, adatlapok, fiók/közösségi felületek. **A kód megléte nem jelent minden funkcióra igazolt működést.**

## Pontosan mi ment át?

### 1. Apple device-archívum és csomagellenőrzés — sikeres

A főapp **és** a WidgetKit-target lefordult. Az IPA-t még a szimulátoros szakasz előtt külön artifactként megőriztem és letöltöttem. Mindkét bináris architektúrája/platformja, azonosítója, egyező verzió/build, a widget extension pointja, privacy manifestjei, URL-séma és az aláíratlan állapot ellenőrizve.

**Az egész archívum-workflow nem lett zöld:** később a szimulátoros szakasz időkorlátba futott, az összesített run `cancelled`. A sikeres device-lépést nem szabad összekeverni egy teljes QA-passzal.

### 2. Pontos aktuális feliratkód, Apple Swift/Foundation, élő forrás — 3/3 sikeres

| Élő eset | Tényleges eredmény |
|---|---|
| Dark Summoner, 208025, 2. rész / EN | 196 valódi dialóguscue, 1 hibás/storyboard sáv kizárva |
| Dark Summoner, 208025, 3. rész / EN | 232 valódi dialóguscue, 1 hibás/storyboard sáv kizárva |
| BLEACH, 185874, 9. rész / HU | 308 valódi dialóguscue, magyar sáv kiválasztva |

Ez a tényleges `CaptionPolicy.swift` és az app pontos VTT/StreamInfo-forrásszeleteinek **Macen futó** próbája. Nem a telefon képernyőjén megjelenő felirat vagy új iOS-lejátszási teszt.

### 3. Aktuális natív modell-, gesztus- és widgetadat-próba Macen — 26/26 ellenőrzés sikeres

Run **39493462287**, QA-commit **`456502fa1b5268cc90f47cf6c9570470795e5a3e`**. Az app tényleges `Anime` forrásszelete, a teljes `NativeGesturePolicy.swift`, `MetadataQueries.swift` és `Shared/LatestEpisodesFeed.swift` Apple Swift-fordítóval lefordítva és végrehajtva.

A 26 ellenőrzés lefedi többek között:

- BLEACH 9/10 és HU 2/12 külön tesztadatból; ismeretlen/tervezett darabszámból nincs lejátszható 12.
- Codable-cache megőrzi a HU- és megjelent darabszámmezőket; elavult következő-rész metaadat nem írja felül az újabb múltbeli adatot.
- Gesztusirányok, szélső fülek, függőleges/apró mozdulatok, nem véges koordináták.
- Widget sorbarendezés, címenként egy legújabb sor, jövőbeli/felnőtt/érvénytelen epizód kizárása, külön link és cookie nélküli session.
- **A tényleges közös natív widgetkliens élő HTTP-lekérése:** 3 aktuális sor, a kliens szándékos háromsoros korlátjával.
- A pontos natív detail-query **HTTP 200 és 0 GraphQL-hiba** mindhárom jelentett címnél, valódi natív modell-dekódolással:

| Anime ID | Megjelent | Tervezett összes a közvetlen AniList-adatban |
|---|---:|---:|
| Yozakura 213657 | 2 | Ismeretlen; nem találtam ki 12-t ebből a válaszból |
| BLEACH 185874 | 9 | 10 |
| Dark Summoner 208025 | 3 | 12 |

**Ez 26 Mac/Foundation-ellenőrzés, nem 26 iOS XCTest, nem UI- vagy AVPlayer-futtatás.** A korábbi build 1 történeti 26 XCTest-passza ettől teljesen külön bizonyíték; nem számolom át build 3-ra.

### 4. Szimulátorhoz készült Release-app fordítása — sikeres; indítás nem igazolt

Xcode **16.4**, iOS **18.5** SDK, x86_64 Release: a főapp és widget szimulátoros fordítása sikerült. Ez a minimum iOS 18 támogatási ág fordításellenőrzése, nem a device-IPA cseréje vagy ugyanazon toolchainnel futtatott iOS 26 QA.

A szimulátor a négyperces boot/install/launch szakasz idejét elfogyasztotta: a rendszerindítás 3:04 után terminal állapotot jelzett, a további művelet még a screenshot előtt időlimitbe futott. **Nincs ebből hiteles új natív képernyőkép vagy igazolt sikeres appindítás.** Az összesített utolsó workflow `failure`, a modellpróba és Release-build lépése külön `success`.

## Mi NEM lett igazolva?

- A build 3 iOS unit/integrációs/UI XCTest-sorozata **nem jutott sikeres végrehajtásig**. A két célzott XCTest-próba boot/fordítás közben kifutott az időből; nincs 0 hibás tesztsorozatot jelentő bizonyíték.
- Nincs új, igazolt natív UI-képsorozat. A korábbi `Previews/` HTML/PNG fájlok továbbra is **böngészős látványtervek**, nem iOS-képernyőképek.
- Nincs fizikai iPhone-os telepítés, lejátszás, feliratmegjelenítés, 3D-gesztus-/teljesítmény-/RAM- vagy akkumulátorteszt.
- Nincs ESign-tanúsítvány/profil-ellenőrzés, widgetgalériás megjelenés vagy valóban kihelyezett widget tesztje.
- A teljes natív port átadási elfogadása továbbra sem lezárt: OAuth natív átadás, valódi fiók/közösségi/multi-device Watch Party és teljes vizuális/landscape/PiP/AirPlay átvétel hiányos. Részletek: `PARITY.md`.

## Aláírás és a widget hozzáadása

1. **Ezt az új build 3 IPA-t** írd alá, ne a régi build 2-t.
2. Az aláírónak a főapp mellett a **`PlugIns/CortexEpisodesWidget.appex`** bővítményt is meg kell tartania és helyesen aláírnia. Egyező csapat, megfelelő host/extension profilok és összetartozó bundle ID-k szükségesek; bundle ID átírásánál a bővítmény kapcsolatát is meg kell tartani.
3. A sikeresen telepített főappot egyszer nyisd meg.
4. Kezdőképernyőn hosszú nyomás → **Edit → Add Widget → CortexAnime / Latest episodes → méret → Add Widget**.

A widget nem kerül ki automatikusan, és a kódaláírás önmagában nem garantálja, hogy egy adott ESign-profilkombinációval működni fog. Az app **Profile → Home Screen widget** lapja fájljelenlétet és kézi súgót ad; nem tanúsítvány-ellenőrző.

## Költség, leállítás és megőrzés

- A felhasználó **már létező** TibikeYH120 Free-fiókja engedélyezetten használva; nem hoztam létre új fiókot és nem állítottam vissza/kerültem meg az első fiók korlátait.
- Új **privát**, elkülönített repó és ág; az eredeti négy saját repó nem módosult, az új repó `main` ága is változatlan maradt.
- Négy bounded standard Intel-Mac-futás, külön ledgerrel. A lezárt futások teljes idejéből, felfelé kerekítve összesen **500/2000 konzervatív súlyozott perc**. A friss jelentett nettó Actions-díj **0**, a kimutatás késhet. Fizetős beállítást nem kapcsoltam be.
- **A workflow-t a végén letiltottam és visszaellenőriztem** (`disabled_manually`, ID 390957513). Mind az öt saját repóban nulla aktív job; nincs automatikus további próba. A külön négypróbás limit elfogyott, nem nulláztam le.
- **424 védett eredeti fájl változatlan**, a régi IPA-k és az eredeti natív projekt megmaradtak. A normál weboldal/Worker, feloldódomének és forráskiválasztás nem változtak.
- A token, aláírókulcs, tanúsítvány, workflow és távoli vezérlő nincs a forrás-ZIP-ben. A megosztott GitHub-tokent a munka végeztével érdemes visszavonni.
