"""v2 deals: a correction (deal_id + action correct) keeps the deal number.

Runs only against a database with the v2 schema and migration 20261119140000_v2_deal_correct_in_place.
Everything runs in one transaction that is rolled back.
"""
import json
from pathlib import Path

import pytest

from tests.test_v2_deal_no_duplicates import DATABASE_URL, SRC, _j, db, psycopg  # noqa: F401  (db is a fixture)

pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _in_place(cur):
    d = cur.execute("select pg_get_functiondef('bots.v2_apply_deal_change(bigint)'::regprocedure)").fetchone()[0]
    if "'in_place',true" not in d:
        pytest.skip("correct-in-place migration not in this database")


def test_migration_and_rollback_files():
    mig = Path("supabase/migrations/20261119140000_v2_deal_correct_in_place.sql").read_text(encoding="utf-8")
    rb = Path("supabase/rollbacks/20261119140000_v2_deal_correct_in_place.sql").read_text(encoding="utf-8")
    assert "'in_place',true" in mig and "'replaces_deal_id'," not in mig
    assert "Replaced by deal" in rb and "replaces_deal_id" in rb


def _correct(db, deal_id, fact):
    item = {"firm_id": db.firm, "table": "v2_deals", "box": "F12",
            "fact": {**SRC, "deal_id": deal_id, "action": "correct", **fact}}
    key = db.cur.execute("select id from bots.ingest_keys order by created_at desc limit 1").fetchone()[0]
    r = _j(db.cur.execute("select public.v2_research_submit(%s, %s::jsonb, false)", (key, json.dumps([item]))).fetchone()[0])
    return r["results"][0]


def test_correction_keeps_deal_id_single_row_visible(db):
    _in_place(db.cur)
    s = db.startup("Ipronics")
    old = db.deal(db.firm, s, round="Series B", deal_date="2026-09-01", deal_date_precision="full date",
                  round_amount=125000000, amount_currency="USD")
    r = _correct(db, old, {"deal_date": "2026-09-02", "deal_date_precision": "full date", "lead": "yes"})
    assert r["status"] == "Accepted" and r["deal_id"] == old and "replaces_deal_id" not in r, r
    rows = db.cur.execute("select deal_id, archived, is_current, shown, deal_date, lead, source_url, round_amount "
                          "from public.v2_deals where startup_id = %s", (s,)).fetchall()
    assert len(rows) == 1  # no new row, nothing archived
    d = rows[0]
    assert d[0] == old and d[1] is False and d[2] is True and d[3] is True  # still on the site
    assert str(d[4]) == "2026-09-02" and d[5] == "yes" and d[6] == SRC["source_url"] and float(d[7]) == 125000000
    log = db.cur.execute("select old_value, new_value from public.v2_change_log where actor = 'v2_deal_change' and row_id = %s "
                         "order by 1 desc limit 1", (old,)).fetchone()
    assert log[0]["deal_date"] == "2026-09-01" and log[0]["source_url"] == "https://news.example/old"
    assert log[1]["in_place"] is True and log[1]["deal_id"] == old and log[1]["before"]["deal_date"] == "2026-09-01"


def test_pending_queued_correction_applies_in_place(db):
    _in_place(db.cur)
    s = db.startup("Queued")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    cur = db.cur
    row = cur.execute("select to_jsonb(d), submission_id from public.v2_deals d where deal_id = %s", (old,)).fetchone()
    qid = cur.execute("insert into public.v2_checker_queue(submission_id, firm_id, kind, table_name, row_id, old_value, new_value) "
                      "values (%s, %s, 'changed-key-fact', 'v2_deals', %s, %s, %s) returning queue_id",
                      (row[1], db.firm, old, json.dumps(row[0]),
                       json.dumps({"round_amount": 3000000, "amount_currency": "USD", "_deal_action": "correct"}))).fetchone()[0]
    receipt = cur.execute("select bots.v2_apply_deal_change(%s)", (qid,)).fetchone()[0]
    assert receipt["deal_id"] == old and receipt["in_place"] is True and receipt["before"]["round_amount"] is None
    assert cur.execute("select count(*), max(round_amount) from public.v2_deals where startup_id = %s", (s,)).fetchone() == (1, 3000000)
    # applying the same queue item again returns the stored receipt and changes nothing
    assert cur.execute("select bots.v2_apply_deal_change(%s)", (qid,)).fetchone()[0] == receipt
    # undo puts the old values back on the same deal_id
    assert cur.execute("select bots.v2_undo_deal_change(%s)", (qid,)).fetchone()[0] == "reverted"
    back = cur.execute("select deal_id, round_amount, archived from public.v2_deals where startup_id = %s", (s,)).fetchall()
    assert back == [(old, None, False)]


def test_old_copy_style_receipt_is_left_alone(db):
    _in_place(db.cur)
    s = db.startup("Legacy")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    sub = db.cur.execute("select submission_id from public.v2_deals where deal_id = %s", (old,)).fetchone()[0]
    legacy = {"action": "correct", "deal_id": 999999999, "active": False}
    qid = db.cur.execute("insert into public.v2_checker_queue(submission_id, firm_id, kind, table_name, row_id, old_value, new_value) "
                         "values (%s, %s, 'changed-key-fact', 'v2_deals', %s, '{}', %s) returning queue_id",
                         (sub, db.firm, old, json.dumps({"_deal_action": "correct", "_deal_receipt": legacy}))).fetchone()[0]
    assert db.cur.execute("select bots.v2_apply_deal_change(%s)", (qid,)).fetchone()[0] == legacy


def test_bad_correction_is_rejected_by_trial_run_and_changes_nothing(db):
    _in_place(db.cur)
    s = db.startup("Bad")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-01-01", deal_date_precision="full date",
                  round_amount=1000000, amount_currency="USD")
    r = _correct(db, old, {"firm_amount": 2000000})  # firm share bigger than the round breaks a table rule
    assert r["status"].startswith("Rejected:"), r
    assert db.cur.execute("select firm_amount from public.v2_deals where deal_id = %s", (old,)).fetchone()[0] is None


def test_remove_is_unchanged(db):
    _in_place(db.cur)
    s = db.startup("Remove")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-01-01", deal_date_precision="full date")
    r = _correct(db, old, {"action": "remove", "reason": "not this firm"})
    assert r["status"] == "Accepted" and r["deal_id"] == old, r
    assert db.cur.execute("select shown, archived from public.v2_deals where deal_id = %s", (old,)).fetchone() == (False, False)
