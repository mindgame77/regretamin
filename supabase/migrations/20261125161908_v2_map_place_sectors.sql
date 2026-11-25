-- Home page map, "Money flow": a pressed place opens on its sectors first, as in "Hot right now" (founder, 25 Nov).
-- New read-only function; nothing existing is changed.
--   p_level / p_place   the map's zoom ('world', 'us', 'eu') and the place as the map names it
--   p_from / p_to       the stretch of time the timeline shows
--   p_stages / p_sectors the map's own names; with sectors chosen only those are listed (as v2_map_summary does)
-- Returns every sector of the place: deals (one row is one firm's part in one round; a startup with several sectors
-- counts in each, as on the map) and firms (the same firms v2_map_firms lists for that sector).
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_firm_places') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_map_place_sectors(p_level text, p_place text, p_from date default '2021-01-01'::date, p_to date default null, p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
fp as materialized (
  select p.firm_id from v2_map_firm_places p
  where (p_level = 'world' and p.region = p_place) or (p_level in ('us', 'eu') and p.level = p_level and p.area = p_place)
),
d as materialized (
  select d.startup_id, d.firm_id
  from v2_deals d join fp using (firm_id) left join stg on stg.round = d.round::text
  where d.is_current and d.shown
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
s as (
  select sc.name, count(*) n, count(distinct d.firm_id) f
  from d join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current join v2_sector sc using (sector_id)
  where p_sectors is null or sc.name = any(p_sectors)
  group by 1
)
select jsonb_build_object(
  'deals', (select count(*) from d),
  'firms', (select count(distinct firm_id) from d),
  'tot', coalesce((select sum(n) from s), 0),
  'sectors', coalesce((select jsonb_agg(jsonb_build_array(name, n, f) order by n desc, name) from s), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_map_place_sectors(text, text, date, date, text[], text[]) from public';
  execute 'grant execute on function public.v2_map_place_sectors(text, text, date, date, text[], text[]) to anon, authenticated';
end $wrapci$;
