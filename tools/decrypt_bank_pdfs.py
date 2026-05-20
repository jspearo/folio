#!/usr/bin/env python3
"""
Decrypt password-protected bank statement PDFs using qpdf.

Usage:
    python tools/decrypt_bank_pdfs.py \\
        --in vystup/2026-04/_bank/raw/ \\
        --out vystup/2026-04/_bank/

Env required:
    BANK_PDF_PASSWORD                 default password

Env optional (per-bank override):
    BANK_PDF_PASSWORD_TATRA           when --bank tatra
    BANK_PDF_PASSWORD_VUB             when --bank vub
    ... etc.

Requires:
    qpdf binary in PATH (https://qpdf.sourceforge.io/)
    Windows: choco install qpdf  /  scoop install qpdf
    Linux:   apt install qpdf  /  dnf install qpdf
    macOS:   brew install qpdf

Security:
    - Password is passed to qpdf via --password=<pw> argument. On Linux this
      is briefly visible in /proc/<pid>/cmdline to the same user only.
    - This script NEVER prints the password to stdout/stderr.
    - On error, qpdf stderr is filtered to mask any echo of the password.
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--in", dest="indir", required=True, help="Input dir with encrypted PDFs")
    ap.add_argument("--out", required=True, help="Output dir for decrypted PDFs")
    ap.add_argument("--bank", default="",
                    help="Bank name suffix for password env var (e.g. tatra, vub)")
    args = ap.parse_args()

    pw_env = f"BANK_PDF_PASSWORD_{args.bank.upper()}" if args.bank else "BANK_PDF_PASSWORD"
    try:
        password = os.environ[pw_env]
    except KeyError:
        print(f"ERROR: missing env var {pw_env}", file=sys.stderr)
        return 2

    qpdf = shutil.which("qpdf") or shutil.which("qpdf.exe")
    if not qpdf:
        print("ERROR: qpdf binary not found in PATH. "
              "Install: https://qpdf.sourceforge.io/", file=sys.stderr)
        return 3

    in_dir = Path(args.indir)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(in_dir.glob("*.pdf"))
    if not pdfs:
        print(f"No PDFs in {in_dir}", file=sys.stderr)
        return 0

    print(f"Decrypting {len(pdfs)} PDF(s) using password from {pw_env}",
          file=sys.stderr)

    failed = []
    skipped = 0
    decrypted = 0
    for pdf in pdfs:
        out_path = out_dir / pdf.name
        if out_path.exists() and out_path.stat().st_size > 0:
            print(f"  SKIP: {pdf.name} (already decrypted)", file=sys.stderr)
            skipped += 1
            continue
        # NEVER print this command — it contains the password.
        cmd = [qpdf, f"--password={password}", "--decrypt",
               str(pdf), str(out_path)]
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            failed.append((pdf.name, "timeout (>60s)"))
            continue
        except FileNotFoundError as e:
            print(f"ERROR: cannot execute qpdf: {e}", file=sys.stderr)
            return 4

        # qpdf exit codes:
        #   0 = success
        #   2 = error
        #   3 = warnings (output usually still produced)
        if r.returncode == 0:
            print(f"  OK:   {pdf.name}", file=sys.stderr)
            decrypted += 1
        elif r.returncode == 3:
            print(f"  WARN: {pdf.name} (qpdf warnings, output saved)",
                  file=sys.stderr)
            decrypted += 1
        else:
            # Mask password if it appears in error message
            err = (r.stderr or "").strip()
            if password and password in err:
                err = err.replace(password, "***")
            failed.append((pdf.name, err[:200]))
            if out_path.exists():
                try:
                    out_path.unlink()
                except OSError:
                    pass

    print(f"\nDecrypted: {decrypted}, skipped: {skipped}, failed: {len(failed)}",
          file=sys.stderr)
    if failed:
        print("Failed files:", file=sys.stderr)
        for name, err in failed:
            print(f"  - {name}: {err}", file=sys.stderr)
        return 5
    return 0


if __name__ == "__main__":
    sys.exit(main())
