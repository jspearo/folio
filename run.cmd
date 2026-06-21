@echo off
rem run.cmd - deleguje na run.ps1 (DPAPI desifrovanie .env.enc je v PowerShell).
rem
rem Pouzitie:
rem     cd folio
rem     run.cmd                spusti claude
rem     run.cmd --help         propaguje argumenty do claude
rem
rem Preco delegovat: DPAPI cez ciste cmd.exe by vyzadovalo extra binarku alebo
rem volat .NET cez powershell aj tak. Jeden zdroj pravdy = run.ps1.

setlocal

set "SCRIPT_DIR=%~dp0"

rem Najprv skus pwsh (PowerShell 7+), fallback na Windows PowerShell 5.1.
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
)

endlocal
exit /b %ERRORLEVEL%
