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


def test_which_firms_filter():
    js = (ROOT / "launch/js/map.js").read_text()
    sql = (ROOT / "docs/map_who_filter.sql").read_text()
    # the filter is sent only when it is on, so the first versions of the functions keep serving the plain view
    assert "a.p_firms = who()" in js and "p_firms: who()" in js
    for mode in ("top", "focused", "new"):
        assert f"'{mode}'" in sql
    for mode in ("top", "focused", "first", "fresh"):
        assert f"['{mode}'," in js
    assert "v2_map_hot(text, int, text[], text[])" in sql
    assert "v2_top_firms" in sql and (ROOT / "docs/top-firms.md").exists()
    # a link can carry the view, but the page never rewrites its own address
    assert "qs.get('firms')" in js and "history.pushState" not in js and "history.replaceState" not in js


def test_new_investors_and_fresh_funds_choices():
    """Founder, 23 Nov: "New investors" = first deal ever (one meaning), "Fresh funds" = raised a fund in the last
    12 months, and while a choice is picked its meaning takes the colour key's place in the corner of the map."""
    js = (ROOT / "launch/js/map.js").read_text()
    firms = (ROOT / "launch/js/firms.js").read_text()
    css = (ROOT / "launch/style.css").read_text()
    mig = (ROOT / "supabase/migrations/20261124064028_map_firms_choice_fresh_funds_and_first_deal_ever.sql").read_text()
    assert "['first', 'New investors'], ['fresh', 'Fresh funds']" in js and "'New entrants']" not in js
    # old links and saved views that say "new" open as "New investors"
    assert "const whoKey = (k) => (k === 'new' ? 'first' : k);" in js
    # each choice has its line, and "Top firms" follows the zoom (the US list is an outside ranking)
    for line in ("The 100 top-ranked US firms of 2026", "Led the most rounds in the last 3 years",
                 "Most of their deals are in one sector", "Made their first deal in this period",
                 "Raised a new fund in the last 12 months"):
        assert line in js
    # it replaces the colour key (founder: "not appear in a new spot"); "All firms" shows the key
    assert "$('#vm-legend').innerHTML = note ? `<span class=\"vm-whonote\">" in js and 'id="vm-whonote"' not in js
    assert ".vm-whonote{display:block" in css and "position:absolute;left:24px;bottom:18px" not in css
    # the investors list passes the two new words on to the same database rule
    assert "['top', 'focused', 'first', 'fresh'].indexOf(who1)" in firms and "who === 'new' ? 'first' : who" in firms
    # rule (founder): every filter the map hands over shows in the list as a label that can be removed
    assert "WHO_LABEL = { top: 'Top firms', focused: 'Focused funds', first: 'New investors', fresh: 'Fresh funds' }" in firms
    assert "data-who-x" in firms and "if (deal) deal.who = null;" in firms
    for key, name in re.findall(r"\['(\w+)', '([^']+)'\]", js.split("const WHO = ")[1].split(";")[0]):
        assert key == 'all' or f"{key}: '{name}'" in firms  # the list uses the map's own names
    # the database: additive (old words answer as before), and the fund list is not open to visitors directly
    assert "v2_fresh_fund_firms" in mig and "revoke all on function public.v2_fresh_fund_firms() from public, anon, authenticated" in mig
    assert "cfg.mode = 'first' or exists" in mig and "p_firms in ('top', 'focused', 'new', 'first', 'fresh')" in mig


def test_investors_list_deals_column_shows_known_and_all():
    """Founder, 24 Nov: the Deals column shows the deals we know in detail and, in brackets, every investment
    found ("9 (228)", "0 (404)"); one number when they are the same. The header stays "Deals"."""
    firms = (ROOT / "launch/js/firms.js").read_text()
    css = (ROOT / "launch/style.css").read_text()
    assert "function dealsCell(f)" in firms and "const investments = dealsCell(f);" in firms
    assert "kn + ' <span class=\"finv-all\" title=" in firms and "(' + all + ')</span>'" in firms and "if (known >= allN) return all;" in firms
    assert ".frow .finv .finv-all{font-weight:400" in css
    assert "headerCell('deals', pageCopy.col_investments || 'Deals')" in firms
    # it sorts by the first number: a sort word of its own in the database, the old one untouched
    mig = (ROOT / "supabase/migrations/20261124175712_investors_list_sort_by_known_deals.sql").read_text()
    assert "p_sort: sort === 'deals' ? 'known' : sort," in firms and "(known(a) - known(b)) || (count(a) - count(b))" in firms
    assert "'deals', 'known', 'activity')" in mig and "v_sort = 'known' and not v_asc then coalesce(m.deals, 0) end desc" in mig


def test_latest_updates_follow_the_map_and_carry_the_amount():
    """Founder, 24 Nov: press United States and the updates are US ones; pick a sector or a stage and they follow;
    a round's amount is written into the line when we know it."""
    js = (ROOT / "launch/js/map.js").read_text()
    css = (ROOT / "launch/style.css").read_text()
    mig = (ROOT / "supabase/migrations/20261124182941_v2_map_updates_for.sql").read_text()
    # asked again whenever the zoom or a filter changes, never for the timeline
    assert "const updKey = () => [S.level === 'world' ? '' : S.level, S.sectors.join('|'), S.stages.join('|')].join('~');" in js
    assert "loadUpdates();  // the zoom buttons redraw without asking the database again" in js
    assert "if (S.view !== 'hot') loadUpdates();" in js and "sb.rpc('v2_map_updates_for', { p_level: S.level === 'world' ? null : S.level" in js
    # the opening view still shows its ready-made answer at once, and the old function is the fallback
    assert "sb.rpc('v2_map_cached', { p_key: 'updates' })" in js and "sb.rpc('v2_map_updates', { p_limit: n })" in js
    # the line under the title names the pick; nothing on the world view with no filter
    assert "'United States' : S.level === 'eu' ? 'Europe' : ''" in js and 'class="vm-tag vm-upfor"' in js and ".vm-side .vm-lh .vm-upfor{flex:1 0 100%" in css
    # the amount, and "a round" instead of "a Other round"
    assert "u.round !== 'Other' ? u.round + ' ' : ''" in js and "m.article + ' ' + m.text" in js and "(u.approx ? '~' : '') + sym + n" in js
    # the database: a new read-only function, open to visitors; the old one is not touched
    assert "create or replace function public.v2_map_updates_for(" in mig and "to anon, authenticated" in mig
    assert "having bool_or(here)" in mig and "current_date - 365" in mig and "create or replace function public.v2_map_updates(" not in mig


def test_hot_view_sectors_first_switch_and_lines():
    js = (ROOT / "launch/js/map.js").read_text()
    sql = (ROOT / "docs/map_hot_detail.sql").read_text()
    assert "sb.rpc('v2_map_hot_detail'" in js and "v2_map_hot_detail(text, text, text, int, text[], text[])" in sql
    # one floor for places and sectors, and a lighter shade for small moves
    assert "const HOT_MIN = 10;" in js and "const HOT_FAINT = 10;" in js and "vm-lt" in js
    # year-only deals stay out of the lines too
    assert "deal_date_precision::text <> 'year'" in sql
    fx = json.loads((ROOT / "tests/fixtures/map_hot_detail.json").read_text())
    assert all(len(r) == 5 and len(r[4]) == 8 for r in fx["sectors"])


def test_money_flow_opens_a_place_on_its_sectors_like_hot_right_now():
    """Founder, 25 Nov: pressing a circle in Money flow shows all its sectors first; a sector opens its firms in the
    panel beside it; the button on top names the place (and the sector) and opens those firms in the Investors list."""
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    js = (root / 'launch/js/map.js').read_text()
    # one way to open a place, for both views; Money flow asks for the place's sectors over the timeline's stretch of time
    assert "const det = await (S.view === 'hot' ? detail(place) : placeSectors(place));" in js
    assert "sb.rpc('v2_map_place_sectors', a)" in js
    # the firms panel, Escape, the Investors-list link and coming back to the map no longer depend on the Hot view
    assert "if (!(L && L.step === 'firms'))" in js and "const open = S.list && S.list.step === 'firms'" in js
    assert "const sec = S.list && S.list.sector ? [S.list.sector] : S.sectors;" in js
    assert "S.view === 'hot' && b.step === 'firms'" not in js
    # the words in Money flow are the ones it had before (the count of firms, the close button, "See the investors"):
    # no place label, no extra lines, no labels in the firms pop-up (founder, 25 Nov: "don't add more text", ask first)
    assert "hotList ? `See the ${num(ctaN)}" in js and "S.view === 'hot' ? `<div class=\"vm-chips\">${tags.map(" in js
    card = js[js.index('if (S.list) {  // Money flow works the same way'):js.index("// The firms behind a place (or one of its sectors) open in a panel of their own")]
    for word in ('vm-chip', 'stands out', 'Sectors here', 'unitSw', 'vm-tag', 'share of deals'):
        assert word not in card.split('side.innerHTML')[1], word
    # the database function is recorded, read-only, and skips where the v2 tables are missing (the test database)
    sql = (root / 'supabase/migrations/20261125161908_v2_map_place_sectors.sql').read_text()
    assert 'create or replace function public.v2_map_place_sectors(' in sql and 'language sql stable security definer' in sql
    assert "if to_regclass('public.v2_deals') is null" in sql and 'to anon, authenticated' in sql
    for word in ('insert into', 'update ', 'delete from', 'drop ', 'alter '):
        assert word not in sql.lower()
