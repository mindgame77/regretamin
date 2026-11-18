"""v2 door next_firm / firm_done: universal per-job firm claims (v2_work_claims), job deal_gaps, up to 10 per key.

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a
local scratch Postgres (host localhost, 127.0.0.1 or a socket). They build a small stand-in v2
schema there, apply the migration, and drop everything again. Never point it at production.
"""
import os
import pathlib
import threading
from urllib.parse import urlparse

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261118200000_v2_work_claims.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261118200000_v2_work_claims.sql").read_text()
HOLD = (ROOT / "supabase/migrations/20261118220000_v2_next_firm_hold_10.sql").read_text()
HOLD_UNDO = (ROOT / "supabase/rollbacks/20261118220000_v2_next_firm_hold_10.sql").read_text()
REOPEN = (ROOT / "supabase/migrations/20261118260000_v2_next_firm_reopen_na_europe.sql").read_text()
REOPEN_UNDO = (ROOT / "supabase/rollbacks/20261118260000_v2_next_firm_reopen_na_europe.sql").read_text()
ALL_HQ = (ROOT / "supabase/migrations/20261118300000_v2_next_firm_all_known_hq.sql").read_text()
ALL_HQ_UNDO = (ROOT / "supabase/rollbacks/20261118300000_v2_next_firm_all_known_hq.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
NEXT = "public.v2_next_firm(uuid, text)"
DONE = "public.v2_firm_done(uuid, text, bigint)"
PRIVATE = ("public.v2_job_firms_deal_gaps(bigint)", "public.v2_work_bot(uuid)", "public.v2_work_job_fn(text)")
URL = os.environ.get("V2_SCRATCH_DATABASE_URL", "").strip()


def test_migration_is_server_only_and_has_one_function_per_job():
    low = SQL.lower()
    assert "primary key (job, firm_id)" in low
    assert "interval '2 hours'" in low
    assert "security definer" in low and "set search_path = public, bots" in low
    assert "create or replace function public.v2_job_firms_deal_gaps(p_firm_id bigint default null)" in low
    assert "format('public.v2_job_firms_%s(bigint)', p_job)" in SQL
    assert "'unknown job'" in SQL
    assert "g.st > 20 and g.good * 2 < g.st" in SQL
    assert "d.is_current and not d.archived" in SQL
    assert "group by d.firm_id" in SQL
    assert "enable row level security" in low
    assert "revoke all on table public.v2_work_claims from public, anon, authenticated" in low
    for sig in (NEXT, DONE) + PRIVATE:
        assert f"revoke all on function {sig} from public, anon, authenticated" in low
        for role in ("to anon", "to authenticated", "to public"):
            assert f"grant execute on function {sig} {role}" not in low
    for sig in (NEXT, DONE):
        assert f"grant execute on function {sig} to service_role" in low
        assert f"drop function if exists {sig};" in UNDO
    for sig in PRIVATE:
        assert f"grant execute on function {sig}" not in low
        assert f"drop function if exists {sig};" in UNDO
    assert "drop table if exists public.v2_work_claims;" in UNDO
    assert "to_regclass('public.v2_deals') is null" in low


def test_hold_10_migration_only_replaces_next_firm_and_rollback_restores_one_claim():
    low = HOLD.lower()
    assert low.count("create or replace function") == 1
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in low
    assert "n_held >= 10" in low
    assert "'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held)" in HOLD
    assert "to_regclass('public.v2_work_claims') is null" in low
    assert f"revoke all on function {NEXT} from public, anon, authenticated" in low
    assert f"grant execute on function {NEXT} to service_role" in low
    for role in ("to anon", "to authenticated", "to public"):
        assert f"grant execute on function {NEXT} {role}" not in low
    # The rollback is the production definition from before: one live claim per key, no held list.
    u = HOLD_UNDO.lower()
    assert u.count("create or replace function") == 1
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in u
    assert "held_firm_ids" not in u and "n_held" not in u
    assert "drop " not in u


def test_reopen_migration_only_replaces_next_firm_and_adds_country_helper():
    low = REOPEN.lower()
    assert low.count("create or replace function") == 2
    assert "create or replace function public.v2_work_hq_na_europe(p_country text)" in low
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in low
    assert "public.v2_work_hq_na_europe(f.hq_country)" in REOPEN
    assert REOPEN.count("public.v2_work_hq_na_europe(f.hq_country)") == 2
    assert "and w.done_at is not null" in REOPEN
    assert "w.bot_key_id is distinct from $2" in REOPEN
    assert "w.bot_key_id is distinct from bk.bot_key_id" in REOPEN
    assert "done_at = null" in REOPEN
    assert "g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)" in REOPEN
    assert "to_regclass('public.v2_work_claims') is null" in low
    assert f"revoke all on function {NEXT} from public, anon, authenticated" in low
    assert f"grant execute on function {NEXT} to service_role" in low
    assert "revoke all on function public.v2_work_hq_na_europe(text) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_work_hq_na_europe" not in low
    for role in ("to anon", "to authenticated", "to public"):
        assert f"grant execute on function {NEXT} {role}" not in low
    u = REOPEN_UNDO.lower()
    assert u.count("create or replace function") == 1
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in u
    assert "drop function if exists public.v2_work_hq_na_europe(text)" in u
    assert "n_held >= 10" in u
    # Rollback is the hold-10 function: no reopen pass, no country filter.
    assert "v2_work_hq_na_europe(f.hq_country)" not in REOPEN_UNDO
    assert "w.bot_key_id is distinct from $2" not in REOPEN_UNDO


def test_all_known_hq_migration_replaces_country_helper_and_keeps_reopen():
    low = ALL_HQ.lower()
    assert low.count("create or replace function") == 2
    assert "create or replace function public.v2_work_hq_known(p_country text)" in low
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in low
    assert "select btrim(coalesce(p_country, '')) <> ''" in ALL_HQ
    assert "public.v2_work_hq_known(f.hq_country)" in ALL_HQ
    assert ALL_HQ.count("public.v2_work_hq_known(f.hq_country)") == 2
    assert "v2_work_hq_na_europe(f.hq_country)" not in ALL_HQ
    assert "drop function if exists public.v2_work_hq_na_europe(text)" in low
    assert "and w.done_at is not null" in ALL_HQ
    assert "w.bot_key_id is distinct from $2" in ALL_HQ
    assert "w.bot_key_id is distinct from bk.bot_key_id" in ALL_HQ
    assert "done_at = null" in ALL_HQ
    assert "g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)" in ALL_HQ
    assert "n_held >= 10" in low
    assert "interval '2 hours'" in ALL_HQ
    assert "to_regclass('public.v2_work_claims') is null" in low
    assert f"revoke all on function {NEXT} from public, anon, authenticated" in low
    assert f"grant execute on function {NEXT} to service_role" in low
    assert "revoke all on function public.v2_work_hq_known(text) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_work_hq_known" not in low
    for role in ("to anon", "to authenticated", "to public"):
        assert f"grant execute on function {NEXT} {role}" not in low
    u = ALL_HQ_UNDO.lower()
    assert u.count("create or replace function") == 2
    assert "create or replace function public.v2_work_hq_na_europe(p_country text)" in u
    assert "create or replace function public.v2_next_firm(p_key_id uuid, p_job text)" in u
    assert "drop function if exists public.v2_work_hq_known(text)" in u
    assert ALL_HQ_UNDO.count("public.v2_work_hq_na_europe(f.hq_country)") == 2
    assert "v2_work_hq_known(f.hq_country)" not in ALL_HQ_UNDO
    assert "w.bot_key_id is distinct from $2" in ALL_HQ_UNDO
    assert "n_held >= 10" in u


def test_edge_routes_next_firm_and_firm_done_from_the_key():
    assert 'body.action === "next_firm" || body.action === "firm_done"' in FN
    block = FN[FN.index('body.action === "next_firm"'):FN.index('body.action !== "submit"')]
    assert 'db.rpc("v2_next_firm", { p_key_id: auth.key_id, p_job: job })' in block
    assert 'db.rpc("v2_firm_done", { p_key_id: auth.key_id, p_job: job, p_firm_id: firmId })' in block
    assert "body.bot_id" not in block
    hint = FN[FN.index("const HINT"):FN.index(";", FN.index("const HINT"))]
    assert "next_firm" in hint and "firm_done" in hint


# ---------- database checks (local scratch Postgres only) ----------

STUB = """
drop schema if exists bots cascade;
drop table if exists public.v2_work_claims, public.v2_deals, public.v2_startups, public.v2_bot_keys, public.v2_firms cascade;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema bots;
create table bots.ingest_keys (id uuid primary key, name text, key_hash text, active boolean not null default true, bot_id text);
create table public.v2_firms (firm_id bigint primary key, slug text, display_name text, website_url text, archived boolean default false, hq_country text default 'US');
create table public.v2_startups (startup_id bigint primary key, is_current boolean default true, archived boolean default false);
create table public.v2_bot_keys (bot_key_id bigserial primary key, bot_name text unique not null, key_hash text,
  frozen boolean not null default false, freeze_date timestamptz, freeze_reason text, freeze_count_7d int);
create table public.v2_deals (deal_id bigserial primary key, firm_id bigint, startup_id bigint, round text, deal_date date,
  is_current boolean default true, archived boolean default false, nothing_found boolean);
"""

K1, K2, K3 = ("11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222",
              "33333333-3333-3333-3333-333333333333")


def _local(url):
    host = urlparse(url).hostname or ""
    return host in ("", "localhost", "127.0.0.1") or host.startswith("/")


@pytest.fixture()
def db():
    if not URL:
        pytest.skip("V2_SCRATCH_DATABASE_URL is not set")
    if not _local(URL):
        pytest.skip("V2_SCRATCH_DATABASE_URL must be a local scratch database")
    import psycopg
    with psycopg.connect(URL, autocommit=True) as c:
        c.execute(STUB)
        for k, b in ((K1, "bot-a"), (K2, "bot-b"), (K3, "bot-c")):
            c.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values (%s, %s, %s)", (k, "h-" + b, b))
        # Firms 1-3 are gap firms (60, 40, 30 startups, none dated). Firm 4 has 25 startups, all dated: not a gap.
        # Firm 5 has 10 startups: too small. Firm 6 is a gap firm but archived.
        sizes = {1: (60, 0), 2: (40, 0), 3: (30, 10), 4: (25, 25), 5: (10, 0), 6: (50, 0)}
        sid = 0
        for fid, (n, dated) in sizes.items():
            c.execute("insert into public.v2_firms values (%s, %s, %s, %s, %s)", (fid, f"f{fid}", f"Firm {fid}", None, fid == 6))
            for i in range(n):
                sid += 1
                c.execute("insert into public.v2_deals(firm_id, startup_id, round, deal_date) values (%s, %s, %s, null)",
                          (fid, sid, "Seed" if i < dated else None))
        c.execute(SQL)
        c.execute(HOLD)
        c.execute(REOPEN)
        c.execute(ALL_HQ)
        yield c
        c.execute(ALL_HQ_UNDO)
        c.execute(REOPEN_UNDO)
        c.execute(UNDO)
        c.execute("drop schema bots cascade; drop table public.v2_deals, public.v2_startups, public.v2_bot_keys, public.v2_firms cascade")


def nxt(c, key, job="deal_gaps"):
    return c.execute("select public.v2_next_firm(%s, %s)", (key, job)).fetchone()[0]


def done(c, key, fid, job="deal_gaps"):
    return c.execute("select public.v2_firm_done(%s, %s, %s)", (key, job, fid)).fetchone()[0]


def add_gap_firms(c, first, count):
    """Extra gap firms first..first+count-1 with 21-29 undated startups each (all smaller than firms 1-3)."""
    sid = c.execute("select coalesce(max(startup_id), 0) from public.v2_deals").fetchone()[0]
    for fid in range(first, first + count):
        c.execute("insert into public.v2_firms values (%s, %s, %s, %s, false)", (fid, f"f{fid}", f"Firm {fid}", None))
        for _ in range(21 + fid % 9):
            sid += 1
            c.execute("insert into public.v2_deals(firm_id, startup_id) values (%s, %s)", (fid, sid))


def test_db_biggest_first_shape_and_repeat_call_gets_a_new_firm(db):
    a = nxt(db, K1)
    assert a["ok"] and a["held"] is False and a["job"] == "deal_gaps"
    assert a["held_firm_ids"] == [1] and a["held_count"] == 1
    f = a["firm"]
    assert (f["firm_id"], f["name"], f["startups"], f["dated_or_staged"]) == (1, "Firm 1", 60, 0)
    assert f["next"] == {"action": "deals", "firm_id": 1, "only_gaps": True}
    again = nxt(db, K1)
    assert again["firm"]["firm_id"] == 2 and again["held"] is False
    assert sorted(again["held_firm_ids"]) == [1, 2] and again["held_count"] == 2


def test_db_ten_calls_ten_firms_then_the_eleventh_is_held(db):
    add_gap_firms(db, 101, 12)
    got = [nxt(db, K1) for _ in range(10)]
    ids = [g["firm"]["firm_id"] for g in got]
    assert len(set(ids)) == 10 and all(g["held"] is False for g in got)
    assert [g["held_count"] for g in got] == list(range(1, 11))
    assert sorted(got[-1]["held_firm_ids"]) == sorted(ids)
    eleventh = nxt(db, K1)
    assert eleventh["held"] is True and eleventh["firm"]["firm_id"] in ids
    assert eleventh["firm"]["firm_id"] == ids[0]  # the oldest one
    assert eleventh["held_count"] == 10 and sorted(eleventh["held_firm_ids"]) == sorted(ids)
    assert db.execute("select count(*) from public.v2_work_claims where done_at is null").fetchone()[0] == 10


def test_db_firm_done_frees_a_slot_for_a_new_firm(db):
    add_gap_firms(db, 101, 12)
    ids = [nxt(db, K1)["firm"]["firm_id"] for _ in range(10)]
    assert done(db, K1, ids[3])["ok"] is True
    n = nxt(db, K1)
    assert n["held"] is False and n["firm"]["firm_id"] not in ids
    assert n["held_count"] == 10 and ids[3] not in n["held_firm_ids"]
    assert nxt(db, K1)["held"] is True


def test_db_two_keys_never_share_a_firm(db):
    add_gap_firms(db, 101, 30)
    a = [nxt(db, K1)["firm"]["firm_id"] for _ in range(10)]
    b = [nxt(db, K2)["firm"]["firm_id"] for _ in range(10)]
    assert len(set(a)) == 10 and len(set(b)) == 10 and not set(a) & set(b)
    rows = db.execute("select bot_key_id, count(*) from public.v2_work_claims group by 1 order by 1").fetchall()
    assert [r[1] for r in rows] == [10, 10]


def test_db_parallel_helpers_of_one_key_stop_at_ten_distinct_firms(db):
    import psycopg
    add_gap_firms(db, 101, 30)
    out, barrier = [], threading.Barrier(12)

    def run():
        with psycopg.connect(URL, autocommit=True) as c:
            barrier.wait()
            out.append(nxt(c, K1))

    ts = [threading.Thread(target=run) for _ in range(12)]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    new = [o["firm"]["firm_id"] for o in out if o["held"] is False]
    assert len(new) == 10 and len(set(new)) == 10
    assert all(o["held"] is True and o["firm"]["firm_id"] in new for o in out if o["held"] is True)
    assert db.execute("select count(*) from public.v2_work_claims where done_at is null").fetchone()[0] == 10


def test_db_no_new_firm_left_returns_null_with_held_list(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    assert nxt(db, K2)["firm"]["firm_id"] == 2
    assert nxt(db, K2)["firm"]["firm_id"] == 3
    r = nxt(db, K1)
    assert r["firm"] is None and r["held_firm_ids"] == [1] and r["held_count"] == 1


def test_db_rollback_puts_back_one_firm_per_key(db):
    db.execute(ALL_HQ_UNDO)
    db.execute(REOPEN_UNDO)
    db.execute(HOLD_UNDO)
    a = nxt(db, K1)
    again = nxt(db, K1)
    assert again["firm"]["firm_id"] == a["firm"]["firm_id"] and again["held"] is True
    assert "held_firm_ids" not in again


def test_db_two_bots_at_the_same_time_get_different_firms(db):
    import psycopg
    out, barrier = {}, threading.Barrier(3)

    def run(name, key):
        with psycopg.connect(URL, autocommit=True) as c:
            barrier.wait()
            out[name] = nxt(c, key)["firm"]["firm_id"]

    ts = [threading.Thread(target=run, args=(n, k)) for n, k in (("a", K1), ("b", K2), ("c", K3))]
    for t in ts:
        t.start()
    for t in ts:
        t.join()
    assert sorted(out.values()) == [1, 2, 3], out
    # Nothing left for a fourth claim while all three are held.
    db.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values ('44444444-4444-4444-4444-444444444444', 'h-d', 'bot-d')")
    assert nxt(db, "44444444-4444-4444-4444-444444444444")["firm"] is None


def test_db_done_frees_the_bot_for_the_next_firm_and_stays_done(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    d = done(db, K1, 1)
    assert d["ok"] and d.get("already_done") is None
    assert done(db, K1, 1)["already_done"] is True
    assert nxt(db, K1)["firm"]["firm_id"] == 2
    assert nxt(db, K2)["firm"]["firm_id"] == 3  # 1 is done, 2 is held by bot-a


def test_db_expired_claim_can_be_reclaimed(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    db.execute("update public.v2_work_claims set expires_at = now() - interval '1 minute' where firm_id = 1")
    b = nxt(db, K2)
    assert b["firm"]["firm_id"] == 1 and b["held"] is False
    # bot-a lost the firm, so it cannot close it.
    assert done(db, K1, 1)["ok"] is False


def test_db_cannot_mark_another_bots_firm_done(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    r = done(db, K2, 1)
    assert r["ok"] is False and "not claimed by you" in r["error"]
    assert db.execute("select done_at from public.v2_work_claims where firm_id = 1").fetchone()[0] is None


def test_db_unknown_job_and_bad_key_are_rejected(db):
    assert nxt(db, K1, "legal") == {"ok": False, "bot_id": "bot-a", "error": "unknown job"}
    assert nxt(db, K1, "x'; drop table v2_firms; --")["error"] == "unknown job"
    assert done(db, K1, 1, "reviews")["error"] == "unknown job"
    assert nxt(db, "99999999-9999-9999-9999-999999999999")["ok"] is False
    assert db.execute("select count(*) from public.v2_work_claims").fetchone()[0] == 0


def test_db_frozen_bot_gets_nothing(db):
    nxt(db, K1)
    db.execute("update public.v2_work_claims set done_at = now()")
    db.execute("update public.v2_bot_keys set frozen = true, freeze_reason = 'test' where bot_name = 'bot-a'")
    assert nxt(db, K1)["error"].startswith("Key frozen")


def test_db_anon_and_authenticated_cannot_call_or_read(db):
    import psycopg
    for role in ("anon", "authenticated"):
        for stmt in (f"select public.v2_next_firm('{K1}', 'deal_gaps')",
                     f"select public.v2_firm_done('{K1}', 'deal_gaps', 1)",
                     "select * from public.v2_job_firms_deal_gaps(null)",
                     f"select public.v2_work_bot('{K1}')",
                     "select * from public.v2_work_claims"):
            db.execute(f"set role {role}")
            try:
                with pytest.raises(psycopg.errors.InsufficientPrivilege):
                    db.execute(stmt)
            finally:
                db.execute("reset role")
    db.execute("set role service_role")
    try:
        assert db.execute(f"select public.v2_next_firm('{K1}', 'deal_gaps')").fetchone()[0]["ok"] is True
    finally:
        db.execute("reset role")


def test_db_reopen_gives_another_bots_done_gappy_firm_not_your_own(db):
    """K1 finishes every gap firm. K2 gets the one with the most remaining gaps.
    K1 then gets nothing, because those firms were done by K1 and K2 holds the other."""
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    assert nxt(db, K1)["firm"]["firm_id"] == 2
    assert nxt(db, K1)["firm"]["firm_id"] == 3
    assert done(db, K1, 1)["ok"] and done(db, K1, 2)["ok"] and done(db, K1, 3)["ok"]
    b = nxt(db, K2)
    # Remaining gaps: firm 1 has 60, firm 2 has 40, firm 3 has 20.
    assert b["ok"] and b["held"] is False and b["firm"]["firm_id"] == 1
    assert b["firm"]["startups"] == 60 and b["firm"]["dated_or_staged"] == 0
    row = db.execute("select bot_key_id, done_at is null from public.v2_work_claims where firm_id = 1").fetchone()
    k2_id = db.execute("select bot_key_id from public.v2_bot_keys where bot_name = 'bot-b'").fetchone()[0]
    assert row == (k2_id, True)
    # The original bot cannot take back its own done firms, or the one K2 now holds.
    a = nxt(db, K1)
    assert a["firm"] is None and a["held_count"] == 0
    # firm_done works for the new holder and sets done_at again.
    d = done(db, K2, 1)
    assert d["ok"] and d.get("already_done") is None and d["done_at"]
    assert done(db, K2, 1)["already_done"] is True
    # After K2 finishes, a third bot may get that firm (no history of the first bot).
    c = nxt(db, K3)
    assert c["firm"]["firm_id"] == 1 and c["held"] is False


def test_db_fresh_and_reopen_passes_include_any_known_country_and_skip_blank(db):
    # Fresh pass hands out Asia (biggest firm) and skips a blank-country firm.
    db.execute("update public.v2_firms set hq_country = 'JP' where firm_id = 1")
    db.execute("update public.v2_firms set hq_country = null where firm_id = 2")
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    assert nxt(db, K1)["firm"]["firm_id"] == 3
    assert nxt(db, K1)["firm"] is None
    assert done(db, K1, 1)["ok"] and done(db, K1, 3)["ok"]

    # Reopen: a done blank firm is skipped; a done Japanese firm is handed out.
    k1_id = db.execute("select bot_key_id from public.v2_bot_keys where bot_name = 'bot-a'").fetchone()[0]
    db.execute(
        "insert into public.v2_work_claims(job, firm_id, bot_key_id, claimed_at, expires_at, done_at) "
        "values ('deal_gaps', 2, %s, now(), now() + interval '2 hours', now())",
        (k1_id,),
    )
    b = nxt(db, K2)
    assert b["firm"]["firm_id"] == 1 and b["held"] is False
    assert db.execute("select done_at is not null from public.v2_work_claims where firm_id = 2").fetchone()[0] is True


def test_db_all_known_rollback_restores_na_europe_filter(db):
    db.execute("update public.v2_firms set hq_country = 'JP' where firm_id = 1")
    db.execute(ALL_HQ_UNDO)
    # Back to NA/Europe only: the Japanese firm is skipped, the US firms are not.
    assert nxt(db, K1)["firm"]["firm_id"] == 2
    assert nxt(db, K1)["firm"]["firm_id"] == 3
    assert nxt(db, K1)["firm"] is None


def test_db_reopen_rollback_stops_handing_out_done_firms(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 1
    assert done(db, K1, 1)["ok"]
    db.execute(ALL_HQ_UNDO)
    db.execute(REOPEN_UNDO)
    # Hold-10 next_firm does not reopen done firms, and has no country filter.
    b = nxt(db, K2)
    assert b["firm"]["firm_id"] == 2
    c = nxt(db, K2)
    assert c["firm"]["firm_id"] == 3
    assert nxt(db, K3)["firm"] is None

