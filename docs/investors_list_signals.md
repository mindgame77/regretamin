# Investors list: signals and the "Deals this year" filter (database side)

Applied to production on 2026-11-22 at the founder's request. For the developer and data owner to review and add to
`supabase/migrations/`. The full SQL is in the Supabase migration history under the two names below.
Nothing that existed was changed: `firm_directory_page_v2` is untouched and the live site keeps using it.

## Migration `investors_list_firm_signals`
- **Table `v2_firm_signals`** (`firm_id` pk, `deals_now`, `deals_prev`, `led_now`, `signals text[]`, `refreshed_at`).
  Row level security on; no access for `anon` or `authenticated`. One row per listed firm.
- **Function `v2_refresh_firm_signals()`** (security definer, 120 s timeout) empties and refills the table.
  Deals counted: `v2_deals` where `is_current and shown`, dated, not in the future, `deal_date_precision <> 'year'`.
  - `deals_now`: the 12 months ending 30 days ago. `deals_prev`: the 12 months before those. `led_now`: of `deals_now`, `lead = 'yes'`.
  - `up`: `deals_now - deals_prev >= 10`. `down`: `deals_prev - deals_now >= 10`.
  - `top`: in `v2_top_firms` for the newest `list_year`, with a `world_rank`.
  - `chain`: at least 5 top firms each first invested in 2 or more of the firm's startups after the firm's own first deal there.
  - `lead`: `deals_now >= 10` and led at least half of them.
  - `spec`: 10 or more deals in 3 years and more than half of them in one sector (not "Other").
  - `fund`: a current `v2_funds` row with `closed_on` in the last 12 months.
  - Not built: "Backs first-timers" (the founder data needs a rule first).
- **Job** `v2-firm-signals`, daily at 09:41 UTC: `select public.v2_refresh_firm_signals()`.
- First run: 5,610 firms; up 68, down 26, top 100, chain 34, lead 67, spec 389, fund 35.

## Migration `investors_list_directory_page_v3`
`firm_directory_page_v3` is `firm_directory_page_v2` copied with these changes (made by text replacement on the stored definition):
- Two more arguments: `p_signals text[]` (a firm must have all of them) and `p_deals_year text` (`lt5`, `5`, `10`, `25`, on `deals_now`).
- `firm_summary` is left-joined to `v2_firm_signals`.
- Search matches the firm's name, short name and website only. The startup-name match is removed (founder: the list finds VCs only).
- Each row carries `signals`, `deals_now`, `deals_prev`, `led_now`, and no longer carries `startups` and `startup_sites`
  (a page of 100 rows went from about 86 KB to about 70 KB).
- The first page's `facets` also carry `signals` and `deals_year` counts.
- Execute is granted to `anon` and `authenticated`, as for v2.

Timed as `anon` after the change: default page 0.55 s (v2: 0.45 s), a signals filter 0.7 s, "25 or more" 0.9 s, a name search 0.9 s.

## Migration `firm_page_signals_for_one_firm` (2026-11-22)
`v2_firm_signals_for(p_slug text)` returns one listed firm's `signals`, `deals_now`, `deals_prev`, `led_now` as JSON, or null
for an unknown slug. Read-only, security definer, 3 s timeout, execute granted to `anon` and `authenticated`.
The firm page calls it to draw the icons in the status tile. Timed as `anon`: 8 ms.

## Migration `ready_to_pitch_interest` (2026-11-22)
For the "Am I ready for this firm?" button, which opens a "coming soon, leave your email" box until the feature is built.
- Table `v2_ready_interest` (`id`, `email`, `firm_slug`, `created_at`; unique on email + firm). Row level security on; no access for `anon` or `authenticated`.
- Function `v2_ready_interest_add(p_email text, p_slug text)`: checks the email's shape, stops at 300 new rows an hour, stores the row, returns `{"status": "ok" | "bad_email" | "rate_limited"}`. Security definer, 3 s timeout, execute granted to `anon` and `authenticated`.

## Migration `firm_page_who_invests_around` (2026-11-22)
`v2_firm_around(p_slug text)` feeds the "Who invests around them" card on the firm page. Read-only, security definer, 4 s timeout,
execute granted to `anon` and `authenticated`. Returns `{startups, before, with, after}`, each group as `{firms, list:[{name, slug, n}]}`.
- For each startup the firm backed, every other listed firm's first deal there is compared with this firm's first deal:
  earlier = before, same day = with, later = after. A firm goes in the group where most of its shared startups fall.
- Deals counted: `is_current and shown`, dated, not in the future, `deal_date_precision <> 'year'`.
- A firm is kept when it shares 3 or more startups, or 2 or more and at least 10% of this firm's startups, or it is a
  top-100 firm that came in after at least twice.
- Not done: hiding pairs that are really the same firm under two names (claude/duplicate-firm-candidates.md in the project).
Timed: about 45 ms for Sequoia, a16z and 500 Global.

## Migration `firm_page_signals_with_map_place` (2026-11-22)
`v2_firm_signals_for` also returns `place: {region, level, area}` from `v2_map_firm_places`, so the firm page's "On the map"
card can put the firm's dot on the right map. The keys it already returned are unchanged. Timed: about 20 ms for two firms.

## Migration `investors_list_directory_page_v4_map_place` (2026-11-22)
`firm_directory_page_v4` is a copy of `firm_directory_page_v3` (left untouched) with two more optional arguments,
`p_place_level text` (`world`, `us` or `eu`) and `p_place text`. Together they keep only firms that sit in that place on the
map, read from `v2_map_firm_places` with the same rule `v2_map_firms` uses: at `world` level `region = p_place`, at `us` / `eu`
level `level = p_place_level and area = p_place`. Any other level is ignored. Rows, totals and facets are as in v3.
Execute granted to `anon`, `authenticated` and `service_role`.

It was made by reading v3's text and replacing five spots (the migration refuses to run if v3's text has changed):
the name, the argument list, two new variables (`v_plevel`, `v_place`), `v_narrow`, and one more line in the `where` of `scored`:

```sql
and (v_place is null or s.firm_id in (select mp.firm_id from v2_map_firm_places mp
     where (v_plevel = 'world' and mp.region = v_place)
        or (v_plevel in ('us', 'eu') and mp.level = v_plevel and mp.area = v_place)))
```

Used by the map's "See the investors" button, which opens the Investors list with the place, sectors and stages as tags
(`investors/?zoom=world&place=US West&pname=US West&sectors=Bio|AI models&stages=Pre-seed`). The map's "Series C+" becomes
Series C, D, E and F on the list.

The list's count is close to the map's but not the same: the map counts firms that did deals in those sectors and stages in
the chosen period; the list counts firms whose profile carries those sectors and stages (founder accepted, 22 Nov).
Example, US West + Bio, Climate & Energy, AI models + Pre-seed: map 125 firms, list 121.
Timed as `anon`: 0.5 s with a place, three sectors and a stage; no place gives the same total as v3 (5,660).
