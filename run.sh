#!/usr/bin/env bash
# run.sh — nacita folio/.env do session env premennych a spusti Claude Code.
#
# Pouzitie:
#     cd folio
#     ./run.sh                  # spusti claude
#     ./run.sh --help           # propaguje argumenty do claude
#
# Bezpecnost:
#     - env premenne su nastavene IBA v tejto shell session
#     - nepiseme hodnoty z .env do stdout

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "CHYBA: chyba subor .env v $SCRIPT_DIR" >&2
    echo "Skopiruj .env.example -> .env a vyplnis svoje credentials." >&2
    exit 1
fi

# Nacitaj .env. set -a exportuje vsetko az do set +a.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# Quick check ze povinne premenne su nastavene (bez vypisu hodnot)
required=(
    IMAP_HOST IMAP_USERNAME IMAP_PASSWORD
    SMTP_HOST SMTP_USERNAME SMTP_PASSWORD
    NC_BASE_URL NC_USERNAME NC_APP_PASSWORD
    ACCOUNTANT_DROP UCTOVNIK_EMAIL ACC_ZIP_PASSWORD
)
missing=()
for v in "${required[@]}"; do
    if [ -z "${!v:-}" ]; then
        missing+=("$v")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    echo "WARN: chybaju env premenne: ${missing[*]}" >&2
    echo "Volitelne (krok 5): BANK_PDF_PASSWORD, BANK_SENDER_WHITELIST" >&2
fi

echo "Spustam Claude Code v $SCRIPT_DIR ..."
exec claude "$@"
