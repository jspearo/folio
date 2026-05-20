---
name: match-transactions-to-invoices
description: Pravidla pre sparovanie bankovych transakcii s uctovnymi dokladmi. Pouzi vzdy ked je potrebne urcit, ktora platba zodpoveda ktorej fakture (alebo ze nezodpoveda ziadnej). Popisuje 3-tier matching (VS, fuzzy vendor+amount+date, len amount+date) a tolerancie.
---

# Match transactions to invoices

Skill pre subagent `bank-reconciler`. Pravidla na fuzzy sparovanie bankovych
transakcii s uctovnymi dokladmi.

## Vstup

- `transactions`: zoznam transakcii z bankoveho vypisu (date, amount, counterparty,
  iban, vs, ks, description)
- `invoices`: zoznam dokladov v pracovnom foldri (filename, vendor_slug, date,
  invoice_number, amount, iban, due_date)

Riesime IBA **vydaje** (amount < 0). Prijmy iba uvedieme do reportu informativne.

## 3-Tier matching

### Tier 1 — high confidence: VS match

Ak `transaction.vs` (variabilný symbol) je nenulové a numericky zodpovedá
`invoice.invoice_number` (s normalizovanymi nulami a pomlcciakmi), je to zhoda
**high confidence**.

Normalizacia:
- Odstran vodiace nuly: `000123` → `123`
- Odstran pomlcky, lomky: `2026/0042` → `20260042`
- Porovnaj po normalizacii

Priklad:
- Transakcia VS: `20260415`
- Faktura cislo: `2026-0415`
- Po normalizacii: oba `20260415` → MATCH high

### Tier 2 — medium confidence: amount + date + vendor

Bez VS (alebo s VS, ktore sa nikde nezhoduje):
- `|transaction.amount| == invoice.amount` (presne, tolerancia 0.01 EUR pre zaokruhlenie)
- `abs(transaction.date - invoice.date) ≤ 14 dni`
- Fuzzy vendor match: `transaction.counterparty` (lowercase, bez diakritiky)
  obsahuje `invoice.vendor_slug` ALEBO jeho aliasy

Priklad:
- Transakcia: 2026-04-18, -29.90, "ORANGE SLOVENSKO, A.S."
- Faktura: `20260415-orange-slovensko.pdf`, amount=29.90, due_date=2026-04-30
- Dni medzi 18 a 15 = 3 ≤ 14 → MATCH medium
- "orange-slovensko" je substring "orange slovensko a s" po normalizacii → vendor OK
- Sumy zhoduju → MATCH medium

### Tier 3 — low confidence: amount + date only

Bez VS, bez vendor matchu:
- `|transaction.amount| == invoice.amount` (tolerancia 0.01 EUR)
- `abs(transaction.date - invoice.date) ≤ 7 dni` (uzsie okno!)

Pouzij iba ak existuje **prave jedna** faktura s touto sumou v okne (inak je to
nejednoznacne — flagni ako `ambiguous`, nech to overi clovek).

## Anti-matches (nepouzit)

- Transakcia s `amount > 0` (prijem) — nesparovat s vydajovou fakturou
- Transakcia za **bankove poplatky** (KS `0379`, `0379x`, alebo description obsahuje
  "poplatok", "fee", "udrzba uctu") — toto nie su faktury, nesparovat
- Dane (description obsahuje "DPH", "FU", "danovy urad", "Financne riaditelstvo") —
  iba flagni ako tax, nesparovat s dokladmi v `work_dir`
- Mzdy a odvody (description "mzda", "vyplata", "Socialna poistovna", "VSZP",
  "Dovera", "Union ZP") — nesparovat

## IBAN match (bonus signal)

Ak `transaction.counterparty_iban` == `invoice.iban`, zvys confidence o jeden level
(low → medium, medium → high). IBAN je velmi silny signal lebo ho nemozno zameniť
nahodou.

## Vystupne kategorie

Pre kazdu transakciu:
- `matched_high` — Tier 1, jeden invoice match
- `matched_medium` — Tier 2, jeden match
- `matched_low` — Tier 3, jeden match
- `ambiguous` — viacero potencialnych dokladov, treba overit clovekom
- `unmatched` — ziadny doklad nesedi
- `excluded` — anti-match (poplatok / dan / mzda)

Pre kazdu fakturu:
- `paid` — sparovala sa s transakciou
- `unpaid` — nesparovala (este nezaplatena alebo bude v dalsom mesiaci)

## Edge cases

### Suma sa lisi o 0.01 - 0.05 EUR
- Mozne zaokruhlenie pri prevodu z meny. Akceptuj toleranciu `0.01`.
- Ak rozdiel > 0.05, nesparovat.

### Faktura uhradena na splatky / casti
- Niekedy uhradite fakturu vo viacerych splatkach. Tier 2 a 3 nemusi zhoduvat.
- V takom pripade flagni ako `partial_payment_possible` ak najdes viac transakcii
  s tym istym counterparty, ktorych suma sa rovna fakture.

### Faktura z minuleho mesiaca uhradena v tomto mesiaci
- Bezne — uhradzame s 14-30 dnovým splatnym lehotou.
- Tier 2/3 hladaju v 14-dnovom okne; pre kontrolu mozes nacitat aj faktury z
  predchadzajuceho mesiaca z `vystup/<previous_month>/`.

### Transakcia bez counterparty
- Niektore SEPA platby maju len IBAN. Pouzi `iban` na vendor lookup.
- Ak `_invoices.json` nema iban, je matching `Tier 1` (VS) alebo `Tier 3`.

## Format reportu

Viz subagent `bank-reconciler` postup krok 6. Klucove sekcie:
1. **Sparovane** (informativne, pre audit)
2. **NESPAROVANE VYDAJE** ⚠️ (najdolezitejsie — platby bez dokladu, potrebne riesit)
3. **NESPAROVANE DOKLADY** (faktury cakajuce na uhradu)
4. **EXCLUDED** (poplatky, dane, mzdy — informativne)

## Co ked nesparovaní

Pre **nesparovany vydaj** (= platba bez dokladu) je nutne:
1. Skontrolovat ci doklad chyba v emaily (mozno zabudol dodavatel poslat)
2. Skontrolovat ci doklad nie je v inom mesiaci (uhrada za prijatie faktury z minulosti)
3. Vyziadat doklad od dodavatela (kontaktovat ho)

Toto je akcia pre **cloveka** — reconciler iba upozorni.
