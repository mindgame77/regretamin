"""The Top 100 view of the home map (founder's design, 26 Nov 2026; claude/plans/top-100-view.md): static wiring only."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JS = (ROOT / 'launch/js/top100.js').read_text()
MAP = (ROOT / 'launch/js/map.js').read_text()
CSS = (ROOT / 'launch/style.css').read_text()
MIG = (ROOT / 'supabase/migrations/20261127150843_v2_top100_active_country.sql').read_text()  # the current version of the function
FX = json.loads((ROOT / 'tests/fixtures/top100_active.json').read_text())
FIRST = json.loads((ROOT / 'tests/fixtures/top100_first.json').read_text())
FUNDS = json.loads((ROOT / 'tests/fixtures/top100_funds.json').read_text())
FUNDS_MIG = (ROOT / 'supabase/migrations/20261127165158_v2_top100_funds.sql').read_text()
SOCIAL = json.loads((ROOT / 'tests/fixtures/top100_social.json').read_text())
SOCIAL_MIG = (ROOT / 'supabase/migrations/20261127170027_v2_top100_social.sql').read_text()
ROUNDS = json.loads((ROOT / 'tests/fixtures/top100_rounds.json').read_text())
ROUNDS_MIG = (ROOT / 'supabase/migrations/20261127170632_v2_top100_rounds.sql').read_text()
FIRST_MIG = (ROOT / 'supabase/migrations/20261127164530_v2_top100_first.sql').read_text()


def test_the_fifth_view_button_and_its_hooks_are_in_the_map():
    assert '<button type="button" data-view="top">Top 100</button>' in MAP
    assert "qs.get('view') === 'top'" in MAP and "m.view === 'top'" in MAP  # a link can open it and a tab remembers it
    assert "if (S.view === 'top') return;" in MAP  # the map asks for nothing while the Top 100 is on screen
    assert "window.REGRET_TOP.hide()" in MAP  # leaving it hides it
    assert "'vm-tview'" in MAP and '.vm.vm-tview:not(.vm-tmap) .vm-zoom,.vm.vm-tview .vm-dock{display:none!important}' in CSS  # no timeline; the zoom card only while the map shows
    assert 'top100.js' in (ROOT / 'launch/pages/map.py').read_text() and 'top100.js' in (ROOT / 'launch/build.py').read_text()


def test_one_video_per_chart_with_the_founders_words():
    """Founder, 26 Nov, 23:12: black button, red play badge, no full stop at the end of a line, one video per chart."""
    for key, line, url in [
        ('active', 'Feeling down? Press play', 'https://youtu.be/0tBw8cB553E'),
        ('social', 'Great work is made of small details', 'https://youtu.be/atXpy2CkNMY'),
        ('first', 'Raising is a grind. Take a breather', 'https://youtu.be/fpIKuufm_WM'),
        ('funds', 'Meanwhile, in ancient Rome', 'https://www.youtube.com/watch?v=_t0uGbCPaf0'),
        ('rounds', 'How top founders pitch big rounds', 'https://www.youtube.com/watch?v=z6gH_v0buUc'),
    ]:
        assert f"{key}: {{ line: '{line}', url: '{url}' }}" in JS
        assert not line.endswith('.')
    assert 'target="_blank" rel="noopener noreferrer"' in JS  # a video opens in a new tab
    assert 'background:#ff0000' in JS and '.cta{' in JS and 'background:var(--ink)' in JS  # black button, red badge


def test_the_view_invents_nothing_and_opens_firm_pages():
    assert 'is not available right now' in JS  # no answer: it says so
    assert "O.root + 'vc/'" in JS  # a bar and a row open the firm's page
    assert 'Based on' in JS and 'd.rounds' in JS  # the count under the title comes from the database
    assert 'attachShadow' in JS  # its styles and the rest of the site never meet


def test_most_active_function_counts_startups_once_per_firm_against_the_same_days_last_year():
    assert 'create or replace function public.v2_top100_active(' in MIG and 'to anon, authenticated' in MIG
    assert 'count(distinct d.startup_id)' in MIG and 'd.is_current and d.shown' in MIG
    assert 'v2_map_counted_places' in MIG  # only the firms the map counts
    assert "(current_date - interval '1 year')::date" in MIG and "date_trunc('year', current_date)" in MIG
    assert 'least(coalesce(p_n, 100), 200)' in MIG  # never more than 200 rows
    assert 'security definer' in MIG and 'drop function if exists public.v2_top100_active(integer)' in MIG  # read-only, with its undo line


def test_saved_answer_has_the_shape_the_page_reads():
    assert len(FX['firms']) == 100 and FX['rounds'] > 0
    for slug, name, n, p, prev, cc in FX['firms']:
        assert slug and name and n > 0 and p >= 0
        assert (prev is None) == (p == 0)  # a firm with nothing last year has no rank last year
    ns = [f[2] for f in FX['firms']]
    assert ns == sorted(ns, reverse=True)  # in rank order


def test_the_skyline_shows_a_flag_under_the_rank_from_the_firms_headquarters_country():
    assert 'assets/flags/' in JS and "cleanCC" in JS  # a small flag picture, only for a two-letter country
    assert "f.cc" in MIG and 'hq_country' in MIG  # the country comes with each firm, from the database
    assert all(c is None or re.fullmatch(r'[A-Z]{2}', c) for *_, c in FX['firms'])
    for c in {c.lower() for *_, c in FX['firms'] if c}:
        assert (ROOT / 'launch/assets/flags' / (c + '.png')).exists(), c  # every flag the saved answer needs is shipped
    assert (ROOT / 'launch/assets/flags/NOTICE.md').exists()  # the open-source licence note
    assert "assets', 'flags'" in (ROOT / 'launch/build.py').read_text()  # and the build copies them


def test_the_map_button_draws_one_circle_per_place_and_uses_the_pages_zoom_card():
    """Founder, 27 Nov: the Map button shows a map inside the Top 100 view; World / United States / Europe sit where they are on the other maps."""
    assert "onMode: (m) => el.classList.toggle('vm-tmap', m === 'map')" in MAP  # the page shows its own zoom card while the map is on
    assert "if (S.view === 'top') { S.level = l; marks(); if (window.REGRET_TOP) window.REGRET_TOP.setLevel(l); return; }" in MAP  # its level goes to the view, nothing under it is redrawn
    assert 'setLevel(l)' in JS and 'v2_top100_places' in JS and "assets/map/places.json" in JS
    assert "lvl === 'world' ? f.region : f.lv === lvl" in JS  # world: the region; United States / Europe: the city or country of that zoom
    assert 'GG: \'GB\'' in JS  # the same islands the map folds into the United Kingdom
    mig = (ROOT / 'supabase/migrations/20261127155459_v2_top100_places.sql').read_text()
    assert 'create or replace function public.v2_top100_places(p_slugs text[])' in mig and 'security definer' in mig and 'stable' in mig
    assert 'revoke all on function public.v2_top100_places(text[]) from public' in mig and 'to anon, authenticated' in mig
    assert 'limit 300' in mig  # no more than 300 slugs
    assert not re.search(r'\b(insert|update|delete|drop|alter)\b\s+(into|table|from|function)?', mig.split('$fn$')[1].lower().replace('create or replace', ''))  # read-only
    places = json.loads((ROOT / 'tests/fixtures/top100_places.json').read_text())
    assert {p[0] for p in places} >= {f[0] for f in FX['firms']} | {f[0] for f in FIRST['firms']} | ({f[0] for f in FUNDS['firms']} - {'lockheed-martin-ventures'}) | {f[0] for f in SOCIAL['firms']}  # the fixture places every firm of every saved chart (Lockheed Martin Ventures has no map place)
    for slug, lv, region, area in places:
        assert lv in ('us', 'eu', None) and region and area


def test_the_account_menu_opens_above_the_top_100_and_founders_views():
    """Founder, 27 Nov 2026: the Account menu hid behind the Skyline. The map views are layers of z-index 6 to 8; the menu must be above them."""
    m = re.search(r'\.dd\{[^}]*z-index:(\d+)\}', CSS)
    assert m and int(m.group(1)) > 8  # above #vt and #vf (6) and the map's own cards (up to 8)
    assert int(m.group(1)) < 60  # and below the full-page dialogs (60)


def test_first_in_chart_is_in_the_drop_down_and_reads_its_own_function():
    """First in (built 27 Nov): same window and row shape as Most active; the tooltip says 'First in on N startups'."""
    assert "key: 'first', label: 'First in', rpc: 'v2_top100_first'" in JS and "fx: 'fx_top100_first'" in JS
    assert "'First in on ' + n" in JS


def test_first_in_function_counts_the_earliest_shown_deal_of_each_startup_over_all_firms():
    assert 'create or replace function public.v2_top100_first(' in FIRST_MIG and 'to anon, authenticated' in FIRST_MIG
    assert 'security definer' in FIRST_MIG and 'stable' in FIRST_MIG and 'drop function if exists public.v2_top100_first(integer)' in FIRST_MIG
    assert 'min(deal_date)' in FIRST_MIG and 'e.d0 = d.deal_date' in FIRST_MIG  # the earliest date; firms tied on it all count
    assert 'where is_current and shown and deal_date is not null' in FIRST_MIG  # the earliest of ALL firms' shown deals, not only the map's
    assert 'd.firm_id in (select firm_id from counted)' in FIRST_MIG and 'v2_map_counted_places' in FIRST_MIG
    assert 'count(distinct d.startup_id)' in FIRST_MIG and 'least(coalesce(p_n, 100), 200)' in FIRST_MIG
    assert not re.search(r'\b(insert|update|delete|alter)\b\s+(into|table|from)', FIRST_MIG.split('$fn$')[1].lower())  # read-only


def test_saved_first_in_answer_has_the_shape_the_page_reads():
    assert len(FIRST['firms']) == 100 and FIRST['rounds'] > 0
    for slug, name, n, p, prev, cc in FIRST['firms']:
        assert slug and name and n > 0 and p >= 0
        assert (prev is None) == (p == 0)
    ns = [f[2] for f in FIRST['firms']]
    assert ns == sorted(ns, reverse=True)


def test_biggest_new_funds_chart_shows_money_the_date_and_grey_bars_for_firms_with_no_earlier_fund():
    """Biggest new funds (built 27 Nov), from the founder's picture ui-20-top100-funds.png."""
    assert "key: 'funds', label: 'Biggest new funds', rpc: 'v2_top100_funds'" in JS and "fx: 'fx_top100_funds'" in JS and 'noPrev: true' in JS
    assert "mv: chart.noPrev && pv == null ? { k: 'na', t: '' }" in JS  # no earlier fund: grey, no move
    assert "na: 'no earlier fund on record'" in JS and "'Based on fund announcements'" in JS
    assert 'const dayMon' in JS and "' · announced '" in JS  # the list and the hover card carry the announcement date
    assert 'K > 1e-12' in JS  # the bars scale to dollars as well as to startup counts


def test_biggest_new_funds_function_takes_each_firms_biggest_fund_announced_in_the_last_12_months():
    assert 'create or replace function public.v2_top100_funds(' in FUNDS_MIG and 'to anon, authenticated' in FUNDS_MIG
    assert 'security definer' in FUNDS_MIG and 'stable' in FUNDS_MIG and 'drop function if exists public.v2_top100_funds(integer)' in FUNDS_MIG
    assert 'from firm_fund_announcements' in FUNDS_MIG and 'a.is_current and not a.archived and a.amount_usd > 0' in FUNDS_MIG
    assert "(current_date - interval '1 year')::date" in FUNDS_MIG and "(current_date - interval '2 year')::date" in FUNDS_MIG
    assert 'distinct on (firm_id)' in FUNDS_MIG and 'amount_usd desc' in FUNDS_MIG  # one fund per firm: the biggest
    assert 'v2_map_counted_places' in FUNDS_MIG and 'least(coalesce(p_n, 100), 200)' in FUNDS_MIG
    assert not re.search(r'\b(insert|update|delete|alter)\b\s+(into|table|from)', FUNDS_MIG.split('$fn$')[1].lower())  # read-only


def test_saved_funds_answer_has_the_shape_the_page_reads():
    assert len(FUNDS['firms']) == 100
    for slug, name, amt, prev_amt, prev_rank, cc, dt in FUNDS['firms']:
        assert slug and name and amt > 0 and re.fullmatch(r'\d{4}-\d{2}-\d{2}', dt)
        assert (prev_amt is None) == (prev_rank is None)  # no fund a year ago, no rank a year ago
    amts = [f[2] for f in FUNDS['firms']]
    assert amts == sorted(amts, reverse=True)


def test_most_social_reach_chart_stacks_each_bar_by_platform_and_draws_no_moves():
    """Most social reach (built 27 Nov), from the founder's picture ui-20-top100-social.png."""
    assert "key: 'social', label: 'Most social reach', rpc: 'v2_top100_social'" in JS and "fx: 'fx_top100_social'" in JS
    assert "const PLAT = [['X', '#10201C'], ['LinkedIn', '#2F6DB5'], ['YouTube', '#D9483B'], ['Instagram', '#B8509E'], ['Substack', '#8C6A4A']]" in JS  # X at the bottom
    assert 'function stackSvg' in JS and 'noPrev: true, stack: true, scale: Math.sqrt' in JS  # segments are shares; heights on a square-root scale
    assert "'Based on ' + num(d.n) + ' firms with a follower count'" in JS and "'mostly '" in JS
    assert 'bar height is scaled, segments = share of followers' in JS


def test_most_social_reach_function_adds_up_followers_per_firm_and_platform():
    assert 'create or replace function public.v2_top100_social(' in SOCIAL_MIG and 'to anon, authenticated' in SOCIAL_MIG
    assert 'security definer' in SOCIAL_MIG and 'stable' in SOCIAL_MIG and 'drop function if exists public.v2_top100_social(integer)' in SOCIAL_MIG
    assert 'from v2_social_accounts a' in SOCIAL_MIG and 'a.is_current and not a.archived and a.follower_count > 0' in SOCIAL_MIG
    assert 'v2_map_counted_places' in SOCIAL_MIG and 'least(coalesce(p_n, 100), 200)' in SOCIAL_MIG
    assert 'social_count_history' not in SOCIAL_MIG  # that table's firm_id is a different kind of id
    assert not re.search(r'\b(insert|update|delete|alter)\b\s+(into|table|from)', SOCIAL_MIG.split('$fn$')[1].lower())  # read-only


def test_saved_social_answer_has_the_shape_the_page_reads():
    assert len(SOCIAL['firms']) == 100 and SOCIAL['n'] > 100
    for slug, name, total, p, prev, cc, parts in SOCIAL['firms']:
        assert slug and name and total > 0 and p is None and prev is None  # one reading per account: no last year
        assert sum(parts.values()) == total and set(parts) <= {'X', 'LinkedIn', 'YouTube', 'Instagram', 'Substack'}
    totals = [f[2] for f in SOCIAL['firms']]
    assert totals == sorted(totals, reverse=True)


def test_biggest_rounds_chart_colours_bars_by_industry_and_has_no_map_or_firm_links():
    """Biggest rounds (built 27 Nov), from the founder's picture ui-20-top100-rounds.png."""
    assert "key: 'rounds', label: 'Biggest rounds', rpc: 'v2_top100_rounds'" in JS and "fx: 'fx_top100_rounds'" in JS
    assert "noPrev: true, noLink: true, noMap: true, scale: Math.sqrt" in JS  # a round has no firm: no page to open, no place on the map
    for g in ['AI', 'Hardware', 'Defense & security', 'Climate', 'Bio & health', 'Fintech & crypto', 'Software', 'Other']:
        assert "['" + g + "', '#" in JS
    assert "legend: 'groups'" in JS and 'last 30 days · ' in JS and 'const FLAME' in JS  # the flame marks a round from the last 30 days
    assert "root.querySelector('.unit').hidden = !!chart.noMap" in JS and '.unit[hidden]{display:none}' in JS  # no Map button for this chart


def test_biggest_rounds_function_ranks_this_years_rounds_in_dollars_and_counts_a_round_once():
    assert 'create or replace function public.v2_top100_rounds(' in ROUNDS_MIG and 'to anon, authenticated' in ROUNDS_MIG
    assert 'security definer' in ROUNDS_MIG and 'stable' in ROUNDS_MIG and 'drop function if exists public.v2_top100_rounds(integer)' in ROUNDS_MIG
    assert "coalesce(e.round, '') <> 'IPO'" in ROUNDS_MIG and 'v2_fx_rates' in ROUNDS_MIG
    assert 'distinct on (startup_id, event_date, usd)' in ROUNDS_MIG and 'least(coalesce(p_n, 100), 200)' in ROUNDS_MIG
    assert not re.search(r'\b(insert|update|delete|alter)\b\s+(into|table|from)', ROUNDS_MIG.split('$fn$')[1].lower())  # read-only


def test_saved_rounds_answer_has_the_shape_the_page_reads():
    assert len(ROUNDS['firms']) == 100 and ROUNDS['hot'] == sum(1 for f in ROUNDS['firms'] if f[6]['h'])
    groups = {'AI', 'Hardware', 'Defense & security', 'Climate', 'Bio & health', 'Fintech & crypto', 'Software', 'Other'}
    for key, name, usd, p, prev, cc, x in ROUNDS['firms']:
        assert re.fullmatch(r'e\d+', key) and name and usd > 0 and p is None and prev is None and cc is None
        assert x['g'] in groups and re.fullmatch(r'\d{4}-\d{2}-\d{2}', x['d']) and x['n'] >= 0
    amts = [f[2] for f in ROUNDS['firms']]
    assert amts == sorted(amts, reverse=True)
    assert len({f[0] for f in ROUNDS['firms']}) == 100
