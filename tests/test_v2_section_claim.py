"""Section claim is additive. Plain claim, done, and submit stay. Existing bot keys are not rewritten."""
import os
import pathlib
import shutil
import subprocess
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261117210000_v2_section_claim.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261117210000_v2_section_claim.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def test_migration_is_additive_and_uses_the_stored_deal_count():
    low = MIG.lower()
    assert "create table if not exists public.v2_section_holds" in low
    assert "section in ('legal', 'reviews', 'youtube')" in low
    assert "primary key (firm_id, section)" in low
    assert "order by s.deals desc, s.firm_id" in low
    assert "firm_summary_listed_deals_idx" in low
    assert "for update of f skip locked" in low
    assert "interval '6 hours'" in low
    assert "nothing_found needs the searches in note" in MIG
    assert "legal nothing_found needs source_level 1" in MIG
    assert "table public.v2_research_assignments" not in low
    assert "function public.v2_research_claim" not in low
    assert "function public.v2_research_done" not in low
    assert "function public.v2_firm_page" not in low
    assert "alter table public.v2_bot_keys" not in low
    assert "alter table bots.ingest_keys" not in low
    assert "v2_search" not in low
    assert "aum" not in low
    assert "to_regclass('public.v2_firms') is null" in low
    assert "enable row level security" in low
    assert "revoke all on function public.v2_section_claim(uuid, text) from public, anon, authenticated" in low
    assert "grant execute on function public.v2_section_claim(uuid, text) to service_role" in low
    # An existing key row is only read. A missing row is inserted. It is not updated.
    assert "do update set key_hash" not in low
    assert "where bot_name = v_bot" in low


def test_rollback_drops_the_new_pieces_and_restores_submit():
    low = UNDO.lower()
    assert "drop function if exists public.v2_section_claim(uuid, text)" in low
    assert "drop function if exists public.v2_section_done(uuid, text, bigint)" in low
    assert "drop table if exists public.v2_section_holds" in low
    assert "drop index if exists public.firm_summary_listed_deals_idx" in low
    assert "v2_reviews_found_content_ck" in low
    assert "nothing_found needs the searches in note" in UNDO
    assert "staff and investment staff are not accepted" in low
    assert "function public.v2_research_claim" not in low
    assert "table public.v2_research_assignments" not in low


def test_edge_keeps_plain_claim_and_routes_a_block_with_the_same_key():
    assert 'body.action === "claim" && body.block === undefined' in FN
    assert 'body.action === "done" && body.block === undefined' in FN
    assert 'db.rpc("v2_research_claim"' in FN
    assert 'db.rpc("v2_research_done"' in FN
    assert 'db.rpc("v2_section_claim"' in FN
    assert 'db.rpc("v2_section_done"' in FN
    assert 'db.rpc("v2_research_submit"' in FN
    assert "action must be submit, add_firm, claim, done, results, deals, next_firm, firm_done, list_queue or verdict" in FN
    plain = FN.index('body.action === "claim" && body.block === undefined')
    section = FN.index('db.rpc("v2_section_claim"')
    done = FN.index('body.action === "done" && body.block === undefined')
    submit = FN.index('db.rpc("v2_research_submit"')
    assert plain < section < done < submit
    claim_block = FN[plain:section]
    assert "p_key_id: auth.key_id" in claim_block
    assert "p_section" not in claim_block
    assert "from(\"firms\")" not in FN


def test_deno_section_routes():
    deno = shutil.which("deno") or str(pathlib.Path.home() / ".deno/bin/deno")
    if not pathlib.Path(deno).exists():
        pytest.skip("deno is not installed")
    r = subprocess.run(
        [deno, "test", "-A", "--no-check", "tests/research_ingest_v2_section_claim.test.ts"],
        cwd=ROOT, capture_output=True, text=True, timeout=180)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-3000:]


def _roles(conn):
    conn.autocommit = True
    for role, extra in (("anon", "nologin"), ("authenticated", "nologin"), ("service_role", "nologin")):
        if conn.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone() is None:
            conn.execute(f"create role {role} {extra}")
    conn.autocommit = False


def _skip_if_real_v2(conn):
    if conn.execute("select to_regclass('public.v2_firms')").fetchone()[0] is not None:
        pytest.skip("v2_firms already exists; not locking that database")


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_migration_is_a_no_op_without_v2():
    import psycopg
    with psycopg.connect(DATABASE_URL) as conn:
        _skip_if_real_v2(conn)
        conn.execute(MIG)
        assert conn.execute("select to_regprocedure('public.v2_section_claim(uuid,text)')").fetchone()[0] is None
        conn.rollback()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_section_claim_orders_by_stored_deals_and_keeps_existing_keys():
    import psycopg
    conn = psycopg.connect(DATABASE_URL)
    try:
        _roles(conn)
        _skip_if_real_v2(conn)
        if conn.execute("select to_regclass('bots.ingest_keys')").fetchone()[0] is None:
            conn.execute("create schema if not exists bots")
            conn.execute("""
                create table bots.ingest_keys (
                  id uuid primary key,
                  name text not null,
                  key_hash text not null,
                  active boolean not null default true,
                  bot_id text)
            """)
        conn.execute("""
            create table public.v2_firms (
              firm_id bigint primary key,
              slug varchar,
              display_name varchar not null,
              website_url text,
              archived boolean not null default false)
        """)
        conn.execute("""
            create table public.firm_summary (
              firm_id bigint primary key,
              listed boolean not null default false,
              firm_status text,
              deals int not null default 0)
        """)
        conn.execute("""
            create table public.v2_bot_keys (
              bot_key_id bigint generated by default as identity primary key,
              bot_name text not null unique,
              key_hash text,
              frozen boolean not null default false,
              freeze_date timestamptz,
              freeze_reason text)
        """)
        conn.execute("""
            create table public.v2_legal_items (
              legal_item_id bigint primary key,
              firm_id bigint not null,
              item_group text not null,
              nothing_found boolean not null default false,
              source_level smallint,
              is_current boolean not null default false,
              archived boolean not null default false,
              constraint v2_legal_items_source_level_check1 check (source_level = 1))
        """)
        conn.execute("""
            create table public.v2_reviews (
              row_id bigint primary key,
              firm_id bigint not null,
              quote varchar not null,
              review_source_name varchar not null,
              nothing_found boolean not null default false,
              is_current boolean not null default false,
              archived boolean not null default false)
        """)
        conn.execute("""
            create table public.v2_interviews (
              row_id bigint primary key,
              firm_id bigint,
              interview_url text not null,
              nothing_found boolean not null default false,
              is_current boolean not null default false,
              archived boolean not null default false)
        """)
        anchor = (
            "    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN\n"
            "      reason := 'Staff and Investment staff are not accepted';\n"
            "    END IF;"
        )
        conn.execute(
            "create or replace function public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean default false)\n"
            "returns jsonb language plpgsql as $fn$\n"
            "declare reason text; tbl text; fact jsonb; it jsonb;\n"
            "begin\n"
            + anchor + "\n"
            "    return '{}'::jsonb;\n"
            "end\n"
            "$fn$"
        )
        conn.execute(MIG)

        def firm(fid, name, deals, listed=True, status="Active", archived=False):
            conn.execute(
                "insert into v2_firms (firm_id, slug, display_name, website_url, archived) values (%s,%s,%s,%s,%s)",
                (fid, f"firm-{fid}", name, f"https://firm-{fid}.example", archived))
            conn.execute(
                "insert into firm_summary (firm_id, listed, firm_status, deals) values (%s,%s,%s,%s)",
                (fid, listed, status, deals))

        firm(20, "Twenty", 9)
        firm(30, "Thirty", 9)
        firm(10, "Ten", 5)
        firm(40, "Hidden", 50, listed=False)
        firm(50, "Inactive", 40, status="Inactive")
        firm(60, "Archived", 30, archived=True)
        firm(70, "Has legal", 20)
        conn.execute(
            """insert into v2_legal_items (legal_item_id, firm_id, item_group, nothing_found, source_level, is_current)
               values (1, 70, 'case', true, 1, true)""")

        def key(bot, bot_key_id, key_hash, frozen=False):
            kid = uuid.uuid4()
            conn.execute(
                "insert into bots.ingest_keys (id, name, key_hash, active, bot_id) values (%s,%s,%s,true,%s)",
                (kid, bot, key_hash, bot))
            conn.execute(
                """insert into v2_bot_keys (bot_key_id, bot_name, key_hash, frozen, freeze_reason)
                   values (%s,%s,%s,%s,%s)""",
                (bot_key_id, bot, key_hash, frozen, "too many" if frozen else None))
            return kid

        k1 = key("bot-one", 501, "hash-one")
        k2 = key("bot-two", 502, "hash-two")
        k3 = key("bot-frozen", 503, "hash-frozen", frozen=True)

        def claim(kid, section):
            row = conn.execute(
                "select public.v2_section_claim(%s, %s)", (kid, section)).fetchone()[0]
            return row

        def done(kid, section, fid):
            return conn.execute(
                "select public.v2_section_done(%s, %s, %s)", (kid, section, fid)).fetchone()[0]

        first = claim(k1, "legal")
        assert first["ok"] is True and first["firm_id"] == 20 and first["name"] == "Twenty"
        assert first["slug"] == "firm-20" and first["section"] == "legal"
        again = claim(k1, "legal")
        assert again["firm_id"] == 20, again
        other = claim(k2, "legal")
        assert other["firm_id"] == 30, other
        assert claim(k1, "reviews")["firm_id"] == 70
        frozen = claim(k3, "legal")
        assert frozen["ok"] is False and frozen["error"].startswith("Key frozen")
        holds = conn.execute("select count(*) from v2_section_holds where bot_key_id = 503").fetchone()[0]
        assert holds == 0
        kept = conn.execute(
            "select bot_key_id, key_hash, frozen from v2_bot_keys where bot_name = 'bot-one'").fetchone()
        assert kept == (501, "hash-one", False)
        assert conn.execute("select count(*) from v2_bot_keys where bot_name = 'bot-one'").fetchone()[0] == 1

        refused = done(k2, "legal", 20)
        assert refused["ok"] is False and "not assigned" in refused["error"]
        finished = done(k1, "legal", 20)
        assert finished["done"] is True and finished["firm_id"] == 20
        assert done(k1, "legal", 20)["done"] is True
        # Checked firm 20 is never handed out again, even though its hold is the caller's.
        conn.execute("update v2_section_holds set claimed_at = now() - interval '7 hours' where firm_id = 30 and section = 'legal'")
        taken = claim(k1, "legal")
        assert taken["firm_id"] == 30, taken
        assert conn.execute(
            "select bot_key_id from v2_section_holds where firm_id = 30 and section = 'legal'").fetchone()[0] == 501
        # Firm 10 is next. Firm 20 stays checked. Firm 70 has a current legal row.
        assert done(k1, "legal", 30)["done"] is True
        assert claim(k2, "legal")["firm_id"] == 10
        assert claim(k1, "youtube")["firm_id"] == 70

        conn.execute(
            """insert into v2_legal_items (legal_item_id, firm_id, item_group, nothing_found, source_level, is_current)
               values (2, 10, null, true, 1, false)""")

        def expect_check(sql):
            conn.execute("savepoint bad_row")
            with pytest.raises(psycopg.errors.CheckViolation):
                conn.execute(sql)
            conn.execute("rollback to savepoint bad_row")

        expect_check(
            """insert into v2_legal_items (legal_item_id, firm_id, item_group, nothing_found, source_level)
               values (3, 10, null, true, 4)""")
        expect_check(
            """insert into v2_legal_items (legal_item_id, firm_id, item_group, nothing_found, source_level)
               values (4, 10, null, false, 1)""")
        conn.execute(
            """insert into v2_reviews (row_id, firm_id, quote, review_source_name, nothing_found)
               values (1, 10, null, null, true)""")
        expect_check(
            """insert into v2_reviews (row_id, firm_id, quote, review_source_name, nothing_found)
               values (2, 10, null, null, false)""")
        conn.execute(
            """insert into v2_interviews (row_id, firm_id, interview_url, nothing_found)
               values (1, 10, null, true)""")
        src = conn.execute(
            "select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure)").fetchone()[0]
        assert "nothing_found needs the searches in note" in src
        assert "legal nothing_found needs source_level 1" in src
        assert src.count("Staff and Investment staff are not accepted") == 1

        conn.execute("delete from v2_legal_items where item_group is null")
        conn.execute("delete from v2_reviews where quote is null")
        conn.execute("delete from v2_interviews where interview_url is null")
        conn.execute(UNDO)
        assert conn.execute("select to_regprocedure('public.v2_section_claim(uuid,text)')").fetchone()[0] is None
        assert conn.execute("select to_regclass('public.v2_section_holds')").fetchone()[0] is None
        restored = conn.execute(
            "select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure)").fetchone()[0]
        assert "nothing_found needs the searches in note" not in restored
        assert "Staff and Investment staff are not accepted" in restored
    finally:
        conn.rollback()
        conn.close()
