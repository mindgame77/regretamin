"""Round list (schema roundlist): the separate 2026 rounds hand-out that replaces the Google Sheet.

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local
scratch Postgres (host localhost, 127.0.0.1 or a socket). They build the small stand-in v2 schema from
test_v2_work_claims, apply the migration, and drop everything again. Never point it at production.
"""
import datetime as dt
import pathlib
import re
import sys
import threading
import time

import pytest

from test_v2_work_claims import K1, K2, K3, STUB, URL, _local
from test_v2_work_claims import SQL as WORK_SQL, UNDO as WORK_UNDO

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261119170000_roundlist.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()
NEW_NAME = "20261125163000_roundlist_finish_done_check.sql"
NEW_MIG = (ROOT / "supabase/migrations" / NEW_NAME).read_text()
NEW_UNDO = (ROOT / "supabase/rollbacks" / NEW_NAME).read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
ENTRY = ("public.roundlist_add_round(uuid, jsonb)", "public.roundlist_claim_next_round(uuid, integer)",
         "public.roundlist_finish_round(uuid, bigint, text, text)")
ENTRY_NEW = "public.roundlist_finish_round(uuid, bigint, text, text, text, jsonb)"
sys.path.insert(0, str(ROOT / "scripts"))


def _code(sql):
    return "\n".join(l.split("--", 1)[0] for l in sql.splitlines())


def test_separate_schema_no_links_to_main_tables():
    code = _code(MIG).lower()
    assert "create schema if not exists roundlist" in code
    assert " references " not in code and "foreign key" not in code
    for t in ("v2_firms", "v2_deals", "v2_startups", "v2_people", "firm_directory"):
        assert f"public.{t}" not in code and f" {t} " not in code, t  # 'v2_deals' only as a payload value
    # The only main-database objects it reads: the key lookup and the submissions log.
    assert set(re.findall(r"public\.(v2_\w+)", code)) == {"v2_work_bot", "v2_bot_keys", "v2_research_submissions"}
    # Tables only in roundlist; the only public objects are the three entry points.
    assert re.findall(r"create table if not exists (\S+)", code) == ["roundlist.rounds", "roundlist.events"]
    pub = re.findall(r"create or replace function (public\.\w+)", code)
    assert pub == ["public.roundlist_add_round", "public.roundlist_claim_next_round", "public.roundlist_finish_round"]
    assert "constraint rounds_no_copies unique (startup_key, round_key, round_date)" in code
    assert "interval '2 hours'" in code


def test_locked_down_and_teardown_drops_everything():
    code = _code(MIG).lower()
    assert code.count("security definer") == 4  # release_expired + 3 entry points
    assert code.count("set search_path = roundlist, public, bots, pg_catalog") == 3
    assert "revoke all on schema roundlist from public" in code
    assert "revoke all on table roundlist.rounds, roundlist.events from anon" in code
    assert "enable row level security" in code
    for sig in ENTRY:
        assert f"grant execute on function {sig} to service_role" in code
        for role in ("to anon", "to authenticated", "to public"):
            assert f"grant execute on function {sig} {role}" not in code
        assert f"drop function if exists {sig};" in UNDO
    assert "drop schema if exists roundlist cascade;" in UNDO
    assert "v2_" not in _code(UNDO)


def test_door_routes_round_actions_with_header_key():
    block = FN[FN.index('body.action === "add_round" || body.action === "claim_next_round"'):FN.index('body.action === "next_firm" || body.action === "firm_done"')]
    for rpc in ("roundlist_add_round", "roundlist_claim_next_round", "roundlist_finish_round"):
        assert f'"{rpc}"' in block
    assert block.count("p_key_id: auth.key_id") == 3
    assert "bot_id" not in block.split("db.rpc", 1)[0]  # the bot comes from the key, never the body


def test_new_done_check_is_locked_down_and_rolls_back_to_the_old_function():
    code = _code(NEW_MIG).lower()
    undo = _code(NEW_UNDO).lower()
    assert "v2_deals.shown" not in code and "v2_map_" not in code and "v2_top_firms" not in code
    assert "create or replace function roundlist.done_check" in code
    assert "create or replace function public.roundlist_finish_round" in code
    assert f"grant execute on function {ENTRY_NEW} to service_role" in code
    assert f"drop function if exists {ENTRY_NEW}" in undo
    assert "drop function if exists roundlist.done_check" in undo
    assert "drop function if exists roundlist.save_pending_firms" in undo
    # Rollback restores the previous 4-argument finish_round; it does not drop the list.
    assert "create or replace function public.roundlist_finish_round(p_key_id uuid, p_round_id bigint, p_result text, p_note text)" in undo
    assert "drop schema" not in undo


# ---------- database checks (local scratch Postgres only) ----------

SUB = """
create table if not exists public.v2_research_submissions (submission_id bigserial primary key, batch_id bigint,
  firm_id bigint, bot_key_id bigint, target_box text, payload jsonb, status text, received_at timestamptz default now());
"""

EXTRA = """
alter table public.v2_startups add column if not exists startup_name text;
alter table public.v2_startups add column if not exists domain text;
alter table public.v2_startups add column if not exists website_url text;
alter table public.v2_startups add column if not exists website_url_norm text;
alter table public.v2_firms add column if not exists website_url_norm text;
alter table public.v2_firms add column if not exists legal_name text;
alter table public.v2_firms add column if not exists short_name text;
alter table public.v2_deals add column if not exists shown boolean default true;
alter table public.v2_deals add column if not exists lead text;
alter table public.v2_deals add column if not exists event_id bigint;
alter table public.v2_deals add column if not exists source_url text;
alter table public.v2_deals add column if not exists round_amount numeric;
create table if not exists public.v2_events (
  event_id bigserial primary key, kind text not null, startup_id bigint, round text,
  event_date date, event_date_precision text, amount numeric);
create table if not exists public.v2_event_sources (
  source_id bigserial primary key, event_id bigint, source_url text);
create table if not exists public.v2_firm_hold_list (
  id bigserial primary key, priority smallint not null check (priority in (1,2,3)),
  name text not null, website_url text not null, website_domain text not null unique,
  source_tag text not null, status text not null default 'held', created_at timestamptz default now());
"""


@pytest.fixture()
def db():
    if not URL:
        pytest.skip("V2_SCRATCH_DATABASE_URL is not set")
    if not _local(URL):
        pytest.skip("V2_SCRATCH_DATABASE_URL must be a local scratch database")
    import psycopg
    with psycopg.connect(URL, autocommit=True) as c:
        c.execute(UNDO)
        c.execute(STUB)
        c.execute(SUB)
        for k, b in ((K1, "bot-a"), (K2, "bot-b"), (K3, "bot-c")):
            c.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values (%s, %s, %s)", (k, "h-" + b, b))
        c.execute(WORK_SQL)  # public.v2_work_bot, the key -> bot lookup the bots already use
        c.execute(EXTRA)
        c.execute(MIG)
        c.execute(NEW_MIG)
        yield c
        c.execute(NEW_UNDO)
        c.execute(UNDO)
        c.execute(WORK_UNDO)
        c.execute("drop schema bots cascade; drop table if exists public.v2_research_submissions, public.v2_deals, "
                  "public.v2_startups, public.v2_bot_keys, public.v2_firms, public.v2_events, "
                  "public.v2_event_sources, public.v2_firm_hold_list cascade")


def add(c, key, **kw):
    r = {"startup_name": "Acme", "startup_website": "https://acme.io", "country": "US", "round": "Seed",
         "round_date": "2026-11-10", "source_url": "https://news.example/acme"}
    r.update(kw)
    from psycopg.types.json import Jsonb
    return c.execute("select public.roundlist_add_round(%s, %s)", (key, Jsonb(r))).fetchone()[0]


def claim(c, key, count=1):
    return c.execute("select public.roundlist_claim_next_round(%s, %s)", (key, count)).fetchone()[0]


def add_many(c, n, prefix="S"):
    return [add(c, K3, startup_name=f"{prefix}{i}", startup_website=f"{prefix.lower()}{i}.io")["round"]["round_id"]
            for i in range(n)]


def finish(c, key, rid, result="done", note="saved 2 deals", source_url="https://news.example/acme", report=None):
    from psycopg.types.json import Jsonb
    return c.execute("select public.roundlist_finish_round(%s, %s, %s, %s, %s, %s)",
                     (key, rid, result, note, source_url, Jsonb(report or {}))).fetchone()[0]


def seed_round(c, firm_id=80, firm_name="Founders Fund", website="https://foundersfund.com",
               startup_id=10, startup_name="Acme", domain="acme.io", amount=8000000,
               date="2026-11-10", rnd="Seed", source="https://news.example/acme", lead="yes"):
    c.execute("insert into public.v2_firms(firm_id, display_name, website_url, website_url_norm) "
              "values (%s,%s,%s,%s) on conflict (firm_id) do update set display_name = excluded.display_name, "
              "website_url = excluded.website_url, website_url_norm = excluded.website_url_norm",
              (firm_id, firm_name, website, website))
    c.execute("insert into public.v2_startups(startup_id, startup_name, domain, website_url, is_current, archived) "
              "values (%s,%s,%s,%s,true,false) on conflict (startup_id) do update set startup_name = excluded.startup_name, "
              "domain = excluded.domain, website_url = excluded.website_url",
              (startup_id, startup_name, domain, "https://" + domain))
    ev = c.execute("insert into public.v2_events(kind, startup_id, round, event_date, event_date_precision, amount) "
                   "values ('round', %s, %s, %s, 'full date', %s) returning event_id",
                   (startup_id, rnd, date, amount)).fetchone()[0]
    c.execute("insert into public.v2_event_sources(event_id, source_url) values (%s,%s)", (ev, source))
    c.execute("insert into public.v2_deals(firm_id, startup_id, round, deal_date, is_current, archived, shown, lead, event_id, source_url, round_amount) "
              "values (%s,%s,%s,%s,true,false,true,%s,%s,%s,%s)",
              (firm_id, startup_id, rnd, date, lead, ev, source, amount))
    return ev


def bot_key_id(c, key):
    return c.execute("select bot_key_id from public.v2_work_bot(%s)", (key,)).fetchone()[0]


def save_deal(c, key, status="Accepted", table="v2_deals", when="now()"):
    c.execute(f"insert into public.v2_research_submissions(bot_key_id, target_box, payload, status, received_at) "
              f"values (%s, 'F12', jsonb_build_object('target_table', %s::text), %s, {when})", (bot_key_id(c, key), table, status))


def test_db_add_and_duplicates_refused(db):
    a = add(db, K1)
    assert a["ok"] and a["round"]["status"] == "open" and a["round"]["added_by"] == "bot-a"
    # Same startup (other spelling of the site), same round (other spelling), same date: refused.
    d = add(db, K2, startup_name="ACME Inc", startup_website="http://www.Acme.io/about", round="seed ")
    assert not d["ok"] and d["duplicate"] and d["existing_round_id"] == a["round"]["round_id"]
    assert "already on the list" in d["error"]
    assert add(db, K2, round="Pre-seed")["ok"]                # different round is fine
    assert not add(db, K2, round="Pre Seed")["ok"]           # ... and "Pre Seed" = "Pre-seed"
    assert add(db, K2, round_date="2026-11-11")["ok"]        # different date is a different round
    # No website: the name is the startup key.
    assert add(db, K1, startup_name="No Site Co", startup_website=None)["ok"]
    assert not add(db, K2, startup_name="no-site co", startup_website="")["ok"]
    # Bad input
    assert "round_date" in add(db, K1, round_date="11/10/2026")["error"]
    assert "source_url" in add(db, K1, startup_name="X", source_url="")["error"]
    assert "not linked" in add(db, "44444444-4444-4444-4444-444444444444")["error"]
    n = db.execute("select count(*) from roundlist.rounds").fetchone()[0]
    assert n == 4
    assert db.execute("select count(*) from roundlist.events where action = 'add_refused'").fetchone()[0] == 3


def test_db_claim_oldest_first_up_to_10_per_bot(db):
    ids = add_many(db, 14)
    a = claim(db, K1)
    assert a["round"]["round_id"] == ids[0] and a["round"]["status"] == "taken"
    assert a["held_count"] == 1 and a["held_round_ids"] == [ids[0]] and a["max_held"] == 10
    b = claim(db, K1)  # a second call gives the next round, not the same one
    assert b["round"]["round_id"] == ids[1] and b["held_round_ids"] == ids[:2]
    for i in range(2, 10):
        assert claim(db, K1)["round"]["round_id"] == ids[i]
    full = claim(db, K1)
    assert not full["ok"] and full["held_count"] == 10 and full["held_round_ids"] == ids[:10]
    assert full["error"] == ("you already hold 10 rounds (the most is 10): " + ", ".join(map(str, ids[:10]))
                             + ". Finish one with finish_round before you ask for more.")
    assert claim(db, K2)["round"]["round_id"] == ids[10]  # other bots are not affected
    # Finishing one frees one slot.
    assert finish(db, K1, ids[0], "rejected", "not a 2026 round")["ok"]
    nxt = claim(db, K1, 5)
    assert nxt["claimed_count"] == 1 and nxt["round"]["round_id"] == ids[11] and nxt["held_count"] == 10


def test_db_count_param(db):
    ids = add_many(db, 12)
    three = claim(db, K1, 3)
    assert [r["round_id"] for r in three["rounds"]] == ids[:3] and three["claimed_count"] == 3
    assert three["round"]["round_id"] == ids[0]
    big = claim(db, K1, 10)  # only 7 slots left
    assert big["claimed_count"] == 7 and [r["round_id"] for r in big["rounds"]] == ids[3:10]
    assert big["held_count"] == 10
    assert not claim(db, K1, 1)["ok"]
    for bad in (0, 11, -1):
        assert claim(db, K2, bad)["error"] == "count must be 1-10"
    rest = claim(db, K2, 10)  # fewer open rounds than asked: gets what is left
    assert rest["claimed_count"] == 2 and [r["round_id"] for r in rest["rounds"]] == ids[10:]
    none = claim(db, K3)
    assert none["ok"] and none["round"] is None and none["rounds"] == [] and none["claimed_count"] == 0


def test_db_claim_race_two_bots_never_share_a_round(db):
    import psycopg
    r1 = add(db, K3, startup_name="One", startup_website="one.io")["round"]["round_id"]
    r2 = add(db, K3, startup_name="Two", startup_website="two.io")["round"]["round_id"]
    with psycopg.connect(URL) as ca, psycopg.connect(URL) as cb:
        a = claim(ca, K1)          # transaction open, row r1 locked
        b = claim(cb, K2)          # must skip the locked row, not wait
        assert a["round"]["round_id"] == r1 and b["round"]["round_id"] == r2
        ca.commit(); cb.commit()
    # Many bots at once on few rounds: every round goes to exactly one bot.
    for i in range(3, 8):
        add(db, K3, startup_name=f"S{i}", startup_website=f"s{i}.io")
    keys = []
    for i in range(10):
        k = f"aaaaaaaa-0000-0000-0000-{i:012d}"
        db.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values (%s, %s, %s)", (k, f"h{i}", f"race-{i}"))
        keys.append(k)
    got, gate = {}, threading.Barrier(len(keys))

    def run(k):
        with psycopg.connect(URL, autocommit=True) as c:
            gate.wait()
            got[k] = claim(c, k)["round"]
    ts = [threading.Thread(target=run, args=(k,)) for k in keys]
    [t.start() for t in ts]; [t.join() for t in ts]
    ids = [r["round_id"] for r in got.values() if r]
    assert len(ids) == 5 and len(set(ids)) == 5
    assert sum(1 for r in got.values() if r is None) == 5
    rows = db.execute("select taken_by, count(*) from roundlist.rounds where status = 'taken' group by 1").fetchall()
    assert all(n == 1 for _, n in rows)


def test_db_same_bot_parallel_calls_never_exceed_10(db):
    import psycopg
    add_many(db, 30)
    # The per-bot lock: a second call waits for the first, then gets the next round.
    out = []
    with psycopg.connect(URL) as ca:
        a = claim(ca, K1)
        t = threading.Thread(target=lambda: out.append(claim(psycopg.connect(URL, autocommit=True), K1)))
        t.start(); time.sleep(0.5)
        assert t.is_alive()
        ca.commit()
        t.join()
    assert out[0]["round"]["round_id"] != a["round"]["round_id"] and out[0]["held_count"] == 2
    # 15 parallel calls from one bot (count 1): exactly 8 more succeed, the rest are refused at 10.
    res, gate = [], threading.Barrier(15)

    def run(count):
        with psycopg.connect(URL, autocommit=True) as c:
            gate.wait()
            res.append(claim(c, K1, count))
    ts = [threading.Thread(target=run, args=(1,)) for _ in range(15)]
    [t.start() for t in ts]; [t.join() for t in ts]
    assert sum(1 for r in res if r["ok"] and r["claimed_count"] == 1) == 8
    assert sum(1 for r in res if not r["ok"] and r["held_count"] == 10) == 7
    held = lambda key: db.execute("select count(*) from roundlist.rounds r join public.v2_bot_keys b on b.bot_name = r.taken_by "
                                  "where r.status = 'taken' and b.bot_name = (select bot_name from public.v2_work_bot(%s))",
                                  (key,)).fetchone()[0]
    assert held(K1) == 10
    # 6 parallel calls from another bot asking 3 each: never more than 10 in total.
    res.clear(); gate = threading.Barrier(6)
    ts = [threading.Thread(target=run_k2, args=(gate, res)) for _ in range(6)]
    [t.start() for t in ts]; [t.join() for t in ts]
    assert sum(r.get("claimed_count", 0) for r in res) == 10 and held(K2) == 10
    ids = db.execute("select round_id from roundlist.rounds where status = 'taken'").fetchall()
    assert len(ids) == 20 and len(set(ids)) == 20


def run_k2(gate, res):
    import psycopg
    with psycopg.connect(URL, autocommit=True) as c:
        gate.wait()
        res.append(claim(c, K2, 3))


def test_db_done_needs_a_complete_event_and_named_investors(db):
    rid = add(db, K3)["round"]["round_id"]
    assert claim(db, K1)["round"]["round_id"] == rid
    # Old-style done (note only): refused.
    r = finish(db, K1, rid)
    assert not r["ok"] and "list every named investor" in r["error"]
    assert db.execute("select status from roundlist.rounds where round_id = %s", (rid,)).fetchone()[0] == "taken"
    assert "note is required" in finish(db, K1, rid, note="  ")["error"]
    assert "source_url is required" in finish(db, K1, rid, source_url="not-a-url")["error"]
    assert "not held by you" in finish(db, K2, rid)["error"]

    # Higgsfield-style miss: DST Global is already in the list, but listed as not in our list, and no lead deal.
    ev = seed_round(db, firm_id=80, firm_name="Accel", website="https://accel.com", lead=None)
    # add DST as an existing firm with no deal
    db.execute("insert into public.v2_firms(firm_id, display_name, website_url, website_url_norm) "
               "values (5811, 'DST Global', 'https://dst-global.com', 'https://dst-global.com')")
    miss = finish(db, K1, rid, note="DST Global led and is not in the system. Accel was saved.",
                  report={"amount": 8000000, "investors": [
                      {"firm_id": 80},
                      {"name": "DST Global", "website": "https://dst-global.com", "lead": True},
                  ]})
    assert not miss["ok"] and "already in our list" in miss["error"] and "5811" in miss["error"]
    assert db.execute("select status from roundlist.rounds where round_id = %s", (rid,)).fetchone()[0] == "taken"
    # Accel saved, DST omitted, no lead: refused for no lead (and DST never linked).
    miss2 = finish(db, K1, rid, note="Saved Accel", report={"amount": 8000000, "investors": [{"firm_id": 80}]})
    assert not miss2["ok"] and "mark the lead deal" in miss2["error"]

    # Correct: add the DST lead deal, list both firm_ids, include a truly new firm.
    db.execute("insert into public.v2_deals(firm_id, startup_id, round, deal_date, is_current, archived, shown, lead, event_id, source_url, round_amount) "
               "select 5811, 10, 'Seed', '2026-11-10', true, false, true, 'yes', %s, 'https://news.example/acme', 8000000", (ev,))
    ok = finish(db, K1, rid, note="Saved DST Global lead and Accel. NewCo not in our list.",
                report={"amount": 8000000, "investors": [
                    {"firm_id": 5811}, {"firm_id": 80},
                    {"name": "NewCo Capital", "website": "https://newco.example"},
                ]})
    assert ok["ok"] and ok["round"]["status"] == "done" and ok["round"]["notes"].startswith("Saved DST Global")
    held = db.execute("select name, website_domain, source_tag, status from public.v2_firm_hold_list").fetchall()
    assert held == [("NewCo Capital", "newco.example", "roundlist_not_in_list", "held")]
    assert finish(db, K1, rid)["already_finished"]

    # rejected needs a note and a source, not an event.
    rid2 = add(db, K3, startup_name="Gone", startup_website="gone.io")["round"]["round_id"]
    assert claim(db, K2)["round"]["round_id"] == rid2
    rej = finish(db, K2, rid2, "rejected", "not a 2026 round", source_url="https://news.example/gone")
    assert rej["ok"] and rej["round"]["status"] == "rejected"
    assert claim(db, K2)["round"] is None


def test_db_expired_hold_goes_back_to_open(db):
    rid = add(db, K3)["round"]["round_id"]
    assert claim(db, K1)["round"]["round_id"] == rid
    db.execute("update roundlist.rounds set taken_at = now() - interval '2 hours 1 minute' where round_id = %s", (rid,))
    b = claim(db, K2)
    assert b["round"]["round_id"] == rid and b["round"]["taken_by"] == "bot-b"
    save_deal(db, K1)
    assert "not held by you" in finish(db, K1, rid)["error"]
    ev = db.execute("select detail->>'was_taken_by' from roundlist.events where action = 'released'").fetchall()
    assert ev == [("bot-a",)]
    # Each round expires from its own taken_at: of two held rounds only the old one goes back.
    r2, r3 = add_many(db, 2, "E")
    assert claim(db, K1, 2)["claimed_count"] == 2
    db.execute("update roundlist.rounds set taken_at = now() - interval '2 hours 5 minutes' where round_id = %s", (r2,))
    db.execute("update roundlist.rounds set taken_at = now() - interval '1 hour 55 minutes' where round_id = %s", (r3,))
    held = claim(db, K1)
    assert held["claimed_count"] == 1 and held["round"]["round_id"] == r2 and r3 in held["held_round_ids"]
    db.execute("update roundlist.rounds set status = 'done' where round_id in (%s, %s)", (r2, r3))
    # release_expired on its own
    db.execute("update roundlist.rounds set taken_at = now() - interval '3 hours' where round_id = %s", (rid,))
    assert db.execute("select roundlist.release_expired()").fetchone()[0] == 1
    assert db.execute("select status, taken_by from roundlist.rounds where round_id = %s", (rid,)).fetchone() == ("open", None)


def test_db_frozen_key_and_no_direct_access(db):
    import psycopg
    add(db, K3)
    db.execute("update public.v2_bot_keys set frozen = true, freeze_reason = 'test' where bot_name = 'bot-c'")
    assert claim(db, K3)["error"].startswith("Key frozen")
    for role in ("anon", "authenticated"):
        for sql in ("select * from roundlist.rounds", "delete from roundlist.rounds",
                    f"select public.roundlist_claim_next_round('{K1}')"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with db.transaction():
                    db.execute(f"set local role {role}")
                    db.execute(sql)
    with db.transaction():
        db.execute("set local role service_role")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with db.transaction():
                db.execute("delete from roundlist.rounds")
        assert claim(db, K1)["ok"]


def test_db_loader_keeps_sheet_state_and_refuses_copies(db, tmp_path):
    import load_roundlist
    f = tmp_path / "rounds.csv"
    f.write_text(
        "startup_name,startup_website,country,round,round_date,source_url,added_by,added_at,status,taken_by,taken_at,notes\n"
        "Perry AI,https://useperry.com,United Kingdom,Seed,2026-11-18,https://p/1,external-research-bot-27,2026-11-19T21:00:00Z,done,bot-b,2026-11-19T21:17:54Z,Not in system: Antler\n"
        "Perry AI,useperry.com/,UK,seed,2026-11-18,https://p/2,external-research-bot-26,2026-11-19T22:00:00Z,open,,,\n"
        "Zya,https://zya.co,UK,Series A,2026-11-16,https://z/1,external-research-bot-27,2026-11-19T21:00:00Z,taken,bot-a,,\n"
        "Alecto,https://alectolegal.com,UK,Seed,2026-11-16,https://a/1,external-research-bot-27,2026-11-19T21:01:00Z,open,,,\n"
        ",https://x.io,UK,Seed,2026-11-16,https://x/1,b,2026-11-19T21:01:00Z,open,,,\n")
    dry = load_roundlist.main([str(f), "--database-url", URL])
    assert not dry["applied"] and dry["would_insert"] == 3
    assert db.execute("select count(*) from roundlist.rounds").fetchone()[0] == 0
    rep = load_roundlist.main([str(f), "--database-url", URL, "--apply"])
    assert rep["inserted"] == 3 and len(rep["refused_copies"]) == 1 and len(rep["skipped"]) == 1
    rows = dict((r[0], r[1:]) for r in db.execute(
        "select startup_name, status, taken_by, notes, added_by from roundlist.rounds").fetchall())
    assert rows["Perry AI"] == ("done", "bot-b", "Not in system: Antler", "external-research-bot-27")
    assert rows["Zya"][:2] == ("taken", "bot-a")      # taken_at missing -> load time, released after 2 hours
    assert rows["Alecto"][0] == "open"
    # bot-a still holds Zya from the sheet (1 of its 10) and gets Alecto next; Perry is done.
    a = claim(db, K1)
    assert a["round"]["startup_name"] == "Alecto" and a["held_count"] == 2
    assert claim(db, K2)["round"] is None
    again = load_roundlist.main([str(f), "--database-url", URL, "--apply"])
    assert again["inserted"] == 0 and len(again["refused_copies"]) == 4


def test_db_loader_backup_xlsx(db):
    xlsx = pathlib.Path("/workspace/regretamin-2026-deals-backup-20261119.xlsx")
    if not xlsx.exists():
        pytest.skip("backup export not on this machine")
    import load_roundlist
    rep = load_roundlist.main([str(xlsx), "--sheet", "26", "--database-url", URL, "--apply"])
    assert rep["rows_in_file"] == 699
    assert rep["inserted"] + len(rep["refused_copies"]) + len(rep["skipped"]) == 699


def test_db_teardown_removes_only_the_round_list(db):
    add(db, K1)
    before = db.execute("select count(*) from public.v2_bot_keys").fetchone()[0]
    db.execute(UNDO)
    assert db.execute("select to_regnamespace('roundlist')").fetchone()[0] is None
    for sig in ENTRY:
        assert db.execute("select to_regprocedure(%s)", (sig,)).fetchone()[0] is None
    assert db.execute("select count(*) from public.v2_bot_keys").fetchone()[0] == before
    assert db.execute("select to_regprocedure('public.v2_work_bot(uuid)')").fetchone()[0] is not None
    db.execute(UNDO)  # running it twice is fine
    db.execute(MIG)   # and the list can be built again
