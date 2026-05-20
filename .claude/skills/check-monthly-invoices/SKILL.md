---
name: check-monthly-invoices
description: Skontroluje, ze v mesacnom foldri su vsetky pravidelne doklady (najom, telco, hosting, energie...). Pouzi pred archivaciou aby uctovnik vedel co doplnit. Popisuje format expected-monthly.yaml, matching logiku a report format.
---

# Check monthly invoices completeness

Skill pre subagent `completeness-checker`. Pravidla pre kontrolu kompletnosti
mesacnych dokladov.

## Config file format

`config/expected-monthly.yaml` ma tuto strukturu:

```yaml
vendors:
  - slug: orange-slovensko
    name: "Orange Slovensko, a.s."
    frequency: monthly
    category: telco

  - slug: webglobe-yegon
    name: "Webglobe – Yegon, s.r.o."
    frequency: monthly
    category: hosting

  - slug: spp
    name: "SPP, a.s."
    frequency: quarterly
    months: [3, 6, 9, 12]
    category: gas

  - slug: nay-elektronika
    name: "NAY, a.s."
    frequency: yearly
    months: [1]
    category: it-hardware

  - slug: revizia-vytahu
    name: "Revizia vytahu"
    frequency: irregular
    category: maintenance
```

### Polia

| Pole | Povinne | Popis |
|---|---|---|
| `slug` | ano | Vendor slug (zhodny s naming konvenciou) |
| `name` | ano | Cely pravny nazov (pre report) |
| `frequency` | ano | `monthly` / `quarterly` / `yearly` / `irregular` |
| `months` | iba pre quarterly/yearly | Cisla mesiacov (1-12), kedy ocakavame |
| `category` | nie | Kategoria pre triedenie v reporte |
| `aliases` | nie | Pole alternativnych slug-ov |

### Frekvencie

| Frekvencia | Co znamena |
|---|---|
| `monthly` | Ocakavany kazdy mesiac. Chybajuci = WARN. |
| `quarterly` | Ocakavany v mesiacoch z `months` pola. Chybajuci v tom mesiaci = WARN. |
| `yearly` | Ocakavany raz rocne, v mesiaci z `months`. Inde sa nehlasi. |
| `irregular` | Pripomenutie ale missing **nie je chyba** (napr. servis). |

## Matching logika

Pre kazdeho vendora z config-u, ktory je ocakavany v danom mesiaci:

1. **Filter ocakavania:**
   - `monthly` -> vzdy ocakavany
   - `quarterly`/`yearly` -> ocakavany iba ak aktualny mesiac je v `months`
   - `irregular` -> nikdy nie required, len uvedeny v reporte

2. **Hladanie v `work_dir`:**
   - Format: `YYYYMMDD-<slug>*.<ext>`
   - `YYYYMMDD` musi zacinat danym mesiacom (napr. pre 2026-04 -> `202604XX`)
   - `<slug>` zodpoveda `vendor.slug` ALEBO niektoremu z `vendor.aliases`
   - Suffix `-2`, `-3` (kolizie) je OK, stale to ratame ako prítomne
   - `<ext>` lubovolna z `pdf`, `jpg`, `jpeg`, `png`, `heic`

3. **Vysledok per vendor:**
   - **present**: aspon jeden subor sa nasiel
   - **missing**: ziadny sa nenasiel
   - **not_expected**: vendor nie je ocakavany v tomto mesiaci (preskoc)

## Sekcia "Ostatne doklady"

Subory v `work_dir`, ktore nezodpovedaju ziadnemu vendor-ovi z config-u, zarad do
sekcie **ℹ️ Ostatne**. Toto je **informativne**, nie chyba — su to napriklad
jednorazove nakupy (tankovanie, restauracie, parkoval).

## Report format

```markdown
# Kontrola kompletnosti za 2026-04

## ✅ Pritomne (4)
- orange-slovensko (telco): `20260415-orange-slovensko.pdf`
- webglobe-yegon (hosting): `20260403-webglobe-yegon.pdf`
- zsdis (energy): `20260420-zsdis.pdf`
- prenajom-priestorov (rent): `20260401-prenajom-priestorov.pdf`

## ⚠️ Chyba (1)
- **o2-slovakia** (telco, monthly) — naposledy najdene v 2026-03

## ℹ️ Ostatne doklady (3)
- `20260412-tesco-stores-sr.jpg` — nakup
- `20260418-shell.pdf` — tankovanie
- `20260425-uber.pdf` — doprava

## Verdikt
WARN — chyba 1 monthly doklad. Pred archivaciou potvrdit, ci sa ma pokracovat.
```

## Verdikt

| Stav | Verdikt | Co dalej |
|---|---|---|
| Vsetky `monthly` a aktivne `quarterly`/`yearly` pritomne | **OK** | Orchestrator moze archivovat |
| Chyba `monthly` | **WARN** | Orchestrator sa MUSI spytat pouzivatela |
| Chyba `quarterly`/`yearly` v ich mesiaci | **WARN** | Orchestrator sa MUSI spytat pouzivatela |
| Chyba iba `irregular` alebo nic | **OK** | Pokracuj |

## Co skill NIE robi

- **Nemeni** subory v `work_dir`
- **Nemaze** missing vendorov z config-u
- **Nekontroluje obsah** suborov (to robi renamer)
- **Nepocita ciastky** ani DPH

Iba checklist `pritomne / chybajuce / ostatne`.

## Edge case: kolizia v slug-u

Ak by aliasy mali konflikty (napr. `o2` aj `o2-slovakia` v rovnaky den), zaratame
prvy najdeny ako pritomny pre primarny slug, ostatne ako "ostatne". V praxi sa
toto stat nemoze ak su slug-y unique v naming konvencii.
