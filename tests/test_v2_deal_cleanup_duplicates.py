"""v2 deals: one-time duplicate cleanup keeps the oldest deal number, fills empty fields, archives copies, undoes exactly.

Runs only against a database with the v2 schema and migration 20261119150000_v2_deal_cleanup_duplicates.
Everything runs in one transaction that is rolled back.
"""
from pathlib import Path

import pytest

from tests.test_v2_deal_no_duplicates import DATABASE_URL, db  # noqa: F401  (db is a fixture)

pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _have(cur):
    if cur.execute("select to_regprocedure('public.v2_deal_cleanup_duplicates(boolean,int)')").fetchone()[0] is None:
        pytest.skip("cleanup migration not in this database")


def test_files():
    assert "v2_deal_cleanup_undo(null)" in Path("supabase/rollbacks/20261119150000_v2_deal_cleanup_duplicates.sql").read_text()
    assert "changes no rows" in Path("supabase/migrations/20261119150000_v2_deal_cleanup_duplicates.sql").read_text()


def _snap(cur, s):
    return cur.execute("select jsonb_agg(to_jsonb(d) order by deal_id) from public.v2_deals d where startup_id = any(%s)", (s,)).fetchone()[0]


def test_dry_run_apply_and_undo(db):
    _have(db.cur)
    cur = db.cur
    a, b, c = db.startup("CleanA"), db.startup("CleanB"), db.startup("CleanC")
    # A: three Seeds; 2 and 3 copy 1 (1 has no amount, copy 2 fills it); a far-apart Seed stays separate
    a1 = db.deal(db.firm, a, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    a2 = db.deal(db.firm, a, round="Seed", deal_date="2026-01-03", deal_date_precision="full date",
                 round_amount=4000000, amount_currency="USD", lead="yes")
    a3 = db.deal(db.merged, a, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    a4 = db.deal(db.firm, a, round="Seed", deal_date="2021-01-01", deal_date_precision="full date")
    # B: Seed and Series A, different stages: untouched
    db.deal(db.firm, b, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    db.deal(db.firm, b, round="Series A", deal_date="2026-01-01", deal_date_precision="full date")
    # C: a duplicate pair where one was removed: skipped
    c1 = db.deal(db.firm, c, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    db.deal(db.firm, c, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    sub = cur.execute("select submission_id from public.v2_deals where deal_id = %s", (c1,)).fetchone()[0]
    cur.execute("insert into public.v2_checker_queue(submission_id, firm_id, kind, table_name, row_id, old_value, new_value) "
                "values (%s, %s, 'changed-key-fact', 'v2_deals', %s, '{}', '{\"_deal_action\":\"remove\",\"_deal_receipt\":{\"active\":true}}')",
                (sub, db.firm, c1))
    before = _snap(cur, [a, b, c])

    dry = cur.execute("select public.v2_deal_cleanup_duplicates(false, 1000)").fetchone()[0]
    assert _snap(cur, [a, b, c]) == before  # dry run changes nothing
    mine = [g for g in dry["sample"] if g["startup_id"] in (a, b, c)]
    assert len(mine) == 1 and mine[0]["startup_id"] == a
    assert sorted((x["keep"], x["archive"]) for x in mine[0]["keep_and_archive"]) == [(a1, a2), (a1, a3)]

    run = cur.execute("select public.v2_deal_cleanup_duplicates(true)").fetchone()[0]["run_id"]
    rows = {r[0]: r[1:] for r in cur.execute(
        "select deal_id, archived, archive_reason, round_amount, lead, deal_date from public.v2_deals where startup_id = %s", (a,)).fetchall()}
    assert rows[a1][0] is False and float(rows[a1][2]) == 4000000 and rows[a1][3] == "yes" and str(rows[a1][4]) == "2026-01-01"
    assert rows[a2][:2] == (True, f"Duplicate of deal {a1}") and rows[a3][:2] == (True, f"Duplicate of deal {a1}")
    assert rows[a4][0] is False  # five years apart: a different Seed
    assert cur.execute("select count(*) from public.v2_deal_fill_sources where deal_id = %s", (a1,)).fetchone()[0] == 1
    again = cur.execute("select public.v2_deal_cleanup_duplicates(false, 1000)").fetchone()[0]
    assert not [g for g in again["sample"] if g["startup_id"] == a]  # nothing left to merge

    cur.execute("select public.v2_deal_cleanup_undo(%s)", (run,))
    assert _snap(cur, [a, b, c]) == before  # undo restores exactly
    assert cur.execute("select count(*) from public.v2_deal_fill_sources where deal_id = %s", (a1,)).fetchone()[0] == 0
