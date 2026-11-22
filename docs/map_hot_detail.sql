-- Sector detail for the Hot right now view: every sector of a zoom level or of one place, with the number of
-- firms behind it and a small line of the last two years.
--
-- STATUS: APPLIED TO PRODUCTION on 2026-11-22 by Claude at the founder's request (migration v2_map_hot_detail).
-- Not yet in supabase/migrations/: for the developer to add.
--
-- Returns {"sectors": [[name, deals_now, deals_before, firms_now, [8 numbers, oldest first]], ...]}
--   deals_now / deals_before  the last p_days against the p_days before, as in v2_map_hot
--   the 8 numbers             deals in eight steps of 91 days ending today, so the last step is the last 91 days
--                             and the line never ends on a half-finished quarter
--   p_place null              the whole zoom level (the Sectors card); otherwise one region or area (a clicked circle)
--   p_firms                   'all' | 'top' | 'focused' | 'new', same meaning as in docs/map_who_filter.sql.
--                             For 'new' each step counts the firms whose first deal fell in that same step.
-- Deals known only by their year, and deals with no date, are left out (as in v2_map_hot).
-- The same migration also changed one rule inside both versions of v2_map_hot: a sector is named as a place's
-- riser or faller once it has 10 deals across the two periods (it was 8 in one period).
-- Undo: drop function if exists public.v2_map_hot_detail(text, text, text, int, text[], text[]);

create or replace function public.v2_map_hot_detail(
  p_firms text, p_level text, p_place text default null,
  p_days int default 90, p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path = public as $fn$
with cfg as (select greatest(30, least(coalesce(p_days, 90), 366)) days,
  case when p_firms in ('top', 'focused', 'new') then p_firms else 'all' end mode),
stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
fp as materialized (
  select p.firm_id from v2_map_firm_places p, cfg
  where ((p_level = 'world' and p.region is not null and (p_place is null or p.region = p_place))
      or (p_level in ('us', 'eu') and p.level = p_level and (p_place is null or p.area = p_place)))
    and (cfg.mode <> 'top' or p.firm_id in (select t.firm_id from v2_top_firms t where t.list_year = 2026 and case p_level
          when 'us' then t.us_rank is not null when 'eu' then t.eu_rank is not null else t.world_rank is not null or t.region_rank is not null end))
),
foc as materialized (
  select x.firm_id from v2_deals x
  where (select mode from cfg) = 'focused' and x.firm_id in (select firm_id from fp)
    and x.is_current and x.deal_date > current_date - interval '3 years' and x.deal_date <= current_date
  group by x.firm_id
  having count(*) >= 10 and case when p_sectors is null then exists (
      select 1 from v2_deals y join v2_startup_sectors ss on ss.startup_id = y.startup_id and ss.is_current join v2_sector sc using (sector_id)
      where y.firm_id = x.firm_id and y.is_current and y.deal_date > current_date - interval '3 years' and y.deal_date <= current_date and sc.name <> 'Other'
      group by sc.name having count(*) > 0.5 * (select count(*) from v2_deals z where z.firm_id = x.firm_id and z.is_current and z.deal_date > current_date - interval '3 years' and z.deal_date <= current_date))
    else count(*) filter (where exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) > 0.33 * count(*) end),
fst as materialized (
  select x.firm_id, min(x.deal_date) fdate from v2_deals x
  where (select mode from cfg) = 'new' and x.firm_id in (select firm_id from fp) and x.is_current and x.deal_date is not null
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors)))
  group by x.firm_id),
d as materialized (
  select d.startup_id, d.firm_id, d.deal_date, (current_date - d.deal_date) / 91 b, fst.fdate
  from v2_deals d cross join cfg left join stg on stg.round = d.round::text left join fst on fst.firm_id = d.firm_id
  where d.is_current
    and d.firm_id in (select firm_id from fp)
    and d.deal_date_precision::text <> 'year'
    and d.deal_date > current_date - greatest(728, 2 * cfg.days) and d.deal_date <= current_date
    and (p_stages is null or stg.stage = any(p_stages))
    and (cfg.mode <> 'focused' or d.firm_id in (select firm_id from foc))
    and (cfg.mode <> 'new' or fst.fdate is not null)
),
s as (
  select sc.name,
    count(*) filter (where d.deal_date > current_date - cfg.days and (cfg.mode <> 'new' or d.fdate > current_date - cfg.days)) n,
    count(*) filter (where d.deal_date <= current_date - cfg.days and d.deal_date > current_date - 2 * cfg.days and (cfg.mode <> 'new' or d.fdate > current_date - 2 * cfg.days)) p,
    count(distinct d.firm_id) filter (where d.deal_date > current_date - cfg.days and (cfg.mode <> 'new' or d.fdate > current_date - cfg.days)) f,
    jsonb_build_array(count(*) filter (where d.b = 7 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 7)), count(*) filter (where d.b = 6 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 6)), count(*) filter (where d.b = 5 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 5)), count(*) filter (where d.b = 4 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 4)), count(*) filter (where d.b = 3 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 3)), count(*) filter (where d.b = 2 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 2)), count(*) filter (where d.b = 1 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 1)), count(*) filter (where d.b = 0 and (cfg.mode <> 'new' or (current_date - d.fdate) / 91 = 0))) line
  from d cross join cfg join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current join v2_sector sc using (sector_id)
  where sc.name <> 'Other' and (p_sectors is null or sc.name = any(p_sectors))
  group by sc.name, cfg.days, cfg.mode
)
select jsonb_build_object('sectors', coalesce((
  select jsonb_agg(jsonb_build_array(name, n, p, f, line) order by n desc, name) from s where n + p > 0), '[]'::jsonb))
$fn$;

grant execute on function public.v2_map_hot_detail(text, text, text, int, text[], text[]) to anon, authenticated;
