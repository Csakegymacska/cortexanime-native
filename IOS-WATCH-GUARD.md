# Are you still watching? — inaktivitás-guard a lejátszóban

Ok: valaki elalszik az animén, a lejátszó tovább lépteti a részeket hajnalig, a képernyő
égve marad, a telefon melegszik. A 3.0 build 28 ezt a helyzetet kezeli.

## Mit csinál

1. **Részlánc-figyelő:** ha egymás után **4 rész** úgy megy le, hogy közben semmihez nem
   nyúlsz (nincs koppintás, seek, beállítás, hangerő, semmi), a lejátszó **a következő rész
   előtt** megáll és megkérdezi: *Are you still watching?* — 30 másodperces visszaszámlálóval.
2. **Hosszú lejátszás-figyelő:** ha ugyanaz az epizód (vagy film) **150 percig** megy
   koppintás nélkül, ugyanez a kérdés jön. Ez a filmes, egyrészes estéket fogja meg.
3. **Válasz nélkül:** a visszaszámláló letelte után a lejátszó **megállítja a lejátszást,
   lezárja a lejátszót és visszalép** — így az iOS a saját automatikus zárásával
   elsötétíti a képernyőt, a telefon pedig lehűl. A pozíció mentve, legközelebb onnan indul.
4. **„Yes, I'm still watching”:** a lánc nullázódik, és ha a rész végén jártunk, az
   automatikus következő rész azonnal elindul a szokásos 8 másodperces kijelzővel.
5. **„Stop here”:** nem indul a következő rész, a lejátszó a végepanelen marad (közbeni
   kérdésnél megáll).

Bármilyen valódi interakció nullázza a számlálót: koppintás a képre, seek (csúszka vagy
dupla koppintás), skip intro/outro, hangerő, PiP, AirPlay, beállítások, sleep timer,
következő rész, újranézés. Az app háttérből való visszatérése is interakciónak számít.

## Beállítások

Lejátszó → fogaskerék/⋯ (Player options) → **Are you still watching?**

- `Pause when nobody responds` — fő kapcsoló, alapból be.
- `Ask after N episodes in a row` — 2 / 3 / **4** / 5 / 6 / 8.
- `Long playback check after …` — 1 h / 1,5 h / 2 h / **2,5 h** / 3 h / 4 h, vagy Off.

A beállítások eszközönként, `UserDefaults`-ban tárolódnak (`player.watchGuard.*`).

## Miért kellett a lejátszó-modellhez is nyúlni

A `Playback` vég-megfigyelője eddig **azonnal** léptette a következő részt, ha az
`player.autoNext` be volt kapcsolva — a képernyőn látható 8 másodperces visszaszámláló így
soha nem érvényesült, és a guardnak sem volt hol beavatkoznia. Ez a sor kikerült: mostantól
a lejátszó-képernyő dönt a folytatásról (visszaszámláló → következő rész, vagy a guard
kérdése előtte).

## Tesztek

`Tests/WatchGuardTests.swift` (13 eset): a küszöbök klampolása, a két kérdés-feltétel
határértékei, a szövegek, valamint a modell viselkedése — 3 rész után nincs kérdés, a 4.
után van; interakció nulláz; kikapcsolt guard soha nem kérdez; 30 perc tick után egyszer
kérdez; álló lejátszásnál nem gyűlik az idő.

## Amit ez nem bizonyít

Fizikai iPhone-on nem futott le (nincs itt Swift toolchain): a Swift-fordítás a GitHub
Actions `xcode-27` futásában történik. A telefon melegedését ez a build a lejátszás
megállításával előzi meg, de a hőmérsékletet magát nem tudja mérni.

## Kiadás — 3.0 build 28

- Commit `0723365`, GitHub Actions run #12 (`40986451405`, `metadata` job) **success**: az app és a widget lefordult, az archiválás és az IPA-ellenőrzés átment.
- IPA: `CortexAnime-3.0-b28.ipa`, 6 097 030 byte, sha256 `fc4ec2c1bc4bdfcc70f84b76c9c65a8a1b4527bff2c8479dd3ecb6a6034005e4`.
- Élő: `https://cortanime.eu/ios/CortexAnime-latest.ipa` (és a verziózott `-3.0-b28.ipa`) 200, byte-azonos; `/app` a 3.0 · build 28-at hirdeti.
- GitHub Release draft: `428566257`, tag `ios-3.0-build28`, csatolmány a fenti IPA.
- Receipt: `cortex-card-test/deployment-ipa-update-v3.0-b28.json`.
- A `WatchGuardTests` a repóban van, de a CI csak archivál, tesztet nem futtat — a teszt-target fordítását a következő `xcodebuild test` fogja igazolni.
