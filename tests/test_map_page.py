"""The map page (/map/): static wiring only; no live service or credentials needed."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'launch'))
from pages.registry import PAGES

SQL = (ROOT / 'docs/map_functions.sql').read_text()
GEO = json.loads((ROOT / 'launch/assets/map/places.json').read_text())
JS = (ROOT / 'launch/js/map.js').read_text()


def test_map_is_registered_hidden_and_not_indexed():
    p = next(p for p in PAGES if p.slug == 'map')
    assert p.noindex and not p.nav and not p.sitemap


def test_every_region_in_the_sql_has_a_spot_on_the_world_map():
    region_block = SQL[SQL.index("then 'US West'"):SQL.index('end as region')]
    regions = set(re.findall(r"then '([^']+)'", region_block)) | {'US West'}
    assert regions == set(GEO['world']['places'])


def test_every_european_country_in_the_sql_has_a_spot():
    line = next(l for l in SQL.splitlines() if "then 'Europe'" in l)
    codes = set(re.findall(r"'([A-Z]{2})'", line))
    assert codes and codes <= set(GEO['eu']['places'])


def test_every_metro_area_in_the_sql_has_a_spot():
    metro_block = SQL[SQL.index('with metro(area, st, city) as (values'):SQL.index('select f.firm_id')]
    areas = set(re.findall(r"\('([^']+)','[A-Z]{2}','", metro_block))
    assert areas <= set(GEO['us']['places'])


def test_backgrounds_exist_and_page_never_invents_data():
    for name in ('world', 'us', 'eu'):
        assert (ROOT / f'launch/assets/map/{name}.svg').read_text().startswith('<svg')
    assert "sb.rpc('v2_map_summary'" in JS and "sb.rpc('v2_map_firms'" in JS and "sb.rpc('v2_map_updates'" in JS
    # the saved test answer is only ever read on a local preview host
    assert 'const FIXTURE = LOCAL ?' in JS
