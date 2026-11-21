"""Founders stored by research bots, plus the separate founder hand-out list.

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local
scratch Postgres (host localhost, 127.0.0.1 or a socket). They build the small stand-in v2 schema from
test_v2_work_claims, apply the migrations, and drop everything again. Never point it at production.
"""
import pathlib
import re
import threading
import time

import pytest

from test_v2_work_claims import K1, K2, K3, URL, _local
from test_v2_work_claims import SQL as WORK_SQL, UNDO as WORK_UNDO

ROOT = pathlib.Path(__file__).resolve().parents[1]
FNAME = "20261121010000_v2_founders.sql"
LNAME = "20261121020000_founderlist.sql"
MIG = (ROOT / "supabase/migrations" / FNAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / FNAME).read_text()
LIST = (ROOT / "supabase/migrations" / LNAME).read_text()
LIST_UNDO = (ROOT / "supabase/rollbacks" / LNAME).read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
REFUSE_DONE = ("finish_founder_startup done refused: you have no founder role saved for this startup since you took it. "
               "Save the founders with add_founder first, or finish it as rejected with the reason.")


def _code(sql):
    return "\n".join(l.split("--", 1)[0] for l in sql.splitlines())


def test_founders_link_only_to_startups_and_keep_the_rules():
    code = _code(MIG)
    low = code.lower()
    assert "create table if not exists public.v2_founders" in low
    assert "create table if not exists public.v2_founder_facts" in low
    assert low.count("references ") == 2
    assert "references public.v2_startups (startup_id) on delete restrict" in low
    assert "references public.v2_founders (founder_id) on delete cascade" in low
    for banned in ("v2_firms", "v2_deals", "v2_people", "v2_reviews"):
        assert banned not in low, banned
    assert "v2 schema missing, skipped" in MIG
    assert "unique index if not exists v2_founders_linkedin_uq" in low
    assert "v2_founder_facts_no_copies unique nulls not distinct" in low
    assert "fact <> 'role' or startup_id is not null" in low
    assert "value ~ '^[A-Z]{2}$'" in code
    assert "^(yes|no)(: \\S.*)?$" in code
    assert "No year" in code
    assert "a founder must have at least one role fact" in low
    assert "deferrable initially deferred" in low
    for word in ("founded_year", "year_founded", "from_year", "to_year"):
        assert word not in low
    alters = re.findall(r"alter table (\S+)", low)
    assert set(alters) <= {"public.v2_founders", "public.v2_founder_facts"}
    assert "update public.v2_startups" not in low and "insert into public.v2_startups" not in low


def test_founderlist_is_separate_and_deletable():
    code = _code(LIST).lower()
    assert "create schema if not exists founderlist" in code
    assert " references " not in code and "foreign key" not in code
    assert "v2_deals" not in code and "v2_firms" not in code and "v2_startups" not in code
    assert "public.v2_founder_facts" in code and "public.v2_work_bot" in code
    assert "insert into founderlist.startups" not in code  # the seed query is not executed here
    assert "interval '2 hours'" in code
    assert "status in ('open', 'taken', 'done', 'rejected')" in code
    assert "constraint founderlist_one_startup unique (startup_id)" in code
    assert "drop schema if exists founderlist cascade;" in LIST_UNDO
    assert "drop table if exists public.v2_founders" not in LIST_UNDO.lower()
    assert "run supabase/rollbacks/20261121020000_founderlist.sql first" in UNDO
    assert "drop table if exists public.v2_founder_facts;" in UNDO
    assert "drop table if exists public.v2_founders;" in UNDO
    assert "v2_startups" not in _code(UNDO).lower()


def test_door_routes_founder_actions_from_the_key():
    assert 'db.rpc("v2_founder_add", {' in FN
    assert "p_key_id: auth.key_id, p_startup_id: body.startup_id" in FN
    assert 'db.rpc("v2_founder_lookup", { p_key: auth.key_id, p_name: name, p_linkedin: linkedin })' in FN
    assert '"founderlist_claim_next_founder_startups"' in FN
    assert '"founderlist_finish_founder_startup"' in FN
    block = FN[FN.index('body.action === "add_founder"'):FN.index('body.action !== "submit"')]
    assert "body.bot_id" not in block
    assert "notes, notes_ack, lookup, list_queue or verdict" in FN
    assert "add_founder, claim_next_founder_startups or finish_founder_startup" in FN


# ---------- database checks (local scratch Postgres only) ----------

STUB = """
drop schema if exists bots cascade;
drop schema if exists founderlist cascade;
drop table if exists public.v2_founder_facts, public.v2_founders, public.v2_work_claims, public.v2_deals,
  public.v2_startups, public.v2_bot_keys, public.v2_firms cascade;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema bots;
create table bots.ingest_keys (id uuid primary key, name text, key_hash text, active boolean not null default true, bot_id text);
create table public.v2_firms (firm_id bigint primary key, slug text, display_name text, website_url text, archived boolean default false, hq_country text default 'US');
create table public.v2_startups (startup_id bigint primary key, startup_name varchar, website_url text, is_current boolean default true, archived boolean default false);
create table public.v2_bot_keys (bot_key_id bigserial primary key, bot_name text unique not null, key_hash text,
  frozen boolean not null default false, freeze_date timestamptz, freeze_reason text, freeze_count_7d int);
create table public.v2_deals (deal_id bigserial primary key, firm_id bigint, startup_id bigint, round text, deal_date date,
  is_current boolean default true, archived boolean default false, nothing_found boolean);
"""


@pytest.fixture()
def db():
    if not URL:
        pytest.skip("V2_SCRATCH_DATABASE_URL is not set")
    if not _local(URL):
        pytest.skip("V2_SCRATCH_DATABASE_URL must be a local scratch database")
    import psycopg
    with psycopg.connect(URL, autocommit=True) as c:
        c.execute(LIST_UNDO)
        c.execute(UNDO)
        c.execute(WORK_UNDO)
        c.execute(STUB)
        for k, b in ((K1, "bot-a"), (K2, "bot-b"), (K3, "bot-c")):
            c.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values (%s, %s, %s)", (k, "h-" + b, b))
        for sid, name, site in ((10, "Analytical Engines", "https://ae.example"),
                                (11, "Ada Labs", "https://adalabs.example"),
                                (12, "Empty Co", "https://empty.example")):
            c.execute("insert into public.v2_startups(startup_id, startup_name, website_url) values (%s, %s, %s)", (sid, name, site))
        c.execute(WORK_SQL)
        c.execute(MIG)
        c.execute(LIST)
        yield c
        c.execute(LIST_UNDO)
        c.execute(UNDO)
        c.execute(WORK_UNDO)
        c.execute("drop schema bots cascade; drop table if exists public.v2_deals, public.v2_startups, public.v2_bot_keys, public.v2_firms cascade")


def add(c, key=K1, startup=10, founder=None, role=None, facts=None):
    from psycopg.types.json import Jsonb
    if founder is None:
        founder = {"name": "Ada Lovelace", "linkedin_url": "https://www.linkedin.com/in/ada"}
    if role is None:
        role = {"value": "CEO", "source_url": "https://example.com/ada"}
    if facts is None:
        facts = []
    return c.execute(
        "select public.v2_founder_add(%s, %s, %s, %s, %s)",
        (key, startup, Jsonb(founder), Jsonb(role), Jsonb(facts)),
    ).fetchone()[0]


def look(c, name=None, linkedin=None, key=K1):
    return c.execute("select public.v2_founder_lookup(%s, %s, %s)", (key, name, linkedin)).fetchone()[0]


def claim(c, key, count=1):
    return c.execute("select public.founderlist_claim_next_founder_startups(%s, %s)", (key, count)).fetchone()[0]


def finish(c, key, startup_id, result="done", note="saved the founders"):
    return c.execute(
        "select public.founderlist_finish_founder_startup(%s, %s, %s, %s)",
        (key, startup_id, result, note),
    ).fetchone()[0]


def seed_list(c, n, first=1000):
    ids = []
    for i in range(n):
        sid = first + i
        c.execute("insert into public.v2_startups(startup_id, startup_name, website_url) values (%s, %s, %s)",
                  (sid, f"Startup {sid}", f"https://s{sid}.example"))
        c.execute("insert into founderlist.startups(startup_id, startup_name, startup_website, added_by) values (%s, %s, %s, 'seed')",
                  (sid, f"Startup {sid}", f"https://s{sid}.example"))
        ids.append(sid)
    return ids


def test_db_add_rules_reuse_and_no_duplicate_facts(db):
    bad = add(db, startup=99)
    assert bad["error"] == "startup_id 99 not found" and db.execute("select count(*) from public.v2_founders").fetchone()[0] == 0
    assert "role source_url" in add(db, role={"value": "CEO"})["error"]
    assert "unknown fact type 'salary'" in add(db, facts=[{"fact": "salary", "value": "1", "source_url": "https://x"}])["error"]
    assert add(db, facts=[{"fact": "past_job", "source_url": "https://x"}])["error"] == "past_job needs a company name in value"
    assert "2-letter country code" in add(db, facts=[{"fact": "current_country", "value": "USA", "source_url": "https://x"}])["error"]
    assert "source_url" in add(db, facts=[{"fact": "current_city", "value": "London"}])["error"]
    assert "company_website is only for past_job" in add(db, facts=[{"fact": "current_city", "value": "London", "company_website": "https://x", "source_url": "https://x"}])["error"]
    assert "founded_before" in add(db, facts=[{"fact": "founded_before", "value": "maybe", "source_url": "https://x"}])["error"]
    # A bad fact in the same call writes nothing.
    assert not add(db, facts=[{"fact": "current_city", "value": "London", "source_url": "https://x"},
                              {"fact": "current_country", "value": "England", "source_url": "https://x"}])["ok"]
    assert db.execute("select count(*) from public.v2_founders").fetchone()[0] == 0

    saved = add(db, facts=[
        {"fact": "current_city", "value": "London", "source_url": "https://example.com/ada"},
        {"fact": "current_country", "value": "gb", "source_url": "https://example.com/ada"},
        {"fact": "previous_country", "value": "FR", "source_url": "https://example.com/ada"},
        {"fact": "past_job", "value": "Babbage Co", "company_website": "https://babbage.example", "source_url": "https://news.example/ada"},
        {"fact": "founded_before", "value": "Yes: Analytical Kids", "source_url": "https://news.example/ada"},
        {"fact": "university", "value": "University of London", "source_url": "https://news.example/ada"},
    ])
    assert saved["ok"] and saved["created"] and saved["founder"]["name"] == "Ada Lovelace"
    assert saved["role"]["startup_id"] == 10 and saved["role"]["skipped"] is False
    countries = dict(db.execute("select fact, value from public.v2_founder_facts where fact like '%country'").fetchall())
    assert countries == {"current_country": "GB", "previous_country": "FR"}
    assert db.execute("select value from public.v2_founder_facts where fact = 'founded_before'").fetchone()[0] == "yes: Analytical Kids"
    # Same LinkedIn, other spelling: refused, with the id to reuse.
    dup = add(db, K2, startup=11, founder={"name": "Someone Else", "linkedin_url": "http://linkedin.com/in/ada/"})
    assert not dup["ok"] and dup["duplicate"] and dup["founder_id"] == saved["founder_id"]
    assert "send founder_id" in dup["error"]
    # Reuse that person at a second startup. The same city is not stored again. The name stays as first written.
    again = add(db, K2, startup=11, founder={"founder_id": saved["founder_id"], "name": "Ada King"},
                role={"value": "Founder", "source_url": "https://adalabs.example/team"},
                facts=[{"fact": "current_city", "value": "london", "source_url": "https://adalabs.example/team"}])
    assert again["ok"] and again["created"] is False and again["founder"]["name"] == "Ada Lovelace"
    assert again["role"]["value"] == "Founder" and again["skipped"][0]["fact"] == "current_city"
    roles = db.execute("select startup_id, value from public.v2_founder_facts where fact = 'role' order by startup_id").fetchall()
    assert roles == [(10, "CEO"), (11, "Founder")]
    # A startup may have nobody. Empty Co has no founder row.
    assert db.execute("select count(*) from public.v2_founder_facts where startup_id = 12").fetchone()[0] == 0
    # Same normalized name, no LinkedIn: a different person is allowed.
    other = add(db, K2, startup=12, founder={"name": "ada lovelace"}, role={"source_url": "https://empty.example/team"})
    assert other["ok"] and other["created"] and other["founder_id"] != saved["founder_id"]


def test_db_lookup_matches_linkedin_then_name_with_startups_and_jobs(db):
    jose = add(db, founder={"name": "José Müller", "linkedin_url": "https://www.linkedin.com/in/Jose-Muller/"},
               facts=[{"fact": "past_job", "value": "Babbage Co", "source_url": "https://news.example/j"}])
    add(db, K2, startup=11, founder={"founder_id": jose["founder_id"]}, role={"value": "Founder", "source_url": "https://adalabs.example/team"})
    by_name = look(db, "jose   muller")
    assert by_name["found"] and by_name["matches"][0]["match_reason"] == "name"
    assert by_name["matches"][0]["past_jobs"] == ["Babbage Co"]
    assert by_name["matches"][0]["startups"] == [{"id": 10, "name": "Analytical Engines"}, {"id": 11, "name": "Ada Labs"}]
    by_link = look(db, "nobody", "https://uk.linkedin.com/in/jose-muller?trk=1")
    assert by_link["matches"][0]["match_reason"] == "linkedin" and by_link["matches"][0]["founder_id"] == jose["founder_id"]
    assert look(db, "No Such Person")["matches"] == [] and look(db, "No Such Person")["found"] is False
    assert "LinkedIn profile" in look(db, linkedin="https://linkedin.com/company/acme")["error"]
    # Six people with one name: total is 6, the reply keeps 5, a LinkedIn hit is first.
    for i in range(6):
        add(db, K3, startup=12, founder={"name": "Sam Lee", "linkedin_url": f"https://www.linkedin.com/in/sam-lee-{i}"},
            role={"source_url": "https://empty.example/team"},
            facts=[{"fact": "past_job", "value": f"Co {i}", "source_url": "https://empty.example/team"}])
    both = look(db, "Sam Lee", "https://www.linkedin.com/in/jose-muller")
    assert both["total"] == 7 and len(both["matches"]) == 5
    assert both["matches"][0]["match_reason"] == "linkedin" and both["matches"][0]["name"] == "José Müller"
    assert all(m["match_reason"] == "name" for m in both["matches"][1:])


def test_db_a_founder_always_has_a_role_and_a_startup_delete_is_blocked(db):
    import psycopg
    saved = add(db)
    with pytest.raises(psycopg.errors.CheckViolation):
        db.execute("insert into public.v2_founders(name, added_by) values ('Ghost', 'bot-a')")
    db.execute("delete from public.v2_founder_facts where founder_id = %s and fact <> 'role'", (saved["founder_id"],))
    with pytest.raises(psycopg.errors.CheckViolation):
        db.execute("delete from public.v2_founder_facts where founder_id = %s and fact = 'role'", (saved["founder_id"],))
    assert db.execute("select count(*) from public.v2_founder_facts where fact = 'role' and founder_id = %s", (saved["founder_id"],)).fetchone()[0] == 1
    with pytest.raises(psycopg.errors.ForeignKeyViolation):
        db.execute("delete from public.v2_startups where startup_id = 10")
    db.execute("delete from public.v2_startups where startup_id = 12")  # no founders
    assert db.execute("select count(*) from public.v2_startups where startup_id = 12").fetchone()[0] == 0
    db.execute("delete from public.v2_founders where founder_id = %s", (saved["founder_id"],))
    assert db.execute("select count(*) from public.v2_founder_facts").fetchone()[0] == 0
    db.execute("delete from public.v2_startups where startup_id = 10")


def test_db_claim_cap_count_and_done_needs_a_role_since_the_claim(db):
    ids = seed_list(db, 14)
    first = claim(db, K1)
    assert first["startup"]["startup_id"] == ids[0] and first["held_count"] == 1 and first["max_held"] == 10
    assert first["startup"]["startup_name"] == "Startup 1000"
    # A role saved before the claim does not count.
    early = add(db, startup=ids[1], founder={"name": "Early", "linkedin_url": "https://www.linkedin.com/in/early"})
    assert early["ok"]
    assert claim(db, K1)["startup"]["startup_id"] == ids[1]
    refused = finish(db, K1, ids[1])
    assert refused["error"] == REFUSE_DONE
    # Another bot's role after the claim does not count either.
    assert add(db, K2, startup=ids[1], founder={"name": "Other Bot"})["ok"]
    assert finish(db, K1, ids[1])["error"] == REFUSE_DONE
    assert add(db, startup=ids[1], founder={"founder_id": early["founder_id"]},
               role={"value": "Co-founder", "source_url": "https://s.example/team"})["ok"]
    done = finish(db, K1, ids[1], note="saved Early")
    assert done["ok"] and done["startup"]["status"] == "done" and done["startup"]["notes"] == "saved Early"
    assert finish(db, K1, ids[1])["already_finished"] is True
    for i in range(2, 10):
        assert claim(db, K1)["startup"]["startup_id"] == ids[i]
    # Held: the first (still taken) plus 2..9. ids[1] was finished. That is 9. One more fills 10.
    assert claim(db, K1)["startup"]["startup_id"] == ids[10]
    full = claim(db, K1)
    assert not full["ok"] and full["held_count"] == 10
    assert full["error"].startswith("you already hold 10 startups")
    assert claim(db, K2)["startup"]["startup_id"] == ids[11]
    assert finish(db, K1, ids[0], "rejected", "no public founders")["ok"]
    nxt = claim(db, K1)
    assert nxt["claimed_count"] == 1 and nxt["startup"]["startup_id"] == ids[12] and nxt["held_count"] == 10
    three = claim(db, K3, 3)
    assert three["claimed_count"] == 1 and three["startup"]["startup_id"] == ids[13]  # one left
    for bad in (0, 11, -1):
        assert claim(db, K3, bad)["error"] == "count must be 1-10"
    assert "note is required" in finish(db, K2, ids[11], note="  ")["error"]
    assert "not held by you" in finish(db, K1, ids[11])["error"]


def test_db_hold_expires_on_its_own_and_frozen_keys_are_refused(db):
    import psycopg
    ids = seed_list(db, 4)
    assert claim(db, K1)["startup"]["startup_id"] == ids[0]
    db.execute("update founderlist.startups set taken_at = now() - interval '2 hours 1 minute' where startup_id = %s", (ids[0],))
    nxt = claim(db, K2)
    assert nxt["startup"]["startup_id"] == ids[0] and nxt["startup"]["taken_by"] == "bot-b"
    assert "not held by you" in finish(db, K1, ids[0], "rejected", "too late")["error"]
    assert db.execute("select detail->>'was_taken_by' from founderlist.events where action = 'released'").fetchone()[0] == "bot-a"
    # Of two held rows, only the one past 2 hours goes back.
    assert claim(db, K1, 2)["claimed_count"] == 2
    db.execute("update founderlist.startups set taken_at = now() - interval '2 hours 5 minutes' where startup_id = %s", (ids[1],))
    held = claim(db, K1)
    assert held["claimed_count"] == 1 and held["startup"]["startup_id"] == ids[1] and ids[2] in held["held_startup_ids"]
    assert claim(db, K3)["ok"]  # first call creates the bot row
    db.execute("update public.v2_bot_keys set frozen = true, freeze_reason = 'test', freeze_date = now() where bot_name = 'bot-c'")
    assert claim(db, K3)["error"].startswith("Key frozen")
    assert add(db, K3)["error"].startswith("Key frozen")
    for role in ("anon", "authenticated"):
        for sql in ("select * from public.v2_founders", "delete from public.v2_founder_facts",
                    "select * from founderlist.startups",
                    f"select public.v2_founder_add('{K1}', 10, '{{}}'::jsonb, '{{}}'::jsonb, '[]'::jsonb)",
                    f"select public.founderlist_claim_next_founder_startups('{K1}', 1)"):
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                with db.transaction():
                    db.execute(f"set local role {role}")
                    db.execute(sql)
    with db.transaction():
        db.execute("set local role service_role")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with db.transaction():
                db.execute("delete from public.v2_founders")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            with db.transaction():
                db.execute("delete from founderlist.startups")
        assert claim(db, K1)["ok"]


def test_db_claim_race_and_one_bot_never_holds_more_than_10(db):
    import psycopg
    ids = seed_list(db, 30)
    with psycopg.connect(URL) as ca, psycopg.connect(URL) as cb:
        a = claim(ca, K1)
        b = claim(cb, K2)
        assert a["startup"]["startup_id"] == ids[0] and b["startup"]["startup_id"] == ids[1]
        ca.commit(); cb.commit()
    # A second call from the same bot waits for the lock, then gets the next row.
    out = []
    with psycopg.connect(URL) as ca:
        claim(ca, K1)
        t = threading.Thread(target=lambda: out.append(claim(psycopg.connect(URL, autocommit=True), K1)))
        t.start(); time.sleep(0.4)
        assert t.is_alive()
        ca.commit()
        t.join()
    assert out[0]["ok"] and out[0]["held_count"] == 3
    # Fill to 10, then parallel calls are refused rather than going over.
    assert claim(db, K1, 7)["claimed_count"] == 7
    assert claim(db, K1)["held_count"] == 10
    res, gate = [], threading.Barrier(6)

    def run():
        with psycopg.connect(URL, autocommit=True) as c:
            gate.wait()
            res.append(claim(c, K1, 1))
    ts = [threading.Thread(target=run) for _ in range(6)]
    [t.start() for t in ts]; [t.join() for t in ts]
    assert all(not r["ok"] and r["held_count"] == 10 for r in res)
    held = db.execute("select count(*) from founderlist.startups where status = 'taken' and taken_by = 'bot-a'").fetchone()[0]
    assert held == 10


def test_db_teardown_removes_the_list_then_the_founders(db):
    add(db)
    seed_list(db, 1)
    before = db.execute("select count(*) from public.v2_startups").fetchone()[0]
    db.execute(LIST_UNDO)
    assert db.execute("select to_regnamespace('founderlist')").fetchone()[0] is None
    assert db.execute("select count(*) from public.v2_founders").fetchone()[0] == 1
    db.execute(UNDO)
    assert db.execute("select to_regclass('public.v2_founders')").fetchone()[0] is None
    assert db.execute("select to_regclass('public.v2_founder_facts')").fetchone()[0] is None
    assert db.execute("select count(*) from public.v2_startups").fetchone()[0] == before
    db.execute(UNDO)
    db.execute(MIG)
    db.execute(LIST)
    assert db.execute("select to_regclass('public.v2_founders')").fetchone()[0] is not None
    assert db.execute("select to_regnamespace('founderlist')").fetchone()[0] is not None


def test_migration_is_a_no_op_without_v2(db):
    # db is only used to know the scratch URL is local. This check uses its own empty database name via a temp schema? 
    # Drop the v2 pieces inside a transaction and apply; the migration notices and changes nothing.
    db.execute("begin")
    try:
        db.execute(LIST_UNDO)
        db.execute(UNDO)
        db.execute("drop function public.v2_work_bot(uuid)")
        db.execute(MIG)
        db.execute(LIST)
        assert db.execute("select to_regclass('public.v2_founders')").fetchone()[0] is None
        assert db.execute("select to_regnamespace('founderlist')").fetchone()[0] is None
    finally:
        db.execute("rollback")
