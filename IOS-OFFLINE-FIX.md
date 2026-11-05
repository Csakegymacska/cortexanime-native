# Offline javítás + lejátszó UI — 2026-10-29

Commit: `c80cea4` + `e915167` (build 27) a `native-iphone-widget-20261020` ágon.
A GitHub Actions 10-es futása a javításokat, a 11-es futás már a build 27-et fordította le és
archiválta: **mindkettő success**.

A kész build a weboldalon is kint van: `https://www.cortanime.eu/app` → **3.0 · build 27**,
a `/ios/CortexAnime-latest.ipa` pedig pontosan ezt a fájlt adja
(6 077 213 byte, sha256 `6ef0f069…c0450d`). Két helyen is élőben ellenőrizve.

---

## 1. Offline lejátszás — mi volt a gond és mi változott

A letöltés és az indítás két külön helyen tud elakadni, ezért mindhárom ponton javítottam:

**a) A mentett csomag nem indult el, és zsákutca lett belőle.**
Eddig, ha az AVFoundation nem tudta megnyitni a mentett HLS-csomagot (`.movpkg`), a lejátszó
csak ennyit írt: „This episode could not be played. Its source may have expired…", és kész.
Mostantól:
- a letöltés rekordja eltárolja az eredeti stream címet (`DownloadItem.remoteURL`, csak https),
- ha a helyi csomag nem indul, a lejátszó **egyszer automatikusan átvált az online forrásra**,
  és a felirat felett kiírja: a mentett példány nem indult, online forrásra váltott, töröld és
  töltsd le újra a javításhoz,
- ha nincs net, a hibaüzenet konkrét: „The saved offline copy could not be started. Remove this
  download and download the episode again." (eddig a félrevezető „expired source" szöveg ment).

**b) „Offline ready" volt, de nem volt Play gomb.**
A sor csak akkor mutatott „Play offline" gombot, ha a fájl-ellenőrzés átment; ha nem, a sor
néma maradt. Mostantól a letöltött sor mindig ad valamit:
- ha a fájl megvan: borítóra vagy a gombra koppintva indul,
- ha a fájl eltűnt (pl. a rendszer kitakarította a csomagot): magyarázat + **Download again**,
  ami valódi újratöltést indít (`Downloads.repair`, nem „failed" rekordot hoz létre).

**c) A listából nem derült ki, mi az.**
A letöltés és az offline könyvtár sora eddig csak szöveg volt.

## 2. Amit a felületen kértél

**Borítók:** a Downloads/Offline lista minden sora most bal oldalon a sorozat borítóját mutatja
(58×82, lekerekített), alatta állapot-jelző: play ikon, ha indítható, narancs figyelmeztetés, ha a
fájl hiányzik. A képernyő alján futó letöltés-sáv is kapott egy kis borítót (26×36) a
folyamatjelző mellé. Az offline módban (amikor net nélkül a Downloads nyílik meg) ugyanez a sor
jelenik meg, tehát ott is látszik a kép.

**Skip intro / Skip outro:** a felső léccel nem nyúltam hozzá. A gomb a lejátszó alján, közvetlenül
a hangnémítás/PiP/AirPlay sor fölött jelenik meg, jobbra igazítva — vagyis pont a hangvezérlők
mellett, és csak akkor, amikor tényleg van mit átugrani (az intro/outro sávban vagy). Kapszula
formájú, „Skip intro" / „Skip outro" felirattal, 44 pontos találattal, a chrome elrejtésével együtt
eltűnik. A meglévő Beállítások-kapcsolók (`player.skipIntro`, `player.skipOutro`) továbbra is
kikapcsolják.

## 3. Amit még nem tudtam lefuttatni

Az offline folyamat **futásidejű** ellenőrzésére írtam egy CI jobot (`offline` a
`.github/workflows/native-port-build21.yml`-ban): elindítja a helyi, hitelesített HTTPS fixture
szervert, letölt, leállítja a forrást, majd hideg indításból lejátszik — vagyis pont azt a
forgatókönyvet, amit a telefonon tapasztaltál.

Ezt **nem tudtam felpusholni**: a token nem rendelkezik a `workflow` jogosultsággal, a GitHub
elutasítja a workflow-fájl módosítását
(`refusing to allow a Personal Access Token to create or update workflow ... without workflow scope`).
A fájl a repóban helyben kész van, csak a push hiányzik.

Ehhez a token beállításaiban a **Workflows: Read and write** (finomhangolt token) vagy a `workflow`
scope (klasszikus token) kell. Utána egy paranccsal megy:

```bash
cd cortexanime-ios-repo
git add .github/workflows/native-port-build21.yml
git commit -m "CI: run the offline download and local playback QA job"
git push
```

## 4. Amit a telefonon érdemes kipróbálni

1. Tölts le egy részt, majd repülőgép módban indítsd el a Downloads listából.
2. Ha mégsem indul: nézd meg, hogy jön-e az „online forrásra váltott" sáv (net mellett), illetve
   hogy a soron megjelenik-e a narancs ikon és a Download again gomb.
3. Indíts el egy streamelt részt: az intro sávban a jobb alsó sarok fölött, a hang ikon mellett
   legyen a Skip intro kapszula.
