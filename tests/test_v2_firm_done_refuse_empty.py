"""v2 work: firm_done refuses an empty close in job missing_details.

A bot that saved nothing for a firm during its claim (no v2_research_submissions row of any status,
nothing_found included) cannot mark a firm done while v2_job_firms_missing_details still lists
missing items. The claim stays open. Anything saved, or nothing missing, closes as before.
deal_gaps is unchanged.

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local
scratch Postgres. Never point it at production.
"""
import pathlib

import pytest

from test_v2_work_current_job import K1, K2, db, done, nxt, use_missing  # noqa: F401  (db is a fixture)

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261119100000_v2_firm_done_refuse_empty.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()
MSG = ("firm_done refused: you saved nothing for this firm. Research the missing fields first, "
       "or save nothing_found for each field you searched.")


def test_migration_rule_is_narrow():
    assert MSG in MIG
    assert "if j = 'missing_details' then" in MIG
    assert "s.received_at >= c.claimed_at" in MIG
    assert "s.bot_key_id = bk.bot_key_id and s.firm_id = p_firm_id" in MIG
    assert "public.v2_job_firms_missing_details(p_firm_id)" in MIG
    assert "status" not in MIG.split("v2_research_submissions s", 1)[1].split("then", 1)[0]  # any status counts
    low = MIG.lower()
    assert low.count("create or replace function") == 1
    assert "revoke all on function public.v2_firm_done(uuid, text, bigint) from public, anon, authenticated" in low
    for role in ("to anon", "to authenticated", "to public"):
        assert f"grant execute on function public.v2_firm_done(uuid, text, bigint) {role}" not in low
    assert "refused" not in UNDO and "v2_research_submissions" not in UNDO.split("$ddl$", 1)[1]


SUB = """
create table if not exists public.v2_research_submissions (submission_id bigserial primary key, batch_id bigint,
  firm_id bigint, bot_key_id bigint, target_box text, payload jsonb, status text, received_at timestamptz default now());
"""


@pytest.fixture()
def db2(db):  # noqa: F811
    db.execute(SUB)
    db.execute(MIG)
    use_missing(db)
    yield db
    db.execute(UNDO)
    db.execute("drop table if exists public.v2_research_submissions")


def key_id(c, key):
    return c.execute("select bot_key_id from public.v2_work_bot(%s)", (key,)).fetchone()[0]


def sub(c, key, fid, status="Accepted", when="now()"):
    c.execute(f"insert into public.v2_research_submissions(firm_id, bot_key_id, status, received_at) "
              f"values (%s, %s, %s, {when})", (fid, key_id(c, key), status))


def open_claim(c, fid):
    return c.execute("select done_at from public.v2_work_claims where job = 'missing_details' and firm_id = %s",
                     (fid,)).fetchone()[0]


def test_db_empty_close_is_refused_and_claim_stays_open(db2):
    fid = nxt(db2, K1)["firm"]["firm_id"]
    d = done(db2, K1, fid, "missing_details")
    assert d["ok"] is False and d["error"] == MSG
    assert open_claim(db2, fid) is None
    # Other bots still cannot take the held firm; the claim is still K1's.
    assert nxt(db2, K2)["firm"]["firm_id"] != fid


def test_db_one_saved_item_any_status_closes(db2):
    a = nxt(db2, K1)["firm"]["firm_id"]
    b = nxt(db2, K1)["firm"]["firm_id"]
    sub(db2, K1, a, "Accepted")
    sub(db2, K1, b, "Rejected: unknown field: x")
    for fid in (a, b):
        d = done(db2, K1, fid, "missing_details")
        assert d["ok"] and d["done_at"] is not None
    assert done(db2, K1, a, "missing_details")["already_done"] is True


def test_db_old_or_other_bot_or_other_firm_items_do_not_count(db2):
    fid = nxt(db2, K1)["firm"]["firm_id"]
    sub(db2, K1, fid, when="now() - interval '1 day'")  # before this claim
    sub(db2, K2, fid)  # another bot
    sub(db2, K1, fid + 1000)  # another firm
    assert done(db2, K1, fid, "missing_details")["ok"] is False
    sub(db2, K1, fid)
    assert done(db2, K1, fid, "missing_details")["ok"] is True


def test_db_nothing_missing_closes_without_items(db2):
    fid = nxt(db2, K1)["firm"]["firm_id"]
    db2.execute("update public.v2_firms set hq_country = 'US', hq_city = 'NYC' where firm_id = %s", (fid,))
    for t, col in (("v2_firm_contacts", "contact_email"), ("v2_social_accounts", "platform"),
                   ("v2_reviews", "quote"), ("v2_legal_items", "item_group")):
        db2.execute(f"insert into public.{t}(firm_id, {col}) values (%s, 'x')", (fid,))
    db2.execute("insert into public.v2_social_accounts(firm_id, platform) values (%s, 'YouTube')", (fid,))
    assert done(db2, K1, fid, "missing_details")["ok"] is True


def test_db_deal_gaps_unchanged(db2):
    k1 = key_id(db2, K1)
    db2.execute("insert into public.v2_work_claims(job, firm_id, bot_key_id, claimed_at, expires_at) "
                "values ('deal_gaps', 8, %s, now(), now() + interval '2 hours')", (k1,))
    d = done(db2, K1, 8)
    assert d["ok"] and d["job"] == "deal_gaps"


def test_db_rollback_restores_plain_done(db2):
    db2.execute(UNDO)
    fid = nxt(db2, K1)["firm"]["firm_id"]
    assert done(db2, K1, fid, "missing_details")["ok"] is True
    db2.execute(MIG)  # fixture teardown runs the rollback again
