"""Public read API: switch, keys, limits, activity, and published rows.

Runs on the local CI database. Hosted Supabase is refused.
"""
import hashlib
import json
import os
import pathlib
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261117190000_public_read_api.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261117190000_public_read_api.sql").read_text()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def _local(url):
    if not url or "supabase.co" in url or "sxxgvkdwgiouyqciztec" in url:
        return False
    return "localhost" in url or "127.0.0.1" in url


pytestmark = pytest.mark.skipif(not _local(DATABASE_URL), reason="DATABASE_URL must be a local database")


def _obj(value):
    if isinstance(value, str):
        return json.loads(value)
    return value


def _call(conn, sql, args=()):
    return _obj(conn.execute(sql, args).fetchone()[0])


@pytest.fixture(scope="module")
def ready():
    import psycopg
    with psycopg.connect(DATABASE_URL, autocommit=True) as conn:
        conn.execute("create schema if not exists extensions")
        conn.execute("create extension if not exists pgcrypto with schema extensions")
        conn.execute("""
            do $$ begin
              if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
              if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
              if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
              if not exists (select 1 from pg_roles where rolname = 'bot_writer') then create role bot_writer nologin; end if;
            end $$
        """)
        if conn.execute("select to_regprocedure('public.api_is_enabled()')").fetchone()[0] is None:
            conn.execute(MIG)
    return DATABASE_URL


@pytest.fixture()
def conn(ready):
    import psycopg
    with psycopg.connect(ready) as c:
        c.execute("set timezone to 'utc'")
        yield c
        c.rollback()


def test_migration_does_not_touch_live_objects():
    lowered = MIG.lower()
    assert "alter table bots." not in lowered
    assert "insert into bots." not in lowered
    assert "update bots." not in lowered
    assert "alter table public." not in lowered
    assert "alter table bots." not in lowered
    assert "create or replace function public.firm_" not in lowered
    assert "create or replace function public.v2_" not in lowered
    assert "create or replace function public._v2" not in lowered
    assert "app_settings" not in lowered
    assert "extract(month from current_date) < 6" in MIG
    assert "when year_n >= 3 then 'Active'" in MIG
    assert "when year_n >= 1 then 'Low activity'" in MIG
    assert "then 'Not active'" in MIG
    assert "else 'Not checked yet'" in MIG
    assert "demand_hidden" in MIG
    assert "merged_into_firm_id is null" in MIG
    assert "not d.nothing_found" in MIG
    assert "api_enabled" in MIG
    assert "drop schema if exists api cascade" in UNDO.lower()


def test_existing_site_pages_stay_registered():
    import sys
    sys.path.insert(0, str(ROOT / "launch"))
    from pages.registry import PAGES
    sitemap = [spec.slug + "/" if spec.slug else "" for spec in PAGES if spec.sitemap]
    assert sitemap == ["", "investors/", "how-we-check/", "privacy/", "terms/"]
    assert [spec.slug for spec in PAGES if spec.nav == "main"] == ["investors", "how-we-check", "plans", "login"]
    api = [spec for spec in PAGES if spec.slug == "api"]
    assert len(api) == 1 and api[0].sitemap is False and api[0].nav == ""


def test_docs_page_has_one_example_per_endpoint():
    import html
    import sys
    from types import SimpleNamespace
    sys.path.insert(0, str(ROOT / "launch"))
    from pages.api_page import render
    copy = json.loads((ROOT / "launch/copy.json").read_text())
    page = render(SimpleNamespace(E=html.escape, S=copy["site"], COPY=copy))
    for path in ("/v1/firms?", "/v1/firms/sequoia", "/v1/firms/sequoia/deals", "/v1/updated"):
        assert path in page
    assert "x-api-key" in page
    assert "<style" not in page
    assert page.startswith('<main class="wrap">')


def test_http_endpoints():
    subprocess.check_call(["node", "--test", "tests/public_api_http.test.mjs"], cwd=ROOT)


def test_switch_starts_off_and_does_not_count(conn):
    assert conn.execute("select public.api_is_enabled()").fetchone()[0] is False
    off = _call(conn, "select public.api_authorize(%s)", ("ab" * 32,))
    assert off == {"ok": False, "error": "off"}
    assert conn.execute("select count(*) from api.key_usage").fetchone()[0] == 0
    assert conn.execute("select count(*) from api.call_log").fetchone()[0] == 0
    firms = _call(conn, "select public.api_firms(null, null, null, null, 10)")
    assert firms["error"] == "off"
    turned = _call(conn, "select public.api_set_enabled(true)")
    assert turned["api_enabled"] is True
    assert conn.execute("select api_enabled from api.settings where id = 1").fetchone()[0] is True


def test_key_is_hashed_picked_up_once_and_limited(conn):
    _call(conn, "select public.api_set_enabled(true)")
    made = _call(conn, "select public.create_api_key(%s, %s, %s)", ("Preview", "holder note", 2))
    assert made["ok"] is True and made["status"] == "sealed"
    blob = json.dumps(made)
    assert "rg_" not in blob
    row = conn.execute(
        "select key_hash, active, daily_limit, pickup_key from api.keys k join api.key_pickup p on p.key_id = k.id where k.id = %s",
        (made["key_id"],),
    ).fetchone()
    raw, stored_hash, active, limit = row[3], row[0], row[1], row[2]
    assert active is True and limit == 2
    assert stored_hash == hashlib.sha256(raw.encode()).hexdigest()
    assert raw not in blob
    proof = "proof-" + ("p" * 40)
    proof_hash = hashlib.sha256(proof.encode()).hexdigest()
    pending = _call(conn, "select public.api_key_apply(%s, %s)", (made["key_id"], proof_hash))
    assert pending["status"] == "pending"
    assert pending["proof_prefix"] == proof_hash[:8]
    assert "key" not in pending
    listed = conn.execute("select proof_prefix from public.pending_api_key_pickups()").fetchone()
    assert listed[0] == proof_hash[:8]
    approved = _call(conn, "select public.approve_api_key_pickup(%s)", (made["key_id"],))
    assert approved["status"] == "approved"
    delivered = _call(conn, "select public.api_key_apply(%s, %s)", (made["key_id"], proof_hash))
    assert delivered["status"] == "delivered" and delivered["key"] == raw
    again = _call(conn, "select public.api_key_apply(%s, %s)", (made["key_id"], proof_hash))
    assert again["error"] == "already_delivered"
    assert conn.execute("select pickup_key is null from api.key_pickup where key_id = %s", (made["key_id"],)).fetchone()[0] is True
    digest = stored_hash
    first = _call(conn, "select public.api_authorize(%s)", (digest,))
    second = _call(conn, "select public.api_authorize(%s)", (digest,))
    third = _call(conn, "select public.api_authorize(%s)", (digest,))
    assert first["ok"] is True and first["remaining"] == 1
    assert second["ok"] is True and second["remaining"] == 0
    assert third["error"] == "rate_limited" and third["remaining"] == 0
    reset = datetime.fromisoformat(third["reset_at"].replace("Z", "+00:00"))
    today = conn.execute("select (now() at time zone 'utc')::date").fetchone()[0]
    assert reset == datetime.combine(today + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)
    assert conn.execute("select calls from api.key_usage where key_id = %s", (made["key_id"],)).fetchone()[0] == 2
    conn.execute("select public.api_log(%s, 'firms', 200, 12)", (made["key_id"],))
    logged = conn.execute(
        "select endpoint, status, duration_ms from api.call_log where key_id = %s", (made["key_id"],)
    ).fetchone()
    assert logged == ("firms", 200, 12)
    _call(conn, "select public.api_set_key_active(%s, false)", (made["key_id"],))
    assert _call(conn, "select public.api_authorize(%s)", (digest,))["error"] == "unauthorized"
    assert _call(conn, "select public.api_authorize(%s)", ("cd" * 32,))["error"] == "unauthorized"


def test_roles_cannot_read_keys(conn):
    with pytest.raises(Exception):
        conn.execute("set local role anon")
        conn.execute("select public.api_is_enabled()")
    conn.rollback()
    conn.execute("set timezone to 'utc'")
    with pytest.raises(Exception):
        conn.execute("set local role service_role")
        conn.execute("select key_hash from api.keys")
    conn.rollback()


def test_activity_matches_investors_list(conn):
    today = conn.execute("select current_date").fetchone()[0].isoformat()
    year = int(today[:4])
    cases = [
        {"dates": [f"{year}-03-01", f"{year}-06-01", f"{year}-11-01"], "deals": 3},
        {"dates": [f"{year}-01-01"], "deals": 4},
        {"dates": [f"{year - 2}-05-01"], "deals": 5},
        {"dates": [], "deals": 0},
        {"dates": [], "deals": 2},
        {"dates": [None, f"{year}-02-02"], "deals": 1},
        {"dates": [f"{year - 1}-12-31", f"{year}-12-31"], "deals": 2},
    ]
    script = r"""
const fs = require('fs');
const vm = require('vm');
const sandbox = {};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
vm.runInNewContext(fs.readFileSync('launch/js/dates.js', 'utf8'), sandbox);
const now = new Date(process.env.ACTIVITY_TODAY + 'T12:00:00Z');
const cases = JSON.parse(process.env.ACTIVITY_CASES);
const out = cases.map((c) => {
  const deals = c.dates.map((d) => ({ date: d }));
  const yearN = sandbox.RegretActivity.countThisYear(deals, now);
  const label = sandbox.RegretActivity.label(yearN, c.deals);
  return label && label.text;
});
process.stdout.write(JSON.stringify(out));
"""
    env = dict(os.environ, ACTIVITY_TODAY=today, ACTIVITY_CASES=json.dumps(cases))
    expected = json.loads(subprocess.check_output(["node", "-e", script], cwd=ROOT, env=env))
    got = []
    for case in cases:
        got.append(conn.execute("select public.api_activity_label(%s, %s::date[])", (case["deals"], case["dates"])).fetchone()[0])
    assert got == expected
    assert set(got) >= {"Active", "Low activity", "Not active", "Not checked yet"}


FIXTURE = """
create table public.v2_firms (
  firm_id bigint primary key,
  display_name varchar not null,
  short_name varchar,
  website_url text,
  archived boolean not null default false,
  merged_into_firm_id bigint,
  demand_hidden boolean not null default false
);
create table public.v2_firm_live (
  firm_id bigint primary key,
  slug text not null unique,
  live_since timestamptz not null
);
create table public.firm_summary (
  firm_id bigint primary key,
  listed boolean not null,
  hq_country text,
  deals integer not null,
  dated_dates date[] not null,
  added timestamptz
);
create table public.v2_startups (
  startup_id bigint primary key,
  startup_name varchar,
  is_current boolean not null,
  archived boolean not null
);
create table public.v2_deals (
  deal_id bigint primary key,
  firm_id bigint not null,
  startup_id bigint not null,
  round text,
  deal_date date,
  source_url text not null,
  is_current boolean not null,
  archived boolean not null,
  shown boolean not null,
  nothing_found boolean not null
);
create index v2_deals_firm_id_idx on public.v2_deals (firm_id);
create table public.v2_people (
  person_id bigint primary key,
  person_name varchar not null,
  is_current boolean not null,
  archived boolean not null,
  nothing_found boolean not null
);
create table public.v2_person_firm_roles (
  row_id bigint primary key,
  person_id bigint not null,
  firm_id bigint not null,
  title varchar,
  is_founder boolean not null,
  is_current boolean not null,
  archived boolean not null,
  nothing_found boolean not null
);
create table public.v2_legal_items (
  legal_item_id bigint primary key,
  firm_id bigint not null,
  other_party varchar,
  regulator_name varchar,
  status text,
  case_type text,
  filed_year smallint,
  court varchar,
  case_summary varchar,
  source_url text not null,
  is_current boolean not null,
  archived boolean not null,
  nothing_found boolean not null,
  lead_only boolean not null
);
create or replace function public._v2_live_id(p_slug text) returns bigint
language sql stable set search_path to 'public' as $$
  select coalesce(f.merged_into_firm_id, f.firm_id)
    from v2_firm_live l
    join v2_firms f on f.firm_id = l.firm_id
    join v2_firms k on k.firm_id = coalesce(f.merged_into_firm_id, f.firm_id)
   where l.slug = lower(btrim(coalesce(p_slug, '')))
     and not coalesce(k.archived, false)
   limit 1
$$;
create or replace function public.v2_is_leader_title(t text) returns boolean
language sql immutable set search_path to 'public' as $$
  select coalesce(t, '') ~* '(\\mCEO\\M|chief executive officer|\\msteward\\M|managing partner)'
$$;
"""


def _load_firms(conn):
    if conn.execute("select to_regclass('public.v2_firms') is not null").fetchone()[0]:
        pytest.skip("v2 tables already exist; fixture runs only on the empty CI database")
    conn.execute(FIXTURE)
    year = conn.execute("select extract(year from current_date)::int").fetchone()[0]
    dates = [f"{year}-01-01", f"{year}-06-01", f"{year}-11-01"]
    conn.execute(
        """insert into v2_firms (firm_id, display_name, short_name, website_url, demand_hidden, archived, merged_into_firm_id) values
          (1, 'Alpha', 'Alf', 'https://alpha.example', false, false, null),
          (2, 'Bravo', null, 'https://bravo.example', false, false, null),
          (3, 'Charlie', null, null, false, false, null),
          (4, 'Hidden', null, null, true, false, null),
          (5, 'Archived', null, null, false, true, null),
          (10, 'Old Alpha', null, null, false, false, 1)"""
    )
    conn.execute(
        """insert into v2_firm_live (firm_id, slug, live_since) values
          (1, 'alpha', '2026-01-01'), (2, 'bravo', '2026-02-01'), (3, 'charlie', '2026-03-01'),
          (4, 'hidden', '2026-04-01'), (5, 'archived', '2026-05-01'), (10, 'old-alpha', '2026-01-02')"""
    )
    conn.execute(
        """insert into firm_summary (firm_id, listed, hq_country, deals, dated_dates, added) values
          (1, true, 'US', 3, %s, '2026-11-02'),
          (2, true, 'GB', 2, '{}', '2026-11-03'),
          (3, true, null, 0, '{}', '2026-11-01'),
          (4, true, 'US', 0, '{}', '2026-11-04'),
          (5, true, 'US', 0, '{}', '2026-11-05'),
          (10, false, 'US', 0, '{}', '2026-01-02')""",
        (dates,),
    )
    conn.execute(
        """insert into v2_startups (startup_id, startup_name, is_current, archived) values
          (1, 'Acme', true, false), (2, 'Gone', false, false), (3, 'Old', true, true)"""
    )
    conn.execute(
        """insert into v2_deals (deal_id, firm_id, startup_id, round, deal_date, source_url, is_current, archived, shown, nothing_found) values
          (1, 3, 1, 'Seed', null, 'https://example.com/undated', true, false, true, false),
          (2, 3, 1, 'A', '2020-01-01', 'https://example.com/dated', true, false, true, false),
          (3, 3, 1, 'B', '2021-01-01', 'https://example.com/hidden', false, false, true, false),
          (4, 3, 1, 'C', '2022-01-01', 'https://example.com/none', true, false, true, true),
          (5, 3, 2, 'D', '2023-01-01', 'https://example.com/startup-old', true, false, true, false),
          (6, 3, 3, 'E', '2024-01-01', 'https://example.com/startup-archived', true, false, true, false)"""
    )
    conn.execute(
        """insert into v2_people (person_id, person_name, is_current, archived, nothing_found) values
          (1, 'Ada Founder', true, false, false),
          (2, 'Bea Chief', true, false, false),
          (3, 'Cy Analyst', true, false, false),
          (4, 'Dee Gone', true, true, false)"""
    )
    conn.execute(
        """insert into v2_person_firm_roles (row_id, person_id, firm_id, title, is_founder, is_current, archived, nothing_found) values
          (1, 1, 1, 'Founder', true, true, false, false),
          (2, 2, 1, 'CEO', false, true, false, false),
          (3, 3, 1, 'Analyst', false, true, false, false),
          (4, 4, 1, 'Founder', true, true, false, false)"""
    )
    conn.execute(
        """insert into v2_legal_items (legal_item_id, firm_id, other_party, status, case_type, filed_year, court, case_summary, source_url, is_current, archived, nothing_found, lead_only) values
          (1, 1, 'Other', 'Active', 'civil', 2024, 'Court', 'A filed case', 'https://example.com/case', true, false, false, false),
          (2, 1, 'Lead', 'Active', 'civil', 2023, 'Court', 'Lead only', 'https://example.com/lead', true, false, false, true),
          (3, 1, 'Draft', 'Active', 'civil', 2022, 'Court', 'Not published', 'https://example.com/draft', false, false, false, false)"""
    )


def test_published_rows_filters_and_pages(conn):
    _load_firms(conn)
    _call(conn, "select public.api_set_enabled(true)")
    page = _call(conn, "select public.api_firms(null, null, null, null, 2)")
    assert [row["slug"] for row in page["firms"]] == ["alpha", "bravo"]
    assert page["firms"][0]["activity"] == "Active"
    assert page["firms"][0]["country"] == "US"
    assert "short_name" not in page["firms"][0]
    nxt = _call(conn, "select public.api_firms(null, null, null, %s, 2)", (page["next_cursor"],))
    assert [row["slug"] for row in nxt["firms"]] == ["charlie"]
    assert nxt["firms"][0]["activity"] == "Not checked yet"
    assert nxt["next_cursor"] is None
    us = _call(conn, "select public.api_firms(null, 'US', null, null, 10)")
    assert [row["slug"] for row in us["firms"]] == ["alpha"]
    quiet = _call(conn, "select public.api_firms(null, null, 'not_checked', null, 10)")
    assert [row["slug"] for row in quiet["firms"]] == ["charlie"]
    found = _call(conn, "select public.api_firms('alf', null, null, null, 10)")
    assert [row["slug"] for row in found["firms"]] == ["alpha"]
    hidden = _call(conn, "select public.api_firm('hidden')")
    assert hidden["error"] == "not_found"
    merged = _call(conn, "select public.api_firm('old-alpha')")
    assert merged["firm"]["slug"] == "alpha"
    assert merged["firm"]["id"] == 1
    assert [person["name"] for person in merged["firm"]["team"]] == ["Ada Founder", "Bea Chief"]
    assert merged["firm"]["legal"][0]["title"] == "Other v. Alpha"
    assert len(merged["firm"]["legal"]) == 1
    assert "submission_id" not in json.dumps(merged["firm"])
    deals = _call(conn, "select public.api_firm_deals('charlie', null, 10)")
    assert [(d["startup"], d["round"], d["date"]) for d in deals["deals"]] == [
        ("Acme", "A", "2020-01-01"),
        ("Acme", "Seed", None),
    ]
    assert deals["deals"][1]["source_url"] == "https://example.com/undated"
    assert "deal_id" not in json.dumps(deals)
    first = _call(conn, "select public.api_firm_deals('charlie', null, 1)")
    assert first["deals"][0]["date"] == "2020-01-01" and first["next_cursor"]
    second = _call(conn, "select public.api_firm_deals('charlie', %s, 1)", (first["next_cursor"],))
    assert second["deals"] == [{"startup": "Acme", "round": "Seed", "date": None, "source_url": "https://example.com/undated"}]
    assert second["next_cursor"] is None
    recent = _call(conn, "select public.api_firms_updated(null, 10)")
    assert [row["slug"] for row in recent["firms"]] == ["bravo", "alpha", "charlie"]
    bad = _call(conn, "select public.api_firms(null, null, null, 'nope', 10)")
    assert bad["error"] == "bad_cursor"


def test_rollback_round_trip(conn):
    conn.execute(UNDO)
    assert conn.execute("select to_regprocedure('public.api_is_enabled()')").fetchone()[0] is None
    assert conn.execute("select to_regnamespace('api')").fetchone()[0] is None
    conn.execute(MIG)
    assert conn.execute("select public.api_is_enabled()").fetchone()[0] is False
