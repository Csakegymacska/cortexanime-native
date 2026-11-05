# Újrészes widget és hibajavítási átnézés

## Fontos állapot

**Elkészült a valódi Apple-fordítású 0.4.0 (3) IPA a beágyazott WidgetKit-bővítménnyel.** Fájl: `CortexAnimeNative-0.4.0-build3-UNSIGNED.ipa`, 1 831 592 bájt, SHA-256 `69b6dbec70e22607d26488ef911420f19ba45dc7e5995fb7882f1febc409565d`. A főapp és a widget valódi arm64/iOS-bináris, a szigorú helyi ellenőrzés mindkettőn átment. **Aláíratlan; ESign, telefonos telepítés és tényleges widgetmegjelenés még nem igazolt.** A régi build 2 változatlanul megmaradt, de nincs benne widget; annak újraaláírása nem elegendő. Az aktuális QA-eredmény a `BUILD3-STATUS.md` jelentésben külön szerepel.

## A kiválasztott widget

A kérdésre a **Legújabb megjelent részek** változatot választottad.

- Külön natív WidgetKit-bővítmény: `CortexEpisodesWidget`, bundle ID `eu.cortex.anime.port.widget`.
- Kis méretben egy, közepes méretben két cím: borító, cím és ténylegesen múltbeli sugárzási adatból származó epizódszám.
- Koppintás az új natív app adatlapját nyitja. Külön **`cortexanime-native-port`** hivatkozássémát kapott, mert a régi app már használja a `cortexanime` sémát. A régi apphoz nem nyúltam.
- Publikus, nem felnőtt anime-metaadat; nincs bejelentkezés, Keychain-hozzáférés, megosztott cookie vagy App Group-igény.
- A widget a saját elkülönített cache-ét használja. Hálózati hibánál a mentett adat külön „Saved” jelölést kap; üres állapotban nincs kitalált cím vagy epizódszám.
- Körülbelül 30 perc utáni újratöltést kér; **az időzítést az iOS dönti el, nem garantált percenkénti vagy félóránkénti frissítés**.
- A sugárzási adat nem bizonyít elérhető videót vagy elkészült magyar feliratot. Ezt a widget leírása és a beállítási súgó is jelzi.

A WidgetKit-bővítmény külön folyamatként/timeline-okkal működik; a mostani widget saját publikus adatlekéréséhez nem kértem App Groupot. [1](https://developer.apple.com/videos/play/wwdc2026/277/)

## Aláírás és hozzáadás

Az új, widgettel lefordított build 3-nál:

1. Az aláírónak a főapp mellett meg kell tartania a `PlugIns/CortexEpisodesWidget.appex` bővítményt, és azt is érvényesen alá kell írnia. A két komponens azonos aláírócsapathoz tartozzon, saját, egymással megfelelő viszonyban álló bundle-azonosítóval és megfelelő profilokkal.
2. Ha az aláíró eltávolítja a PlugIns/bővítményeket, vagy csak a főappot írja alá megfelelően, a widget működése nem várható. ESign-bizonyítványt, profilt és fizikai telepítést nem ellenőriztem; általános kompatibilitási garanciát nem adok.
3. Telepítés után nyisd meg egyszer a CortexAnime-ot. Az új app az első megnyitáskor widgetfrissítést kér, de ez **nem helyez ki automatikusan widgetet**.
4. Kezdőképernyő: üres terület hosszú nyomása → **Edit → Add Widget → CortexAnime / Latest episodes → méret → Add Widget**. Ez felhasználói művelet. [2](https://support.apple.com/en-us/118610)

Az app új **Profile → Home Screen widget** képernyője útmutatót és csomagellenőrzést tartalmaz: jelzi, hogy a bővítmény fájljai megtalálhatók-e. **Ez csak fájljelenlét-ellenőrzés, nem a tanúsítvány vagy az iOS-regisztráció igazolása.** A külön frissítőgomb is csak kérelmet ad az iOS-nak.

## Az átnézésben javított konkrét problémák

Forrásellenőrzéssel talált hibalehetőségek; nem állítom, hogy mindet telefonon reprodukáltam.

| Probléma | Forrásbeli javítás |
|---|---|
| A friss AniList-adat eldobhatta az explicit, korábban ismert megjelent darabszámot és HU-katalógusjelölést, ha nem kapott új sugárzási adatot | Ismert `currentEpisodes` és HU-tagság megőrzése; a tervezett összlétszám továbbra sem jelent kiadott részeket |
| Új külső/widgethivatkozásnál a régi adatlap vagy navigációs útvonal maradhatott a megnyitott lapon | Új hivatkozásonként külön lapazonosság, új navigációs állapot; az adatbetöltés az anime ID-jához kötött, pozitív ID szükséges |
| A régi és az új app azonos `cortexanime` URL-sémája ütközhetett | Az új port és a widget külön `cortexanime-native-port` sémát használ; az eredeti app változatlan |
| Csökkenő aktuális címlistaszámnál a spotlight kiválasztása/jelölője kimehetett az új tartományból | Kiválasztott index visszakorlátozása az új lista hosszára |
| Újrafuttatott ZIP-frissítés régen eltávolított fájlokat hagyhatott az IPA-ban | Új, egyedi ideiglenes csomag és új ZIP; a meglévő kimenet csak sikeres ellenőrzés után cserélődik |

Az archívum új ellenőrzője a főapp **és** a beágyazott widget arm64/device Mach-O-ját, egyező verzióját/buildjét, bundle ID-ját, widget extension pointját, privacy manifestjét, az elkülönített URL-sémát és az aláíratlan állapotot is ellenőrzi. A régi build 2-t helyesen elutasította az új widgetkövetelmény miatt: nincs benne lefordított widget. Ez nem jelenti, hogy a régi bináris megsérült.

## Tényleges ellenőrzések

- **11/11 élő natív metadata-lekérdezési HTTP-kontraktus**: HTTP 200, GraphQL-hiba nélkül. Ez nem a natív UI vagy dekóder futtatása.
- **Az új widget pontos lekérdezése:** HTTP 200, 20 múltbeli sugárzási sor, 0 GraphQL-hiba. Mind a 20 sor nem felnőtt anime volt. Ez nem WidgetKit-futtatás.
- **9/9 Pythonos csomagellenőrző-teszt**: szintetikus, memóriabeli ZIP-adatokkal; nem gyártottam belőlük IPA-t vagy futtatható iOS-appot.
- **A régi ZIP-frissítés hibája ténylegesen reprodukálva** ideiglenes szövegfájlokkal: a frissített régi ZIP-ben bent maradt a törölt fájl, az új ZIP-ben nem. Nem Apple-archiválási teszt.
- **XcodeGen-projektgenerálás és Xcode 26.3 device-archiválás sikeres**, a widget is beágyazva. Privát run: `39486840314`; forráscommit: `bebee12c4cb8217e69fdce25da29e70442cbcd29`. Az összes feltöltött forrás SHA-256-azonossága helyben ellenőrizve.
- **33 Swift-fájl strukturális parse-ja sikeres.** Ez nem Swift-típusellenőrzés, fordítás vagy XCTest.
- Az első új futás szimulátora indítás/fordítás közben kifutott az időkeretből, XCTest nem indult el. Külön, párhuzamos boot/build QA-futás készült; végleges eredmény a `BUILD3-STATUS.md` jelentésben. Csak ténylegesen lefutott teszt számíthat sikeresnek.
- **A build 3 pontos feliratkódja Apple Swift/Foundation alatt 3/3 élő próbát teljesített**: Dark 2 EN 196, Dark 3 EN 232, BLEACH 9 HU 308 valódi dialóguscue. Ez nem fizikai feliratmegjelenítés.
- **424 védett eredeti fájl változatlan**, a régi IPA és a CaptionPolicy/NativePlayer források is változatlanok. A normál weboldal nem módosult.

## Buildkeret és megőrzés

Nem hoztam létre új fiókot, nem vásároltam Apple-tagságot/Macet, és nem kapcsoltam fizetős beállítást. A felhasználó külön engedélyezte saját, **már korábban létező TibikeYH120** GitHub Free-fiókját. Friss, teljes láthatóságú ellenőrzés történt mind az öt saját repóra, az üres használati kimutatásra és a futó jobokra. Külön privát natív repó, külön bounded ledger: legfeljebb négy 12 perces standard Intel-Mac-próba, kezdetben 130, a végső ellenőrzéseknél 160 súlyozott perc tartalék/próba, minden push előtt új keret- és konkurenciaellenőrzés. A korábbi fiók 1990-es konzervatív korlátja és letiltott workflow-ja változatlan.

Az új IPA a javításokat és widgetet tartalmazza, de **nem aláírt és nem teljes portátvétel**. A régi appok, eredeti fájlok, weboldal és szolgáltatói feloldás megmaradtak. A token, segédprogramok, workflow-k és nyers távoli naplók nem részei az átadott forráscsomagnak.

## Lezárt új QA-eredmény

**26/26 tényleges Apple Swift/Mac/Foundation ellenőrzés sikeres**, köztük a pontos közös natív widgetkliens élő HTTP-lekérése, a modell/szűrés/link/cookie/gesztuslogika és három valós anime adatlapjának natív dekódolása. **Ez nem XCTest, WidgetKit-render vagy iPhone-teszt.** Az iOS18.5 Release szimulátoros app/widget fordítása szintén sikerült, de az indítási művelet időlimitbe futott, nincs új hiteles natív screenshot vagy sikeres teljes XCTest. Mind a négy futás lezárt; konzervatívan500/2000 súlyozott perc, jelentett nettó díj0. A workflow letiltva, nincs aktív job vagy további automatikus próba. Részletesen: `BUILD3-STATUS.md`.
