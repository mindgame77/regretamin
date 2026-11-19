"""v2 work handout: one setting (v2_work_setting.current_job) picks the job next_firm hands out.
Job missing_details: live firms missing hq_country, hq_city, a contact, a non-YouTube social,
YouTube, founder reviews, or legal. Missing founder LinkedIn is not a reason to hand a firm out.
A nothing_found row counts as checked. Not-disclosed first, then North America and Europe, then
other regions; within a group, most empty parts first.

Static checks always run. Database checks run only when V2_SCRATCH_DATABASE_URL points at a local
scratch Postgres. Never point it at production.
"""
import os
import pathlib
from urllib.parse import urlparse

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations"
RB = ROOT / "supabase/rollbacks"
CLAIMS = (MIG / "20261118200000_v2_work_claims.sql").read_text()
CLAIMS_UNDO = (RB / "20261118200000_v2_work_claims.sql").read_text()
HOLD = (MIG / "20261118220000_v2_next_firm_hold_10.sql").read_text()
REOPEN = (MIG / "20261118260000_v2_next_firm_reopen_na_europe.sql").read_text()
REOPEN_UNDO = (RB / "20261118260000_v2_next_firm_reopen_na_europe.sql").read_text()
ALL_HQ = (MIG / "20261118300000_v2_next_firm_all_known_hq.sql").read_text()
ALL_HQ_UNDO = (RB / "20261118300000_v2_next_firm_all_known_hq.sql").read_text()
CUR = (MIG / "20261118310000_v2_work_current_job_missing_details.sql").read_text()
CUR_UNDO = (RB / "20261118310000_v2_work_current_job_missing_details.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
URL = os.environ.get("V2_SCRATCH_DATABASE_URL", "").strip()


def test_migration_is_one_setting_and_server_only():
    low = CUR.lower()
    assert "20261118310000" in str((MIG / "20261118310000_v2_work_current_job_missing_details.sql").name)
    assert not (MIG / "20261118290000_v2_work_current_job_missing_details.sql").exists()
    assert "create table if not exists public.v2_work_setting" in low
    assert "insert into public.v2_work_setting (name, value) values ('current_job', 'missing_details')" in low
    assert "v_job text := coalesce(public.v2_work_current_job(), p_job)" in CUR
    assert "if c.firm_id is null and v_job = 'deal_gaps' then" in CUR
    assert "interval '2 hours'" in low and "n_held >= 10" in low
    assert "alter table public.v2_work_setting enable row level security" in low
    assert "revoke all on table public.v2_work_setting from public, anon, authenticated" in low
    assert "public.v2_work_hq_known(f.hq_country)" in CUR
    assert "case when $1 = ''deal_gaps'' then public.v2_work_hq_known(f.hq_country) else true end" in CUR
    assert "(x.grp * 1000 + x.n)::bigint as sort_key" in CUR
    assert "public.firm_summary_region" in CUR
    for sig in ("public.v2_job_firms_missing_details(bigint)", "public.v2_work_current_job()",
                "public.v2_next_firm(uuid, text)", "public.v2_firm_done(uuid, text, bigint)"):
        assert f"revoke all on function {sig} from public, anon, authenticated" in low
        for role in ("to anon", "to authenticated", "to public"):
            assert f"grant execute on function {sig} {role}" not in low
    u = CUR_UNDO.lower()
    assert "drop table if exists public.v2_work_setting" in u
    assert "drop function if exists public.v2_job_firms_missing_details(bigint)" in u
    assert "where job = 'deal_gaps'" in u
    assert "v2_work_current_job()" not in u.replace("drop function if exists public.v2_work_current_job()", "")
    assert "public.v2_work_hq_known(f.hq_country)" in CUR_UNDO
    assert "v_job text := coalesce(public.v2_work_current_job(), p_job)" not in CUR_UNDO


def test_missing_details_rules_in_sql():
    job = CUR[CUR.index("create or replace function public.v2_job_firms_missing_details"):
              CUR.index("create or replace function public.v2_work_current_job")]
    assert "people_linkedin" not in job
    assert "linkedin_url" not in job.split("saved_people")[0]
    for part in ("hq_country", "hq_city", "contact", "socials", "youtube", "reviews", "legal"):
        assert f"'{part}'" in job
    assert "lower(btrim(coalesce(platform, ''))) is distinct from 'youtube'" in job
    assert "lower(btrim(coalesce(platform, ''))) = 'youtube'" in job
    assert "coalesce(nothing_found, false)" in job
    assert "from public.v2_interviews" in job
    assert "from public.v2_reviews" in job
    assert "from public.v2_legal_items" in job
    assert "when coalesce(public.firm_summary_region(y.hq_country), 'unknown') = 'unknown' then 2" in job
    assert "when public.firm_summary_region(y.hq_country) in ('north_america', 'europe') then 1" in job


def test_submit_fills_blank_person_urls_only():
    assert "existing person: only linkedin_url or x_url can be filled" in CUR
    assert "person already has a different linkedin_url; never overwritten" in CUR
    assert "person already has a different x_url; never overwritten" in CUR
    assert "Held: empty person url waits for the Checker" in CUR
    assert "existing person: only linkedin_url or x_url can be filled" not in CUR_UNDO
    assert "person already has a different linkedin_url; never overwritten" not in CUR_UNDO


def test_edge_job_is_optional_and_hints_use_the_job_used():
    block = FN[FN.index('body.action === "next_firm" || body.action === "firm_done"'):FN.index('body.action !== "submit"')]
    assert "const job = body.job ?? null;" in block
    assert 'typeof data.job === "string" ? data.job : job' in block
    assert '"\\",\\"firm_id\\":" + data.firm.firm_id' in block


# ---------- database checks (local scratch Postgres only) ----------

STUB = """
drop schema if exists bots cascade;
drop table if exists public.v2_work_setting, public.v2_work_claims, public.v2_deals, public.v2_startups, public.v2_bot_keys,
  public.v2_firm_contacts, public.v2_social_accounts, public.v2_interviews, public.v2_reviews, public.v2_legal_items,
  public.v2_person_firm_roles, public.v2_people, public.v2_firms cascade;
drop function if exists public.firm_summary_region(text);
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
create schema bots;
create table bots.ingest_keys (id uuid primary key, name text, key_hash text, active boolean not null default true, bot_id text);
create table public.v2_firms (firm_id bigint primary key, slug text, display_name text, website_url text, archived boolean default false,
  hq_country text default 'US', hq_city text, merged_into_firm_id bigint);
create table public.v2_startups (startup_id bigint primary key, is_current boolean default true, archived boolean default false);
create table public.v2_bot_keys (bot_key_id bigserial primary key, bot_name text unique not null, key_hash text,
  frozen boolean not null default false, freeze_date timestamptz, freeze_reason text, freeze_count_7d int);
create table public.v2_deals (deal_id bigserial primary key, firm_id bigint, startup_id bigint, round text, deal_date date,
  is_current boolean default true, archived boolean default false, nothing_found boolean);
create table public.v2_firm_contacts (row_id bigserial primary key, firm_id bigint, contact_email text, archived boolean default false,
  nothing_found boolean default false);
create table public.v2_social_accounts (row_id bigserial primary key, firm_id bigint, platform text, archived boolean default false,
  nothing_found boolean default false);
create table public.v2_interviews (row_id bigserial primary key, firm_id bigint, interview_url text, archived boolean default false,
  nothing_found boolean default false);
create table public.v2_reviews (row_id bigserial primary key, firm_id bigint, quote text, archived boolean default false,
  nothing_found boolean default false);
create table public.v2_legal_items (legal_item_id bigserial primary key, firm_id bigint, item_group text, archived boolean default false,
  nothing_found boolean default false);
create table public.v2_people (person_id bigint primary key, person_name text, linkedin_url text, archived boolean default false);
create table public.v2_person_firm_roles (row_id bigserial primary key, person_id bigint, firm_id bigint, archived boolean default false);
create or replace function public.firm_summary_region(p_country text)
returns text language sql immutable as $$
  select case case when upper(btrim(p_country)) ~ '^[A-Z]{2}$' then upper(btrim(p_country)) end
    when 'US' then 'north_america' when 'CA' then 'north_america' when 'MX' then 'north_america'
    when 'DE' then 'europe' when 'GB' then 'europe'
    when 'JP' then 'asia'
    else 'unknown' end
$$;
"""

K1, K2 = ("11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222")


def _local(url):
    host = urlparse(url).hostname or ""
    return host in ("", "localhost", "127.0.0.1") or host.startswith("/")


def _fill(c, fid, contact=False, social=False, youtube=False, reviews=False, legal=False, reviews_nf=False):
    if contact:
        c.execute("insert into public.v2_firm_contacts(firm_id, contact_email) values (%s, 'a@b.co')", (fid,))
    if social:
        c.execute("insert into public.v2_social_accounts(firm_id, platform) values (%s, 'X')", (fid,))
    if youtube:
        c.execute("insert into public.v2_social_accounts(firm_id, platform) values (%s, 'YouTube')", (fid,))
    if reviews:
        c.execute("insert into public.v2_reviews(firm_id, quote) values (%s, 'q')", (fid,))
    if reviews_nf:
        c.execute("insert into public.v2_reviews(firm_id, nothing_found) values (%s, true)", (fid,))
    if legal:
        c.execute("insert into public.v2_legal_items(firm_id, item_group) values (%s, 'case')", (fid,))


@pytest.fixture()
def db():
    if not URL:
        pytest.skip("V2_SCRATCH_DATABASE_URL is not set")
    if not _local(URL):
        pytest.skip("V2_SCRATCH_DATABASE_URL must be a local scratch database")
    import psycopg
    with psycopg.connect(URL, autocommit=True) as c:
        c.execute(STUB)
        for k, b in ((K1, "bot-a"), (K2, "bot-b")):
            c.execute("insert into bots.ingest_keys(id, key_hash, bot_id) values (%s, %s, %s)", (k, "h-" + b, b))
        # 1: US, complete (not handed out). 2: US, city only missing.
        # 3: blank country, all 7 empty (not-disclosed, most empty, first overall).
        # 4: JP, all enrichment empty (other region). 5: DE, no socials and no reviews.
        # 6: blank country but archived. 7: merged. 8: gap firm, complete details.
        # 9: US, only founder LinkedIn missing (not handed out).
        # 10: US, YouTube account only, so socials still missing.
        # 11: US, reviews nothing_found, otherwise complete (not handed out).
        # 12: US, never checked (country only; 6 empty) — front of NA/Europe.
        # 13: blank country with a contact (6 empty) — behind firm 3 in not-disclosed.
        firms = [(1, "US", "NYC", None, False), (2, "US", None, None, False), (3, None, None, None, False),
                 (4, "JP", None, None, False), (5, "DE", "Berlin", None, False), (6, None, None, None, True),
                 (7, None, None, 1, False), (8, "US", "SF", None, False), (9, "US", "SF", None, False),
                 (10, "US", "SF", None, False), (11, "US", "SF", None, False),
                 (12, "US", None, None, False), (13, None, None, None, False)]
        for fid, cc, city, merged, arch in firms:
            c.execute("insert into public.v2_firms(firm_id, slug, display_name, hq_country, hq_city, merged_into_firm_id, archived) "
                      "values (%s, %s, %s, %s, %s, %s, %s)", (fid, f"f{fid}", f"Firm {fid}", cc, city, merged, arch))
        for fid in (1, 2, 5, 8, 9, 10, 11, 13):
            _fill(c, fid, contact=True)
        for fid in (1, 2, 8, 9, 11):
            _fill(c, fid, social=True)
        for fid in (1, 2, 5, 8, 9, 10, 11):
            _fill(c, fid, youtube=True)
        for fid in (1, 2, 8, 9, 10):
            _fill(c, fid, reviews=True)
        _fill(c, 11, reviews_nf=True)
        for fid in (1, 2, 5, 8, 9, 10, 11):
            _fill(c, fid, legal=True)
        c.execute("insert into public.v2_social_accounts(firm_id, platform, archived) values (5, 'X', true)")
        for pid, fid, li in ((1, 1, "https://www.linkedin.com/in/a"), (2, 2, "https://www.linkedin.com/in/b"),
                             (3, 5, None), (4, 8, "https://www.linkedin.com/in/d"),
                             (5, 9, None)):
            c.execute("insert into public.v2_people values (%s, %s, %s)", (pid, f"P{pid}", li))
            c.execute("insert into public.v2_person_firm_roles(person_id, firm_id) values (%s, %s)", (pid, fid))
        for i in range(30):
            c.execute("insert into public.v2_deals(firm_id, startup_id) values (8, %s)", (100 + i,))
        c.execute(CLAIMS)
        c.execute(HOLD)
        c.execute(REOPEN)
        c.execute(ALL_HQ)
        c.execute(CUR)
        yield c
        c.execute(CUR_UNDO)
        c.execute(ALL_HQ_UNDO)
        c.execute(REOPEN_UNDO)
        c.execute(CLAIMS_UNDO)
        c.execute("drop schema bots cascade; drop table public.v2_deals, public.v2_startups, public.v2_bot_keys, public.v2_firms, "
                  "public.v2_firm_contacts, public.v2_social_accounts, public.v2_interviews, public.v2_reviews, public.v2_legal_items, "
                  "public.v2_person_firm_roles, public.v2_people cascade; drop function if exists public.firm_summary_region(text)")


def nxt(c, key, job="deal_gaps"):
    return c.execute("select public.v2_next_firm(%s, %s)", (key, job)).fetchone()[0]


def done(c, key, fid, job="deal_gaps"):
    return c.execute("select public.v2_firm_done(%s, %s, %s)", (key, job, fid)).fetchone()[0]


def test_db_list_and_order(db):
    rows = {r[0]: (r[1], r[2]) for r in db.execute("select firm_id, sort_key, info from public.v2_job_firms_missing_details(null)")}
    # LinkedIn-only firm 9 and nothing_found-reviews firm 11 are complete for this job.
    assert set(rows) == {2, 3, 4, 5, 10, 12, 13}
    assert 9 not in rows and 11 not in rows and 1 not in rows and 8 not in rows
    # Brand-new never-checked firm (all 7 empty) leads its group, and not-disclosed leads overall.
    assert rows[3][0] == 2007 and rows[3][1]["missing_count"] == 7 and rows[3][1]["needs_country"] is True
    assert rows[13][0] == 2006 and rows[13][1]["missing_count"] == 6
    # US never-checked (country only) leads North America / Europe, ahead of partial firms.
    assert rows[12][0] == 1006 and rows[12][1]["missing_count"] == 6
    assert rows[5][0] == 1002 and rows[5][1]["missing"] == ["socials", "reviews"]
    assert rows[2][0] == 1001 and rows[2][1]["missing"] == ["hq_city"]
    assert rows[10][0] == 1001 and rows[10][1]["missing"] == ["socials"]
    # Other region, after NA/Europe even with 6 empty parts.
    assert rows[4][0] == 6 and rows[4][1]["missing_count"] == 6
    order = [r[0] for r in db.execute(
        "select firm_id from public.v2_job_firms_missing_details(null) order by sort_key desc, firm_id")]
    assert order == [3, 13, 12, 5, 2, 10, 4]
    one = db.execute("select info from public.v2_job_firms_missing_details(5)").fetchone()[0]
    assert one["saved_people"] == [{"person_id": 3, "name": "P3", "has_linkedin": False}]
    nine = db.execute("select info from public.v2_job_firms_missing_details(9)").fetchone()[0]
    assert nine["missing"] == [] and nine["saved_people"] == [{"person_id": 5, "name": "P5", "has_linkedin": False}]


def test_db_same_call_hands_out_missing_details_not_deal_gaps(db):
    a = nxt(db, K1)  # bot still sends job deal_gaps
    assert a["job"] == "missing_details" and a["asked_job"] == "deal_gaps"
    assert a["firm"]["firm_id"] == 3 and a["firm"]["missing_count"] == 7
    assert [nxt(db, K1)["firm"]["firm_id"] for _ in range(6)] == [13, 12, 5, 2, 10, 4]
    assert nxt(db, K1)["firm"] is None  # LinkedIn-only 9 and complete firms never handed out
    assert db.execute("select count(*) from public.v2_work_claims where job = 'deal_gaps'").fetchone()[0] == 0


def test_db_done_is_final_and_old_job_name_works(db):
    assert nxt(db, K1)["firm"]["firm_id"] == 3
    d = done(db, K1, 3)  # bot sends the old job name
    assert d["ok"] and d["job"] == "missing_details"
    assert done(db, K1, 3, "missing_details")["already_done"] is True
    # Another bot never gets the done firm back (no reopen for missing_details).
    got = [nxt(db, K2)["firm"]["firm_id"] for _ in range(6)]
    assert got == [13, 12, 5, 2, 10, 4]
    assert nxt(db, K2)["firm"] is None


def test_db_hold_from_before_the_switch_can_still_be_done(db):
    k1 = db.execute("select bot_key_id from public.v2_work_bot(%s)", (K1,)).fetchone()[0]
    db.execute("insert into public.v2_work_claims(job, firm_id, bot_key_id, claimed_at, expires_at) "
               "values ('deal_gaps', 8, %s, now(), now() + interval '2 hours')", (k1,))
    d = done(db, K1, 8)
    assert d["ok"] and d["job"] == "deal_gaps"


def test_db_swapping_the_setting_swaps_the_job(db):
    db.execute("update public.v2_work_setting set value = 'deal_gaps' where name = 'current_job'")
    a = nxt(db, K1, "missing_details")
    assert a["job"] == "deal_gaps" and a["firm"]["firm_id"] == 8
    db.execute("update public.v2_work_setting set value = 'no_such_job' where name = 'current_job'")
    assert nxt(db, K2, "missing_details")["job"] == "missing_details"  # unknown setting: falls back to the job sent


def test_db_setting_is_private(db):
    import psycopg
    for role in ("anon", "authenticated"):
        for stmt in ("select * from public.v2_work_setting", "select public.v2_work_current_job()",
                     "select * from public.v2_job_firms_missing_details(null)"):
            db.execute(f"set role {role}")
            try:
                with pytest.raises(psycopg.errors.InsufficientPrivilege):
                    db.execute(stmt)
            finally:
                db.execute("reset role")


def test_db_rollback_restores_deal_gaps(db):
    db.execute(CUR_UNDO)
    assert db.execute("select to_regclass('public.v2_work_setting')").fetchone()[0] is None
    a = nxt(db, K1)
    assert a["job"] == "deal_gaps" and a["firm"]["firm_id"] == 8
    db.execute(CUR)  # fixture teardown runs the rollback again
