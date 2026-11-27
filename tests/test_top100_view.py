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
    assert {p[0] for p in places} >= {f[0] for f in FX['firms']} | {f[0] for f in FIRST['firms']}  # the fixture places every firm of every saved chart
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
