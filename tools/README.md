# tools/ — Python helper scripts

Pure Python **stdlib only** scripts that agents invoke via `Bash`.
Žiadne tretie strany, žiadne pip dependencies, žiadne MCP middleware.

## `fetch_invoices.py` — IMAP downloader (faktúry)

Stiahne prílohy z účtovných emailov do pracovného foldra.

```bash
python tools/fetch_invoices.py --month 2026-04 --out vystup/2026-04/
```

API: stdlib `imaplib.IMAP4_SSL` (IMAP over TLS, RFC 3501 — od 1986).

Pravidlá:
- Otvorenie schránky cez `readonly=True`
- `BODY.PEEK[]` (nenastavuje `\Seen` flag)
- Nikdy nemaže, nepresúva, neoznačuje
- Dedupe podľa `Message-ID` v `_email-collector.log.json`

## `fetch_bank_statements.py` — IMAP downloader (bankové výpisy)

Stiahne **šifrované PDF** bankové výpisy do `_bank/raw/` foldra.

```bash
python tools/fetch_bank_statements.py --month 2026-04 --out vystup/2026-04/_bank/raw/
```

Líši sa od `fetch_invoices.py`:
- Iné subject keywords (`vypis`, `výpis`, `statement`, ...)
- Rozšírené dátumové okno (do 15. dňa mesiaca-po-nasledujúcom — výpisy chodia neskôr)
- Voliteľný env filter `BANK_SENDER_WHITELIST` (whitelist emailov banky)

## `decrypt_bank_pdfs.py` — qpdf wrapper

Dekryptuje heslom-chránené PDF výpisy cez **qpdf** (shell out).

```bash
python tools/decrypt_bank_pdfs.py --in vystup/2026-04/_bank/raw/ --out vystup/2026-04/_bank/
```

API: `subprocess` → `qpdf --password=<env> --decrypt input.pdf output.pdf`.

Bezpečnosť:
- Heslo z env (`BANK_PDF_PASSWORD` alebo per-bank `BANK_PDF_PASSWORD_<NAME>`)
- Heslo NIKDY do stdout/stderr; ak ho qpdf v chyovej hláške vypľuje, maskuje sa `***`
- qpdf je rock-solid (~20 rokov, používa ho aj LibreOffice na sanitáciu PDF)

## `nc_share_and_notify.py` — Nextcloud share + email

Po tom, ako desktop klient Nextcloud zosynchronizuje 7z do cloudu,
vytvorí public share link cez OCS Share API a pošle ho účtovníkovi emailom.

```bash
python tools/nc_share_and_notify.py \
    --file vystup/2026-04.7z \
    --nc-path /Uctovnictvo/2026-04.7z \
    --month 2026-04
```

API:
- **Nextcloud WebDAV** (RFC 4918) — `HEAD` polling kým súbor neobjaví na serveri
- **Nextcloud OCS Share API** (`/ocs/v2.php/apps/files_sharing/api/v1/shares`)
  — stabilné od Nextcloud 8.x (2015), backwards-compatible dodnes
- **SMTP** (RFC 5321) — `smtplib.SMTP` cez STARTTLS alebo `SMTP_SSL`

## Dve heslá v hre

| Heslo | Kde sa generuje | Kde je |
|---|---|---|
| **7z heslo** | nastavené ručne v env `ACC_ZIP_PASSWORD` | šifruje obsah archívu |
| **Share heslo** | náhodne generované scriptom (20 znakov) | chráni download link |

Script **netlačí** `ACC_ZIP_PASSWORD`. Share heslo printuje na stdout
(`SHARE_PASSWORD=...`) aby ho agent vedel ďalej posunúť používateľovi.
Používateľ pošle obe heslá účtovníkovi **out-of-band** (SMS, Signal, telefón).

## Prečo nie MCP?

| Kritérium | MCP server | Tento script |
|---|---|---|
| Token cost | každý tool call serializovaný do kontextu | jedna Bash invokácia + summary |
| Audit | tretia strana z GitHub | čistý stdlib, čitateľný kód |
| Stabilita | community projekt, môže zmiznúť | imaplib/smtplib/urllib od 1990s |
| Bezpečnosť | credentials prejdú cez MCP wrapper | env vars priamo do stdlib |
| Deterministickosť | LLM volá jednotlivé tooly | deterministický skript |

Pre filesystem operácie ostáva **official MCP server** (sandboxovaný,
od Anthropicu). MCP používame tam, kde dáva zmysel; pre IMAP / Nextcloud
sú natívne API priame a spoľahlivejšie.
