#!/usr/bin/env bash
# run.sh - na tomto projekte uz NIE je podporeny ako primarny entry point.
#
# Secrety su sifrovane Windows DPAPI (CurrentUser scope), co je Windows-only.
# DPAPI klúč nie je dostupny v Linux/WSL/Git Bash, takze .env.enc sa neda
# desifrovat mimo natívneho Windows PowerShell session.
#
# Pouzi namiesto toho:
#     pwsh ./run.ps1            (PowerShell 7+)
#     powershell ./run.ps1      (Windows PowerShell 5.1)
#     ./run.cmd                 (cmd.exe wrapper okolo run.ps1)
#
# Ak potrebujes spustenie aj na Linux/WSL, treba prejst na cross-platform
# secret store (napr. sops+age alebo PowerShell SecretManagement).

set -e

cat >&2 <<'EOF'
CHYBA: run.sh uz nie je podporeny - secrety su sifrovane Windows DPAPI.

DPAPI funguje IBA v natívnom Windows PowerShell session pod tym istym
Windows uctom ktory subor zasifroval. WSL, Git Bash a Linux nemaju
pristup k DPAPI klúču.

Pouzi:
    pwsh ./run.ps1
    powershell ./run.ps1
    ./run.cmd
EOF

exit 1
