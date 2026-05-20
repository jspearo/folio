# run.ps1 — nacita folio/.env do session env premennych a spusti Claude Code.
#
# Pouzitie:
#     cd folio
#     ./run.ps1                 # spusti claude
#     ./run.ps1 -- --help       # propaguje argumenty do claude
#
# Format .env:
#     KEY=value                 (medzery okolo = su trim-nute)
#     KEY="hodnota s medzerami"
#     # komentar (preskoci sa)
#
# Bezpecnost:
#     - nepiseme nic z .env do stdout
#     - env premenne su nastavene IBA v tejto PowerShell session
#       (nezasahujeme do User/Machine scope)

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'
$envFile = Join-Path $PSScriptRoot '.env'

if (-not (Test-Path $envFile)) {
    Write-Host ""
    Write-Host "CHYBA: chyba subor .env v $PSScriptRoot" -ForegroundColor Red
    Write-Host "Skopiruj .env.example -> .env a vyplnis svoje credentials." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$loaded = 0
$skipped = 0
Get-Content $envFile | ForEach-Object {
    $line = $_

    # Preskoc prazdne riadky a komentare
    if ($line -match '^\s*$' -or $line -match '^\s*#') {
        $skipped++
        return
    }

    # Parsuj KEY=value
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $key = $matches[1]
        $val = $matches[2]

        # Odstran obklucujuce uvodzovky ak su
        if ($val -match '^"(.*)"$') { $val = $matches[1] }
        elseif ($val -match "^'(.*)'$") { $val = $matches[1] }

        # Nastav iba pre tuto session (Process scope)
        [Environment]::SetEnvironmentVariable($key, $val, 'Process')
        $loaded++
    } else {
        Write-Warning "Preskakujem nevalidny riadok: $line"
    }
}

Write-Host "Nacitanych $loaded env premennych z .env" -ForegroundColor Green

# Quick smoke-check ze co potrebujeme je nastavene (bez vypisu hodnot!)
$required = @(
    'IMAP_HOST', 'IMAP_USERNAME', 'IMAP_PASSWORD',
    'SMTP_HOST', 'SMTP_USERNAME', 'SMTP_PASSWORD',
    'NC_BASE_URL', 'NC_USERNAME', 'NC_APP_PASSWORD',
    'ACCOUNTANT_DROP', 'UCTOVNIK_EMAIL', 'ACC_ZIP_PASSWORD'
)
$missing = @($required | Where-Object {
    [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))
})

if ($missing.Count -gt 0) {
    Write-Warning "Chybajuce povinne env premenne: $($missing -join ', ')"
    Write-Warning "Doplnis ich do .env. Volitelne (krok 5): BANK_PDF_PASSWORD, BANK_SENDER_WHITELIST"
}

# Spusti Claude Code (propaguje argumenty)
Write-Host "Spustam Claude Code v $PSScriptRoot ..." -ForegroundColor Cyan
& claude @ClaudeArgs
