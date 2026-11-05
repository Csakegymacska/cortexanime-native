> **Frissítés — 2026-10-20:** az itt leírt javítások már valódi Apple-fordítású **0.4.0 (3)** IPA-ban vannak, a WidgetKit-bővítménnyel és 3D-gesztusforrással együtt. Az alábbi eredeti forrásfázis-leírás történeti; az aktuális futási eredmény, IPA-azonosító és korlátok a **BUILD3-STATUS.md** jelentésben. Az IPA továbbra is aláíratlan, fizikai iPhone/ESign nincs igazolva.

# CortexAnime iPhone-hibajavítás — forrás elkészült, új IPA még nincs

**A képeken látható hiba az általam készített appban van, nem a telefonodban vagy az aláírásban.** A jelenlegi `0.4.0 (2)` IPA továbbra is a régi bináris; a mostani javítás még nincs benne. Ugyanannak az IPA-nak az újratelepítése nem javítja meg.

## Megtalált és reprodukált okok

1. **HTTP 400 a főoldalon, keresésnél és adatlapokon.** A közös natív AniList-lekérdezés a `Media.airingSchedule` mezőnek adott `sort: TIME_DESC` paramétert. Ezt a mezőt az AniList nem támogatja. A tényleges válasz:
   ```
   Unknown argument "sort" on field "airingSchedule" of type "Media".
   ```
   A hibás natív lekérdezést élő kéréssel reprodukáltam: **HTTP 400**.
2. **Unknown epizódszám és letiltott Watch Now.** A hibás frissítés miatt az app a HU-katalógus adatán maradt, de annak explicit `currentEpisodes` mezőjét nem olvasta be. Így a rendelkezésre álló 2 részből is ismeretlen szám lett.
3. **Kettős alsó navigáció.** A saját kapszulás sáv mögött a rendszer `TabView`-sávja is megmaradt. A korábbi elrejtési mód az általad használt iOS-on nem volt elég.

## Javítás az app forrásában

- Új, közös `MetadataQueries.swift`: a főoldal és az adatlap a ténylegesen ellenőrzött lekérdezéseket használja.
- A legutóbbi megjelent epizód a támogatott **`Page.airingSchedules(mediaId:..., notYetAired:false, sort:TIME_DESC)`** lekérdezésből jön. Nem az első megjelent részt veszem legutóbbinak, és nem találok ki epizódszámot.
- A HU-katalógus explicit `currentEpisodes` mezője beolvasásra kerül. Az ismert tervezett összlétszám nem vész el, ha az AniListnél a tervezett összes rész `null`; ez az összlétszám soha nem számít megjelent résznek.
- A rendszeres `TabView` helyett egyetlen saját natív alsó sáv van, külön, állapotukat megtartó `NavigationStack`-ekkel. Nincs több létrehozott rendszer-tabbar, amit el kellene rejteni.
- **A navigáció megjelenése is átírva a külön kérésedre:** nincs szürke, elmosott, lebegő kapszula és külön kijelölt szürke buborék. A sáv az app fekete hátterébe simul, felül finom elválasztóval. A kiválasztott ikon/felirat lila, felette kicsi lila jelölő; a többi visszafogott szürke. Az öt angol felirat megmaradt. A gombok 60 pont magasak, a safe-area és a home indicator háttere is fekete; a tartalom nem alájuk görgetett fedőréteget kap. Ez még **forrásbeli megvalósítás**, nem új iPhone-képernyőkép vagy renderelt UI-teszt.
- A GraphQL hibaválasz tényleges üzenete megjeleníthető, nem csak az általános „HTTP 400”.
- Új unit-, élő API- és UI-regressziós tesztesetek készültek, többek között a dupla sávra és a valódi, nem fixture-alapú főoldali lekérésre.

## Ami most ténylegesen ellenőrizve van

**11/11 élő GraphQL-kontraktus HTTP 200-zal, GraphQL-hiba nélkül:**

- Home: **25 trending + 24 seasonal cím**.
- Böngészés, Yozakura-keresés, évadlista, filmek.
- Adatlap: Mission: Yozakura Family Season 2 Part 2, BLEACH, Dark Summoner, One Piece.
- Megjelenési ütemezés, karakterek/kapcsolódó címek/ajánlások lekérdezése.

Konkrét élő adatok:

| Cím | Legutóbbi megjelent epizód | További adat |
|---|---:|---|
| A képen szereplő Yozakura Part 2 | **2** | Év: **2026**; AniListnél a tervezett összes rész ismeretlen, a HU-katalógus explicit terve **12** |
| BLEACH | **9** | Tervezett összes rész: **10** |
| Dark Summoner | **3** | Tervezett összes rész: **12** |
| One Piece | **1180** | A legutóbbi, nem az első megjelent rész lekérdezése ellenőrizve |

A Swift-fájlok strukturális szintaxisellenőrzése is átment. **Ez nem Apple-fordítás. Az új XCTest-ek és az új navigáció iPhone-os futtatása még nem történt meg.**

## Új kiegészítés: húzható 3D navigáció és animekártyák

A pontosításra **mindkettőt** kérted; mindkettő bekerült a natív SwiftUI-forrásba:

- **Alsó navigáció:** a lila kijelölő folyamatosan követi az ujjat, húzás közben enyhe térbeli döntést kap, elengedéskor a megfelelő fülre vált. A koppintás és az öt angol felirat megmaradt. A jelölő fekete–lila, nem egy második szürke rendszersáv.
- **Spotlight:** vízszintes húzással lapozható és a húzás alatt térben dönthető. A döntés mértéke korlátozott; a függőleges görgetés nem lapoz címet. Az automatikus címváltás a húzás alatt szünetel.
- **Anime-polcok:** natív vízszintes görgetés, kártyára igazodó megállás, térbeli fordulás a be-/kilépő kártyákon.
- **Mozgás csökkentése:** a 3D-transzformációk és a rugós gesztusanimáció kikapcsol, a húzás és a koppintás használható marad.

Új tiszta gesztusdöntési segéd: `Sources/NativeGesturePolicy.swift`. Új unit- és húzásos UI-tesztesetek készültek, **még nem futottak Apple-környezetben**. A 30 Swift-fájl strukturális parse-ja sikeres; nem fordítási vagy működési garancia.

### Képek és külön interaktív látványterv

- `CortexAnime-Preview-Home.png`: a javasolt fekete–lila kinézet nyugalmi állapotban.
- `CortexAnime-Preview-3D-Drag.png`: a térhatás/húzás közbeni állapot látványterve.
- `CortexAnime-3D-Design-Preview.html`: önálló, beágyazott képes, interaktív böngészős makett. Ez **nem a natív app**, nem az appba épített HTML/webes felület.

**A PNG-k a külön makett Chromium-renderelései, nem iPhone-, Xcode-szimulátor- vagy SwiftUI-képernyőképek.** A képeken ez külön feliratként szerepel. Az elrendezés szemléltető; nem a teljes natív feed sorrendjének vagy pixelpontos egyezésének igazolása.

A makettben a valódi pointeres Profile→Home húzás, a spotlight húzása közbeni 3D-mátrix, az egyetlen navigáció, a 320/390/768 px-es elrendezés, a betöltött képek és az emulált csökkentett mozgás ellenőrizve. **Ez kizárólag a makett ellenőrzése, nem natív regressziós teszt.** Részletek: `Build/gesture-preview-qa.json`.

Másik virtuális Mac **ugyanazon buildfiókkal nem ad külön havi keretet**. Nem indult új gép, build vagy fizetős futás; a workflow letiltva maradt. A következő Apple-fordítás továbbra is hiányzik, a telefonon telepített régi IPA nem változott.

## Miért nincs új IPA?

A korábbi futások teljes időtartamával konzervatívan számolva **1990 / 2000 súlyozott ingyenes Actions-perc** fogyott el. A biztonságos maradék **10 súlyozott perc, körülbelül 1 Mac-perc**. Ez nem elegendő egy új, ellenőrzött Xcode-fordításhoz.

- **Új buildet nem indítottam, fizetős futást nem engedélyeztem.**
- A feladathoz korábban létrehozott workflow letiltva maradt.
- Nem módosítottam vagy binárisan foltoztam át a régi IPA-t új buildnek álcázva.
- A javított forrás következő verziószáma **0.4.0 (3)**, de **build 3 IPA nem készült**.

A javítás telefonra juttatásához még egy tényleges Apple-fordítás szükséges rendelkezésre álló ingyenes kerettel vagy már meglévő Mac-környezettel. Új fizetős szolgáltatást vagy Mac-vásárlást nem kezdeményeztem.

## Fájlok és megőrzés

**`CortexAnimeNative-iPhone-Hotfix-Source.zip`**: a javított teljes natív forrás, lekérdezések, tesztek és élő ellenőrzési jelentés. Nem tartalmaz IPA-t vagy titkos kulcsot.

A normál weboldalt, a forrásfeloldót és a régi appokat nem módosítottam. A korábbi build 2 forrása és IPA-ja megőrizve maradt. A védett eredeti fájlok hash-ellenőrzése külön is lefutott.
