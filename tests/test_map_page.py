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
    assert "const det = await (S.view === 'hot' ? detail(place) : S.view === 'path' ? pathPlace(place) : placeSectors(place));" in js
    assert "sb.rpc('v2_map_place_sectors', a)" in js
    # the firms panel, Escape, the Investors-list link and coming back to the map no longer depend on the Hot view
    assert "if (!(L && L.step === 'firms'))" in js and "const open = S.list && S.list.step === 'firms'" in js
    assert "const sec = S.list && S.list.sector ? [S.list.sector] : S.sectors;" in js
    assert "S.view === 'hot' && b.step === 'firms'" not in js
    # the words in Money flow: what was there before plus the four things he said yes to on 25 Nov (the place in the card's
    # title, the sector in the pop-up's title, the button naming what it opens, the % / # switch). Nothing else: no place
    # label with an x, no "stands out for" line, no "Sectors here", no "share of deals", no labels in the firms pop-up.
    card = js[js.index('if (S.list) {  // Money flow works the same way'):js.index("// The firms behind a place (or one of its sectors) open in a panel of their own")].split('side.innerHTML')[1]
    assert "<h2>${esc(L.place.n)} · ${det ? num(det.firms) + ' firm'" in card and '${unitSw()}' in card
    for word in ('vm-chip', 'stands out', 'Sectors here', 'vm-tag', 'share of deals'):
        assert word not in card, word
    assert "(S.view !== 'hot' && L.sector ? ' ' + esc(L.sector) : '') + ' firm'" in js
    assert "S.view === 'hot' ? `<div class=\"vm-chips\">${tags.map(" in js
    assert "$('#vm-cta').textContent = S.list ? `See the ${num(ctaN)}" in js
    # the button is always one line; a long text ("See the 31 Enterprise software investors in Seattle") is cut with …
    assert '#vm-cta{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' in (root / 'launch/style.css').read_text()
    # the database function is recorded, read-only, and skips where the v2 tables are missing (the test database)
    sql = (root / 'supabase/migrations/20261125161908_v2_map_place_sectors.sql').read_text()
    assert 'create or replace function public.v2_map_place_sectors(' in sql and 'language sql stable security definer' in sql
    assert "if to_regclass('public.v2_deals') is null" in sql and 'to anon, authenticated' in sql
    for word in ('insert into', 'update ', 'delete from', 'drop ', 'alter '):
        assert word not in sql.lower()


def test_the_second_view_is_called_trends():
    """Founder, 25 Nov: "Hot right now" is renamed "Trends" on the button; old links with ?view=hot keep working."""
    assert '<button type="button" data-view="hot">Trends</button>' in JS and '>Hot right now<' not in JS
    assert "'hot'" in JS  # the view's own name in links and code is unchanged


def test_head_card_is_the_same_four_rows_in_every_view():
    """Founder, 25 Nov: one fixed title line, the buttons, one "Based on" line, the black button, in all three views.
    The title never names the place or the sector (it wrapped onto a second line when it did)."""
    F = (ROOT / 'launch/js/founders.js').read_text(); L = (ROOT / 'launch/js/firms.js').read_text()
    assert "$('#vm-h1').textContent = 'What VCs are investing in.';" in JS and "$('#vm-h1').textContent = 'Where it is heating up.';" in JS
    assert "$('#h1').textContent = 'What founders are building.';" in F
    for old in ('What US investors are backing.', 'Who backs ${sec}', 'heating up${where}', 'What founders in ${label('):
        assert old not in JS and old not in F, old
    # Trends has a "Based on" line too, in Money flow's pattern
    hot = JS[JS.index('function drawHotHead()'):JS.index('function drawHead()')]
    assert "$('#vm-based').textContent = `Based on ${num(t.deals)} deal" in hot and 'VC firm' in hot
    # Founders: one line, and the black button, which opens the firms behind what the map shows
    assert "`Based on ${num(isPlace() ? C.total : ids.size)} startups, ${num(n)} ${things}`" in F
    assert '<a class="cta" id="cta" href="#">See the investors</a>' in F and "$('#cta').href = listUrl();" in F
    assert "'zoom=' + (isPlace() ? 'fplace' : S.kind === 'unis' ? 'funi' : 'fco')" in F
    # the note about rounds of $1B or more sits on the map (Universities and Companies), not in the head card
    assert '<p class="mapnote">Rounds of $1B or more are not counted in the cash here.</p>' in F
    # the Investors list takes the three Founders words and shows the map's name for them as its label
    assert "founders = ['fplace', 'funi', 'fco'].indexOf(zoom) !== -1" in L
    # database: the new function and the one extra filter are recorded and skip where the tables are missing
    m = ROOT / 'supabase/migrations'
    a = (m / '20261125190940_founders_see_the_investors.sql').read_text(); b = (m / '20261125191132_founders_see_the_investors_own_dates.sql').read_text(); c = (m / '20261125191257_v2_founders_firm_ids_faster.sql').read_text()
    for sql in (a, b, c):
        assert "to_regclass('public.v2_founders_cache') is null" in sql and 'raise exception' not in sql.lower()
    assert "v_fkind is null or s.firm_id in (select v2_founders_firm_ids(v_fkind, p_place, p_deal_from, p_deal_to))" in a
    assert 'create or replace function public.v2_founders_firm_ids(' in c and 'fl as materialized' in c


def test_which_firms_count_on_the_map_is_one_rule_with_a_register():
    """Founder, 25 Nov: only VC-like firms count on the map (accelerators, incubators and, for now, PE and hedge funds
    do not); the rule is kept in one place and every change to it is registered."""
    sql = (ROOT / 'supabase/migrations/20261125201804_v2_map_type_rules.sql').read_text()
    assert 'create table if not exists public.v2_map_type_rules' in sql and 'create table if not exists public.v2_map_rules_log' in sql
    assert 'create trigger v2_map_type_rules_log before insert or update or delete on public.v2_map_type_rules' in sql
    assert "t.name not in ('Accelerator', 'Incubator', 'PE', 'Hedge fund')" in sql
    assert 'create or replace view public.v2_map_counted_places' in sql
    # only the functions that count for the map read the counted view; the Investors list and firm pages are not in the list
    assert "p.proname in ('v2_map_summary', 'v2_map_firms', 'v2_map_firm_ids', 'v2_map_hot', 'v2_map_hot_detail', 'v2_map_place_sectors')" in sql
    assert 'firm_directory_page_v5' not in sql.split('do $wrapci$')[1]
    for s in (sql, (ROOT / 'supabase/migrations/20261125201859_v2_firm_type_fixes_haiku_high.sql').read_text()):
        assert "to_regclass('public.v2_firm_types_firms') is null" in s and 'raise exception' not in s.lower()
        assert 'v2_firm_type_retag_20261125' in s  # old tags are kept


def test_money_flow_and_trends_can_be_zoomed_like_founders():
    """Founder, 25 Nov: "Zoom on all three maps, phone and computer." Money flow and Trends get + and - (same spot as in
    Founders), the wheel, a pinch and a drag. At rest nothing changes; no text is added."""
    js = (ROOT / 'launch/js/map.js').read_text(); css = (ROOT / 'launch/style.css').read_text(); F = (ROOT / 'launch/js/founders.js').read_text()
    # the only new control: two buttons with no words
    assert '<div class="vm-pm" role="group" aria-label="Zoom the map"><button type="button" data-z="in" aria-label="Zoom in">+</button><button type="button" data-z="out" aria-label="Zoom out">−</button></div>' in js
    assert '.vm-pm{position:absolute;right:24px;bottom:108px;' in css and '.vm .vm-pm{right:10px;bottom:10px}' in css
    assert '.zoom{right:24px;bottom:108px}' in F and '.zoom{right:10px;bottom:10px}' in F  # the same spots as in Founders
    assert '.vm.vm-fview .vm-pm{display:none}' in css  # Founders has its own
    # at rest the map is drawn exactly as before: the zoom only multiplies
    assert "if (z <= 1.001) { S.z = 1;" in js and 'const RZ = () => 1 / Math.sqrt(S.z || 1)' in js
    # zoom goes back to rest with the view and with World / United States / Europe
    assert "S.view = v; S.list = null; S.pinned = null; zoomReset();" in js and "S.level = l; zoomReset(); land();" in js
    # wheel, pinch, drag; the end of a drag is not a click on a place
    for s in ("addEventListener('wheel'", "ptrs.size === 2 && pinch", "panBy(dx, dy)", "if (dragged) { dragged = false; return; }", "addEventListener('dragstart'"):
        assert s in js, s
    # a phone: a finger scrolls the page at rest and moves the map when zoomed in, in Founders too
    assert '.vm-map{touch-action:pan-y}.vm-map.vm-zoomed{touch-action:none;' in css
    assert '.stage.zoomed svg{touch-action:none}' in F and "classList.toggle('zoomed', z > 1)" in F
    # names and lines keep their size on the screen
    assert '.vm-lab{position:absolute;font-size:calc(12px*var(--lz,1))' in css and "calc(${p.getAttribute('stroke-width')}px * var(--lz, 1))" in js


def test_latest_updates_list_a_round_once_and_us_cities_sit_in_their_region():
    """Founder, 25 Nov ("3 is really important, double check"): a round is the database's own grouping, listed once on
    the day most of its rows carry, with each firm counted once. And "Where they invest" files a US city under the
    region most of its firms have, so the Bay Area is no longer "US Central". Old city values are kept."""
    sql = (ROOT / 'supabase/migrations/20261125222950_v2_updates_once_per_round_us_region_jp_cities.sql').read_text()
    assert sql.count("coalesce('e' || ") == 2 and sql.count('mode() within group (order by deal_date) deal_date') == 2
    assert "replace(def, 'min(region) region', 'mode() within group (order by region) region')" in sql
    assert 'v2_startup_city_cleanup_20261125' in sql and 'To undo:' in sql
    assert "to_regclass('public.v2_deals') is null" in sql  # a test database without the v2 tables skips it


def test_top_firms_have_a_logo_on_their_page_and_in_the_investors_list():
    """Founder, 25 Nov: logos for the 100 top firms. Firm page: left of the name. Investors list: in front of the name,
    and a grey square with initials for a firm without a logo ("good"). The build lists the firms that have a file."""
    logos = sorted(p.name[2:-4] for p in (ROOT / 'launch/assets/logos').glob('f-*.png'))
    assert len(logos) >= 290 and 'generalcatalyst' in logos and 'sequoia' in logos and 'y-combinator' in logos  # 90 top firms + 210 of the next 250 (25 Nov)
    build = (ROOT / 'launch/build.py').read_text(); F = (ROOT / 'launch/js/firms.js').read_text(); C = (ROOT / 'launch/js/company.js').read_text(); css = (ROOT / 'launch/style.css').read_text()
    assert "'flv': hashlib.sha1(" in build and "'f-*.png'" in build and "'firms.json'" in build and "'flogos'" not in build  # the list is its own file, not in every page
    assert """'<span class="fnm">' + logoOf(f) + '<b>'""" in F and 'class="flg flg-i"' in F and "FLOGOS.has(f.slug)" in F
    assert "function paintLogo(main)" in C and "im.onload = () =>" in C and "row.insertBefore(im, row.firstChild)" in C and "assets/logos/firms.json" in F
    assert 'main.prof .ph .ph1 .plg{width:52px;height:52px;' in css and '.firms-pg .frow .flg{width:28px;height:28px;' in css
    # generic or blurry icons were left out on purpose (a default WordPress icon, 16 and 32 px icons)
    for s in ('uniiq', 'benchmark', 'accel'):
        assert s not in logos


def test_share_link_button_copies_a_link_to_the_map_as_it_is_set_up():
    """Founder, 25 Nov: "I like share link without all this details. Just press on it, share link. That's it." He chose
    the spot above + and -. One button with no words; the link carries the view and its settings; nothing else changes."""
    js = (ROOT / 'launch/js/map.js').read_text(); css = (ROOT / 'launch/style.css').read_text(); F = (ROOT / 'launch/js/founders.js').read_text()
    assert '<button type="button" class="vm-sh" id="vm-sh" aria-label="Share link" title="Share link">' in js
    assert '.vm-sh{position:absolute;right:24px;bottom:196px;' in css and '.vm .vm-sh{right:10px;bottom:98px}' in css
    assert '.vm.vm-fview .vm-sh{display:none}' in css and 'class="share" id="share"' in F  # Founders shows its own, same spot
    # every setting the link writes is one the page reads back
    for key in ('view', 'days', 'firms', 'zoom', 'sectors', 'stages', 'from', 'to', 'unit', 'place', 'fk', 'fm'):
        assert f"'{key}=" in js or f"'{key}'" in js, key
        assert f"qs.get('{key}')" in js or f"num('{key}')" in js or f"list('{key}'" in js or f"whoKey(qs.get('{key}'))" in js, key
    assert "'unit', 'place', 'fk', 'fm'].some((k) => qs.has(k))" in js  # a shared link wins over the map remembered in this tab
    assert 'history.replaceState' not in js and 'history.pushState' not in js  # the page still never rewrites its own address
    assert "kind: ['unis', 'cos'].includes(O.kind) ? O.kind : 'places', mode: O.mode === 'blocks' ? 'blocks' : 'map'" in F


def test_pathfinders_view_shows_the_small_firms_the_top_100_follow():
    """Founder, 25 Nov: "who follows whom ... small companies that are being followed by the top 100", on the map. A fourth
    view; same head card, timeline and buttons as the others; circles per place, and a ranked list of firms."""
    js = (ROOT / 'launch/js/map.js').read_text(); css = (ROOT / 'launch/style.css').read_text()
    mig = (ROOT / 'supabase/migrations/20261126030945_v2_map_pathfinders.sql').read_text()
    assert '<button type="button" data-view="founders">Founders</button><button type="button" data-view="path">Pathfinders</button></div>' in js
    assert "sb.rpc('v2_map_pathfinders', a)" in js and "$('#vm-h1').textContent = 'Who the top firms follow.';" in js
    assert "<h2>Most followed</h2><span class=\"vm-tag\">startups followed</span>" in js
    assert "qs.get('view') === 'pathfinders'" in js and "S.view === 'path' ? 'pathfinders' : S.view" in js  # a link can open it and the share link names it
    assert '.vm-pl.vm-path{background:#F0861E;' in css
    # the rule lives in the database: small = not on the list and at most 50 deals; followed = the top firm came in later
    assert 'p_max_deals integer default 50' in mig and 'b.d > a.d' in mig and 'v2_map_counted_places' in mig
    assert 'create or replace function public.v2_map_pathfinders(' in mig and 'to anon, authenticated' in mig
