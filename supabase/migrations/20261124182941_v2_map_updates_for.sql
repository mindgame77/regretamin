-- Home page map, "Latest updates": the list follows what the map shows (founder, 24 Nov).
-- New read-only function; v2_map_updates() and the 15-minute cache are untouched.
--   p_level   'us' or 'eu' = only rounds a firm from there took part in (the firms named are the ones from there);
--             anything else = everywhere.
--   p_sectors / p_stages = the map's own names (stages as on the map: Pre-seed, Seed, Series A, Series B, Series C+, Growth).
-- It also returns the round's amount, when known. A narrow pick reaches back up to a year instead of coming back empty.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_firm_places') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_map_updates_for(p_level text default null, p_sectors text[] default null, p_stages text[] default null, p_limit integer default 6)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
lv as (select case when p_level in ('us', 'eu') then p_level end l),
d as (
  select d.startup_id, d.round::text round, d.deal_date, d.firm_id, (d.lead::text = 'yes') is_lead, f.deals fdeals, d.created_at,
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
r as (
  select startup_id, round, deal_date, count(*) investors,
    (array_agg(firm_id order by is_lead desc nulls last, fdeals desc nulls last) filter (where here))[1:2] top_firms,
    coalesce(bool_or(is_lead) filter (where here), false) has_lead, count(*) filter (where is_lead and here) leads, max(created_at) seen,
    max(round_amount) amount, (array_agg(cur order by round_amount desc nulls last))[1] currency, coalesce(bool_or(approx), false) approx
  from d group by 1, 2, 3
  having bool_or(here)
  order by deal_date desc, max(created_at) desc
  limit greatest(1, least(coalesce(p_limit, 6), 20))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'startup', s.startup_name, 'round', r.round, 'date', r.deal_date, 'investors', r.investors, 'led', r.has_lead, 'leads', r.leads,
  'amount', r.amount, 'currency', case when r.amount is not null then r.currency end, 'approx', r.amount is not null and r.approx,
  'firms', (select jsonb_agg(jsonb_build_object('name', f.display_name, 'slug', f.slug) order by o.i)
            from unnest(r.top_firms) with ordinality o(fid, i) join firm_summary f on f.firm_id = o.fid),
  'region', p.region, 'level', p.level, 'area', p.area) order by r.deal_date desc, r.seen desc), '[]'::jsonb)
from r join v2_startups s using (startup_id) left join v2_map_firm_places p on p.firm_id = r.top_firms[1]
$body$
  $fn$;
  execute 'revoke all on function public.v2_map_updates_for(text, text[], text[], integer) from public';
  execute 'grant execute on function public.v2_map_updates_for(text, text[], text[], integer) to anon, authenticated';
end $wrapci$;
