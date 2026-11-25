"""The Founders view of the home page map: static wiring only; no live service or credentials needed."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'launch'))

MAP = (ROOT / 'launch/js/map.js').read_text()
JS = (ROOT / 'launch/js/founders.js').read_text()
CSS = (ROOT / 'launch/style.css').read_text()
ORGS = json.loads((ROOT / 'launch/assets/founders/orgs.json').read_text())
GEO = json.loads((ROOT / 'launch/assets/founders/geo.json').read_text())


def test_third_view_button_and_switch():
    # the button sits next to the two older views, and the choice survives a reload or a link
    assert '<button type="button" data-view="founders">Founders</button>' in MAP
    assert "m.view === 'founders'" in MAP and "qs.get('view') === 'founders'" in MAP
    assert "window.REGRET_FOUNDERS.hide()" in MAP and "window.REGRET_FOUNDERS.setLevel(l)" in MAP
    # while it is open, the old map's cards are out of the way and only the View and Zoom buttons and the timeline stay on top
    assert ".vm.vm-fview .vm-colwrap" in CSS and ".vm.vm-fview .vm-views,.vm.vm-fview .vm-zoom,.vm.vm-fview .vm-dock{z-index:8}" in CSS


def test_script_is_loaded_before_the_map_script():
    from pages import map as page

    class C:
        @staticmethod
        def _v(f):
            return 'x'
    html = page.render_home(C)
    assert html.index('founders.js?v=') < html.index('map.js?v=')


def test_draws_in_its_own_shadow_root_from_one_database_function():
    assert "attachShadow({ mode: 'open' })" in JS
    assert "O.sb.rpc('v2_founders_data')" in JS
    # founder's decisions: no tick box for giant rounds, no "Whole map" button, no word "then" between two sectors
    assert 'Include rounds of $1B' not in JS and 'Whole map' not in JS and "', then '" not in JS
    # every round counts in the cash, however big (founder, 25 Nov: "count everything")
    assert 'not counted in the cash' not in JS and 'r[1] < 1000' not in JS
    # the three choices and the two ways to draw them
    # one timeline for the whole map: Founders reads the page's own handles, it has no year buttons of its own
    assert 'seg-year' not in JS and 'setSpan' in JS and 'window.REGRET_FOUNDERS.setSpan(span())' in MAP
    assert '.vm.vm-fview .vm-dock' in CSS and '.vm.vm-fview .vm-map,.vm.vm-fview .vm-dock' not in CSS
    for word in ('data-v="places"', 'data-v="unis"', 'data-v="cos"', 'data-v="map"', 'data-v="blocks"'):
        assert word in JS


def test_every_logo_named_in_the_list_is_a_file():
    logos = ROOT / 'launch/assets/logos'
    named = [o['lg'] for kind in ('unis', 'cos') for o in ORGS[kind] if o.get('lg')]
    assert len(named) == len(set(named)) and len(named) > 200
    for fn in named:
        assert re.fullmatch(r'[uc]-[a-z0-9-]+\.png', fn) and (logos / fn).is_file(), fn
    # companies that no longer exist under that name, or whose site shows a new owner's logo, have none on purpose
    without = {o['n'] for o in ORGS['cos'] if not o.get('lg')}
    assert {'Twitter', 'Sun Microsystems', 'Lehman Brothers', 'Symantec', 'Juniper Networks', 'Cruise', 'Credit Suisse'} <= without


def test_map_rules():
    world = {s['n']: s for s in GEO['shapes']['world']}
    # French Guiana is not drawn as France; France is the part in Europe
    assert world['France']['k'] == 'fr' and world['France (overseas)']['k'] is None
    # the Europe view shows no Russian territory; Ukraine is there (with Crimea, see tools/map/gen_founders.cjs)
    eu = {s['n'] for s in GEO['shapes']['eu']}
    assert 'Russia' not in eu and 'Ukraine' in eu
    assert len(GEO['shapes']['us']) == 51
    # every university and company knows which country it is in; a US one knows its state
    for kind in ('unis', 'cos'):
        for o in ORGS[kind]:
            assert o['a'][0], o['n']
            assert o['a'][0] != 'United States' or o['a'][1], o['n']


def test_database_addition_is_recorded_and_skips_a_database_without_the_v2_tables():
    sql = (ROOT / 'supabase/migrations/20261125091159_v2_founders_view.sql').read_text()
    assert "to_regclass('public.v2_founder_facts') is null" in sql and 'raise notice' in sql
    assert 'create or replace function public.v2_founders_data()' in sql
    assert 'grant execute on function public.v2_founders_data() to anon, authenticated' in sql
    # the build function is not open to visitors; only the cached answer is
    assert 'revoke all on function public.v2_founders_build() from public, anon, authenticated' in sql
    faster = (ROOT / 'supabase/migrations/20261125091305_v2_founders_build_faster.sql').read_text()
    assert "to_regprocedure('public.v2_founders_build()') is null" in faster
