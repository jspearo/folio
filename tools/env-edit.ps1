# tools/env-edit.ps1 - bezpecne editovanie sifrovaneho .env.enc.
#
# Postup:
#     1. Desifruje .env.enc do docasneho suboru v %TEMP% (NTFS ACL na CurrentUser).
#     2. Otvori ho v editore (default: notepad, alebo $env:EDITOR).
#     3. Pocka az editor skonci.
#     4. Presifruje upraveny obsah do .env.enc.
#     5. Bezpecne vymaze docasny plaintext (overwrite + delete).
#
# Pouzitie:
#     ./tools/env-edit.ps1
#     ./tools/env-edit.ps1 -Editor 'code --wait'    # VS Code (musi byt --wait)
#     ./tools/env-edit.ps1 -Editor notepad

[CmdletBinding()]
param(
    [string]$EncFile,
    [string]$Editor
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $EncFile) { $EncFile = Join-Path $projectRoot '.env.enc' }
if (-not $Editor) {
    if ($env:EDITOR) { $Editor = $env:EDITOR } else { $Editor = 'notepad' }
}

if (-not (Test-Path $EncFile)) {
    Write-Host "CHYBA: nenajdeny $EncFile" -ForegroundColor Red
    Write-Host "Najprv vytvor sifrovany subor: ./tools/env-protect.ps1" -ForegroundColor Yellow
    exit 1
}

# Desifruj do docasneho suboru v user-scope TEMP (nie projekt, nie shared).
$tempDir = $env:TEMP
$tempFile = Join-Path $tempDir ("folio-env-edit-" + [Guid]::NewGuid().ToString('N') + ".tmp")

try {
    $cipher = Get-Content -Raw -Path $EncFile
    $secure = ConvertTo-SecureString -String $cipher  # DPAPI CurrentUser
    $plaintext = [System.Net.NetworkCredential]::new('', $secure).Password

    Set-Content -Path $tempFile -Value $plaintext -Encoding UTF8 -NoNewline

    Write-Host "Otvaram $tempFile v editore: $Editor" -ForegroundColor Cyan
    Write-Host "(Po ulozeni a zatvoreni editora sa subor presifruje a zmaze.)" -ForegroundColor DarkGray

    # Start-Process s -Wait blokuje az editor skonci.
    # Editor musi byt nakonfigurovany aby cakal na zatvorenie (napr. 'code --wait').
    $parts = $Editor.Split(' ', 2)
    $exe = $parts[0]
    $extraArgs = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    $allArgs = if ($extraArgs) { "$extraArgs `"$tempFile`"" } else { "`"$tempFile`"" }
    Start-Process -FilePath $exe -ArgumentList $allArgs -Wait -NoNewWindow

    # Precitaj upraveny obsah a presifruj.
    $updated = Get-Content -Raw -Path $tempFile
    $newSecure = ConvertTo-SecureString -String $updated -AsPlainText -Force
    $newCipher = ConvertFrom-SecureString -SecureString $newSecure
    Set-Content -Path $EncFile -Value $newCipher -Encoding ASCII -NoNewline

    Write-Host "OK: zmeny presifrovane do $EncFile" -ForegroundColor Green
}
finally {
    # Best-effort safe delete: prepiseme nulami a vymazeme.
    if (Test-Path $tempFile) {
        try {
            $size = (Get-Item $tempFile).Length
            if ($size -gt 0) {
                $zeros = New-Object byte[] $size
                [System.IO.File]::WriteAllBytes($tempFile, $zeros)
            }
        } catch {
            # ignoruj - aj tak budeme mazat
        }
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}
