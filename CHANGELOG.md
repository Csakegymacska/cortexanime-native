## 2.1.0 (210) — 2026-11-05
- **Epizód-megosztás a chatben:** a `+` menüből kereshető listából küldhető egy
  epizód; az üzenetből lejátszható kártya lesz, egy koppintás a megnyitás.
- **Watch party meghívó:** kóddal meghívó-kártya megy a beszélgetésbe, a fogadó
  fél egy koppintással csatlakozik.
- **Cortex Call (első verzió):** hívás-gomb a beszélgetés fejlécében — nyomd és
  beszélj (walkie-talkie a meglévő üzenet-csatornán), némítás, süketítés,
  kamera-megosztás, hívásidő; a bejövő hangok automatikusan játszódnak.
- **Hangjegyzet-buborék:** a hangüzenetek lejátszható buborékot kapnak.
- A `+` menü: epizód, party-meghívó, hívás — a fotó/GIF a megszokott helyén.

## 2.0.0 (200) — 2026-11-05
- **Chat-javítás (a „nem működik" hiba gyökere):** a képernyők a munkamenet
  érvényesítésének befejezése előtt „kijelentkezett"-nek látták a felhasználót, és
  üres listával álltak meg — most megvárják az érvényesítést (`ensureSession`), és
  csak tényleges kijelentkezéskor állnak le. Barátlista, beszélgetéslista és a szál
  is javítva; a szerver végpontok végig ellenőrizve (friends + watch party).
- Keresés a beszélgetésben: beépített keresősáv, szövegre szűr.
- Idézetes válasz: hosszú nyomás → Reply; az idézet az üzenetben "> " sorral
  utazik, a buborékban külön idézet-kártyaként jelenik meg.
- Olvasatlan-jelvény a Profil Messages során (összesített szám).
- What's New képernyő: verzióváltáskor egyszer automatikusan, plusz Profil → What's new.
- Szív-kitörés dupla koppintásra az üzeneten; jobbra húzás = válasz (swipe-to-reply).
- Barátkérés-jelvény a Profil Friends során.


## 6.7 (38) — 2026-11-02
- Nyolc stílus (+Ember, Sakura, Noir), élő mesh háttér minden képernyő mögött.
- Nyolc váltható app ikon, „Follow the theme” kapcsolóval (CFBundleAlternateIcons + Assets.car).
- CortexPlayer újraépítve: fókuszos play, saját csúszka fejezet-jelölésekkel, következő epizód kártya,
  három fülű üveges beállításlap (Epizód · Feliratok · Lejátszás).
## 6.8 (39) — 2026-11-02
- Avatar dekorációk újraépítve: a cellák gesztusa miatt nem lehetett görgetni/kiválasztani — most
  minden csempe `Button` + `ButtonStyle`, a rács görgethető, a találat koppintásra felkerül.
- 42 dekoráció öt kategóriában (Frames / Auras / Weather / Cosmic / Arcane), SwiftUI-ban rajzolva,
  TimelineView-al animálva; külső CDN helyett saját vektorok (offline is ugyanaz).
- Élő előnézet a Profil szerkesztésénél + alsó sáv (Wear / Buy / None), keresés és kategória-chipek.
- Régi dekoráció-id-k a legközelebbi új dizájnra képződnek le; a kreditshop ugyanazt a katalógust használja.
## 7.0 (40) — 2026-11-02
- Dekorációk 46 → 105 tétel, hét gyűjtemény (frame, aura, weather, cosmic, arcane, seasonal, treasure)
  és hét új rajzolási stílus: plasma, halo, crystal, confetti, waves, bolt (+ háromszög-facet).
- Két réteg egyszerre: `DecorationSlot` (frame / aura), a tárolt érték `"frame_x|glow_y"`, a szerverre
  az elsődleges (frame) id megy; a régi egy-id-s értékek továbbra is feloldódnak.
- Választó újraírva: réteg-picker, gyűjtemény-számláló, kedvencek (hosszú nyomás), Owned / Favourites
  szűrő, „Surprise me”, vásárlás közvetlenül a csempéről.
## 7.1 (41) — 2026-11-02
- Ingyenes készlet: 32 dekoráció ára 0 (ebből 19 aura) — új hullám: soft glow, sunrise, ocean mist,
  candy, neon pulse, frost halo, peach, lime, sky, grape, rose gold, spectrum, petal drift, stardust.
- „Free” szűrő és FREE jelvény a választóban; a ContractTests legalább 30 ingyenes tételt és 18 ingyenes
  aurát ellenőriz.
- Profil-stúdió (Customise profile): élő kártya, 8 banner-előbeállítás vagy saját fotó, akcentszín,
  állapotszöveg, About me, dekoráció-választó — mentés a PATCH /api/user/profile végpontra.
- A banner `preset:<id>` alakban utazik, a `status` és az `accent` új szervermező (worker: profile v2).
- Üzenetek 2.0: beszélgetéslista előnézettel, idővel és olvasatlan-számlálóval; szálon belül nap-elválasztók,
  kézbesítési állapot, újraküldés, törlés, másolás, növekvő beviteli mező.
- Új szervervégpontok: GET /api/messages/threads, POST /api/messages/read, DELETE /api/messages/{id};
  a POST /api/messages mostantól visszaadja az új üzenet id-jét.
- Nyilvános profil: a kártya a banner-presetet, az állapotot és az akcentszínt is mutatja; a barátlistából
  egy koppintás a beszélgetés.

## 7.2 (42) — 2026-11-02
- CortexPlayer 3: a vezérlők egy üvegdokkban (fejezet-jelölt csúszka, idő-kapszula, nagy transport sor,
  csendes segédsor), a fejlécben poszter-bélyeg, hátralévő percek és élő PARTY jelvény.
- Watch Party újraépítve: lobby (create / join kód / 3 lépés), 6 karakteres kód, tag-chipek,
  sync-jelző, buborékos chat és animált reakciók (szimbólum, nem szöveg).
- Bejelentkezés/regisztráció új felület: egységes, világított háttér, saját módváltó, ikonos üvegmezők,
  inline hibák, ellenőrző kód lépés — a régi azonosítók (`auth.email`, `auth.password`, `auth.submit`) maradtak.
- Új fájlok: `Sources/AuthDesign.swift` (AuthBackdrop, AuthMark, AuthModeSwitch, AuthField),
  `Sources/WatchParty.swift` teljes újraírás (PartyMessage modell).
- Widgetek: `CxHeroBanner` (teljes felületű borító, epizódszám-vízjel, WATCH pirula) és `CxMiniRow`;
  a Trending small teljes poszter, a Releases / Episodes / Subtitle Radar medium és large hősbannerrel nyit.
  A borítók nagyobb felbontásban töltődnek (460/360/240 px, Trending 700 px).
- Chat: fotó és animált GIF küldése (`PhotosPicker` + `ChatAttachment`, JPEG 1200 px / 380 000 karakter alá
  tömörítve, GIF érintetlenül), buborékban `ChatImage` (GIF → `AnimatedImage`), hosszú nyomásra másolás/törlés.
- Oldalsó sáv: kitöltött akcentus, animált ikon (`symbolEffect`) és fénylő kijelölés.
- Szerver: `messages.image` oszlop, `POST /api/messages` `image` mezővel (data URL, ≤380 000 karakter),
  a thread-előnézet képnél „Photo” / „GIF”; élőben ellenőrizve GIF, PNG, szöveg és válasz körrel.


## 7.3 (43) — 2026-11-02
- **Lejátszó: a kép nem kerül a vezérlők alá.** A dokk négy sorból kettő lett (csúszka + idő, majd egy
  transport-sor); a „következő rész” teljes szélességű kártya helyett egy `UP NEXT` pirula, a segédsor
  (AirPlay, PiP, party, feliratok, sleep, sebesség) a beállításlapon kapott helyet. Portréban a videó
  `dockReserve` térközzel feljebb kerül, amíg a chrome látszik, így a vezérlők nem takarják a képet.
- A letterbox helyén **elmosott borító** (`playerBackdrop`), a `PlayerLayerView` háttere átlátszó, a
  fekete sávok helyett a poszter színei látszanak.
- **Animált bannerek:** 8 új előbeállítás (Starfield, Aurora Flow, Sakura Drift, Tide, Ember Wave,
  Neon Grid, Comet, Frost) `Canvas` + `TimelineView` rajzolással, Reduce Motion esetén állóképpel.
  A tárolt érték ugyanaz a `preset:<id>`, a stúdióban `LIVE` jelvény és élő előnézet.
- **14 új dekoráció** (Sunfire, Lagoon, Lavender, Ice ingyenes; Holo Edge, Ashen, Prism, Verdant,
  Cherry Fall, Monsoon, Shooting Star, Nebula Veil, Ink Seal, Obsidian Crown) — összesen 137 tétel,
  36 ingyenes.
- What's new 7.3 (`whatsNew.seen.730`), verzió 7.3 (43).

## 7.4 (44) — 2026-11-02
- **Világnyelv:** új `AppLanguage` (device locale). Az app alapból angol; magyar készüléken a
  frissítés-hibák, a felirat-előnézet és a kiadás-jelölők magyarul jelennek meg — sehol nem keveredik
  a két nyelv. `ReleaseFeed` az angol `NEW SERIES` jelölőt is érti.
- What's new 7.4 (`whatsNew.seen.740`), verzió 7.4 (44).

## 7.4.1 (45) — 2026-11-02
- **Lejátszó: a kilógó, elcsúszott elrendezés javítva.** A `PlayerScreen` eddig a shell alatt
  kapott `fullScreenCover`-t; forgatáskor a shell kicserélődik (`NativeRoot` ↔
  `CortexWidePhoneShell`), a bemutató konténer viszont megtartotta a korábbi irány méretét.
  Fekvőből állóba fordítva a teljes lejátszó egy ~852 pt-os vászonra rendeződött: a fejléc-pirula,
  a csúszka és a jobb oldali gombok leestek a képernyőről, a felirat jobb széle elvágódott.
- **Új `PlayerPresenter`:** a lejátszót a gyökér (`CortexRoot5`) mutatja be, ami forgatáskor nem
  cserélődik el, így a konténer mindig a valódi képernyőméretet követi. A `NativeDetail`,
  a letöltések és a gyűjtemények `.handOffPlayerRoute($route)`-tal adják át az útvonalat.
- **Kemény keret:** a vászon és a chrome-oszlop a `GeometryReader` méretére van rögzítve és vágva;
  a fejléc címe zsugorodik/levág (`.minimumScaleFactor(0.82)`, `truncationMode(.tail)`), a
  beállítás-gomb `fixedSize`, így szűk kijelzőn sem tolja ki a sort.
- What's new 7.4.1 (`whatsNew.seen.741`), verzió 7.4.1 (45).

## 7.4.2 (46) — 2026-11-02
- **A lejátszó a készülék képernyőjéhez igazodik, nem a konténerhez.** Álló helyzetben a
  bemutató konténer megtartotta a fekvő szélességet (~852 pt): a fejléc jobb vége, a csúszka,
  az előre 10 s és a következő rész gomb leesett, a felirat jobb széle elvágódott. Új
  `ScreenMetrics` (`UIWindowScene.screen.bounds`, orientáció- és aktivitás-figyeléssel)
  adja a valódi méretet; a `canvas(for:)` a kisebbet veszi a konténer és a képernyő közül,
  így beragadt konténer esetén is a telefon méretére rajzol.
- **Álló elrendezés újra:** a kép felül, a fejléc alatt jelenik meg (16:9 arányban, a
  `presentationSize`-ből számolva), a felirat a kép alján belül, a vezérlő-dokk alul.
  Fekvőben a kép középen, kitöltve a magasságot; a letterbox helyén továbbra is az elmosott borító.
- Verzió 7.4.2 (46), What's new `whatsNew.seen.742`.

## 7.4.3 (47) — 2026-11-02
- **A lejátszó saját ablakban fut.** Nem a képernyőfa része, hanem egy `.normal` feletti
  `UIWindow`, amelynek kerete mindig a `UIWindowScene` mérete — forgatáskor az iOS méretezi,
  így nem maradhat beragadt (fekvő szélességű) vászon, és az app ablakából nem lóghat be
  semmilyen maradék lap.
- **Fekvő elrendezés újra:** egyetlen, keskeny vezérlősáv (play · idő · csúszka · hang ·
  ±10 s · következő rész / PiP · beállítások) a kép alján. A chrome eltűnése után egy
  mini sáv (play + csúszka + hossz) marad — korábban 3 mp után minden eltűnt, ezért tűnt
  „nem látszónak” a vezérlés.
- `PlayerPlayButton` méretezhető (`size:`), a lejátszó bezárása a hoszt closure-én megy
  (`onClose`), a régi QA-fixture és teljes képernyős borítás továbbra is `dismiss()`-szel zár.
- Verzió 7.4.3 (47), What's new `whatsNew.seen.743`.

## 7.4.4 (48) — 2026-11-02
- **Felirat-soha-nem-lóg-ki:** a kép téglalapja a vászon méretére van vágva (`fit`), így
  a felirat akkor is a látható kép aljára kerül, ha a konténer valamelyik mérete beragad.
  Fekvőben ez volt a tünet: a kép nagyobb vászonra rajzolódott, a felirat alatta maradt.
- Verzió 7.4.4 (48).

## 7.5 (49) — 2026-11-02
- **A lejátszó teljes újradizájnolása.** Álló és fekvő külön elrendezést kap, közös
  videó-réteggel (`videoLayer`) és közös felirat-réteggel (`captionLayer`).
- **Álló = oldal:** fejléc (bezárás · cím · hátralévő idő · nyelv · beállítások) → a kép
  felül, a felirat a kép alján → nagy, lila fényű vezérlőkártya (csúszka, idők, fejezet,
  hang · −10 · nagy play · +10 · következő rész/PiP) → gyorspanel (UP NEXT kártya +
  Feliratok / Sebesség / Watch Party csempék). Semmi nem lebeg a kép fölött.
- **Fekvő = mozi:** a kép kitölti a magasságot, alul üveg sáv (play · idő · csúszka · hang ·
  ±10 · következő rész/PiP · beállítások); 3 mp után **mini sáv** marad (play + csúszka).
- A `PlayerPlayButton` méretezhető, a régi dokk-kód (`controls`, `portraitDock`) kivéve a
  használatból — a 7.5-ös elrendezés veszi át a helyét.
- Verzió 7.5 (49), What's new `whatsNew.seen.750`.

## 7.6 (50) — 2026-11-02
- **Visszaállítva a 7.0 (40) lejátszója** — a felhasználó szerint az volt jó. A
  `PlayerControls.swift` és `PlayerShell.swift` szó szerint a `938ee3ee8d` commitból jön
  (46 659 B / 8 910 B); a `NativePlayer`, `PlayerPresentation`, `PlayerGestures` közben
  nem változott, tehát a lejátszó motor és a gesztusok ugyanazok.
- **Amit megtartottam a későbbi javításokból:** a lejátszót a gyökér (`CortexRoot5`) mutatja
  be `fullScreenCover`-rel, nem a shell alatt — ez volt az, ami az álló elrendezést
  helyre tette. A 7.4.3-as külön `UIWindow` és a 7.5-ös új oldal-elrendezés kikerült.
- Verzió 7.6 (50), What's new `whatsNew.seen.760`.

## 8.0 (51) — 2026-11-02
- **Studio 8**: négy profil-elrendezés, négy avatarforma, hat gyűrű, hat háttérminta,
  saját akcentusszín (hex), tagline, három műfajcímke, Discord/AniList/MAL linkek, négy
  kitűzött jelvény, szint-haladásgyűrű, statisztika-kapcsolók, három adatvédelmi kapcsoló
  és hat menthető preset.
- **Négy új téma**: Jade, Copper, Ice, Violet (12 összesen).
- **Felirat-stúdió**: hat szín, félkövér, lemez-opacitás 30–100%, három sorszélesség —
  ugyanaz a renderelő fut az élő feliraton és az előnézetben.
- **Lejátszás**: alapértelmezett sebesség 0.5×–2×, dupla koppintás 5/10/15/30 mp; a
  ±10 gombok és a HUD is ezt követi.
- **Főoldal**: nyolc polc átrendezhető/elrejthető, „Surprise me" véletlen sorozat.
- **Előzmények**: kereshető lista, egyenkénti törlés, visszaugrás epizódra.
- Verzió 8.0 (51), What's new `whatsNew.seen.800`.

## 1.0.0 (100) — 2026-11-02
- **46 új dekoráció, 12 új rajzstílussal** — összesen **190 darab** (38 ingyenes):
  runes, constellation, bloom, clockwork, shards, ribbons, pixel, spiral, doubleHalo,
  crownArc, boltRing, snowRing.
- **Bolt-szűrők**: ritkaság, „csak saját", „csak megfizethető", rendezés kategória/ár/ritkaság/A–Z.
  A fejléc számolja a kollekciót; üres szekció nem jelenik meg.
- **Today's window**: naponta más kiemelt darab, nagy előnézettel.
- **Surprise look** és **Match the pair** a dekoráció-választóban.
- **3 új jelvény**: Wardrobe (20 dekoráció), Legendary Owner, Devoted (100 óra).
- **Javítások**: két duplikált dekoráció-id (petals_cherry, nebula_veil) egyedivé téve;
  a katalógus-számok számolt értékek.
- Verzió 1.0.0 (100), What's new `whatsNew.seen.1000`.

## 1.0.1 — build 101 (2026-11-02)

- **Account credits.** A `credits` column on `users`, returned by `/api/auth/*` and
  `/api/auth/me`. The app tops its local balance up to the account value on every
  sign-in and session check; it never lowers it.
- **`POST /api/credits/redeem`.** Single-use, account-bound codes stored in
  `credit_codes` with a `credit_grants` ledger, so a code cannot be claimed twice
  or by two accounts. Errors: 404 unknown, 409 already used, 410 exhausted.
- **Redeem screen.** A ticket button under the balance card in the Credit Shop,
  with the server's answer shown inline.
- **Shop performance.** Lazy stack + static row previews for the 190-piece catalogue.

