"""Firm page SEO: v2_firm_seo (titles, descriptions, indexable, facts) is filled by a pg_cron batch job, never by bot writes."""
import json
import os
import pathlib
import re
import shutil
import subprocess
import threading
import time

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261118120000_v2_firm_seo.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()


def _code(sql):
    return "\n".join(l.split("--")[0] for l in sql.lower().splitlines())


def test_nothing_is_added_to_the_bot_write_path():
    low = _code(MIG)
    assert "create trigger" not in low and "create or replace trigger" not in low
    # bot tables are only read: no write to any of them
    for t in ("v2_firms", "firm_summary", "v2_firm_industries", "v2_firm_stages", "v2_research_submissions",
              "v2_person_firm_roles", "v2_people", "v2_firm_live", "v2_research_assignments"):
        assert not re.search(rf"(update|insert into|delete from)\s+(public\.)?{t}\b", low), t
        assert not re.search(rf"alter table\s+(public\.)?{t}\b", low), t
    for name in ("v2_research_submit", "v2_research_claim", "firm_meta(p_slug text)", "firm_sitemap(p_page"):
        assert f"function public.{name}" not in low, name
    # SEO lives in its own table, with no foreign key to v2_firms
    assert "create table if not exists public.v2_firm_seo" in low and "references" not in low
    # the job: small batch, one run at a time, never waits on a lock
    assert "pg_try_advisory_xact_lock" in low and "for update skip locked" in low
    assert "set lock_timeout = '1s'" in low
    assert "cron.schedule('v2-firm-seo-refresh', '*/10 * * * *'" in low
    assert "statement_timeout = ''30s''" in low and "lock_timeout = ''1s''" in low
    assert "manual_edit" in low and "case when s.manual_edit then s.seo_title" in low
    assert "raise notice 'v2 tables missing, v2_firm_seo skipped'" in low
    # Supabase default privileges grant EXECUTE on new functions to anon/authenticated directly,
    # so the internal (security definer) job functions must be revoked from those roles by name.
    for role in ("anon", "authenticated"):
        for fn in ("v2_firm_seo_compute(bigint[])", "v2_firm_seo_refresh(int)"):
            assert f"revoke all on function public.{fn} from {role}" in low, (fn, role)


def test_rollback_drops_only_the_new_objects():
    low = UNDO.lower()
    for obj in ("table if exists public.v2_firm_seo", "function if exists public.firm_meta_seo(text)",
                "function if exists public.firm_seo_sitemap(integer, integer)", "function if exists public.firm_seo_directory(integer, integer)",
                "function if exists public.v2_firm_seo_refresh(int)", "function if exists public.v2_firm_seo_compute(bigint[])"):
        assert "drop " + obj in low, obj
    assert "cron.unschedule('v2-firm-seo-refresh')" in low
    code = _code(UNDO)
    assert "function if exists public.firm_meta(" not in code and "firm_sitemap(" not in code.replace("firm_seo_sitemap(", "")
    assert "v2_firms" not in code


SEO_FIRM = {
    "slug": "lux", "name": "Lux & Co", "hq": "New York, NY", "legal_name": "LUX CAPITAL MANAGEMENT, LLC", "primary_domain": "lux.com",
    "founded_year": 2000, "indexable": False, "seo_title": "Lux & Co: Deep tech VC in New York | Regretamin",
    "seo_description": "Lux & Co is a seed VC firm in New York, founded 2000.",
    "seo_facts": {"name": "Lux & Co", "hq": "New York, NY", "founded": 2000, "website": "https://www.lux.com", "sectors": ["Deep tech", "Bio <x>"],
                  "stages": ["Pre-seed", "Growth"], "latest_company": "Crosby", "latest_deal_date": "2026-03-31", "last_checked": "2026-11-08",
                  "address": {"street": "920 Broadway", "city": "New York", "region": "NY", "postal": "10010", "country": "US"},
                  "leaders": [{"name": "Josh Wolfe", "title": "Co-Founder", "founder": True}, {"name": "Ann \u00e9 Lee", "title": None, "founder": False}],
                  "registry": [{"type": "SEC CRD", "value": "163026", "url": "https://adviserinfo.sec.gov/firm/summary/163026"}],
                  "social": ["https://x.com/lux"]},
}


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
@pytest.mark.parametrize("full", [False, True])
def test_static_build_and_edge_render_stored_seo_byte_for_byte(full, tmp_path):
    """build.py fill() and edge fillFirm() must give the same page for a firm with stored SEO and facts."""
    env = os.environ.copy(); env.pop("SUPABASE_URL", None); env.pop("SUPABASE_ANON_KEY", None)
    subprocess.run(["python3", "launch/build.py"], cwd=ROOT, check=True, capture_output=True, env=env)
    tpl = (ROOT / "site-launch/_tpl" / ("full.html" if full else "summary.html")).read_text()
    (tmp_path / "f.json").write_text(json.dumps(SEO_FIRM))
    py = subprocess.run(["python3", "-c", (
        "import sys, json, importlib.util; sys.path.insert(0, 'launch');"
        "s = importlib.util.spec_from_file_location('b', 'launch/build.py'); b = importlib.util.module_from_spec(s); s.loader.exec_module(b);"
        f"F = json.load(open({str(tmp_path / 'f.json')!r})); tpl = open({str(ROOT / 'site-launch/_tpl' / ('full.html' if full else 'summary.html'))!r}).read();"
        f"sys.stdout.write(b.fill(tpl, F, {full}))")], cwd=ROOT, check=True, capture_output=True, text=True).stdout
    js = subprocess.run(["node", "--input-type=module", "-e", (
        "import { fillFirm } from './launch/edge/firm.mjs'; import fs from 'node:fs';"
        f"const F = JSON.parse(fs.readFileSync({json.dumps(str(tmp_path / 'f.json'))}, 'utf8'));"
        f"const tpl = fs.readFileSync({json.dumps(str(ROOT / 'site-launch/_tpl' / ('full.html' if full else 'summary.html')))}, 'utf8');"
        "const sk = fs.readFileSync('site-launch/_tpl/pmain.html', 'utf8');"
        f"process.stdout.write(fillFirm(tpl, F, {str(full).lower()}, sk));")], cwd=ROOT, check=True, capture_output=True, text=True).stdout
    assert py == js
    assert "<title>Lux &amp; Co: Deep tech VC in New York | Regretamin</title>" in py
    assert '<meta name="robots" content="noindex, follow">' in py
    assert "<h2>Lux &amp; Co team</h2>" in py and "{{" not in py
    assert tpl.count("{{PMAIN}}") == 1 and tpl.count("{{META}}") == 1 and "<title>{{TITLE}}</title>" in tpl


DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()


def _conn(**kw):
    psycopg = pytest.importorskip("psycopg")
    return psycopg.connect(DATABASE_URL, **kw)


def _need_seo():
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    with _conn() as c:
        if c.execute("select to_regclass('public.v2_firm_seo')").fetchone()[0] is None:
            pytest.skip("v2 tables are not in this database (CI): the migration is a no-op there")


def _firm(cur, name, city=None, sectors=(), stages=(), founded=None, checked=None, researched=True):
    fid = cur.execute("insert into v2_firms (display_name, hq_city, hq_state, hq_country, founded_year, last_checked_date) values (%s, %s, %s, 'US', %s, %s) returning firm_id",
                      (name, city, "NY" if city else None, founded, checked)).fetchone()[0]
    cur.execute("insert into v2_firm_live (firm_id, slug) values (%s, %s)", (fid, f"zz-seo-{fid}"))
    for i, s in enumerate(sectors, 1):
        cur.execute("insert into v2_firm_industries (firm_id, industry_text, position, date_read, source_url, is_current, archived) values (%s, %s, %s, current_date, 'https://x.test', true, false)", (fid, s, i))
    for s in stages:
        cur.execute("insert into v2_firm_stages (firm_id, stage, read_on, source_text, source_url, is_current, archived) values (%s, %s, current_date, 'x', 'https://x.test', true, false)", (fid, s))
    if researched:
        cur.execute("insert into v2_research_assignments (firm_id, claimed_by, done_at) values (%s, 'zz', now()) on conflict do nothing", (fid,))
    cur.execute("select refresh_firm_summary(array[%s]::bigint[])", (fid,))
    # the checked date is firm_summary.added (20261118140000); last_checked_date above covers the older definition
    cur.execute("update firm_summary set listed = true, researched = %s, added = %s::date::timestamptz where firm_id = %s", (researched, checked, fid))
    return fid


def test_titles_descriptions_and_indexable_follow_the_rules():
    _need_seo()
    with _conn() as conn, conn.cursor() as cur:
        rich = _firm(cur, "Zeta Ventures", "NEW YORK", ["Deep tech", "Fintech"], ["Series A", "Seed", "Debt"], 2001, "2026-11-08")
        nosec = _firm(cur, "Eta Partners", "Boston", [], ["Seed"], 2010)
        nocity = _firm(cur, "Theta Capital", None, ["Health"], [], 2015)
        thin = _firm(cur, "Iota Fund", None, [], [], None, researched=False)
        long_ = _firm(cur, "The Extremely Long Name Growth Equity Partners Fund", "San Francisco", ["Enterprise software"], ["Growth"], 1999)
        rows = {r[0]: r[1:] for r in cur.execute("select firm_id, seo_title, seo_description, seo_indexable, facts from v2_firm_seo_compute(%s)", ([rich, nosec, nocity, thin, long_],))}
        assert rows[rich][0] == "Zeta Ventures: Deep tech VC in New York | Regretamin"
        assert rows[rich][1] == "Zeta Ventures is a seed to Series A VC firm in New York, founded 2001. Checked Nov 8, 2026 against SEC, court and sanctions records."
        assert rows[rich][2] is True and rows[rich][3]["stages"] == ["Seed", "Series A", "Debt"]
        assert rows[nosec][0] == "Eta Partners: VC in Boston | Regretamin"
        assert rows[nocity][0] == "Theta Capital: Health VC | Regretamin"
        assert rows[nocity][1] == "Theta Capital is a VC firm, founded 2015."
        assert rows[thin][0] == "Iota Fund: Venture Capital Firm | Regretamin" and rows[thin][1] == "Iota Fund is a VC firm." and rows[thin][2] is False
        # too long: brand dropped first, then the city
        assert rows[long_][0] == "The Extremely Long Name Growth Equity Partners Fund"
        for t, d, *_ in rows.values():
            assert len(t) <= 60 and len(d) <= 160 and not re.search(r"\d", t.replace("Series", ""))
        conn.rollback()


def test_refresh_job_keeps_manual_edits_and_only_writes_its_own_table():
    _need_seo()
    with _conn() as conn, conn.cursor() as cur:
        fid = _firm(cur, "Kappa Ventures", "Austin", ["Climate"], ["Seed"], 2012)
        cur.execute("insert into v2_firm_seo (firm_id, seo_title, seo_description, manual_edit, checked_at) values (%s, 'Hand title', 'Hand description', true, now() - interval '9 days')", (fid,))
        before = cur.execute("select xmin::text from v2_firms where firm_id = %s", (fid,)).fetchone()[0]
        cur.execute("select v2_firm_seo_refresh(2000)")
        t, d, idx, facts = cur.execute("select seo_title, seo_description, seo_indexable, facts from v2_firm_seo where firm_id = %s", (fid,)).fetchone()
        assert (t, d) == ("Hand title", "Hand description") and idx is True and facts["sectors"] == ["Climate"]
        assert cur.execute("select xmin::text from v2_firms where firm_id = %s", (fid,)).fetchone()[0] == before  # v2_firms row untouched
        conn.rollback()


def test_a_running_refresh_never_blocks_a_bot_write_and_a_bot_write_never_blocks_the_refresh():
    _need_seo()
    with _conn(autocommit=True) as setup:
        fid = setup.execute("select firm_id from v2_firms order by firm_id limit 1").fetchone()[0]
    # 1) refresh transaction open (not committed) -> a bot-style update of v2_firms and an insert of a new industry row go through at once
    with _conn() as job, _conn() as bot:
        job.execute("select v2_firm_seo_refresh(500)")
        bot.execute("set lock_timeout = '500ms'")
        t0 = time.monotonic()
        bot.execute("update v2_firms set last_checked_date = last_checked_date where firm_id = %s", (fid,))
        bot.execute("insert into v2_firm_industries (firm_id, industry_text, position, date_read, source_url, is_current, archived) values (%s, 'zz', 99, current_date, 'https://x.test', false, true)", (fid,))
        assert time.monotonic() - t0 < 2
        bot.rollback(); job.rollback()
    # 2) bot transaction holding the v2_firms row lock -> the refresh still finishes (it only reads)
    with _conn() as bot, _conn() as job:
        bot.execute("update v2_firms set last_checked_date = last_checked_date where firm_id = %s", (fid,))
        job.execute("set statement_timeout = '10s'")
        t0 = time.monotonic()
        job.execute("select v2_firm_seo_refresh(500)")
        assert time.monotonic() - t0 < 5
        job.rollback(); bot.rollback()


def test_public_reads():
    _need_seo()
    with _conn() as conn, conn.cursor() as cur:
        for fn in ("firm_meta_seo(text)", "firm_seo_sitemap(integer,integer)", "firm_seo_directory(integer,integer)"):
            secdef, vol = cur.execute("select prosecdef, provolatile from pg_proc where oid = %s::regprocedure", ("public." + fn,)).fetchone()
            assert secdef and vol == "s", fn
            assert cur.execute("select has_function_privilege('anon', %s, 'execute')", ("public." + fn,)).fetchone()[0], fn
        for fn in ("v2_firm_seo_refresh(integer)", "v2_firm_seo_compute(bigint[])"):
            assert not cur.execute("select has_function_privilege('anon', %s, 'execute')", ("public." + fn,)).fetchone()[0], fn
        assert not cur.execute("select has_table_privilege('anon', 'public.v2_firm_seo', 'select')").fetchone()[0]
        assert cur.execute("select count(*) from firm_seo_sitemap(1, 100000)").fetchone()[0] <= 1000
        assert cur.execute("select count(*) from firm_seo_sitemap(1, 1000) s join v2_firm_live l using (slug) join v2_firm_seo x on x.firm_id = l.firm_id where not x.seo_indexable").fetchone()[0] == 0
        assert cur.execute("select count(*) from firm_seo_directory(1, 1000)").fetchone()[0] <= 100
