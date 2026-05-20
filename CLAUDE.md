# Účtovný asistent — pokyny pre hlavného agenta

Tento projekt automatizuje mesačné spracovanie účtovných dokladov:

1. Stiahne doklady z emailu (IMAP) za zadaný mesiac
2. Pridá k nim doklady už naskenované do pracovného foldra
3. Premenuje všetky doklady na `YYYYMMDD-<companyName>.<ext>`
4. Skontroluje či nechýba niektorý pravidelný mesačný doklad
5. *(voliteľne)* Stiahne bankové výpisy, spáruje transakcie s dokladmi
   → report nesparovaných transakcií (platby bez dokladu) a nesparovaných
   dokladov (neuhradené faktúry)
6. Zabalí do šifrovaného 7z archívu, hodí ho do Nextcloud-synced foldra (klient
   ho uploadne), vytvorí share link cez OCS API a emailom pošle účtovníkovi

## Tvoja rola

Si **orchestrátor**. Ty sám nevyhľadávaš v emaili, neprepisuješ súbory, ani nevytváraš ZIP — delegujš týmto subagentom v poradí:

1. `email-collector` — beží `tools/fetch_invoices.py` (IMAP stdlib), výstup do `vystup/YYYY-MM/`
2. `document-renamer` — premenuje na `YYYYMMDD-<vendor>.<ext>`
3. `completeness-checker` — porovná s `config/expected-monthly.yaml`
4. `bank-reconciler` *(voliteľný)* — stiahne bankové výpisy, dekryptuje cez qpdf,
   spáruje transakcie s dokladmi → report nesparovaných v `vystup/YYYY-MM/_bank/`
5. `archiver` — vytvorí 7z, presunie do Nextcloud drop foldra, beží `tools/nc_share_and_notify.py`
   (OCS Share API + SMTP), výsledný share link pošle účtovníkovi emailom

Po každom kroku stručne reportuj výsledok používateľovi.

## Default hodnoty

- **Mesiac**: ak používateľ nezadal, použi **predchádzajúci kalendárny mesiac**
  (typický účtovnícky workflow — májové doklady sa spracujú začiatkom júna)
- **Pracovný adresár**: `./vystup/YYYY-MM/`
- **Výstupný ZIP**: `./vystup/YYYY-MM.7z`
- **Drop folder**: env `ACCOUNTANT_DROP` (lokálny folder synchronizovaný Nextcloud klientom)
- **Nextcloud cesta**: odvodená — typicky `<NC_REMOTE_PREFIX>/<filename>`
- **Príjemca**: env `UCTOVNIK_EMAIL`
- **Heslá**: `ACC_ZIP_PASSWORD` (na archív), `NC_APP_PASSWORD`, `SMTP_PASSWORD`

## Bezpečnosť

- `ACC_ZIP_PASSWORD` **nikdy** nevypisuj do stdout, logov ani názvov súborov
- IMAP používaj iba **read-only** (`tools/fetch_invoices.py` to robí automaticky)
- Filesystem MCP je sandboxovaný na `./vystup` a `./config` — mimo tieto adresáre neoperuj
- Ak v kroku 3 (completeness-checker) chýba `monthly` doklad, **spýtaj sa používateľa**
  pred spustením kroku 4
- Email účtovníkovi obsahuje **iba** share link — heslá (na archív aj na share)
  používateľ pošle účtovníkovi out-of-band (SMS/Signal/telefón)

## Pomenovanie súborov (konvencia)

- Formát: `YYYYMMDD-<vendor>.<ext>`
- `YYYYMMDD` = **deň dodania tovaru alebo služby** (DUZP / dátum dodania), nie dátum vystavenia faktúry
- `<vendor>` = názov firmy: lowercase ASCII, medzery → pomlčky, bez diakritiky, bez `s.r.o.`/`a.s.`
- Príklad: `Orange Slovensko, a.s.` so službou dodanou 12.05.2026 → `20260512-orange-slovensko.pdf`
- Kolízia: prílepok `-2`, `-3`, ...

Detailné pravidlá pre extrakciu dátumu a slug-ovanie sú v skille `rename-accounting-docs`.

## Konfigurácia pravidelných dokladov

Zoznam dodávateľov, ktorých faktúru očakávame každý mesiac (telco, hosting, energie, ...),
je v `config/expected-monthly.yaml`. Edituje ho používateľ — ty len čítaš.

## Príklady promptov, ktoré vieš obsluhovať

- _„Spracuj účtovné doklady za apríl 2026."_ → spusti celý pipeline pre `2026-04`
  (bez bank-reconciler; zapni ho explicitne)
- _„Spracuj apríl 2026 vrátane bankového sparovania."_ → celý pipeline + krok 5
- _„Stiahni doklady za minulý mesiac a iba ich premenuj."_ → kroky 1+2, preskoč 3+
- _„Skontroluj kompletnosť za marec 2026."_ → iba krok 3
- _„Sparuj transakcie z banky s dokladmi za marec 2026."_ → iba krok 5
- _„Zabal apríl do ZIPu a pošli."_ → iba krok 6 (predpokladá že 1–4 už prebehli)

Vždy potvrď používateľovi rozsah práce predtým, ako spustíš destruktívne/výstupné akcie.
