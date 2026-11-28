"""Admin analytics (28 Nov 2026, claude/plans/admin-analytics.md): the page is closed to everyone but admin accounts, the visitor door is capped,
and every block of admin_report() answers on a small fixture. The first group needs no database; the second runs when DATABASE_URL is set."""
import glob, json, os, re, subprocess, sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'launch'))
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
ADMIN = "71b72d7b-5899-45e2-a5cb-81b39a02a418"


def read(*p):
    return open(os.path.join(ROOT, *p), encoding='utf-8').read()


def migration():
    return read('supabase', 'migrations', os.path.basename(glob.glob(os.path.join(ROOT, 'supabase', 'migrations', '*_admin_analytics.sql'))[0]))


def test_the_admin_page_is_unlinked_noindex_and_starts_as_page_not_found():
    from pages import registry
    spec = [s for s in registry.PAGES if s.slug == 'admin'][0]
    assert spec.noindex and not spec.nav and not spec.sitemap
    html = read('launch', 'pages', 'admin.py')
    assert '404' in html and 'hidden></main>' in html          # the 404 words are in the page, the admin block is hidden
    site = json.loads(read('launch', 'copy.json'))['site']
    assert site['pages']['admin']['title'].startswith('Not found')
    assert not any(re.search(r'href="[^"]*admin/?"', read('launch', 'pages', f)) for f in os.listdir(os.path.join(ROOT, 'launch', 'pages')) if f.endswith('.py'))


def test_the_page_script_goes_back_to_not_found_without_an_admin_answer():
    js = read('launch', 'js', 'admin.js')
    assert "rpc('analytics_is_admin')" in js and "rpc('admin_report'" in js
    assert 'if (error || !data) { host.hidden = true;' in js
    assert 'deck_path' not in js and 'deck_path' not in migration().split('admin_report')[-1]   # never a link to a deck


def test_the_numbers_are_locked_in_the_database():
    m = migration()
    body = m[m.index('function public.admin_report'):]
    assert body.index('analytics_is_admin()') < body.index("'numbers'")    # the admin check comes first
    assert 'if not public.analytics_is_admin() then return null; end if;' in m
    for t in ('admins', 'track_events'):
        assert f'alter table public.{t} enable row level security' in m
        assert f'revoke all on table public.{t} from public, anon, authenticated' in m
    assert 'grant execute on function public.admin_report(integer) to authenticated' in m and 'admin_report(integer) to anon' not in m
    assert 'create policy' not in m
    assert 'interval \'90 days\'' in m                                       # raw rows are deleted after 90 days


def test_tracking_script_uses_the_existing_visitor_id_and_stops_when_hidden():
    js = read('launch', 'js', 'track.js')
    assert "'regretamin.anon'" in js and 'document.cookie' not in js
    assert 'document.hidden' in js and '30 * 60 * 1000' in js and '15000' in js
    assert "/^\\/admin(\\/|$)/" in js                                        # the admin page does not count itself
    build = read('launch', 'build.py')
    assert 'track.js' in build and '/track.js\\n  Cache-Control' in build


def test_privacy_page_says_we_count_visits_ourselves():
    p = json.loads(read('launch', 'copy.json'))['site']['legal']['privacy']
    assert 'count visits ourselves' in p and 'November 28, 2026' in p


# ---- with a database (the migration applied) ----
def _conn():
    psycopg = pytest.importorskip("psycopg")
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL is not set")
    c = psycopg.connect(DATABASE_URL)
    if c.execute("select to_regclass('public.track_events')").fetchone()[0] is None:
        c.close(); pytest.skip("admin analytics migration not in this database")
    return c


def _as(c, sub):
    c.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({"sub": sub, "role": "authenticated"} if sub else {"role": "anon"}),))


def test_visitors_are_capped_and_cannot_read():
    c = _conn()
    try:
        a = c.execute("select gen_random_uuid()").fetchone()[0]
        _as(c, None)
        ev = json.dumps([{"k": "beat", "p": "/map/", "v": "trends", "t": 15}] * 25)
        c.execute("select track_visit(%s, %s::jsonb)", (a, ev))
        assert c.execute("select count(*) from track_events where anon_id=%s", (a,)).fetchone()[0] == 10   # 10 events per call
        for _ in range(6):
            c.execute("select track_visit(%s, %s::jsonb)", (a, json.dumps([{"k": "beat", "p": "/map/", "t": 15}] * 10)))
        assert c.execute("select count(*) from track_events where anon_id=%s", (a,)).fetchone()[0] == 40   # 40 a minute per visitor
        b = c.execute("select gen_random_uuid()").fetchone()[0]
        c.execute("select track_visit(%s, %s::jsonb)", (b, json.dumps([{"k": "evil"}, {"k": "view", "p": "x" * 500, "d": "fridge", "t": "999"}])))
        assert c.execute("select count(*), max(length(path)) from track_events where anon_id=%s", (b,)).fetchone() == (1, 120)
        _as(c, ADMIN)
        c.execute("select track_visit(gen_random_uuid(), %s::jsonb)", (json.dumps([{"k": "view", "p": "/", "s": "adminvisit"}]),))
        assert c.execute("select count(*) from track_events where src='adminvisit'").fetchone()[0] == 0     # admins' own visits are left out
        for role, table in (("anon", "track_events"), ("authenticated", "admins")):
            c.execute(f"set local role {role}")
            with pytest.raises(Exception):
                c.execute(f"select count(*) from {table}")
            c.rollback(); break
    finally:
        c.rollback(); c.close()


def test_every_block_answers_on_a_small_fixture_and_closes_to_non_admins():
    c = _conn()
    try:
        _as(c, ADMIN)
        base = c.execute("select admin_report(7)").fetchone()[0]
        u = c.execute("select gen_random_uuid()").fetchone()[0]; a = c.execute("select gen_random_uuid()").fetchone()[0]
        _as(c, None)
        c.execute("insert into auth.users (id, email, created_at) values (%s, 'fixture@example.com', now())", (u,))
        bal = c.execute("insert into check_balances (user_id, anon_id) values (%s, %s) returning id", (u, a)).fetchone()[0]
        c.execute("insert into track_events (anon_id, kind, path, src) values (%s, 'view', '/', 'news.ycombinator.com')", (a,))
        c.execute("insert into track_events (anon_id, kind, path, view, secs) values (%s, 'beat', '/map/', 'top', 15)", (a,))
        c.execute("insert into check_events (balance_id, firm_id, kind, amount) select %s, id, 'spend_paid', 1 from firms limit 1", (bal,))
        c.execute("insert into ready_reports (user_id, status, deck_name, deck_path, result, tokens_in, tokens_out) values (%s, 'done', 'fixture.pdf', 'secret/path.pdf', %s, 1000000, 100000)",
                  (u, json.dumps({"company": {"stage": "Seed", "sector": "Fintech"}, "scores": {"deck": 7}, "verdict": "Fix 2 things first.", "research": {}})))
        c.execute("insert into payments (profile_id, status, amount, currency) values (%s, 'paid', 4900, 'usd')", (u,))
        rq = c.execute("insert into firm_requests (name, name_key) values ('Fixture Capital', 'fixturecapital') returning id").fetchone()[0]
        c.execute("insert into firm_request_emails (request_id, email) values (%s, 'asker@example.com')", (rq,))
        _as(c, ADMIN)
        rep = c.execute("select admin_report(7)").fetchone()[0]
        d = lambda k: rep['numbers'][k][0] - base['numbers'][k][0]
        assert (d('visitors'), d('registrations'), d('decks'), d('researches'), d('revenue')) == (1, 1, 1, 1, 4900)
        assert rep['numbers']['invites'] == [0, 0] and rep['invites'] == []                                   # invites do not exist yet
        assert any(s['source'] == 'news.ycombinator.com' and s['registered'] >= 1 for s in rep['sources'])
        assert any(r['email'] == 'fixture@example.com' and r['src'] == 'news.ycombinator.com' and r['paid'] == 4900 and r['opened'] == 1 for r in rep['registrations'])
        row = [r for r in rep['deckrows'] if r['file'] == 'fixture.pdf'][0]
        assert (row['score'], row['stage'], row['sector'], row['research']) == ('7', 'Seed', 'Fintech', True)
        assert 'secret/path' not in json.dumps(rep)                                                            # never a link to a deck
        assert any(q['firm'] == 'Fixture Capital' for q in rep['requests'])
        assert any(m['view'] == 'top' and m['secs'] >= 15 for m in rep['maps'])
        assert rep['funnel']['opened'] >= 1 and rep['funnel']['paid'] >= 1 and rep['cost']['model_usd'] >= 4 + 2
        _as(c, str(u))
        assert c.execute("select admin_report(7)").fetchone()[0] is None                                      # a signed-in non-admin gets nothing
        _as(c, None)
        assert c.execute("select admin_report(7)").fetchone()[0] is None                                      # so does a signed-out visitor
    finally:
        c.rollback(); c.close()
