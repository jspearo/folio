---
name: extract-invoices-from-email
description: Pravidla a postup, ako z IMAP schranky vyhladat a stiahnut uctovne doklady (faktury, danove doklady, vyuctovania) za zadany mesiac. Pouzi vzdy, ked treba vytiahnut doklady z emailu pre uctovnictvo — popisuje IMAP search query, attachment filtre, dedupe logiku.
---

# Extract invoices from IMAP

Skill pre subagent `email-collector`. Pravidla pre vyber a stahovanie priloh.

## IMAP search query patterns

Pre IMAP search pouzit kombinaciu casoveho a textoveho filtra:

```
SINCE <prvy-den-mesiaca> BEFORE <prvy-den-nasledujuceho-mesiaca>
  AND (
    SUBJECT "faktúra" OR SUBJECT "faktura" OR
    SUBJECT "invoice" OR SUBJECT "daňový doklad" OR
    SUBJECT "vyúčtovanie" OR SUBJECT "účet" OR
    BODY "číslo faktúry" OR BODY "invoice number"
  )
```

Priklad pre april 2026:
```
SINCE 1-Apr-2026 BEFORE 1-May-2026 SUBJECT "faktúra"
```

### Foldre, ktore treba prejst

- `INBOX` (vzdy)
- `INBOX/Účtovníctvo` (ak existuje)
- `INBOX/Faktúry` (ak existuje)
- `INBOX/Invoices` (ak existuje, pre dodavatelov pisuich anglicky)

Foldre vyhladaj cez `LIST` pred zaciatkom.

## Attachment filtre

### Stahuj iba

| Pripona | Pouzitie |
|---|---|
| `.pdf` | Najcastejsi format faktur |
| `.jpg`, `.jpeg` | Foto faktury z mobilu |
| `.png` | Skener / screenshot |
| `.heic` | iPhone foto |

### Ignoruj

- Subory < 5 KB (pravdepodobne podpisy/loga v paticke)
- `image001.png`, `image002.png`, ... (inline obrazky v signature Outlook/Gmail)
- Subory s `signature`, `logo`, `banner` v nazve
- `.eml`, `.msg` (vnorene emaily — to nie je faktura)
- `.xml` (ak je sucasne aj `.pdf` — XML obvykle ide s PDF, ber iba PDF)
- `.zip` priloh — to su obvykle archivy nieco ineho

## Dedupe

Daj si pozor na tieto situacie:

### Ten isty email forwardnuty

- Sleduj `Message-ID` header, nie iba subject
- Ak `Message-ID` uz je v `_email-collector.log.json`, preskoc

### Pripomenutie tej istej faktury

- Niektori dodavatelia posielaju ten isty PDF cez 7 dni ako pripomenutie
- Preferuj najstarsi email s tym istym subject patternom (regex: `[fF]akt[uú]ra[\s_-]*\d+`)

### PDF + XML versia tej istej faktury

- Niektore ucto-systemy posielaju `faktura.pdf` + `faktura.xml` (ISDOC, e-faktura)
- Vzdy ber PDF, XML ignoruj

## Nazov suborov pri stiahnuti

**Nepremenovavaj** — to robi skill `rename-accounting-docs` v dalsom kroku.
Ulozi sa to pod povodnym menom z prilohy. Pri kolizii pridaj `(2)`, `(3)`...

Priklad:
- Priloha: `Faktúra 12345.pdf`
- Po stiahnuti: `vystup/2026-04/Faktúra 12345.pdf`
- (Renamer to neskor premeni na `20260412-orange-slovensko.pdf`)

## Log file format

Po skonceni napis `vystup/<mesiac>/_email-collector.log.json`:

```json
[
  {
    "message_id": "<CAE...@mail.example>",
    "from": "fakturacia@orange.sk",
    "subject": "Faktúra č. 12345 za 04/2026",
    "received_at": "2026-04-15T08:23:00+02:00",
    "attachments_saved": ["Faktúra 12345.pdf"]
  }
]
```

Tento log sluzi:
1. Na dedupe pri opakovanom spusteni (skoncis ak `Message-ID` je v logu)
2. Na audit — uctovnik si vie pozriet, z akeho emailu prisla ktora priloha

## Co NIE

- Nemaz emaily
- Neoznacuj ako precitane (necas `\Seen` flag)
- Nepresuvaj emaily medzi foldrami
- Neukladaj heslo IMAP do logu

IMAP MCP server by mal byt nakonfigurovany s `IMAP_READ_ONLY=true`, ale tvoj kod
sa na to nemoze spoliehat — vzdy konaj read-only sam od seba.
