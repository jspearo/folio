# Example workflow — ako spustiť orchestrátora a ako on volá subagentov

## Krátky workflow

```
cd folio
claude              # spusti Claude Code v root foldri
```

Tým ti vznikne **orchestrátor** — to je samotný Claude Code session, ktorý si
Claude Code automaticky inicializuje z `CLAUDE.md` v aktuálnom foldri. Žiadny
extra príkaz neexistuje — orchestrátor = main session.

Potom napíšeš prompt, napr.:

```
Spracuj uctovne doklady za april 2026.
```

A Claude Code sám rozdistribuuje prácu medzi subagentmi.

## Čo sa stane pod kapotou

1. **Auto-discovery pri spustení** — Claude Code pri štarte načíta:
   - `.claude/settings.json` → permissions + MCP servery (spustí `filesystem` MCP cez `npx`)
   - `.claude/agents/*.md` → registruje 4 subagentov (frontmatter `name:`, `description:`, `tools:`, `model:`)
   - `.claude/skills/*/SKILL.md` → registruje 4 skill-y
   - `CLAUDE.md` → priloží ako system prompt orchestrátorovi
   - `.env` premenné si načítaš sám pred `claude` (viď README)

2. **Invocation subagenta** — orchestrátor má vstavaný **Agent** (resp. Task) tool.
   Keď z CLAUDE.md vidí, že má volať `email-collector`, on:
   - vyberie agenta podľa zhody jeho `description:` s aktuálnou úlohou
   - vytvorí **nový izolovaný context** s agentovým prompt-om (telo `.md` súboru)
   - subagent dostane iba tie tools, ktoré má v `tools:` frontmatter
   - subagent dobehne, vráti orchestrátorovi **jednu textovú správu** (svoj report)
   - jeho context sa zahodí — orchestrátor pokračuje s čistou hlavou

3. **Skill loading** — keď subagent (alebo orchestrátor) narazí na úlohu, ktorej
   popis sa zhoduje so skill-ovým `description:`, vyvolá ho cez **Skill** tool.
   Skill-y nie sú subagenti — nemajú vlastný context window, sú to "návody"
   načítané ad-hoc do aktuálneho contextu.

## Príklad behu — čo uvidíš v termináli

```
> Spracuj uctovne doklady za april 2026.

[orchestrátor] Spustim email-collector subagenta...
  └─ Agent(email-collector, "month=2026-04, work_dir=./vystup/2026-04/")
     └─ Bash: python tools/fetch_invoices.py --month 2026-04 --out vystup/2026-04/
     └─ stderr: Found 47 messages, saved 12 attachments to vystup/2026-04
     └─ Report: 12 prilôh stiahnutých, log v _email-collector.log.json

[orchestrátor] Email hotový. Spustim document-renamer...
  └─ Agent(document-renamer, "work_dir=./vystup/2026-04/")
     └─ Read: vystup/2026-04/Faktura 12345.pdf (vision)
     └─ Skill(rename-accounting-docs)
     └─ mcp__filesystem__move_file: Faktura 12345.pdf → 20260412-orange-slovensko.pdf
     └─ ... (12x)
     └─ Report: 11 premenovaných (high), 1 needs_review

[orchestrátor] Pred archivaciou skontrolujem kompletnost...
  └─ Agent(completeness-checker, ...)
     └─ Report: WARN — chyba 1 monthly (o2-slovakia)

[orchestrátor] Pozor: chyba o2-slovakia faktúra. Mám pokračovať s ZIP-om alebo počkať?

# (po OK pre pokračovanie, ak je požiadavka aj na bankové sparovanie:)

[orchestrátor] Spustim bank-reconciler subagenta...
  └─ Agent(bank-reconciler, "work_dir=./vystup/2026-04/, month=2026-04")
     └─ Bash: python tools/fetch_bank_statements.py --month 2026-04 --out vystup/2026-04/_bank/raw/
     └─ stderr: Saved 1 bank statement PDF to vystup/2026-04/_bank/raw
     └─ Bash: python tools/decrypt_bank_pdfs.py --in vystup/2026-04/_bank/raw/ --out vystup/2026-04/_bank/
     └─ stderr: Decrypted 1, skipped 0, failed 0
     └─ Read: vystup/2026-04/_bank/vypis-tatra-2026-04.pdf (vision)
     └─ Skill(match-transactions-to-invoices)
     └─ Read: 11x faktúry vo vystup/2026-04/*.pdf
     └─ Write: vystup/2026-04/_bank/_reconciliation-report.md
     └─ Report: 14 výdajov: 11 sparovaných (9 high VS, 2 medium), 3 NESPAROVANÉ
                ⚠️ 3 nesparovane vydaje — viz _reconciliation-report.md

[orchestrátor] Reconciliation hotový. Spustim archiver...
  └─ Agent(archiver, ...)
     └─ Bash: 7z a -t7z -mhe=on -p*** -mx=5 vystup/2026-04.7z vystup/2026-04/*
     └─ Bash: 7z t -p*** vystup/2026-04.7z          # integrity test OK
     └─ Bash: mv vystup/2026-04.7z $ACCOUNTANT_DROP/
     └─ Bash: python tools/nc_share_and_notify.py --file ... --nc-path ... --month 2026-04
     └─ stderr: sync confirmed after 4 polls (4234567 bytes)
     └─ stderr: OK — share URL emailed to uctovnik@mojauctovnicka.sk
     └─ stdout: SHARE_PASSWORD=K7p2Xq9_Rj4mZbN8wL3t
     └─ Report: archiv 4.0 MB, 12 suborov, share platnost do 2026-06-19

[orchestrátor]
✅ Hotovo. Sumár:
  - 12 dokladov spracovaných, 11 high-confidence rename, 1 potrebuje review
  - Bankové sparovanie: 11/14 výdajov sparovaných (3 nesparované — viď report)
  - Archív doručený na Nextcloud: https://cloud.../s/aBc123XyZ
  - Share password (out-of-band): K7p2Xq9_Rj4mZbN8wL3t
  - 7z password si pošli účtovníkovi cez SMS/Signal
```

## Užitočné slash-commandy v session

| Príkaz | Načo |
|---|---|
| `/agents` | zobrazí registrovaných subagentov (mali by byť 4) |
| `/skills` (alebo `/help`) | zobrazí dostupné skill-y |
| `/mcp` | status MCP serverov — `filesystem` má byť `connected` |
| `/config` | aktuálna konfigurácia z `settings.json` |
| `/clear` | reset orchestrátorovho contextu (ak chceš začať odznova) |

## Smoke test pred prvým ostrým behom

```powershell
cd folio
# nacitaj .env
Get-Content .env | ForEach-Object {
  if ($_ -match '^(.+?)=(.+)$') {
    [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
  }
}
# over ze python skript bezi (read-only, nic nezneskodlivi)
python tools/fetch_invoices.py --month 2026-04 --out vystup/test/
# startni Claude Code
claude
```

V Claude Code potom skús: `/agents` — uvidíš `email-collector`, `document-renamer`,
`completeness-checker`, `bank-reconciler`, `archiver`. Ak nie, niečo je zle so súborom
(zlý frontmatter alebo cesta).

## Tri praktické nuansy

1. **Orchestrátora explicitne nezakladáš.** Claude Code session **je**
   orchestrátor. CLAUDE.md ho len naladí na túto úlohu.
2. **Subagentov sám nevoláš.** Píš prirodzene tomu Claude Code v termináli
   (*„spracuj april"*); on rozhodne kedy a koho zavolať podľa `description:`
   v agent súboroch.
3. **Môžeš ich aj explicitne nasmerovať** ak chceš testovať: napr.
   *„Použi iba subagenta `completeness-checker` na vystup/2026-04/"*
   — orchestrátor ti vyhovie.
