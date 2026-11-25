-- 25 Nov 2026 (founder: "2 solve, 3 yes and double check, 8 solve").
-- (3) "Latest updates" lists a round once: a round is the database's own grouping (v2_deals.event_id), dated by the day
--     most of its rows carry; a firm that is in a round twice counts once. v2_map_updates_for and v2_map_updates.
-- (2) "Where they invest": a US city takes the region most of its firms are filed under, not the first in the alphabet
--     (a few Bay Area and New York firms are filed under "US Central", which put those cities there).
-- (8) Seven Japanese startups whose city was only a ward name get their city (looked up on the web); old values kept.
do $wrapci$
declare def text;
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_startups') is null then
    raise notice 'v2 tables are not here, nothing to do'; return;
  end if;

  execute $m1$
create or replace function public.v2_map_updates_for(p_level text default null::text, p_sectors text[] default null::text[], p_stages text[] default null::text[], p_limit integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
lv as (select case when p_level in ('us', 'eu') then p_level end l),
d0 as (
  select d.event_id, d.startup_id, d.round::text round, d.deal_date, d.firm_id, (d.lead::text = 'yes') is_lead, f.deals fdeals, d.created_at,
    d.round_amount, d.amount_currency::text cur, d.amount_approximate approx,
    ((select l from lv) is null or p.level = (select l from lv)) here
  from v2_deals d join firm_summary f using (firm_id) left join v2_map_firm_places p on p.firm_id = d.firm_id
  where f.listed and d.is_current and d.shown and d.deal_date_precision::text = 'full date'
    and d.deal_date <= current_date and d.deal_date >= current_date - 365 and d.round is not null
    and (p_stages is null or cardinality(p_stages) = 0 or exists (select 1 from stg where stg.round = d.round::text and stg.stage = any(p_stages)))
    and (p_sectors is null or cardinality(p_sectors) = 0 or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
-- One line per firm in a round. A round is the database's own grouping (v2_deals.event_id); a row without one stands
-- for startup + round name + day, as before. So a round whose rows carry different days is listed once, on the day
-- most of its rows carry (the earliest when tied), and a firm that is in a round twice is counted once.
d as (
  select coalesce('e' || event_id::text, 's' || startup_id::text || '|' || round || '|' || deal_date::text) rk, firm_id,
    min(startup_id) startup_id, min(round) round, min(deal_date) deal_date, bool_or(is_lead) is_lead, max(fdeals) fdeals, max(created_at) created_at,
    max(round_amount) round_amount, (array_agg(cur order by round_amount desc nulls last))[1] cur, bool_or(approx) approx, bool_or(here) here
  from d0 group by 1, 2
),
r as (
  select min(startup_id) startup_id, min(round) round, mode() within group (order by deal_date) deal_date, count(*) investors,
    (array_agg(firm_id order by is_lead desc nulls last, fdeals desc nulls last, firm_id) filter (where here))[1:2] top_firms,
    coalesce(bool_or(is_lead) filter (where here), false) has_lead, count(*) filter (where is_lead and here) leads, max(created_at) seen,
    max(round_amount) amount, (array_agg(cur order by round_amount desc nulls last))[1] currency, coalesce(bool_or(approx), false) approx
  from d group by rk
  having bool_or(here)
  order by mode() within group (order by deal_date) desc, max(created_at) desc
  limit greatest(1, least(coalesce(p_limit, 6), 20))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'startup', s.startup_name, 'round', r.round, 'date', r.deal_date, 'investors', r.investors, 'led', r.has_lead, 'leads', r.leads,
  'amount', r.amount, 'currency', case when r.amount is not null then r.currency end, 'approx', r.amount is not null and r.approx,
  'firms', (select jsonb_agg(jsonb_build_object('name', f.display_name, 'slug', f.slug) order by o.i)
            from unnest(r.top_firms) with ordinality o(fid, i) join firm_summary f on f.firm_id = o.fid),
  'region', p.region, 'level', p.level, 'area', p.area) order by r.deal_date desc, r.seen desc), '[]'::jsonb)
from r join v2_startups s using (startup_id) left join v2_map_firm_places p on p.firm_id = r.top_firms[1]
$function$
  $m1$;

  execute $m2$
create or replace function public.v2_map_updates(p_limit integer default 4)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
with d as (  -- one line per firm in a round; a round is the database's own grouping (event_id), else startup + round + day
  select coalesce('e' || d.event_id::text, 's' || d.startup_id::text || '|' || d.round::text || '|' || d.deal_date::text) rk, d.firm_id,
    min(d.startup_id) startup_id, min(d.round::text) round, min(d.deal_date) deal_date, bool_or(d.lead::text = 'yes') is_lead, max(f.deals) fdeals, max(d.created_at) created_at
  from v2_deals d join firm_summary f using (firm_id)
  where f.listed and d.is_current and d.shown and d.deal_date_precision::text = 'full date'
    and d.deal_date <= current_date and d.deal_date >= current_date - 30 and d.round is not null
  group by 1, 2
),
r as (
  select min(startup_id) startup_id, min(round) round, mode() within group (order by deal_date) deal_date, count(*) investors,
    (array_agg(firm_id order by is_lead desc nulls last, fdeals desc nulls last, firm_id))[1:2] top_firms,
    bool_or(is_lead) has_lead, count(*) filter (where is_lead) leads, max(created_at) seen
  from d group by rk
  order by mode() within group (order by deal_date) desc, max(created_at) desc
  limit greatest(1, least(coalesce(p_limit, 4), 20))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'startup', s.startup_name, 'round', r.round, 'date', r.deal_date, 'investors', r.investors, 'led', r.has_lead, 'leads', r.leads,
  'firms', (select jsonb_agg(jsonb_build_object('name', f.display_name, 'slug', f.slug) order by o.i)
            from unnest(r.top_firms) with ordinality o(fid, i) join firm_summary f on f.firm_id = o.fid),
  'region', p.region, 'level', p.level, 'area', p.area) order by r.deal_date desc, r.seen desc), '[]'::jsonb)
from r join v2_startups s using (startup_id) left join v2_map_firm_places p on p.firm_id = r.top_firms[1]
$function$
  $m2$;

  select pg_get_functiondef('public.v2_firm_invests_where(text)'::regprocedure) into def;
  if position('min(region) region' in def) > 0 then
    execute replace(def, 'min(region) region', 'mode() within group (order by region) region');
  else
    raise notice 'v2_firm_invests_where: the region rule is not the one expected, left as it is';
  end if;

  create table if not exists public.v2_startup_city_cleanup_20261125 (
    startup_id bigint primary key, old_city text, new_city text, source text, changed_at timestamptz not null default now());
  alter table public.v2_startup_city_cleanup_20261125 enable row level security;
  comment on table public.v2_startup_city_cleanup_20261125 is
    'Japanese startups whose city was a ward name, before and after 25 Nov 2026. To undo: update v2_startups s set st_city = c.old_city from v2_startup_city_cleanup_20261125 c where c.startup_id = s.startup_id;';
  insert into public.v2_startup_city_cleanup_20261125 (startup_id, old_city, new_city, source)
  select s.startup_id, s.st_city, v.new_city, v.source
  from (values
    (143756, 'Chuo',   'Tokyo',  'initial.inc/companies/A-VAEDL: Kyobashi, Chuo-ku, Tokyo'),
    (146244, '中央区', 'Tokyo',  'initial.inc/companies/A-45680: Ginza, Chuo-ku, Tokyo'),
    (138662, '中央区', 'Tokyo',  'NEDO and its own press releases: Nihonbashi-Hamacho, Chuo-ku, Tokyo'),
    (138849, '中央区', 'Tokyo',  'compalyze.co.jp/company/2010001207814: Nihonbashi, Chuo-ku, Tokyo'),
    (138691, '中央区', 'Tokyo',  'initial.inc/companies/A-36047: Higashi-Nihonbashi, Chuo-ku, Tokyo'),
    (141774, '中区',   'Nagoya', 'METI Chubu slide: head office Nishiki 3-chome, Nagoya'),
    (141773, '東区',   'Nagoya', 'initial.inc/companies/A-38429: Aoi, Higashi-ku, Nagoya')
  ) v(startup_id, old_city, new_city, source)
  join public.v2_startups s on s.startup_id = v.startup_id and s.st_city = v.old_city
  on conflict (startup_id) do nothing;
  update public.v2_startups s set st_city = c.new_city
  from public.v2_startup_city_cleanup_20261125 c where c.startup_id = s.startup_id and s.st_city = c.old_city;
end $wrapci$;