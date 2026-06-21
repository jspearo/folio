# tools/env-protect.ps1 - zasifruje .env -> .env.enc cez Windows DPAPI.
#
# Pouzitie:
#     ./tools/env-protect.ps1              # zasifruje folio/.env -> folio/.env.enc
#     ./tools/env-protect.ps1 -RemovePlain # po uspechu vymaze povodny .env
#
# Bezpecnostny model:
#     - DPAPI sifrovanie scope=CurrentUser.
#     - Desifrovat moze IBA Windows ucet ktory siframel, NA TOM ISTOM stroji.
#     - Iny user/iny stroj/po reinstalacii Windows = neda sa desifrovat.
#     - Preto NEcommitnut .env.enc do gitu - patri len na tento stroj.
#
# Stratil si .env.enc alebo Windows profil? Obnov z .env.example +
# manualne doplnis hesla (alebo z password managera).

[CmdletBinding()]
param(
    [string]$EnvFile,
    [string]$EncFile,
    [switch]$RemovePlain
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $EnvFile) { $EnvFile = Join-Path $projectRoot '.env' }
if (-not $EncFile) { $EncFile = Join-Path $projectRoot '.env.enc' }

if (-not (Test-Path $EnvFile)) {
    Write-Host "CHYBA: nenajdeny $EnvFile" -ForegroundColor Red
    Write-Host "Skopiruj .env.example -> .env, vyplnis a spustis tento skript znova." -ForegroundColor Yellow
    exit 1
}

# Precitaj cely .env ako jeden string (vratane komentarov a prazdnych riadkov).
$plaintext = Get-Content -Raw -Path $EnvFile

# DPAPI cez SecureString - ConvertFrom-SecureString bez -Key pouziva
# Windows Data Protection API so scope=CurrentUser (transparentne).
$secure = ConvertTo-SecureString -String $plaintext -AsPlainText -Force
$cipher = ConvertFrom-SecureString -SecureString $secure

Set-Content -Path $EncFile -Value $cipher -Encoding ASCII -NoNewline

Write-Host "OK: zasifrovane do $EncFile" -ForegroundColor Green
Write-Host "    (DPAPI CurrentUser - viazane na tento Windows ucet a stroj)" -ForegroundColor DarkGray

if ($RemovePlain) {
    Remove-Item -Path $EnvFile -Force
    Write-Host "OK: zmazany povodny $EnvFile" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Dalsi krok: zmaz povodny plaintext .env:" -ForegroundColor Yellow
    Write-Host "    Remove-Item '$EnvFile'" -ForegroundColor Yellow
    Write-Host "alebo spusti znova s -RemovePlain." -ForegroundColor Yellow
}
