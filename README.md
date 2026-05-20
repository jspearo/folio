# Uctovny asistent — Claude Code agent

Mesacny uctovny pipeline pre Claude Code: stiahne doklady z emailu (IMAP),
premenuje ich na `YYYYMMDD-<companyName>.<ext>`, skontroluje kompletnost
podla zoznamu pravidelnych dodavatelov, zabali do sifrovaneho 7z archivu,
hodi do Nextcloud-synced foldra (klient ho uploadne automaticky), vytvori
public share link cez OCS API a posle ho uctovnikovi emailom.

Vypracovane ako domaca uloha #3 pre kurz AI (maj 2026).

## Architektura

```
Claude Code (orchestrator — instrukcie v CLAUDE.md)
  │
  ├── 🤖 email-collector       ── Bash → tools/fetch_invoices.py (stdlib imaplib)
  │     └── 📜 extract-invoices-from-email
  │
  ├── 🤖 document-renamer       ── Read (Claude vision na PDF/JPG) + MCP filesystem
  │     └── 📜 rename-accounting-docs
  │
  ├── 🤖 completeness-checker   ── MCP filesystem (read-only)
  │     └── 📜 check-monthly-invoices
  │
  ├── 🤖 bank-reconciler        ── Bash → tools/fetch_bank_statements.py
  │     │                          + tools/decrypt_bank_pdfs.py (qpdf)
  │     │                          + Read (vision na vypisy a faktury)
  │     └── 📜 match-transactions-to-invoices
  │
  └── 🤖 archiver               ── Bash 7z + Bash → tools/nc_share_and_notify.py
        └── 📜 package-encrypted-zip          (stdlib urllib + smtplib)
```

Pouzite primitivy Claude Code:

| Primitiva | Co je v projekte |
|---|---|
| **MCP server** | `filesystem` (oficialny od Anthropic, sandboxovany na `./vystup` + `./config`) |
| **Subagenti** | 5 — `email-collector`, `document-renamer`, `completeness-checker`, `bank-reconciler`, `archiver` |
| **Skill-y** | 5 — `extract-invoices-from-email`, `rename-accounting-docs`, `check-monthly-invoices`, `match-transactions-to-invoices`, `package-encrypted-zip` |
| **Tools/** | 4 Python stdlib skripty — `fetch_invoices.py`, `fetch_bank_statements.py`, `decrypt_bank_pdfs.py`, `nc_share_and_notify.py` |
| **CLAUDE.md** | instrukcie pre top-level orchestrator |
| **settings.json** | permissions allowlist + MCP server config + env premapovanie |

Bez pluginov, bez marketplace, **bez community MCP serverov s nasimi credentials**.

## Preco nie MCP pre IMAP a Nextcloud?

| | MCP pristup | Python skript |
|---|---|---|
| Audit | community kod z GitHub | cisty stdlib (imaplib, smtplib, urllib od 1986+) |
| Token cost | kazdy tool call serializovany do kontextu | jedna Bash invokacia + summary |
| Stabilita | community projekt moze zmiznut | RFC-stabilizovane protokoly, stdlib |
| Bezpecnost | credentials cez MCP wrapper tretej strany | env vars priamo do stdlib |
| Deterministickost | LLM rozhoduje co volat | deterministicky skript |

Pre filesystem operacie ostáva **oficialny MCP server od Anthropic** — to je tam,
kde MCP prinasa hodnotu (sandboxing). IMAP a Nextcloud su priame API hovory.

## Prerekvizity

| Co | Preco | Instalacia |
|---|---|---|
| Claude Code | hlavny agent | https://claude.com/claude-code |
| 7-Zip | sifrovany archiv | Win: https://www.7-zip.org/ ; Linux: `apt install p7zip-full` ; Mac: `brew install p7zip` |
| qpdf | dekrypcia bankovych PDF vypisov (iba ak chces krok 5) | Win: `choco install qpdf` ; Linux: `apt install qpdf` ; Mac: `brew install qpdf` |
| Node.js + npx | filesystem MCP server | https://nodejs.org/ |
| Python 3.9+ | tools/ skripty | https://python.org/ (stdlib only, ziadny pip install) |
| Nextcloud desktop client | upload do cloudu | https://nextcloud.com/install/ |
| IMAP ucet | citanie emailov | IMAP credentials (Gmail App Password / Outlook / vlastny mail) |
| SMTP ucet | odoslanie emailu uctovnikovi | typicky rovnaky provider ako IMAP |
| Nextcloud app password | OCS Share API auth | Settings → Security → Generate app password |

## Konfiguracia

### 1. Env premenne — vytvor `.env` v `folio/`

```bash
# === IMAP (citanie uctovnych emailov) ===
IMAP_HOST=imap.gmail.com
IMAP_PORT=993
IMAP_USERNAME=ucto@mojafirma.sk
IMAP_PASSWORD=app-specific-password-here

# === SMTP (odoslanie emailu uctovnikovi) ===
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=ucto@mojafirma.sk
SMTP_PASSWORD=app-specific-password-here

# === Nextcloud ===
NC_BASE_URL=https://cloud.mojafirma.sk
NC_USERNAME=ucto
NC_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx-xxxx

# === Lokalny drop folder ===
# Toto je lokalny folder ktory Nextcloud klient synchronizuje do cloudu.
# Mapovanie napr.: ACCOUNTANT_DROP=/home/user/Nextcloud/Uctovnictvo
# zodpoveda Nextcloud ceste /Uctovnictvo/<file>
ACCOUNTANT_DROP=/home/user/Nextcloud/Uctovnictvo
NC_REMOTE_PREFIX=/Uctovnictvo

# === Email uctovnika ===
UCTOVNIK_EMAIL=uctovnik@mojauctovnicka.sk

# === Heslo na sifrovanie 7z (min. 16 znakov) ===
ACC_ZIP_PASSWORD=silne-heslo-min-16-znakov-tu

# === Bankove sparovanie (volitelne, krok 5) ===
# Heslo na dekrypciu PDF vypisov (typicky pevne stanovene v internet bankingu)
BANK_PDF_PASSWORD=heslo-na-pdf-vypis
# Volitelne: whitelist email odosielatelov, ked je vypisov viac z roznych adries
BANK_SENDER_WHITELIST=noreply@tatrabanka.sk,statements@vub.sk
# Per-bank override (pouzi --bank tatra resp. --bank vub v decrypt skripte):
# BANK_PDF_PASSWORD_TATRA=...
# BANK_PDF_PASSWORD_VUB=...
```

Nacitanie env pred spustenim Claude Code:

```powershell
# PowerShell
Get-Content .env | ForEach-Object {
  if ($_ -match '^(.+?)=(.+)$') {
    [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
  }
}
```

```bash
# bash / zsh
set -a; source .env; set +a
```

### 2. Edituj `config/expected-monthly.yaml`

Default zoznam obsahuje typickych slovenskych dodavatelov (Orange, Telekom,
ZSDIS, SPP, Webglobe, Microsoft 365, ...). Uprav podla skutocnych dodavatelov
tvojej firmy.

### 3. Over filesystem MCP

```bash
npx -y @modelcontextprotocol/server-filesystem --help
```

### 4. Over Python skripty (manualne)

```bash
python tools/fetch_invoices.py --month 2026-04 --out /tmp/test/
python tools/nc_share_and_notify.py --file /tmp/test.txt --nc-path /Uctovnictvo/test.txt
```

## Pouzitie

V root foldri **folio/**:

```bash
claude
```

Priklady promptov:

| Prompt | Co sa stane |
|---|---|
| `Spracuj uctovne doklady za april 2026.` | Cely pipeline: email → rename → check → 7z → share + notify |
| `Stiahni doklady za minuly mesiac, iba ich premenuj.` | Kroky 1+2, preskoci 3+4 |
| `Skontroluj kompletnost za marec 2026.` | Iba krok 3 (predpoklada ze 1+2 prebehlo) |
| `Zabal april a posli uctovnikovi.` | Iba krok 4 (predpoklada ze 1-3 prebehlo) |

Default mesiac (ak nezadany) = **predchadzajuci kalendarny mesiac**.

## Struktura projektu

```
folio/
├── README.md                       (tento subor)
├── CLAUDE.md                       instrukcie pre orchestrator
├── .env                            (NIE v git! credentials)
├── .claude/
│   ├── settings.json               MCP filesystem + permissions
│   ├── agents/
│   │   ├── email-collector.md
│   │   ├── document-renamer.md
│   │   ├── completeness-checker.md
│   │   └── archiver.md
│   └── skills/
│       ├── extract-invoices-from-email/SKILL.md
│       ├── rename-accounting-docs/SKILL.md
│       ├── check-monthly-invoices/SKILL.md
│       └── package-encrypted-zip/SKILL.md
├── tools/
│   ├── README.md
│   ├── fetch_invoices.py           IMAP downloader pre faktury (stdlib)
│   ├── fetch_bank_statements.py    IMAP downloader pre bankove vypisy (stdlib)
│   ├── decrypt_bank_pdfs.py        qpdf wrapper na dekrypciu PDF (stdlib + qpdf CLI)
│   └── nc_share_and_notify.py      Nextcloud OCS Share + SMTP (stdlib)
├── config/
│   └── expected-monthly.yaml       zoznam pravidelnych dodavatelov
└── vystup/                          (vytvori sa automaticky)
    └── 2026-04/                     pracovny adresar
```

## Pipeline tok (krok po kroku)

### 1. email-collector
- Spusti `python tools/fetch_invoices.py --month <YYYY-MM> --out vystup/<YYYY-MM>/`
- Skript: `imaplib.IMAP4_SSL` (stdlib), `readonly=True`, `BODY.PEEK[]`
- Filter: dátový rozsah (IMAP server-side) + subject keywords (Python)
- Stiahne `.pdf`, `.jpg`, `.png` ≥ 5 KB
- Dedupe podľa `Message-ID` v `_email-collector.log.json`

### 2. document-renamer
- Vylistuje vsetky doklady v `vystup/<YYYY-MM>/`
- Pre kazdy: precita PDF / obrazok cez Claude vision -> dátum dodania + vendor
- Premenuje na `YYYYMMDD-<vendor>.<ext>`
- Zapise `_renamer.log.json` (vratane confidence levels)

### 3. completeness-checker
- Porovna obsah `vystup/<YYYY-MM>/` so zoznamom v `config/expected-monthly.yaml`
- Report: **Pritomne / Chyba / Ostatne**
- Ak chyba `monthly` doklad -> orchestrator sa spyta pouzivatela

### 4. bank-reconciler *(volitelne)*
- `python tools/fetch_bank_statements.py` → stiahne sifrovane PDF vypisy
- `python tools/decrypt_bank_pdfs.py` → qpdf dekrypcia s heslom z `BANK_PDF_PASSWORD`
- Claude vision precita vypisy aj faktury, fuzzy spáruje (3-tier: VS / amount+date+vendor / amount+date)
- Output: `vystup/<YYYY-MM>/_bank/_reconciliation-report.md` so sekciami:
  - **Sparovane** (audit trail)
  - **NESPAROVANE VYDAJE** ⚠️ (platby bez dokladu — vyziadat doklady)
  - **NESPAROVANE DOKLADY** (faktury cakajuce na uhradu)
  - **EXCLUDED** (poplatky, dane, mzdy — info)

### 5. archiver
- Vytvori `vystup/<YYYY-MM>.7z` cez `7z a -t7z -mhe=on -p"$ACC_ZIP_PASSWORD"`
- Test integrity (`7z t`)
- Presunie do `$ACCOUNTANT_DROP/` (= lokalny Nextcloud-synced folder)
- Spusti `python tools/nc_share_and_notify.py`:
  - Polluje Nextcloud cez WebDAV `HEAD` az kym subor neobjavi v cloude
  - Vytvori public share link cez OCS Share API (nahodne heslo + 30 dni expiracia)
  - Posle link emailom na `UCTOVNIK_EMAIL`
  - Vypise `SHARE_PASSWORD=...` na stdout (orchestrator ho zobrazi pouzivatelovi)

## Bezpecnost

- **`ACC_ZIP_PASSWORD`** nikdy nie je v repo, logoch, stdout, ani v nazvoch suborov
- **`NC_APP_PASSWORD`** je Nextcloud-specific (Settings → Security), nie hlavne heslo
- **IMAP prístup** je read-only — skript otvara mailbox s `readonly=True`,
  pouziva `BODY.PEEK[]` (nenastavuje `\Seen` flag), nikdy nemaze ani nepresúva
- **Filesystem MCP** sandboxovany na `./vystup` a `./config` — agent neoperuje mimo
- **Bash whitelist**: iba `7z`, `ls`, `mv`, `cp`, `test`, `python tools/*` — ziadne
  `curl`, `wget`, `rm -rf`, `git push`
- **7z `-mhe=on`** sifruje aj nazvy suborov v archive (nie iba obsah)
- **Email uctovnikovi** obsahuje IBA share link — heslo na share aj heslo na archiv
  pouzivatel posiela uctovnikovi **out-of-band** (SMS, Signal, telefon)
- **Pred archivaciou** sa orchestrator spyta pouzivatela ak chyba monthly doklad

## Troubleshooting

### `python: command not found`

Na Windows skús `py` namiesto `python`. Na Linux/Mac skús `python3`.
Skripty su v `.claude/settings.json` povolene pod oboma menami.

### Nextcloud sync je pomaly

`nc_share_and_notify.py` polluje WebDAV pocas 10 minut (default).
Ak je sync este pomalsi, zvys `--sync-timeout 1800` (30 min) v agent prompte
alebo skontroluj, ze klient bezi a folder je synced.

### OCS Share API vrati 403 / 401

- `NC_APP_PASSWORD` musi byt **app password** vytvorene v Nextcloud Settings,
  nie normalne uzivatelske heslo
- Uzivatel musi mat permissions na zdielanie suborov (admin setting)

### Gmail vyzaduje App Password

Pri Gmail-e treba `App Password` (nie obycajne heslo k uctu) ak je dvojfaktorova
overovanie zapnute. Vytvor na https://myaccount.google.com/apppasswords.

### 7z nenajdene

```bash
which 7z       # Linux/Mac
where 7z.exe   # Windows
```

Ak nie je v PATH, doplnit v `.claude/settings.json` absolutnu cestu:
```json
"Bash(C:\\Program Files\\7-Zip\\7z.exe:*)"
```

## Hodnotenie / Co tu najdes

- **4 subagenti** s rolami a tool-restrikciami (`tools:` frontmatter)
- **4 skill-y** s detailnym domain knowledge (formaty datumov, slug rules, OCS API, ...)
- **1 oficialny MCP server** (filesystem od Anthropic) — sandboxovany
- **2 Python stdlib skripty** namiesto fragilnych community MCP serverov
- **Permissions allowlist & denylist** v settings.json
- **CLAUDE.md** pre top-level orchestrator
- **expected-monthly.yaml** ako konfiguracia pre business pravidla
- **Bezpecnostne pravidla** v kazdom subagent-ovi + skill-e
- **Logy** pre audit a dedupe (`_email-collector.log.json`, `_renamer.log.json`)
- **Rock-solid APIs**: IMAP (RFC 3501, 1986), SMTP (RFC 5321, 1982),
  WebDAV (RFC 4918, 1999), Nextcloud OCS Share API (since 2015)

## Licencia

Projekt pre ucely domacej ulohy. Volne pouzitelne na rozsirovanie.
