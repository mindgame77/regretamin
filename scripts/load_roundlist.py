#!/usr/bin/env python3
"""Load the 2026 rounds sheet (xlsx or csv) into the separate round list (schema roundlist).

    python3 scripts/load_roundlist.py FILE.xlsx [--sheet 26]            # dry run: counts only, writes nothing
    ROUNDLIST_DATABASE_URL=postgresql://... python3 scripts/load_roundlist.py FILE.xlsx --apply

Columns (header row, any order): startup_name, startup_website, country, round, round_date, source_url,
added_by, added_at, status, taken_by, taken_at, notes. Each row keeps its status, taken_by, taken_at and notes.
- A copy (same startup website, or name when there is no website, + round + round_date) is refused, both
  inside the file and against rows already in the list. Re-running the loader adds only new rows.
- Rows without startup_name, round or a valid round_date are skipped and listed.
- A "taken" row with no taken_by goes in as open. A "taken" row with no taken_at gets the load time, so it
  goes back to open 2 hours later like any hold.
- Unknown status values go in as open.
The dry run checks copies against the database too when ROUNDLIST_DATABASE_URL is set (read only).
Writes only to roundlist.rounds and roundlist.events, in one transaction.
"""
import argparse
import csv
import datetime as dt
import json
import pathlib
import re
import sys

COLS = ("startup_name", "startup_website", "country", "round", "round_date", "source_url",
        "added_by", "added_at", "status", "taken_by", "taken_at", "notes")
STATUSES = ("open", "taken", "done", "rejected")


def norm_site(s):
    d = (s or "").strip().lower()
    d = re.sub(r"^[a-z][a-z0-9+.-]*://", "", d)
    d = re.sub(r"^www\.", "", d)
    d = re.sub(r"[/?#].*$", "", d)
    d = re.sub(r":[0-9]+$", "", d)
    return d if re.fullmatch(r"[a-z0-9-]+(\.[a-z0-9-]+)+", d) else None


def norm_text(s):
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


def copy_key(r):
    site = norm_site(r["startup_website"])
    return ("site:" + site if site else "name:" + norm_text(r["startup_name"]), norm_text(r["round"]), r["round_date"])


def cell(v):
    if v is None:
        return None
    if isinstance(v, (dt.datetime, dt.date)):
        return v
    s = str(v).strip()
    return s or None


def read_rows(path, sheet):
    p = pathlib.Path(path)
    if p.suffix.lower() == ".csv":
        with p.open(newline="", encoding="utf-8-sig") as f:
            rows = list(csv.reader(f))
    else:
        import openpyxl
        wb = openpyxl.load_workbook(p, read_only=True, data_only=True)
        if sheet not in wb.sheetnames:
            sys.exit(f"sheet {sheet!r} not found; sheets: {wb.sheetnames}")
        rows = [list(r) for r in wb[sheet].iter_rows(values_only=True)]
    if not rows:
        sys.exit("the file is empty")
    head = [str(h).strip().lower() if h is not None else "" for h in rows[0]]
    missing = [c for c in ("startup_name", "round", "round_date") if c not in head]
    if missing:
        sys.exit(f"header is missing {missing}; header is {head}")
    out = []
    for n, r in enumerate(rows[1:], start=2):
        if all(cell(v) is None for v in r):
            continue
        out.append((n, {c: cell(r[head.index(c)]) if c in head and head.index(c) < len(r) else None for c in COLS}))
    return out


def to_date(v):
    if isinstance(v, dt.datetime):
        return v.date()
    if isinstance(v, dt.date):
        return v
    if isinstance(v, str):
        m = re.match(r"^(\d{4}-\d{2}-\d{2})", v)
        if m:
            try:
                return dt.date.fromisoformat(m.group(1))
            except ValueError:
                return None
    return None


def to_ts(v):
    if isinstance(v, dt.datetime):
        return v if v.tzinfo else v.replace(tzinfo=dt.timezone.utc)
    if isinstance(v, dt.date):
        return dt.datetime(v.year, v.month, v.day, tzinfo=dt.timezone.utc)
    if isinstance(v, str):
        try:
            t = dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
            return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)
        except ValueError:
            return None
    return None


def prepare(rows, now):
    keep, skipped, copies, fixes = [], [], [], []
    seen = {}
    for n, r in rows:
        r = dict(r)
        for c in ("startup_name", "startup_website", "country", "round", "source_url", "added_by", "status", "taken_by", "notes"):
            if r[c] is not None and not isinstance(r[c], str):
                r[c] = str(r[c])
        r["round_date"] = to_date(r["round_date"])
        if not r["startup_name"] or not r["round"] or not norm_text(r["round"]) or r["round_date"] is None:
            skipped.append({"row": n, "why": "needs startup_name, round and round_date", "startup_name": r["startup_name"]})
            continue
        if r["startup_website"] and not norm_site(r["startup_website"]):
            fixes.append({"row": n, "fix": "website is not a domain; copy check uses the name", "website": r["startup_website"]})
        st = (r["status"] or "open").strip().lower()
        if st not in STATUSES:
            fixes.append({"row": n, "fix": f"status {r['status']!r} loaded as open"})
            st = "open"
        r["status"] = st
        r["added_by"] = r["added_by"] or "sheet-import"
        r["added_at"] = to_ts(r["added_at"]) or now
        r["taken_at"] = to_ts(r["taken_at"])
        if st == "taken" and not r["taken_by"]:
            fixes.append({"row": n, "fix": "taken without taken_by, loaded as open"})
            r["status"], r["taken_at"] = "open", None
        elif st == "taken" and r["taken_at"] is None:
            fixes.append({"row": n, "fix": "taken without taken_at, taken_at = load time (released 2 hours later)"})
            r["taken_at"] = now
        if r["status"] == "open":
            r["taken_by"], r["taken_at"] = None, None
        if r["notes"] and len(r["notes"]) > 4000:
            r["notes"] = r["notes"][:4000]
            fixes.append({"row": n, "fix": "notes cut to 4000 characters"})
        k = copy_key(r)
        if k in seen:
            copies.append({"row": n, "copy_of_row": seen[k], "startup_name": r["startup_name"], "round": r["round"],
                           "round_date": str(r["round_date"]), "where": "file"})
            continue
        seen[k] = n
        keep.append((n, r))
    return keep, skipped, copies, fixes


INSERT = """
insert into roundlist.rounds (startup_name, startup_website, country, round, round_date, source_url,
                              added_by, added_at, status, taken_by, taken_at, notes)
values (%(startup_name)s, %(startup_website)s, %(country)s, %(round)s, %(round_date)s, %(source_url)s,
        %(added_by)s, %(added_at)s, %(status)s, %(taken_by)s, %(taken_at)s, %(notes)s)
on conflict on constraint rounds_no_copies do nothing
returning round_id
"""


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", help="xlsx or csv export of the sheet")
    ap.add_argument("--sheet", default="26", help="tab with the rounds (xlsx only, default 26)")
    ap.add_argument("--apply", action="store_true", help="write to the database (default is a dry run)")
    ap.add_argument("--database-url", default=None, help="default: env ROUNDLIST_DATABASE_URL")
    ap.add_argument("--report", default=None, help="also write the full report as JSON to this path")
    a = ap.parse_args(argv)
    import os
    url = (a.database_url or os.environ.get("ROUNDLIST_DATABASE_URL", "")).strip()
    if a.apply and not url:
        sys.exit("--apply needs ROUNDLIST_DATABASE_URL (or --database-url)")

    now = dt.datetime.now(dt.timezone.utc)
    rows = read_rows(a.file, a.sheet)
    keep, skipped, copies, fixes = prepare(rows, now)
    by_status = {s: sum(1 for _, r in keep if r["status"] == s) for s in STATUSES}
    report = {"file": str(a.file), "rows_in_file": len(rows), "to_load": len(keep), "to_load_by_status": by_status,
              "skipped": skipped, "refused_copies": copies, "fixes": fixes, "applied": False}

    if url:
        import psycopg
        with psycopg.connect(url) as c:
            if c.execute("select to_regclass('roundlist.rounds')").fetchone()[0] is None:
                sys.exit("roundlist.rounds does not exist; apply supabase/migrations/20261119170000_roundlist.sql first")
            inserted, already = 0, []
            with c.transaction() as tx:
                for n, r in keep:
                    got = c.execute(INSERT, r).fetchone()
                    if got:
                        inserted += 1
                    else:
                        already.append({"row": n, "startup_name": r["startup_name"], "round": r["round"],
                                        "round_date": str(r["round_date"]), "where": "already in the list"})
                if a.apply:
                    c.execute("insert into roundlist.events (bot, action, detail) values ('sheet-import', 'loaded', %s)",
                              (json.dumps({"file": pathlib.Path(a.file).name, "inserted": inserted,
                                           "refused_copies": len(copies) + len(already)}),))
                else:
                    raise_rollback(tx)
            report["inserted" if a.apply else "would_insert"] = inserted
            report["refused_copies"] += already
            report["applied"] = a.apply
            report["list_by_status"] = dict(c.execute(
                "select status, count(*) from roundlist.rounds group by 1 order by 1").fetchall())

    if a.report:
        pathlib.Path(a.report).write_text(json.dumps(report, indent=2, default=str))
    print(f"rows in file: {report['rows_in_file']}")
    print(f"to load: {report['to_load']}  by status: {by_status}")
    if "inserted" in report:
        print(f"inserted: {report['inserted']}")
    if "would_insert" in report:
        print(f"would insert (dry run, rolled back): {report['would_insert']}")
    print(f"refused copies: {len(report['refused_copies'])}")
    for x in report["refused_copies"]:
        print(f"  row {x['row']}: {x['startup_name']} | {x['round']} | {x['round_date']} ({x['where']}"
              + (f", copy of row {x['copy_of_row']}" if 'copy_of_row' in x else "") + ")")
    print(f"skipped: {len(skipped)}")
    for x in skipped:
        print(f"  row {x['row']}: {x['why']} ({x['startup_name']})")
    print(f"fixes: {len(fixes)}")
    for x in fixes:
        print(f"  row {x['row']}: {x['fix']}")
    if "list_by_status" in report:
        print(f"list now by status{'' if a.apply else ' (unchanged, dry run)'}: {report['list_by_status']}")
    if not a.apply:
        print("dry run: nothing written. Add --apply to load.")
    return report


def raise_rollback(tx):
    import psycopg
    raise psycopg.Rollback(tx)


if __name__ == "__main__":
    main()
