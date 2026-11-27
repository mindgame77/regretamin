"""Pre-seed / Seed / Incubator plans, report and research credits (26 Nov 2026)."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..')
read = lambda *p: open(os.path.join(ROOT, *p), encoding='utf-8').read()
PLANS = json.loads(read('launch', 'copy.json'))['plans']


def test_three_plans_with_the_agreed_prices_and_credits():
    names = [k for k in PLANS if k[0] != '_']
    assert names == ['preseed', 'seed', 'incubator']
    want = {'preseed': ('Pre-seed', 100, 29, 290), 'seed': ('Seed', 400, 99, 990), 'incubator': ('Incubator', 1000, 199, 1990)}
    for k, (name, checks, month, year) in want.items():
        p = PLANS[k]
        assert (p['name'], p['checks'], p['amount'], p['yearly']['amount']) == (name, checks, month, year)
        assert p['price'] == f'${month}' and p['yearly']['price'] == f'${year:,}'
        assert year == month * 10                                   # yearly = 10 months, 2 free
        assert p['yearly']['kind'] == k + '_y' and p['monthly'] is True
    assert PLANS['seed'].get('highlight') and not PLANS['preseed'].get('highlight')


def test_checkout_matches_copy_json():
    ts = read('supabase', 'functions', 'create-checkout', 'index.ts')
    for k, p in PLANS.items():
        if k[0] == '_':
            continue
        for kind in (k, p['yearly']['kind']):
            assert re.search(rf'{kind}: \{{ checks: {p["checks"]}, name: "{re.escape(p["name"])}" \}}', ts), kind
    plans = read('supabase', 'functions', '_shared', 'stripe_plans.ts')
    for kind in ('preseed', 'preseed_y', 'seed', 'seed_y', 'incubator', 'incubator_y'):
        assert f'"{kind}"' in plans
    assert 'single' not in plans and 'm10' not in ts and 'm30' not in ts


def test_the_migration_charges_once_and_is_closed_to_visitors():
    sql = read('supabase', 'migrations', '20261127013452_ready_credits.sql')
    assert "case p_kind when 'report' then 10 else 25 end" in sql
    assert sql.count("case p_kind when 'report' then 10 else 25 end") == 2
    assert 'free_left + 10' in sql and "'grant_signup', 10" in sql
    assert 'n >= 30' in sql
    assert 'enable row level security' in sql and 'revoke all on public.credit_log from anon, authenticated' in sql
    assert 'grant execute on function public.ready_credits_ok(text), public.ready_charge(uuid, text) to authenticated' in sql
    assert 'grant_credits_admin' in sql and 'grant_credits_admin(text, integer, text) to' not in sql   # never granted to visitors
    assert 'not exists (select 1 from ready_reports where id = p_report and user_id = uid)' in sql     # only your own report


def test_the_functions_charge_after_the_result_and_the_page_says_so():
    for f, kind, cost in (('ready.js', 'report', 10), ('research.js', 'research', 25)):
        js = read('launch', 'functions', 'api', f)
        assert f"'ready_credits_ok', {{ p_kind: '{kind}' }}" in js and f"'ready_charge', {{ p_report: id, p_kind: '{kind}' }}" in js
        assert js.index('ready_credits_ok') < js.index('api.anthropic.com') and js.index("'ready_charge'") > js.index('assemble(') if f == 'ready.js' else True
        assert "error: 'out_of_credits'" in js and "'daily_limit'" in js
    page = read('launch', 'js', 'ready.js')
    assert 'const COST = { report: 10, research: 25 }' in page
    assert '${COST.research} credits' in page and 'Nothing was charged' in page
    assert 'Get my report · 10 credits' in read('launch', 'pages', 'ready.py')


def test_no_old_plan_or_four_free_credits_left_in_the_words():
    copy = read('launch', 'copy.json')
    assert 'Starter' not in copy and 'Single credit' not in copy
    assert 'Get 4 free' not in copy and 'for 4 more' not in copy and 'its own 4 credits' not in copy
