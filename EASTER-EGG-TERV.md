# Easter egg — terv (nem buildelt kód)

Döntés: **eredeti Springtrap**, mert ez a te builded, csak te látod, és tisztelgés a karakter előtt.

## A határ, amit én húznék

- **Nem szedünk ki fájlt a játékból.** Nincs rip-elt modell, textúra, screenshot, hang. A kép, ami
  a jelenetben megjelenik, saját, erre a célra készült rajz — ez a tisztelgés, nem a másolás.
- **Csak a saját, sideloadolt buildben van benne.** Ha egyszer App Store-ba menne vagy nyilvános
  IPA-ként terjesztenéd, ezt a részt ki kell venni (egy `#if` kapcsolóval egy sor az egész).
- A `I always come back` rövid idézet magában elmegy; a felismerhető figura a kockázat, és az most
  a saját rajzunk.

## A trigger

- **3 koppintás a Home fejléc logójára 0,7 másodpercen belül.** A logó 32 pt, kényelmesen eltalálható.
- Az első két koppintásnál semmi látható. A 2.-nál halk `UIImpactFeedbackGenerator(.soft)`,
  a 3.-nál `.rigid` — érzed, hogy történt valami, de nem árulja el.
- Utána **24 órás zár**: újra elő lehet hozni, de nem lehet tömegnyomkodással kikényszeríteni.
- A `CortexHeader` kap egy `onTripleTap` closure-t, a jelenetet egy külön `EasterEgg.swift` rajzolja.
  A fejléc marad buta és tesztelhető.

## A jelenet — 4,5 másodperc

| idő | mi történik |
|---|---|
| 0,0–0,35 s | glitch: a logó 2 px-t elcsúszik, RGB-szétcsúszás (piros/cián réteg), 3 soros szakadás, gyors villanás |
| 0,35 s | a képernyő elfeketedik, a háttér 0,15 s alatt 8%-ra sötétedik |
| 0,5–1,6 s | a figura alulról beúszik, először csak a sziluettje, aztán kivilágosodik — enyhe kézitartás-remegés |
| 1,6–3,2 s | a szöveg írógéppel: `I always come back.` betűnként 45 ms, glitch-elve (2-3 karakter random átrendeződik) |
| 3,2–3,8 s | a szöveg egy pillanatra „elromlik", majd: `Cortex Void always comes back.` |
| 3,8–4,5 s | minden kifakul, a chat/homescreen ugyanott folytatódik, ahol volt |

Hang: alapból **néma**. Ha be van kapcsolva, egyetlen mély, 1,2 s-es moraj (saját generált, nem a játékból),
a rendszer némító kapcsolóját tiszteletben tartva.

## Amit kötelezően kezelni kell

- **Reduce Motion**: nincs glitch, nincs beúszás — egy statikus kép + a szöveg, 2,5 s.
- **VoiceOver**: a logó `accessibilityLabel("Cortex Anime")` marad, a jelenet alatt egy rejtett
  „Bezárás" gomb, hogy bárki ki tudjon lépni.
- **QA/screenshot mód**: `--qa` argumentumnál (mint a boot animációnál) a jelenet nem indul,
  különben a UI-tesztek véletlenül elkapják.
- **Egyszerre csak egy**: ha már fut, a további koppintás nem indít újat.

## Fájlok, ha rábökünk

```
cortex_anime_native/
  Sources/EasterEgg.swift          új: a trigger-állapot + a jelenet
  Sources/Design.swift             CortexHeader: +1 closure, +onTapGesture(count: 3)
  Resources/Assets.xcassets/
    SpringtrapTribute.imageset/    saját rajz (1 kép, univerzális)
  Info.plist                       nincs változás
```

## Mélyebb réteg (opcionális, ha kell)

Ha a jelenet alatt még 5-öt koppintasz, a záró sor átvált: `Az OmegaTech mindig visszatér.`
És utána a Profil képernyőn megjelenik egy rejtett „Void" jelvény — csak annak, aki megtalálta.

## Ami még nyitott

1. Melyik logó legyen a trigger: a Home fejléc 32 pt-os ikonja, vagy a bal sáv 26 pt-os ikonja?
   (A fejléc jobb: nagyobb cél, és ott van a wordmark mellett.)
2. A zár 24 óra vagy véglegesen egyszeri?
3. Kell-e hang, vagy maradjon teljesen néma?
