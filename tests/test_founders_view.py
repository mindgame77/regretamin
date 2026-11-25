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
    # rounds of $1B or more stay out of the cash of universities and companies, and the page says so there; a place
    # counts every round (founder, 25 Nov: "we don't hide them completely, we just don't use them for universities")
    assert 'Rounds of $1B or more are not counted in the cash here.' in JS and '(isPlace() || r[1] < BIG)' in JS and 'const BIG = 1000;' in JS
    # the three choices and the two ways to draw them
    # one timeline for the whole map: Founders reads the page's own handles, it has no year buttons of its own
    assert 'seg-year' not in JS and 'setSpan' in JS and 'window.REGRET_FOUNDERS.setSpan(span())' in MAP
    assert '.vm.vm-fview .vm-dock' in CSS and '.vm.vm-fview .vm-map,.vm.vm-fview .vm-dock' not in CSS
    # one look for all three views (founder, 25 Nov): no colour key; Places / Universities / Companies in the head card;
    # Map / Blocks in the list card's header; a white hover card; the map in the same room as the main map
    assert 'id="key"' not in JS and 'what most startups there do' not in JS
    assert 'class="unit" id="seg-mode"' in JS and 'All other sectors' in JS
    assert 'const ROOM = { world: [16, 16, 84, 104], us: [24, 24, 96, 120], eu: [24, 24, 62, 100] };' in JS
    assert "{ world: [16, 16, 84, 104], us: [24, 24, 96, 120], eu: [24, 24, 62, 100] }" in MAP  # the main map's own numbers: keep the two in step
    for word in ('data-v="places"', 'data-v="unis"', 'data-v="cos"', 'data-v="map"', 'data-v="blocks"'):
        assert word in JS
    # one map for every view (founder, 25 Nov: "why we cannot use the same map?"): the page's land picture stays on
    # screen in the Founders view, which only lays its colours over it; only Money flow's circles and names are hidden
    rule = next(l for l in CSS.splitlines() if l.startswith('.vm.vm-fview .vm-colwrap'))
    assert '.vm-map' not in rule and '.vm.vm-fview #vm-pls,.vm.vm-fview #vm-labs' in CSS
    assert '@media (max-width:900px){.vm.vm-fview .vm-map{display:none!important}' in CSS  # on a phone it is a block of its own
    assert 'function land()' in MAP and 'function founders() { land();' in MAP
    assert '<g clip-path="url(#frame)">' in JS  # land outside the picture's frame (the tip of Alaska's islands, Fiji) is cut as the picture cuts it
    assert '.shp.plain{fill:transparent;stroke:none}' in JS and '.stage.own .shp.plain{fill:#CCD5D1;stroke:#fff}' in JS
    assert '.soft .shp.tint{animation:tint' in JS  # the colours fade in
    # the white lines of its own land are as thick as the ones build.py draws into <level>-land.svg
    assert 'const LINE = { world: 1.1, us: 1.5, eu: 1.3 };' in JS
    assert '1.5 if level == "us" else 1.3 if level == "eu" else 1.1' in (ROOT / 'launch/build.py').read_text()
    # the head card in the order of Money flow's: title, the three choices as buttons, then one "Based on" line
    assert JS.index('id="h1"') < JS.index('class="picks" id="seg-kind"') < JS.index('<p id="based">')
    assert 'that raised ${when}' not in JS
    # the startups of a pressed place: the first 25, and a button that shows them all (founder, 25 Nov)
    assert 'id="more">Show all ${num(all.length)} startups' in JS and 'more.</p>' not in JS


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


def test_founders_shapes_lie_on_the_sites_own_map():
    """The Founders view lays its states and countries over the site's grey land picture, so both must be the same
    drawing. On 25 Nov the US was fitted to a different outline in the two generators and every state sat 25 to 35 px
    beside the land (founder: "we got a little fucked up here"). Compare the land itself, not only the frames."""
    import json, re
    land = json.loads((ROOT / 'launch/assets/map/land.json').read_text())
    geo = json.loads((ROOT / 'launch/assets/founders/geo.json').read_text())
    places = json.loads((ROOT / 'launch/assets/map/places.json').read_text())

    def box(paths):
        xs, ys = [], []
        for d in paths:
            nums = [float(n) for n in re.findall(r'-?\d+(?:\.\d+)?', d)]
            xs += nums[0::2]; ys += nums[1::2]
        return min(xs), min(ys), max(xs), max(ys)

    for level in ('world', 'us', 'eu'):  # the same frame
        assert (geo['views'][level]['w'], geo['views'][level]['h']) == (places[level]['w'], places[level]['h'])
    # the United States: all states together cover exactly what the site's US land covers
    a, b = box([land['us']]), box([s['d'] for s in geo['shapes']['us']])
    assert all(abs(x - y) <= 1.5 for x, y in zip(a, b)), (a, b)
    # Europe: the frame cuts both at the same edges
    a, b = box([land['eu']]), box([s['d'] for s in geo['shapes']['eu']])
    assert all(abs(x - y) <= 1.5 for x, y in zip(a, b)), (a, b)
    # and the two generators say so: one fit per view, word for word
    A = (ROOT / 'tools/map/gen_assets.cjs').read_text(); F = (ROOT / 'tools/map/gen_founders.cjs').read_text()
    assert "d3.geoAlbersUsa().fitExtent([[10, 10], [890, 530]], usa)" in A and "find((f) => f.id === '840')" in A
    assert "d3.geoAlbersUsa().fitExtent([[10, 10], [890, 530]], topo.feature(A110, A110.objects.countries).features.find((f) => f.id === '840'))" in F
    for fit in ("d3.geoNaturalEarth1().fitExtent([[20, 70], [1040, 580]], { type: 'MultiPoint', coordinates: [[-170, -52], [180, 72], [-170, 72], [180, -52]] })",
                "d3.geoMercator().fitExtent([[0, 0], [876, 600]], { type: 'MultiPoint', coordinates: [[-25, 34.5], [50.5, 34.5], [-25, 67], [50.5, 67]] })"):
        assert fit in A and fit in F
