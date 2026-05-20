#!/usr/bin/env python3
"""
Fetch bank statement PDFs from IMAP for a given month.

Bank statements often arrive on the 1st-10th of the FOLLOWING month, so the
date window is widened beyond a single calendar month.

Usage:
    python tools/fetch_bank_statements.py --month 2026-04 --out vystup/2026-04/_bank/raw/

Env required:
    IMAP_HOST, IMAP_PORT (default 993), IMAP_USERNAME, IMAP_PASSWORD

Env optional:
    BANK_SENDER_WHITELIST   Comma-separated email addresses to accept,
                            e.g. "noreply@tatrabanka.sk,statements@vub.sk".
                            If empty, all senders matching the subject filter.

Read-only IMAP: never sets \\Seen, never deletes.
"""
import argparse
import email
import imaplib
import json
import os
import sys
from datetime import date
from email.header import decode_header
from pathlib import Path

SUBJECT_KEYWORDS = [
    "vypis",
    "výpis",
    "statement",
    "vyuctovanie uctu",
    "vyúčtovanie účtu",
    "monthly statement",
    "kontoauszug",  # nemecký, ak by ste mali nemecký bank
]
ALLOWED_EXT = {".pdf"}
MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def imap_date(d):
    return f"{d.day:02d}-{MONTHS_EN[d.month - 1]}-{d.year}"


def decode_field(s):
    if not s:
        return ""
    parts = decode_header(s)
    out = []
    for p, enc in parts:
        if isinstance(p, bytes):
            try:
                out.append(p.decode(enc or "utf-8", errors="replace"))
            except LookupError:
                out.append(p.decode("utf-8", errors="replace"))
        else:
            out.append(p)
    return "".join(out)


def month_range_extended(yyyy_mm):
    """Bank statements typically arrive within ~15 days after month end."""
    y, m = map(int, yyyy_mm.split("-"))
    first = date(y, m, 1)
    # Window: 1st of target month → 15th of month-after-next, to catch
    # statements that arrive late or were named for the prior period.
    if m >= 11:
        last = date(y + 1, m - 10, 15)
    else:
        last = date(y, m + 2, 15)
    return imap_date(first), imap_date(last)


def matches_statement(subject):
    s = (subject or "").lower()
    return any(k in s for k in SUBJECT_KEYWORDS)


def matches_sender(sender, whitelist):
    if not whitelist:
        return True
    s = (sender or "").lower()
    return any(w.strip().lower() in s for w in whitelist.split(",") if w.strip())


def safe_filename(name, existing):
    base, ext = os.path.splitext(name)
    candidate = name
    n = 2
    while candidate in existing:
        candidate = f"{base}({n}){ext}"
        n += 1
    return candidate


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--month", required=True, help="YYYY-MM")
    ap.add_argument("--out", required=True, help="Output directory")
    ap.add_argument("--folder", default="INBOX")
    args = ap.parse_args()

    try:
        host = os.environ["IMAP_HOST"]
        user = os.environ["IMAP_USERNAME"]
        pw = os.environ["IMAP_PASSWORD"]
    except KeyError as e:
        print(f"ERROR: missing env var {e}", file=sys.stderr)
        return 2
    port = int(os.environ.get("IMAP_PORT", "993"))
    sender_wl = os.environ.get("BANK_SENDER_WHITELIST", "")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    log_path = out / "_bank-fetch.log.json"
    seen_ids = set()
    log = []
    if log_path.exists():
        try:
            log = json.loads(log_path.read_text(encoding="utf-8"))
            seen_ids = {e["message_id"] for e in log}
        except (json.JSONDecodeError, KeyError):
            log = []

    since, before = month_range_extended(args.month)
    print(f"IMAP date window: {since} → {before}", file=sys.stderr)

    M = imaplib.IMAP4_SSL(host, port)
    try:
        M.login(user, pw)
    except imaplib.IMAP4.error as e:
        print(f"ERROR: IMAP login failed: {e}", file=sys.stderr)
        return 3

    try:
        status, _ = M.select(args.folder, readonly=True)
        if status != "OK":
            print(f"ERROR: cannot select {args.folder}", file=sys.stderr)
            return 4
        status, data = M.search(None, f"(SINCE {since} BEFORE {before})")
        if status != "OK":
            print("ERROR: IMAP search failed", file=sys.stderr)
            return 5

        msg_nums = data[0].split()
        print(f"Found {len(msg_nums)} messages in window, "
              f"filtering for bank statements...", file=sys.stderr)

        saved_count = 0
        considered = 0
        for num in msg_nums:
            status, msg_data = M.fetch(num, "(BODY.PEEK[])")
            if status != "OK" or not msg_data or not msg_data[0]:
                continue
            msg = email.message_from_bytes(msg_data[0][1])
            mid = (msg.get("Message-ID") or "").strip()
            if not mid or mid in seen_ids:
                continue
            subject = decode_field(msg.get("Subject", ""))
            if not matches_statement(subject):
                continue
            sender = decode_field(msg.get("From", ""))
            if not matches_sender(sender, sender_wl):
                continue
            considered += 1
            received = decode_field(msg.get("Date", ""))
            existing = {p.name for p in out.iterdir() if p.is_file()}
            attachments_saved = []
            for part in msg.walk():
                if part.get_content_maintype() == "multipart":
                    continue
                fn = part.get_filename()
                if not fn:
                    continue
                fn = decode_field(fn)
                ext = os.path.splitext(fn)[1].lower()
                if ext not in ALLOWED_EXT:
                    continue
                payload = part.get_payload(decode=True)
                if payload is None:
                    continue
                safe = safe_filename(fn, existing)
                (out / safe).write_bytes(payload)
                existing.add(safe)
                attachments_saved.append(safe)
            if attachments_saved:
                log.append({
                    "message_id": mid,
                    "from": sender,
                    "subject": subject,
                    "received_at": received,
                    "attachments_saved": attachments_saved,
                })
                seen_ids.add(mid)
                saved_count += len(attachments_saved)

        log_path.write_text(json.dumps(log, ensure_ascii=False, indent=2),
                             encoding="utf-8")
        print(f"Considered {considered} bank-like messages, "
              f"saved {saved_count} new PDFs to {out}", file=sys.stderr)
        return 0
    finally:
        try:
            M.close()
        except Exception:
            pass
        M.logout()


if __name__ == "__main__":
    sys.exit(main())
