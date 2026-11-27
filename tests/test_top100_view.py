"""The Top 100 view of the home map (founder's design, 26 Nov 2026; claude/plans/top-100-view.md): static wiring only."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
JS = (ROOT / 'launch/js/top100.js').read_text()
MAP = (ROOT / 'launch/js/map.js').read_text()
CSS = (ROOT / 'launch/style.css').read_text()
MIG = (ROOT / 'supabase/migrations/20261127073000_v2_top100_active.sql').read_text()
FX = json.loads((ROOT / 'tests/fixtures/top100_active.json').read_text())


def test_the_fifth_view_button_and_its_hooks_are_in_the_map():
    assert '<button type="button" data-view="top">Top 100</button>' in MAP
    assert "qs.get('view') === 'top'" in MAP and "m.view === 'top'" in MAP  # a link can open it and a tab remembers it
    assert "if (S.view === 'top') return;" in MAP  # the map asks for nothing while the Top 100 is on screen
    assert "window.REGRET_TOP.hide()" in MAP and 'onMap: () => setView(' in MAP  # leaving it hides it; its Map button goes back to the map
    assert "'vm-tview'" in MAP and '.vm.vm-tview .vm-zoom,.vm.vm-tview .vm-dock{display:none!important}' in CSS  # no zoom buttons and no timeline
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
    for slug, name, n, p, prev in FX['firms']:
        assert slug and name and n > 0 and p >= 0
        assert (prev is None) == (p == 0)  # a firm with nothing last year has no rank last year
    ns = [f[2] for f in FX['firms']]
    assert ns == sorted(ns, reverse=True)  # in rank order
