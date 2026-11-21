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
    assert "'v2_map_summary'" in JS and "sb.rpc('v2_map_firms'" in JS and "sb.rpc('v2_map_updates'" in JS
    # the saved test answer is only ever read on a local preview host
    assert 'const FIXTURE = LOCAL ?' in JS


def test_hot_view_reads_its_own_function_and_skips_year_only_dates():
    hot_sql = (ROOT / 'docs/map_hot_function.sql').read_text()
    assert "sb.rpc(hot ? 'v2_map_hot' : 'v2_map_summary'" in JS
    # a deal known only by its year sits on 1 January and would fake a jump
    assert "deal_date_precision::text <> 'year'" in hot_sql


def test_which_firms_filter_and_copy_link():
    js = (ROOT / "launch/js/map.js").read_text()
    sql = (ROOT / "docs/map_who_filter.sql").read_text()
    # the filter is sent only when it is on, so the first versions of the functions keep serving the plain view
    assert "a.p_firms = who()" in js and "p_firms: who()" in js
    for mode in ("top", "focused", "new"):
        assert f"'{mode}'" in sql and f"['{mode}'," in js
    assert "v2_map_hot(text, int, text[], text[])" in sql
    assert "v2_top_firms" in sql and (ROOT / "docs/top-firms.md").exists()
    # the copied link is built on demand; the page never rewrites its own address
    assert "linkNow" in js and "history.pushState" not in js and "history.replaceState" not in js
