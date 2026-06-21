# run.ps1 - desifruje folio/.env.enc cez DPAPI a spusti Claude Code.
#
# Pouzitie:
#     cd folio
#     ./run.ps1                 # spusti claude
#     ./run.ps1 -- --help       # propaguje argumenty do claude
#
# Setup (jednorazovo):
#     1. Skopiruj .env.example -> .env, vyplnis hodnoty.
#     2. Zasifruj: ./tools/env-protect.ps1 -RemovePlain
#        (vytvori .env.enc a zmaze plaintext .env)
#     3. Editovanie do buducnosti: ./tools/env-edit.ps1
#
# Bezpecnostny model:
#     - .env.enc je sifrovany Windows DPAPI scope=CurrentUser.
#     - Desifruje sa IBA pod tymto Windows uctom na tomto stroji.
#     - Plaintext hodnoty su nastavene IBA do tohto Process scope env;
#       po skonceni claude session zmiznu.
#     - Nepiseme hodnoty do stdout ani do logov.

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ClaudeArgs
)

$ErrorActionPreference = 'Stop'
$encFile = Join-Path $PSScriptRoot '.env.enc'
$plainFile = Join-Path $PSScriptRoot '.env'

# Backward-compat warning: ak je tu este stary plaintext .env, upozorni.
if (Test-Path $plainFile) {
    Write-Host ""
    Write-Host "VAROVANIE: existuje plaintext .env vedla .env.enc." -ForegroundColor Yellow
    Write-Host "  Hesla v plaintext = bezpecnostne riziko. Po zasifrovani zmaz:" -ForegroundColor Yellow
    Write-Host "      ./tools/env-protect.ps1 -RemovePlain" -ForegroundColor Yellow
    Write-Host ""
}

if (-not (Test-Path $encFile)) {
    Write-Host ""
    Write-Host "CHYBA: chyba subor .env.enc v $PSScriptRoot" -ForegroundColor Red
    Write-Host "Setup:" -ForegroundColor Yellow
    Write-Host "  1. cp .env.example .env" -ForegroundColor Yellow
    Write-Host "  2. otvor .env a vyplnis credentials" -ForegroundColor Yellow
    Write-Host "  3. ./tools/env-protect.ps1 -RemovePlain" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Desifruj .env.enc cez DPAPI (ConvertTo-SecureString bez -Key => DPAPI CurrentUser).
try {
    $cipher = Get-Content -Raw -Path $encFile
    $secure = ConvertTo-SecureString -String $cipher
    $plaintext = [System.Net.NetworkCredential]::new('', $secure).Password
} catch {
    Write-Host ""
    Write-Host "CHYBA: nepodarilo sa desifrovat .env.enc" -ForegroundColor Red
    Write-Host "Pravdepodobne je sifrovany inym Windows uctom alebo na inom stroji." -ForegroundColor Yellow
    Write-Host "DPAPI scope=CurrentUser viaze sifrovanie na pouzivatela+stroj." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Detail: $($_.Exception.Message)" -ForegroundColor DarkGray
    exit 1
}

$loaded = 0
foreach ($line in $plaintext -split "`r?`n") {
    # Preskoc prazdne riadky a komentare
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

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
        Write-Warning "Preskakujem nevalidny riadok"
    }
}

# Plaintext premennu hned vynuluj (nech zbytocne netrci v pamati skriptu).
$plaintext = $null
$secure = $null
[System.GC]::Collect()

Write-Host "Nacitanych $loaded env premennych z .env.enc" -ForegroundColor Green

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
    Write-Warning "Doplnis ich do .env (./tools/env-edit.ps1). Volitelne (krok 5): BANK_PDF_PASSWORD, BANK_SENDER_WHITELIST"
}

# Spusti Claude Code (propaguje argumenty)
Write-Host "Spustam Claude Code v $PSScriptRoot ..." -ForegroundColor Cyan
& claude @ClaudeArgs
