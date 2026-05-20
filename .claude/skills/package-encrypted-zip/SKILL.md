---
name: package-encrypted-zip
description: Vytvori AES-256 sifrovany 7z archiv s heslom z env premennej a doruci ho do drop foldra uctovnika. Pouzi ako posledny krok pipeline. Popisuje 7z flagy, integrity test, bezpecne narabanie s heslom.
---

# Package encrypted ZIP

Skill pre subagent `archiver`. Pravidla pre vytvorenie a doručenie sifrovaneho archivu.

## Nastroj: 7-Zip

| Platforma | Binarka | Instalacia |
|---|---|---|
| Windows | `7z.exe` | https://www.7-zip.org/ (musi byt v PATH) |
| Linux | `7z` | `apt install p7zip-full` / `dnf install p7zip` |
| macOS | `7z` | `brew install p7zip` |

Pred pouzitim over: `7z --help` -> ma to vystup? Ak nie, zastav a hlas chybu.

## Kompletny prikaz

```
7z a -t7z -mhe=on -p"$ACC_ZIP_PASSWORD" -mx=5 \
   "vystup/2026-04.7z" "vystup/2026-04/"*
```

### Flagy

| Flag | Co robi |
|---|---|
| `a` | Add (vytvor / pridaj do archivu) |
| `-t7z` | Typ archivu = 7z (najlepsie sifrovanie aj kompresia) |
| `-mhe=on` | **Sifruj aj header** — bez tohto sa nazvy suborov v archive daju precitat aj bez hesla |
| `-p<heslo>` | Heslo na archiv (z env premennej, nikdy hardcoded) |
| `-mx=5` | Normalna kompresia (rychle + dobre, default) |

`-mhe=on` je **kriticky** — bez neho je zoznam suborov a metadata viditelny.
Heslo chrani iba obsah, nie kto-co-kedy.

## Test integrity

Po vytvoreni vzdy:

```
7z t -p"$ACC_ZIP_PASSWORD" "vystup/2026-04.7z"
```

Ak skoncia `Everything is Ok` -> OK.
Ak fails -> zmaz poskodeny archiv a hlas chybu.

## Listing (pre report)

```
7z l -p"$ACC_ZIP_PASSWORD" "vystup/2026-04.7z"
```

Z vystupu vyextrahuj pocet suborov a celkovu velkost (pre report).

## Dorucenie do drop folder

### Rovnaky filesystem

```
mv "vystup/2026-04.7z" "$ACCOUNTANT_DROP/"
```

### Siet / UNC / pripojeny disk

```
cp "vystup/2026-04.7z" "$ACCOUNTANT_DROP/"
# verifikuj velkost zhody
ls -l "vystup/2026-04.7z" "$ACCOUNTANT_DROP/2026-04.7z"
# az potom zmaz original
rm "vystup/2026-04.7z"
```

Cez sietove pripojenie sa `mv` moze sprcat (precopiruje, ale neoznami chybu)
— bezpecnejsie je `cp` + manualne overit.

## Bezpecnostne pravidla

### Heslo

- **NIKDY** ho nevypisuj do stdout / stderr / logov / nazvov suborov / commitov
- Pri ukazovani prikazu pouzivatelovi maskuj ako `***`:
  ```
  7z a -t7z -mhe=on -p*** -mx=5 vystup/2026-04.7z vystup/2026-04/*
  ```
- Nezapisuj heslo do `_archiver.log.json`
- Heslo necitaj cez `echo` ani `printf` — 7z ho prebera priamo z env-u
- Pri kontrole logov pred odovzdanim este raz overit, ze tam heslo nie je

### Co ak `ACC_ZIP_PASSWORD` nie je nastavene

- **Zastav** a hlas pouzivatelovi
- **NEPOUZI** default / fallback heslo
- **NEHLAS** ze "heslo bolo prazdne" — len ze treba nastavit env

### Validacia hesla

- Min. dlzka 16 znakov (kratsie sa daju bruteforce-nut)
- Nesmie obsahovat medzery zaciatku/konci (`trim`)

## Co ak archiv uz existuje

```
test -f "vystup/2026-04.7z" && echo "EXISTS"
```

- Ak ano -> **spytaj sa orchestrátora** ci prepisat
- Default akcia: **NEPREPISAT**, pridat suffix `_2`, `_3`

Nikdy nemaz existujuci archiv bez explicitneho potvrdenia od pouzivatela.

## Velkost archivu — pre report

```
ls -lh "$ACCOUNTANT_DROP/2026-04.7z" | awk '{print $5}'
```

Hlas pouzivatelovi:
```
Archiv: $ACCOUNTANT_DROP/2026-04.7z
Velkost: 4.2 MB
Pocet suborov: 12
Sifrovanie: AES-256 (vratane header)
```

## Bash whitelist

Tvoj Bash ma povolene iba:
- `7z` / `7z.exe`
- `ls`, `mv`, `cp`, `test`

Nic ine. Ziadne `curl`, `wget`, `rm -rf`, `git`, `ssh`, ...
Ak potrebujes nieco ine -> spytaj sa orchestratora.

## Co skill NIE robi

- Negeneruje heslo (musi byt v `ACC_ZIP_PASSWORD`)
- Neposiela email s heslom uctovnikovi (to robi clovek, mimo tohto pipeline)
- Nemaze povodne subory v `vystup/<mesiac>/` — to nech robi uctovnik po overení,
  alebo neskorsi cleanup script
