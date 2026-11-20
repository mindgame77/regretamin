"""Required lookup + duplicate-startup routing + accent-free lookup (migration 20261120090000_v2_required_lookup).

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local scratch Postgres
(host localhost, 127.0.0.1 or a socket) with the unaccent extension available. They build a small stand-in v2 schema
with the copies found on 2026-11-20, apply the lookup migration and this one, and drop everything again.
Never point it at production.
"""
import os
import pathlib
import re
from urllib.parse import urlparse

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261120090000_v2_required_lookup.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()
LOOKUP_MIG = (ROOT / "supabase/migrations/20261120060000_v2_research_lookup.sql").read_text()
LOOKUP_UNDO = (ROOT / "supabase/rollbacks/20261120060000_v2_research_lookup.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
URL = os.environ.get("V2_SCRATCH_DATABASE_URL", "").strip()
NEW_FNS = ("public.v2_lookup_fold(text)", "public.v2_site_base(text)", "public.v2_lookup_block_on()",
           "public.v2_startup_dup_route(text, text)", "public.v2_startup_guard(text, text)",
           "public.v2_firm_guard(uuid, text, text)",
           "public.v2_lookup_override_log(uuid, text, text, text, bigint[], text, bigint)")


def _code(sql):
    return "\n".join(l.split("--", 1)[0] for l in sql.splitlines())


def test_no_data_rows_changed_by_the_migration():
    code = _code(MIG[:MIG.index("CREATE OR REPLACE FUNCTION public.v2_research_submit")]).lower()
    # outside the (patched, existing) submit body the only writes are the new setting row and the overrides insert inside functions
    assert "update public.v2_startups" not in code and "update public.v2_deals" not in code and "update public.v2_firms" not in code
    assert "delete from" not in code and "truncate" not in code
    assert "insert into public.v2_work_setting (name, value) values (''lookup_block'', ''on'') on conflict (name) do nothing" in code


def test_server_only_and_rollback_drops_everything_new():
    code = _code(MIG)
    for fn in NEW_FNS:
        assert f"revoke all on function {fn} from public, anon, authenticated" in code
    assert code.count("grant execute") == 2
    assert "revoke all on table public.v2_lookup_overrides from public, anon, authenticated" in code
    undo = _code(UNDO)
    for fn in NEW_FNS:
        assert f"drop function if exists {fn};" in undo
    assert "drop table if exists public.v2_lookup_overrides;" in undo
    assert "delete from public.v2_work_setting where name = 'lookup_block';" in undo
    # the name index is dropped before v2_lookup_name is restored
    assert undo.index("drop index if exists public.v2_startups_lookup_name_idx") < undo.index("FUNCTION public.v2_lookup_name")
    for fn in ("v2_research_submit", "v2_lookup_name", "v2_research_lookup"):
        assert f"CREATE OR REPLACE FUNCTION public.{fn}(" in undo


def test_submit_patch_is_small_and_in_place():
    sub = MIG[MIG.index("CREATE OR REPLACE FUNCTION public.v2_research_submit"):]
    assert "public.v2_startup_dup_route(v_st_raw, v_st_host)" in sub
    assert "public.v2_startup_guard(p->>'startup_name', v_st_host)" in sub
    assert "public.v2_lookup_block_on()" in sub
    assert "'same_as', v_same_as" in sub
    assert "INSERT INTO public.v2_lookup_overrides" in sub
    # routing and guard run only when no live startup has the website, inside the new-startup branch
    i_match = sub.index("IF v_st_id IS NOT NULL THEN v_st_match := true; END IF;")
    assert i_match < sub.index("v2_startup_dup_route") < sub.index("v2_startup_guard")


def test_door_add_firm_guard_and_409():
    block = FN[FN.index('if (body.action === "add_firm")'):FN.index('if (body.action === "claim" && body.block === undefined)')]
    assert 'db.rpc("v2_firm_guard", { p_key: auth.key_id, p_name: fName, p_website: fSite })' in block
    assert "guard.block_on === true" in block and ", 409);" in block and "same_as: ids" in block
    assert block.index("v2_firm_guard") < block.index("v2_research_add_firm")
    assert 'db.rpc("v2_lookup_override_log"' in block
    assert "body.bot_id" not in block and "body.key" not in block
    assert "sameAs ? 409 : 422" in FN
    assert "notes, notes_ack, lookup, list_queue or verdict" in FN


# ---------- database checks (local scratch Postgres only) ----------

K1 = "11111111-1111-1111-1111-111111111111"
STUB = """
drop schema if exists bots cascade;
drop table if exists public.v2_firms, public.v2_startups, public.v2_work_setting, public.v2_bot_keys, public.v2_deals,
  public.v2_lookup_overrides cascade;
drop function if exists public.v2_research_submit(uuid, jsonb, boolean);
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema bots;
create table bots.ingest_keys (id uuid primary key, active boolean not null default true, bot_id text, key_hash text);
create table public.v2_firms (firm_id bigint primary key, display_name varchar, short_name varchar, legal_name varchar,
  website_url text, archived boolean default false);
create table public.v2_startups (startup_id bigint primary key, startup_name varchar, website_url text,
  is_current boolean default true, archived boolean default false, archive_reason text,
  domain text generated always as (lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\\.', '', 'i'), '/', 1))) stored);
create table public.v2_work_setting (name text primary key, value text, updated_at timestamptz default now());
create table public.v2_bot_keys (bot_key_id bigint primary key, bot_name text unique, key_hash text, frozen boolean, freeze_reason text, freeze_date timestamptz);
create table public.v2_deals (deal_id bigint primary key);
create function public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean default false) returns jsonb language sql as 'select null::jsonb';
"""
FIRMS = [
    (343, "RTP Global Management", None, "RTP Global Management LLC", "https://rtp.vc", False),
    (5019, "Trail Mix Ventures", None, None, "https://tmv.vc", False),
    (1253, "Entrée Capital", None, None, "https://entreecap.com", False),
    (11, "Founders Fund", None, None, "https://foundersfund.com", False),
    (4997, "TMV", None, None, "https://tmvcapital.com", True),
]
STARTUPS = [
    (5614, "Spiko", "https://spiko.io", False, None),
    (90673, "Spiko", "https://www.spiko.xyz/", True, "Duplicate of startup 5614 (merge 2026-11-20)"),
    (14, "Cognition", "https://cognition.com/", False, None),
    (21977, "Cognition", "https://cognition.ai/", True, "Duplicate of startup 14 (Cognition merge 2026-11-19)"),
    (181, "ElevenLabs", "https://elevenlabs.io", False, None),
    (84, "ElevenLabs", "https://eleven-labs.com", True, "Duplicate of startup_id 181 (ElevenLabs); merged 2026-11-04 per Alex"),
    (140903, "Cake.jp Co., Ltd.", "https://cake.jp/", False, None),
    (16503, "Omaze", "https://omaze.com/", False, None),
    (898, "Rain", "https://www.rain.xyz/", False, None),
    (16510, "Rain", "https://rain.ai/", False, None),
    (742, "Café Señor", "https://cafesenor.com", False, None),
    (77, "Gone", "https://gone.example", True, "Duplicate of startup 78 (x)"),
    (78, "Gone2", "https://gone2.example", True, "Checker rejected: wrong"),
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
        c.execute("insert into bots.ingest_keys (id, active, bot_id) values (%s, true, 'test-bot')", (K1,))
        for row in FIRMS:
            c.execute("insert into public.v2_firms values (%s, %s, %s, %s, %s, %s)", row)
        for row in STARTUPS:
            c.execute("insert into public.v2_startups(startup_id, startup_name, website_url, archived, archive_reason) values (%s, %s, %s, %s, %s)", row)
        c.execute(LOOKUP_MIG)
        c.execute(MIG)
        yield c
        c.execute(UNDO)
        c.execute(LOOKUP_UNDO)
        c.execute("drop schema bots cascade; drop table public.v2_firms, public.v2_startups, public.v2_work_setting, public.v2_bot_keys, public.v2_deals cascade;"
                  "drop function if exists public.v2_research_submit(uuid, jsonb, boolean)")


def one(c, sql, *args):
    return c.execute(sql, args).fetchone()[0]


def test_accents_ignored(db):
    assert one(db, "select public.v2_lookup_name('Entrée Capital', 'firm')") == "entree"
    r = one(db, "select public.v2_research_lookup(%s, 'firm', 'Entree Capital', null)", K1)
    assert r["matches"][0]["id"] == 1253 and r["matches"][0]["match_reason"] == "name"
    r = one(db, "select public.v2_research_lookup(%s, 'startup', 'Cafe Senor', null)", K1)
    assert r["matches"][0]["id"] == 742


@pytest.mark.parametrize("host,base", [
    ("spiko.io", "spiko"), ("www.spiko.xyz", "spiko"), ("corp.cake.jp", "cake"), ("omaze.co.uk", "omaze"),
    ("get.bidnamic.com", "bidnamic"), ("smarkets.com.br", "smarkets"), ("https://us.sulekha.com/x", "sulekha"), ("nodot", None)])
def test_site_base(db, host, base):
    assert one(db, "select public.v2_site_base(%s)", host) == base


def test_duplicate_routing(db):
    assert one(db, "select public.v2_startup_dup_route('spiko.xyz', 'spiko.xyz')") == 5614
    assert one(db, "select public.v2_startup_dup_route('cognition.ai', 'cognition.ai')") == 14
    assert one(db, "select public.v2_startup_dup_route('eleven-labs.com', 'eleven-labs.com')") == 181
    assert one(db, "select public.v2_startup_dup_route('gone.example', 'gone.example')") is None  # target archived for another reason
    assert one(db, "select public.v2_startup_dup_route('nothing.example', 'nothing.example')") is None


def test_startup_guard_strong_and_weak(db):
    g = one(db, "select public.v2_startup_guard('Cake.jp', 'corp.cake.jp')")
    assert g["strong"]["id"] == 140903  # "Cake.jp Co., Ltd." -> legal suffixes dropped, same base "cake"
    g = one(db, "select public.v2_startup_guard('Omaze', 'omaze.co.uk')")
    assert g["strong"]["id"] == 16503
    g = one(db, "select public.v2_startup_guard('Omaze', 'omaze-uk.org')")
    assert g["strong"] is None and [m["id"] for m in g["weak"]] == [16503]
    g = one(db, "select public.v2_startup_guard('Rain', 'rain.xyz')")
    assert g["strong"] is None and [m["id"] for m in g["weak"]] == [898, 16510]  # two older Rains -> only a warning
    g = one(db, "select public.v2_startup_guard('Spiko', 'spiko.fr')")
    assert g["strong"]["id"] == 5614  # archived copy 90673 is not counted


def test_firm_guard(db):
    g = one(db, "select public.v2_firm_guard(%s, 'RTP Global', 'rtp.global')", K1)
    assert g["ok"] and g["block_on"] and [m["id"] for m in g["strong"]] == [343]
    g = one(db, "select public.v2_firm_guard(%s, 'Entree Capital', 'entree.example')", K1)
    assert [m["id"] for m in g["strong"]] == [1253]
    g = one(db, "select public.v2_firm_guard(%s, 'Founders Fund Growth', 'ffg.example')", K1)
    assert g["strong"] == [] and [m["id"] for m in g["weak"]] == [11]
    g = one(db, "select public.v2_firm_guard(%s, 'TMV', 'tmvcapital.com')", K1)
    assert g["strong"] == []  # archived (merged) firms are not matched


def test_switch(db):
    assert one(db, "select public.v2_lookup_block_on()") is True
    db.execute("update public.v2_work_setting set value = 'off' where name = 'lookup_block'")
    assert one(db, "select public.v2_lookup_block_on()") is False
    assert one(db, "select public.v2_firm_guard(%s, 'RTP Global', 'rtp.global')", K1)["block_on"] is False
    db.execute("delete from public.v2_work_setting where name = 'lookup_block'")
    assert one(db, "select public.v2_lookup_block_on()") is True


def test_name_index_used_and_private(db):
    assert one(db, "select count(*) from pg_indexes where indexname = 'v2_startups_lookup_name_idx'") == 1
    assert one(db, "select has_function_privilege('anon', 'public.v2_firm_guard(uuid, text, text)', 'execute')") is False
    assert one(db, "select has_table_privilege('anon', 'public.v2_lookup_overrides', 'select')") is False
