---
name: rename-accounting-docs
description: Pravidla na extrakciu datumu dodania a nazvu dodavatela z faktury a premenovanie suboru na format YYYYMMDD-<companyName>.<ext>. Pouzi vzdy pri premenovavani uctovnych dokladov — popisuje prioritu datumov, vendor extraction, slug rules, kolizie a confidence levels.
---

# Rename accounting documents

Skill pre subagent `document-renamer`. Pravidla pre premenovanie uctovnych dokladov
na standardny format.

## Cielovy format

`YYYYMMDD-<vendor-slug>.<ext>`

Priklady:
- `20260512-orange-slovensko.pdf`
- `20260403-slovak-telekom.pdf`
- `20260515-tesco-stores.jpg`
- `20260401-prenajom-priestorov.pdf`

## Extrakcia datumu — priorita

Hladaj v tomto poradi (prvy najdeny vyhrava):

| Priorita | Co hladat | Slovensky / Cesky | Anglicky |
|---|---|---|---|
| 1 | Datum dodania tovaru/sluzby | "Dátum dodania", "DUZP", "Datum uskutečnitelného plnění" | "Date of supply", "Service date", "Delivery date" |
| 2 | Datum vystavenia faktury | "Dátum vystavenia", "Datum vystavení" | "Issue date", "Invoice date" |
| 3 | Datum splatnosti (POSLEDNA moznost) | "Splatnosť", "Splatnost" | "Due date", "Payment due" |

**Nikdy nepouzivaj:**
- Datum platby / "Paid on"
- Datum prijatia emailu
- Datum stiahnutia suboru
- Datum v subject emailu

### Format datumu na vstupe

Faktury maju roznorode formaty datumov, vsetky preved na `YYYYMMDD`:

| Vstup | Vystup |
|---|---|
| `12.05.2026` | `20260512` |
| `12. máj 2026` | `20260512` |
| `2026-05-12` | `20260512` |
| `May 12, 2026` | `20260512` |
| `12/05/2026` (SK/EU format) | `20260512` |
| `05/12/2026` (US format — pozor!) | rozlis podla `>12` v jednej pozicii |

Pri 2-cifrovom roku predpokladaj 21. storocie (`26` -> `2026`).

## Extrakcia dodavatela

Hladaj sekciu **"Dodávateľ"** / **"Supplier"** / **"Bill from"** / **"Vystavil"** /
**"Issued by"**. Pozor — NIE "Odberateľ" / "Bill to" / "Customer" (to je vasa firma!).

### Pouzi pravny nazov (legal name)

| Spravne | Nespravne |
|---|---|
| `Orange Slovensko, a.s.` | `Orange` |
| `Slovak Telekom, a.s.` | `Telekom` |
| `O2 Slovakia, s.r.o.` | `O2` |

Z pravneho nazvu potom vyrob slug (viz nizsie).

### Co s OSVC / freelancer-mi

Ak je dodavatel fyzicka osoba s IC, pouzi meno + priezvisko:
- `Ján Novák, ICO 12345678` -> slug `jan-novak`

## Slug rules

1. **Lowercase**
2. **Odstran diakritiku** (transliterate):
   - `á é í ó ú ý` -> `a e i o u y`
   - `č ď ľ ň š ť ž` -> `c d l n s t z`
   - `ä ô` -> `a o`
3. **Odstran pravne sufixy:**
   - `s.r.o.`, `s. r. o.`, `spol. s r.o.`
   - `a.s.`, `a. s.`
   - `k.s.`, `v.o.s.`
   - `ltd`, `gmbh`, `inc`, `corp`
4. **Odstran interpunkciu:** `, . & ( ) ' "` -> nahrad medzerou
5. **Medzery -> pomlcky** (`-`)
6. **Zluc viacero pomlciek** do jednej (`--` -> `-`)
7. **Trim** leading/trailing `-`

### Priklady transformacii

| Pravny nazov | Slug |
|---|---|
| `Orange Slovensko, a.s.` | `orange-slovensko` |
| `Tesco Stores SR, a.s.` | `tesco-stores-sr` |
| `O2 Slovakia, s.r.o.` | `o2-slovakia` |
| `Webglobe – Yegon, s.r.o.` | `webglobe-yegon` |
| `Západoslovenská distribučná, a.s.` | `zapadoslovenska-distribucna` |
| `Slovenský plynárenský priemysel, a.s.` | `slovensky-plynarensky-priemysel` |
| `Microsoft Ireland Operations Limited` | `microsoft-ireland-operations` |

## Kolizia nazvov

Ak `20260512-orange-slovensko.pdf` uz existuje v cielovom adresari:
- Skus `20260512-orange-slovensko-2.pdf`
- Pokracuj `-3`, `-4`, ...

Kolizia obvykle znaci, ze ten isty dodavatel vystavil viac faktur v ten isty den
(napr. velkoodber + maly nakup) — to je legitimne, neriesit to.

## Confidence levels

V `_renamer.log.json` oznac kazdy dokument:

| Confidence | Kedy | Akcia |
|---|---|---|
| `high` | Datum (z #1 priority) aj vendor jasne extrahovane | Premenuj |
| `medium` | Pouzity fallback datum (#2) alebo vendor extrahovany s neistotou | Premenuj, ale flagni |
| `low` | Zla kvalita obrazku, OCR zlyhal, nemozno s istotou urcit | **NEPREMENUJ** — log s `needs_review: true` |

## Pravidla — nikdy

- Nepremenovavaj ak nevies s istotou urcit datum **aj** vendora
- Neprepis existujuci subor — vzdy najdi novy nazov s prilepkom
- Nepouzivaj `IC` (identifikacne cislo) ako vendor slug — moze byt OCR chyba
- Nepouzivaj IBAN, cislo faktury alebo VS ako sucast nazvu
- Nepremenovavaj log subory (`_email-collector.log.json`, `_renamer.log.json`)
- Move, nie Copy+Delete (vzdy `mcp__filesystem__move_file`)

## Konvencia pre rozne typy dokladov

| Typ | Priklad nazvu |
|---|---|
| Beznay faktura | `20260512-orange-slovensko.pdf` |
| Najomne | `20260401-prenajom-priestorov.pdf` (vendor = "prenajom-priestorov") |
| Bloček z casino/parkovania | `20260418-shell.jpg` (vendor = retail brand) |
| Tankovanie | `20260420-omv.pdf` |
| Restauracia (reprezentacne) | `20260415-hotel-tatra.pdf` |

## Cerpacie stanice / pohonne hmoty

- Doklad z cerpacej stanice pomenuj podla ZNACKY, nie podla prevadzkovatela:
  - `Janosik - NEA, s.r.o.`, `BEDYMAR, s.r.o.`, `HSV s.r.o.` = **Shell** -> slug `shell`
  - `OMV` -> `omv`, `Slovnaft` -> `slovnaft`
- **Shell Bernolakovo** (prevadzkovatel `J&J Property Invest, s.r.o.`, Senecka cesta 3231,
  90027 Bernolakovo; predava V-P Diesel): na koniec nazvu pridaj `-discovery`
  -> `YYYYMMDD-shell-discovery.<ext>`

## Bankove vypisy (vypis z uctu)

- Bankovy vypis (napr. Tatra banka) je **doklad** -> patri medzi doklady (nie do `_ignored/`).
- Pomenovanie: **`YYYYMM-vypisy.pdf`** (iba rok+mesiac, bez dna), kde `YYYYMM` je
  obdobie, ZA ktore vypis je.
- Mesiac urci podla datumu dorucenia / datumu vypisu:
  - prisiel **posledny den v mesiaci** -> je za **dany** mesiac,
  - prisiel **na zaciatku mesiaca** -> je za **predchadzajuci** mesiac.
- Vypisy chodia **sifrovane**: desifruj cez `pypdf` s heslom z env `BANK_PDF_PASSWORD`
  (qpdf nie je nutny) a uloz citatelne PDF medzi doklady.
- Viac uctov v rovnakom mesiaci -> kolizia: priloz `-2`, `-3`, ...
