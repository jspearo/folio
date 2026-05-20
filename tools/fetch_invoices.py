#!/usr/bin/env python3
"""
Fetch invoice attachments from IMAP mailbox for a given month.

Usage:
    python tools/fetch_invoices.py --month 2026-04 --out vystup/2026-04/

Env required:
    IMAP_HOST              e.g. imap.gmail.com
    IMAP_PORT              default 993
    IMAP_USERNAME
    IMAP_PASSWORD          app-specific password recommended

Read-only by design:
    - opens mailbox with readonly=True
    - uses BODY.PEEK[] (does NOT set \\Seen)
    - never deletes, moves, or labels messages
"""
import argparse
import email
import imaplib
import json
import os
import re
import sys
from datetime import date
from email.header import decode_header
from pathlib import Path

SUBJECT_KEYWORDS = [
    "fakt",          # faktura / faktúra
    "invoice",
    "danovy doklad",
    "daňový doklad",
    "vyuctovanie",
    "vyúčtovanie",
    "účet",
]
ALLOWED_EXT = {".pdf", ".jpg", ".jpeg", ".png", ".heic"}
MIN_ATTACHMENT_SIZE = 5 * 1024  # 5 KB — under this is likely a signature/logo
IGNORE_NAMES_RE = re.compile(
    r"^image\d+\.(png|jpg|jpeg|gif)$|signature|logo|banner", re.I
)

# Force English month abbreviations regardless of system locale (IMAP requires English)
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


def month_range(yyyy_mm):
    """Search window for invoices.

    Invoices for an accounting month often arrive late — vendors typically
    issue them in the first half of the following month. Window goes from
    1st of target month to 15th of the next month (inclusive of the 14th).
    IMAP BEFORE is exclusive, so we pass day 15.
    """
    y, m = map(int, yyyy_mm.split("-"))
    first = date(y, m, 1)
    if m == 12:
        last = date(y + 1, 1, 15)
    else:
        last = date(y, m + 1, 15)
    return imap_date(first), imap_date(last)


def matches_invoice(subject):
    s = (subject or "").lower()
    return any(k in s for k in SUBJECT_KEYWORDS)


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
    ap.add_argument("--folder", default="INBOX",
                    help="IMAP folder (default INBOX)")
    args = ap.parse_args()

    try:
        host = os.environ["IMAP_HOST"]
        user = os.environ["IMAP_USERNAME"]
        pw = os.environ["IMAP_PASSWORD"]
    except KeyError as e:
        print(f"ERROR: missing env var {e}", file=sys.stderr)
        return 2
    port = int(os.environ.get("IMAP_PORT", "993"))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    log_path = out / "_email-collector.log.json"
    seen_ids = set()
    log = []
    if log_path.exists():
        try:
            log = json.loads(log_path.read_text(encoding="utf-8"))
            seen_ids = {e["message_id"] for e in log}
        except (json.JSONDecodeError, KeyError):
            log = []

    since, before = month_range(args.month)

    M = imaplib.IMAP4_SSL(host, port)
    try:
        M.login(user, pw)
    except imaplib.IMAP4.error as e:
        print(f"ERROR: IMAP login failed: {e}", file=sys.stderr)
        return 3

    try:
        status, _ = M.select(args.folder, readonly=True)
        if status != "OK":
            print(f"ERROR: cannot select folder {args.folder}", file=sys.stderr)
            return 4

        # Filter by date only on server side. Subject filter in Python because
        # IMAP SEARCH with UTF-8 / Slovak diacritics is server-dependent.
        status, data = M.search(None, f"(SINCE {since} BEFORE {before})")
        if status != "OK":
            print(f"ERROR: IMAP search failed", file=sys.stderr)
            return 5

        msg_nums = data[0].split()
        print(f"Found {len(msg_nums)} messages in {args.month} "
              f"({args.folder})", file=sys.stderr)

        saved_count = 0
        considered_count = 0
        for num in msg_nums:
            status, msg_data = M.fetch(num, "(BODY.PEEK[])")
            if status != "OK" or not msg_data or not msg_data[0]:
                continue
            msg = email.message_from_bytes(msg_data[0][1])
            mid = (msg.get("Message-ID") or "").strip()
            if not mid or mid in seen_ids:
                continue
            subject = decode_field(msg.get("Subject", ""))
            if not matches_invoice(subject):
                continue
            considered_count += 1
            sender = decode_field(msg.get("From", ""))
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
                if IGNORE_NAMES_RE.search(fn):
                    continue
                payload = part.get_payload(decode=True)
                if payload is None or len(payload) < MIN_ATTACHMENT_SIZE:
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

        log_path.write_text(
            json.dumps(log, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print(f"Considered {considered_count} invoice-like messages, "
              f"saved {saved_count} new attachments to {out}", file=sys.stderr)
        return 0
    finally:
        try:
            M.close()
        except Exception:
            pass
        M.logout()


if __name__ == "__main__":
    sys.exit(main())
