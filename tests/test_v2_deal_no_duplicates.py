"""v2 deals: a new deal never makes a second live row for the same firm + startup + round.

Runs only against a database that has the v2 schema and migration 20261119120000_v2_deal_no_duplicates.
Everything runs in one transaction that is rolled back.
"""
import json
import os
import uuid
from pathlib import Path

import pytest

psycopg = pytest.importorskip("psycopg")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
pytestmark = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")

MIG = Path("supabase/migrations/20261119120000_v2_deal_no_duplicates.sql")
SRC = {"source_url": "https://news.example/tesor-seed", "source_level": 2, "source_date": "2026-11-18",
       "source_type": "News"}


def _j(v):
    return v if isinstance(v, dict) else json.loads(v)


def test_migration_text():
    sql = MIG.read_text(encoding="utf-8")
    assert "create constraint trigger v2_deals_no_dup" in sql
    assert "deferrable initially deferred" in sql
    assert "v2_deals_seed_a_same_amount" in sql
    assert "'leftover empty deal'" in sql
    assert Path("supabase/rollbacks/20261119120000_v2_deal_no_duplicates.sql").exists()


@pytest.fixture()
def db():
    with psycopg.connect(DATABASE_URL) as conn:
        cur = conn.cursor()
        if cur.execute("select to_regprocedure('public.v2_deal_same_round(bigint,bigint,text,text,date,text,numeric,bigint)')").fetchone()[0] is None:
            pytest.skip("v2 schema or deal no-dup migration not in this database")
        tag = uuid.uuid4().hex[:8]
        key = cur.execute("insert into bots.ingest_keys(name, key_hash, active, bot_id) values (%s, %s, true, %s) returning id",
                          ("dd-" + tag, "hash-" + tag, "dd-" + tag)).fetchone()[0]
        cur.execute("insert into public.v2_bot_keys(bot_name, key_hash) values (%s, %s)", ("dd-" + tag, "hash-" + tag))
        bk = cur.execute("select bot_key_id from public.v2_bot_keys where bot_name = %s", ("dd-" + tag,)).fetchone()[0]
        sid = cur.execute("insert into public.v2_research_submissions(batch_id, bot_key_id, target_box, payload, status) "
                          "values (0, %s, 'F12', '{}', 'Accepted') returning submission_id", (bk,)).fetchone()[0]
        firm = cur.execute("insert into public.v2_firms(display_name, slug) values (%s, %s) returning firm_id",
                           ("DD Firm " + tag, "dd-firm-" + tag)).fetchone()[0]
        merged = cur.execute("insert into public.v2_firms(display_name, slug, merged_into_firm_id) values (%s, %s, %s) returning firm_id",
                             ("DD Old " + tag, "dd-old-" + tag, firm)).fetchone()[0]

        def startup(name):
            return cur.execute(
                "insert into public.v2_startups(startup_name, website_url, source_url, source_level, source_date, source_type, "
                "source_owner, submission_id, is_current) values (%s, %s, 'https://news.example/s', 2, '2026-11-18', 'News', 'test', %s, true) "
                "returning startup_id", (name, f"https://{name.lower()}-{tag}.example", sid)).fetchone()[0]

        def deal(firm_id, startup_id, **kw):
            cols = {"firm_id": firm_id, "startup_id": startup_id, "submission_id": sid, "source_url": "https://news.example/old",
                    "source_level": 2, "source_date": "2026-11-18", "source_type": "News", "source_owner": "test",
                    "is_current": True, "shown": True, **kw}
            if cols.get("deal_date") is None and cols.get("round_amount") is None:
                cols["shown"] = False
            names = ", ".join(cols)
            ph = ", ".join(["%s"] * len(cols))
            return cur.execute(f"insert into public.v2_deals({names}) values ({ph}) returning deal_id", list(cols.values())).fetchone()[0]

        def submit(firm_id, fact):
            item = {"firm_id": firm_id, "table": "v2_deals", "box": "F12", "fact": {**SRC, **fact}}
            r = _j(cur.execute("select public.v2_research_submit(%s, %s::jsonb, false)", (key, json.dumps([item]))).fetchone()[0])
            return r["results"][0]

        def live(firm_id, startup_id):
            return cur.execute("select deal_id, round, round_amount, deal_date, lead from public.v2_deals "
                               "where firm_id in (select public.v2_firm_family(%s)) and startup_id = %s and not archived "
                               "order by deal_id", (firm_id, startup_id)).fetchall()

        yield type("DB", (), dict(cur=cur, firm=firm, merged=merged, startup=staticmethod(startup), deal=staticmethod(deal),
                                  submit=staticmethod(submit), live=staticmethod(live)))
        conn.rollback()


def test_round_names_normalized(db):
    got = [db.cur.execute("select public.v2_deal_round_norm(%s)", (x,)).fetchone()[0]
           for x in ("Seed round", "seed", "A", "series-b", "Series C Round", "pre seed", "ipo", "Something")]
    assert got == ["Seed", "Seed", "Series A", "Series B", "Series C", "Pre-seed", "IPO", "Something"]


def test_same_round_merges_and_fills_empty_fields(db):
    s = db.startup("Tesor")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-11-18", deal_date_precision="full date")
    r = db.submit(db.firm, {"startup_id": s, "round": "Seed round", "deal_date": "2026-11-18", "deal_date_precision": "full date",
                            "round_amount": 5300000, "amount_currency": "USD", "lead": "yes"})
    assert r["status"] == "Accepted", r
    assert r["merged_into_deal_id"] == old and r["replaces_deal_id"] == old
    rows = db.live(db.firm, s)
    assert len(rows) == 1
    assert rows[0][1] == "Seed" and float(rows[0][2]) == 5300000 and rows[0][4] == "yes"


def test_same_round_nothing_new_is_skipped(db):
    s = db.startup("Tesor2")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-11-18", deal_date_precision="full date",
                  round_amount=5300000, amount_currency="USD")
    r = db.submit(db.firm, {"startup_id": s, "round": "Seed", "deal_date": "2026-11-18", "deal_date_precision": "full date",
                            "round_amount": 6000000, "amount_currency": "USD"})
    assert r["status"] == f"Skipped: already saved as deal {old}; nothing new to fill", r
    rows = db.live(db.firm, s)
    assert [x[0] for x in rows] == [old] and float(rows[0][2]) == 5300000  # never overwritten


def test_merged_firm_is_the_same_firm(db):
    s = db.startup("Merged")
    old = db.deal(db.merged, s, round="Series A", deal_date="2026-03-01", deal_date_precision="full date")
    r = db.submit(db.firm, {"startup_id": s, "round": "A", "deal_date": "2026-03-02", "deal_date_precision": "full date"})
    assert r["status"].startswith("Rejected: duplicate: this deal is already saved as deal_id %s" % old), r
    assert len(db.live(db.firm, s)) == 1


def test_different_round_or_far_apart_stays_separate(db):
    s = db.startup("Two")
    db.deal(db.firm, s, round="Seed", deal_date="2020-05-01", deal_date_precision="full date")
    a = db.submit(db.firm, {"startup_id": s, "round": "Series A", "deal_date": "2026-05-01", "deal_date_precision": "full date"})
    b = db.submit(db.firm, {"startup_id": s, "round": "Seed", "deal_date": "2023-05-01", "deal_date_precision": "full date"})
    assert a["status"] == "Accepted" and "merged_into_deal_id" not in a, a
    assert b["status"] == "Accepted" and "merged_into_deal_id" not in b, b
    assert len(db.live(db.firm, s)) == 3


def test_missing_date_counts_as_same_round(db):
    s = db.startup("NoDate")
    old = db.deal(db.firm, s, round="Seed", round_amount=1000000, amount_currency="USD")
    r = db.submit(db.firm, {"startup_id": s, "round": "Seed", "deal_date": "2026-01-10", "deal_date_precision": "full date"})
    assert r["status"] == "Accepted" and r["merged_into_deal_id"] == old, r
    rows = db.live(db.firm, s)
    assert len(rows) == 1 and str(rows[0][3]) == "2026-01-10"


def test_empty_deal_is_filled(db):
    s = db.startup("Empty")
    old = db.deal(db.firm, s)
    r = db.submit(db.firm, {"startup_id": s, "round": "Series A", "deal_date": "2026-02-01", "deal_date_precision": "full date",
                            "round_amount": 12000000, "amount_currency": "USD"})
    assert r["status"] == "Accepted" and r["merged_into_deal_id"] == old, r
    rows = db.live(db.firm, s)
    assert len(rows) == 1 and rows[0][1] == "Series A"
    src = db.cur.execute("select source_url from public.v2_deals where deal_id = %s", (rows[0][0],)).fetchone()[0]
    assert src == "https://news.example/old"  # existing evidence is never overwritten
    evidence = db.cur.execute("select fields, source from public.v2_deal_fill_sources where deal_id = %s", (rows[0][0],)).fetchone()
    assert "round" in evidence[0] and "round_amount" in evidence[0]
    assert evidence[1]["source_url"] == SRC["source_url"]


def test_two_empty_deals_fill_one_and_flag_the_rest(db):
    s = db.startup("Empties")
    e1 = db.deal(db.firm, s)
    e2 = db.deal(db.firm, s)
    r = db.submit(db.firm, {"startup_id": s, "round": "Seed", "deal_date": "2026-02-01", "deal_date_precision": "full date"})
    assert r["status"] == "Accepted" and r["merged_into_deal_id"] == e1, r
    flags = db.cur.execute("select deal_id, related_deal_id, reason from public.v2_deal_review_flags where deal_id = %s", (e2,)).fetchall()
    assert flags == [(e2, e1, "leftover empty deal")]
    assert db.cur.execute("select count(*) from public.v2_deal_review where deal_id = %s", (e2,)).fetchone()[0] == 1


def test_empty_deal_not_filled_when_another_stage_is_known(db):
    s = db.startup("Known")
    db.deal(db.firm, s)
    db.deal(db.firm, s, round="Seed", deal_date="2024-01-01", deal_date_precision="full date")
    r = db.submit(db.firm, {"startup_id": s, "round": "Series A", "deal_date": "2026-02-01", "deal_date_precision": "full date"})
    assert r["status"] == "Accepted" and "merged_into_deal_id" not in r, r
    assert len(db.live(db.firm, s)) == 3


def test_seed_and_a_same_amount_flagged_not_blocked(db):
    s = db.startup("Flash")
    seed = db.deal(db.firm, s, round="Seed", deal_date="2026-01-01", deal_date_precision="full date",
                   round_amount=128000000, amount_currency="USD")
    other = db.cur.execute("insert into public.v2_firms(display_name, slug) values ('DD other', %s) returning firm_id",
                           ("dd-other-" + uuid.uuid4().hex[:6],)).fetchone()[0]
    r = db.submit(other, {"startup_id": s, "round": "Series A", "deal_date": "2026-01-01", "deal_date_precision": "full date",
                          "round_amount": 128000000, "amount_currency": "USD"})
    assert r["status"] == "Accepted", r
    ids = {x[0] for x in db.cur.execute("select deal_id from public.v2_deal_review where reason = 'same amount as Seed and Series A' "
                                        "and deal_id in (select deal_id from public.v2_deals where startup_id = %s)", (s,)).fetchall()}
    assert seed in ids and len(ids) == 2


def test_database_guard_refuses_a_direct_second_insert(db):
    s = db.startup("Guard")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-11-18", deal_date_precision="full date")
    new = db.deal(db.firm, s, round="Seed", deal_date="2026-11-19", deal_date_precision="full date")
    with pytest.raises(psycopg.errors.UniqueViolation) as e:
        db.cur.execute("set constraints public.v2_deals_no_dup immediate")
    assert f"deal_id {old}" in str(e.value) or f"deal_id {new}" in str(e.value)


def test_database_guard_lets_a_correction_through(db):
    s = db.startup("Fix")
    old = db.deal(db.firm, s, round="Seed", deal_date="2026-11-18", deal_date_precision="full date")
    r = db.submit(db.firm, {"deal_id": old, "action": "correct", "round_amount": 2000000, "amount_currency": "USD"})
    assert r["status"] == "Accepted", r
    db.cur.execute("set constraints public.v2_deals_no_dup immediate")
    assert len(db.live(db.firm, s)) == 1


def test_dry_run_saves_nothing(db):
    s = db.startup("Dry")
    db.deal(db.firm, s, round="Seed", deal_date="2026-11-18", deal_date_precision="full date")
    key = db.cur.execute("select id from bots.ingest_keys order by created_at desc limit 1").fetchone()[0]
    item = {"firm_id": db.firm, "table": "v2_deals", "box": "F12",
            "fact": {**SRC, "startup_id": s, "round": "Seed", "round_amount": 5, "amount_currency": "USD"}}
    r = _j(db.cur.execute("select public.v2_research_submit(%s, %s::jsonb, true)", (key, json.dumps([item]))).fetchone()[0])
    assert r["results"][0]["status"] == "Accepted" and r["results"][0]["merged_into_deal_id"]
    assert len(db.live(db.firm, s)) == 1 and db.live(db.firm, s)[0][2] is None


def test_no_stage_new_deal_with_known_stage_deal_saves_as_before(db):
    s = db.startup("Plain")
    db.deal(db.firm, s, round="Seed", deal_date="2024-01-01", deal_date_precision="full date")
    r = db.submit(db.firm, {"startup_id": s, "deal_date": "2026-02-01", "deal_date_precision": "full date"})
    assert r["status"] == "Accepted" and "merged_into_deal_id" not in r, r
    assert len(db.live(db.firm, s)) == 2
