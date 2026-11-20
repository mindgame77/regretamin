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
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
ENTRY = ("public.roundlist_add_round(uuid, jsonb)", "public.roundlist_claim_next_round(uuid)",
         "public.roundlist_finish_round(uuid, bigint, text, text)")
REFUSE_DONE = ("finish_round done refused: you have no accepted deal saved since you took this round. "
               "Save the deals first, or finish it as rejected with the reason.")
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


# ---------- database checks (local scratch Postgres only) ----------

SUB = """
create table if not exists public.v2_research_submissions (submission_id bigserial primary key, batch_id bigint,
  firm_id bigint, bot_key_id bigint, target_box text, payload jsonb, status text, received_at timestamptz default now());
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
        c.execute(MIG)
        yield c
        c.execute(UNDO)
        c.execute(WORK_UNDO)
        c.execute("drop schema bots cascade; drop table public.v2_research_submissions, public.v2_deals, "
                  "public.v2_startups, public.v2_bot_keys, public.v2_firms cascade")


def add(c, key, **kw):
    r = {"startup_name": "Acme", "startup_website": "https://acme.io", "country": "US", "round": "Seed",
         "round_date": "2026-11-10", "source_url": "https://news.example/acme"}
    r.update(kw)
    from psycopg.types.json import Jsonb
    return c.execute("select public.roundlist_add_round(%s, %s)", (key, Jsonb(r))).fetchone()[0]


def claim(c, key):
    return c.execute("select public.roundlist_claim_next_round(%s)", (key,)).fetchone()[0]


def finish(c, key, rid, result="done", note="saved 2 deals"):
    return c.execute("select public.roundlist_finish_round(%s, %s, %s, %s)", (key, rid, result, note)).fetchone()[0]


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


def test_db_claim_oldest_first_and_one_held_round_per_bot(db):
    r1 = add(db, K3, startup_name="One", startup_website="one.io")["round"]["round_id"]
    r2 = add(db, K3, startup_name="Two", startup_website="two.io")["round"]["round_id"]
    a = claim(db, K1)
    assert a["round"]["round_id"] == r1 and a["round"]["status"] == "taken" and not a["held"]
    again = claim(db, K1)
    assert again["held"] and again["round"]["round_id"] == r1
    b = claim(db, K2)
    assert b["round"]["round_id"] == r2
    assert claim(db, K3)["round"] is None


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


def test_db_same_bot_twice_at_once_gets_one_round(db):
    import psycopg
    for i in range(3):
        add(db, K3, startup_name=f"S{i}", startup_website=f"s{i}.io")
    out = []
    with psycopg.connect(URL) as ca:
        a = claim(ca, K1)  # holds the per-bot lock until commit
        t = threading.Thread(target=lambda: out.append(claim(psycopg.connect(URL, autocommit=True), K1)))
        t.start(); time.sleep(0.5)
        assert t.is_alive()  # waits for the first call
        ca.commit()
        t.join()
    assert out[0]["held"] and out[0]["round"]["round_id"] == a["round"]["round_id"]
    assert db.execute("select count(*) from roundlist.rounds where status = 'taken'").fetchone()[0] == 1


def test_db_done_needs_an_accepted_deal_since_the_claim(db):
    rid = add(db, K3)["round"]["round_id"]
    save_deal(db, K1, when="now() - interval '1 minute'")  # before the claim: does not count
    db.execute("select pg_sleep(0.01)")
    assert claim(db, K1)["round"]["round_id"] == rid
    r = finish(db, K1, rid)
    assert not r["ok"] and r["error"] == REFUSE_DONE
    save_deal(db, K1, status="Rejected: no source link (source_url)")  # rejected: does not count
    save_deal(db, K1, table="v2_people")                                 # not a deal: does not count
    save_deal(db, K2)                                                    # other bot: does not count
    assert finish(db, K1, rid)["error"] == REFUSE_DONE
    assert db.execute("select status from roundlist.rounds where round_id = %s", (rid,)).fetchone()[0] == "taken"
    assert "note is required" in finish(db, K1, rid, note="  ")["error"]
    assert "not held by you" in finish(db, K2, rid)["error"]
    save_deal(db, K1)
    ok = finish(db, K1, rid, note="Saved Founders Fund lead")
    assert ok["ok"] and ok["round"]["status"] == "done" and ok["round"]["notes"] == "Saved Founders Fund lead"
    assert finish(db, K1, rid)["already_finished"]
    # rejected needs only the note
    rid2 = add(db, K3, startup_name="Gone", startup_website="gone.io")["round"]["round_id"]
    assert claim(db, K2)["round"]["round_id"] == rid2
    rej = finish(db, K2, rid2, "rejected", "not a 2026 round")
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
    # bot-a still holds Zya from the sheet and gets it back; bot-b gets Alecto (Perry is done).
    assert claim(db, K1)["round"]["startup_name"] == "Zya"
    assert claim(db, K2)["round"]["startup_name"] == "Alecto"
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
