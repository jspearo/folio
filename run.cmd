@echo off
rem run.cmd — nacita folio\.env do env premennych a spusti Claude Code.
rem
rem Pouzitie:
rem     cd folio
rem     run.cmd                spusti claude
rem     run.cmd --help         propaguje argumenty do claude
rem
rem Format .env:
rem     KEY=value
rem     # komentar             (preskoci sa)
rem     prazdny riadok         (preskoci sa)
rem
rem Bezpecnost:
rem     - env premenne su nastavene IBA pre tento cmd session
rem       (setlocal scope — po skonceni scriptu sa env vrati)
rem     - hodnoty z .env sa nevypisuju do stdout

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "ENV_FILE=%SCRIPT_DIR%.env"

if not exist "%ENV_FILE%" (
    echo CHYBA: chyba subor .env v %SCRIPT_DIR%
    echo Skopiruj .env.example -^> .env a vyplnis svoje credentials.
    exit /b 1
)

set /a LOADED=0
for /f "usebackq tokens=* delims=" %%a in ("%ENV_FILE%") do (
    set "line=%%a"
    if defined line (
        rem preskoc komentare (riadky zacinajuce #)
        if not "!line:~0,1!"=="#" (
            rem rozdel KEY=value (value moze obsahovat dalsie =)
            for /f "tokens=1,* delims==" %%x in ("!line!") do (
                set "%%x=%%y"
                set /a LOADED+=1
            )
        )
    )
)

echo Nacitanych %LOADED% env premennych z .env

rem Smoke-check povinnych premennych (bez vypisu hodnot!)
set "MISSING="
for %%V in (IMAP_HOST IMAP_USERNAME IMAP_PASSWORD SMTP_HOST SMTP_USERNAME SMTP_PASSWORD NC_BASE_URL NC_USERNAME NC_APP_PASSWORD ACCOUNTANT_DROP UCTOVNIK_EMAIL ACC_ZIP_PASSWORD) do (
    if not defined %%V set "MISSING=!MISSING! %%V"
)

if defined MISSING (
    echo WARN: chybaju povinne env premenne:!MISSING!
    echo Volitelne ^(krok 5 bank-reconciler^): BANK_PDF_PASSWORD, BANK_SENDER_WHITELIST
)

echo Spustam Claude Code v %SCRIPT_DIR% ...
claude %*

endlocal
