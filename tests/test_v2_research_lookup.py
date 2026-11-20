"""lookup: read-only firm / startup search for research bots (migration 20261120060000_v2_research_lookup).

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local
scratch Postgres (host localhost, 127.0.0.1 or a socket). They build a small stand-in v2 schema with the
names bots missed on 2026-11-20, apply the migration, and drop everything again. Never point it at production.
"""
import os
import pathlib
import re
from urllib.parse import urlparse

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261120060000_v2_research_lookup.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
URL = os.environ.get("V2_SCRATCH_DATABASE_URL", "").strip()
SIG = "public.v2_research_lookup(uuid, text, text, text)"
HELPERS = ("public.v2_lookup_domain(text)", "public.v2_lookup_name(text, text)")


def _code(sql):
    return "\n".join(l.split("--", 1)[0] for l in sql.splitlines())


def test_read_only_no_tables_no_writes():
    code = _code(MIG).lower()
    for word in ("insert ", "update ", "delete ", "truncate ", "create table", "create index", "alter table", "drop "):
        assert word not in code, word
    assert re.findall(r"create or replace function (public\.\w+)", code) == [
        "public.v2_lookup_domain", "public.v2_lookup_name", "public.v2_research_lookup"]
    assert "stable\n security definer" in code and code.count("immutable") == 2
    assert "bots.ingest_keys k where k.id = p_key and k.active" in code
    assert "not coalesce(f.archived, false)" in code and "s.is_current and not coalesce(s.archived, false)" in code


def test_server_only_and_rollback_drops_all_three():
    code = _code(MIG)
    for fn in (SIG,) + HELPERS:
        assert f"revoke all on function {fn} from public, anon, authenticated" in code
    assert f"grant execute on function {SIG} to service_role" in code
    assert code.count("grant execute") == 1
    undo = _code(UNDO)
    for fn in (SIG,) + HELPERS:
        assert f"drop function if exists {fn};" in undo


def test_door_routes_lookup_from_the_key():
    block = FN[FN.index('if (body.action === "lookup")'):FN.index("// Round list (schema roundlist")]
    assert 'db.rpc("v2_research_lookup", { p_key: auth.key_id, p_kind: kind, p_name: name, p_website: website })' in block
    assert "body.bot_id" not in block and "body.key" not in block
    assert ".from(" not in block
    hint = FN[FN.index("const HINT"):FN.index(";", FN.index("const HINT"))]
    assert '\\"action\\":\\"lookup\\"' in hint
    assert "notes, notes_ack, lookup, list_queue or verdict" in FN


# ---------- database checks (local scratch Postgres only) ----------

K1, K_OFF = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"
STUB = """
drop schema if exists bots cascade;
drop table if exists public.v2_firms, public.v2_startups cascade;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema bots;
create table bots.ingest_keys (id uuid primary key, active boolean not null default true);
create table public.v2_firms (firm_id bigint primary key, display_name varchar, short_name varchar, legal_name varchar,
  website_url text, archived boolean default false);
create table public.v2_startups (startup_id bigint primary key, startup_name varchar, website_url text,
  is_current boolean default true, archived boolean default false,
  domain text generated always as (lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\\.', '', 'i'), '/', 1))) stored);
"""
FIRMS = [
    (2543, "All Aboard", None, None, "https://allaboard.vc/", False),
    (5148, "Wayfinder Ventures", None, None, "https://www.wayfinder.com/", False),
    (3398, "Animal Capital", None, None, "https://animalcapital.com/", False),
    (672, "Endeavor Catalyst", None, None, "https://endeavor.org", False),
    (4966, "The Catalyst", None, None, "https://thecatalystfund.com", False),
    (2342, "HV Capital", None, None, "https://hvcapital.com", False),
    (1626, "Bpifrance", None, None, "https://www.bpifrance.fr", False),
    (2, "Andreessen Horowitz", "a16z", None, "https://a16z.com", False),
    (9001, "All Aboard Old", None, None, "https://old.example", True),
    (9002, "Pointer Capital", None, None, "https://pointer.example", False),
]
STARTUPS = [
    (91313, "Rivercell", "https://www.rivercell.ai/", True, False),
    (898, "Rain", "https://www.rain.xyz/", True, False),
    (109850, "Rain", "https://www.raincards.xyz/", True, False),
    (16510, "Rain AI", "https://rain.ai/", True, False),
    (5000, "Terrain", "https://terrain.example", True, False),
    (5001, "Rivercell", "https://old-rivercell.example", False, False),
    (742, "Mistral AI", "https://mistral.ai", True, False),
]


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
        c.execute("insert into bots.ingest_keys values (%s, true), (%s, false)", (K1, K_OFF))
        for row in FIRMS:
            c.execute("insert into public.v2_firms values (%s, %s, %s, %s, %s, %s)", row)
        for row in STARTUPS:
            c.execute("insert into public.v2_startups(startup_id, startup_name, website_url, is_current, archived) values (%s, %s, %s, %s, %s)", row)
        c.execute(MIG)
        yield c
        c.execute(UNDO)
        c.execute("drop schema bots cascade; drop table public.v2_firms, public.v2_startups cascade")


def look(c, kind, name=None, website=None, key=K1):
    return c.execute("select public.v2_research_lookup(%s, %s, %s, %s)", (key, kind, name, website)).fetchone()[0]


def ids(r):
    return [(m["id"], m["match_reason"]) for m in r["matches"]]


@pytest.mark.parametrize("name,website,want", [
    ("All Aboard Fund", None, (2543, "name")),
    ("Wayfinder", None, (5148, "name")),
    ("Animal Capital", "animalcapital.com", (3398, "website")),
    ("Endeavor Catalyst", None, (672, "name")),
    ("HV Capital", None, (2342, "name")),
    ("Bpifrance", None, (1626, "name")),
    ("Bpi France", None, (1626, "name")),
    ("a16z", None, (2, "short name")),
    (None, "https://WWW.allaboard.vc:443/team?x=1", (2543, "website")),
    ("Something Else", "allaboard.vc.", (2543, "website")),
])
def test_firms_bots_missed_are_found_first(db, name, website, want):
    r = look(db, "firm", name, website)
    assert r["ok"] and r["found"] and ids(r)[0] == want


def test_firm_not_in_system_is_empty_and_archived_is_skipped(db):
    for name in ("Point72", "Leaps by Bayer"):
        r = look(db, "firm", name)
        assert r["ok"] and not r["found"] and r["matches"] == [] and r["total"] == 0
    assert 9001 not in [m["id"] for m in look(db, "firm", "All Aboard Old")["matches"]]


def test_partial_names_rank_after_exact(db):
    r = look(db, "firm", "Endeavor Catalyst")
    assert ids(r) == [(672, "name"), (4966, "partial name")]
    assert ids(look(db, "startup", "Mistral")) == [(742, "partial name")]


def test_startups(db):
    assert ids(look(db, "startup", "Rivercell", "rivercell.ai")) == [(91313, "website")]
    assert ids(look(db, "startup", "Rivercell")) == [(91313, "name")]  # old row 5001 is not is_current
    r = look(db, "startup", "Rain", "rain.xyz")
    assert ids(r) == [(898, "website"), (109850, "name"), (16510, "partial name")]  # word match: no "Terrain"
    assert ids(look(db, "startup", None, "raincards.xyz")) == [(109850, "website")]


def test_at_most_five_with_total(db):
    for i in range(8):
        db.execute("insert into public.v2_firms values (%s, %s, null, null, null, false)", (8000 + i, f"Pointer Partners {i}"))
    r = look(db, "firm", "Pointer")
    assert len(r["matches"]) == 5 and r["total"] == 9


def test_refusals(db):
    assert look(db, "firm", "All Aboard", key=K_OFF) == {"ok": False, "error": "unauthorized"}
    assert look(db, "person", "x")["error"] == "send a firm or a startup"
    assert look(db, "firm")["error"] == "send a name or a website"
    assert look(db, "firm", "!!!")["error"] == "send a name or a website"
    assert look(db, "firm", None, "not a site")["error"] == "website is not a valid domain, and no name was sent"
    assert look(db, "firm", "x" * 201)["ok"] is False


def test_no_rows_change(db):
    before = db.execute("select md5(string_agg(t::text, ',' order by firm_id)) from public.v2_firms t").fetchone()[0]
    look(db, "firm", "All Aboard Fund", "allaboard.vc")
    assert db.execute("select md5(string_agg(t::text, ',' order by firm_id)) from public.v2_firms t").fetchone()[0] == before
    assert db.execute("select has_function_privilege('anon', %s, 'execute')", (SIG,)).fetchone()[0] is False
