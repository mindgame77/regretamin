-- Home page map, Trends view: the "$" button on the Sectors card (founder, 27 Nov 2026): how many dollars rounds raised in each sector, last period vs the one before.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_map_hot_money(text, text, text, integer, text[], text[]);
--
-- Same firms, places, stages, sectors and "who" picks as v2_map_hot_detail (this is a copy of its filters), so the # and $ views look at the same deals.
--   * each round counts once per sector (several firms in one round are not added up), in dollars: v2_events.amount, converted with the latest v2_fx_rates row
--   * IPOs are left out; only rounds with an amount count (about 6 in 10 do, so totals undercount); deals with no round on record are skipped
--   * a startup with several sectors counts in each of them (as in the # view); "Other" is not listed (as in the # view)
-- Answer: {sectors: [[name, dollars in the last p_days, dollars in the p_days before, rounds with an amount in the last p_days], ...]} biggest first.
do $wrapmoney$
begin
  if to_regclass('public.v2_events') is null or to_regclass('public.v2_deals') is null or to_regclass('public.v2_fx_rates') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_map_hot_money(p_firms text, p_level text, p_place text default null, p_days integer default 90, p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (select greatest(30, least(coalesce(p_days, 90), 366)) days,
  case when p_firms in ('top', 'focused', 'new', 'first', 'fresh') then p_firms else 'all' end mode),
fresh as materialized (select f.firm_id from v2_fresh_fund_firms() f(firm_id) where (select mode from cfg) = 'fresh'),
stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
fp as materialized (
  select p.firm_id from v2_map_counted_places p, cfg
  where ((p_level = 'world' and p.region is not null and (p_place is null or p.region = p_place))
      or (p_level in ('us', 'eu') and p.level = p_level and (p_place is null or p.area = p_place)))
    and (cfg.mode <> 'top' or p.firm_id in (select t.firm_id from v2_top_firms t where t.list_year = 2026 and case p_level
          when 'us' then t.us_rank is not null when 'eu' then t.eu_rank is not null else t.world_rank is not null or t.region_rank is not null end))
),
foc as materialized (
  select x.firm_id from v2_deals x
  where (select mode from cfg) = 'focused' and x.firm_id in (select firm_id from fp)
    and x.is_current and x.shown and x.deal_date > current_date - interval '3 years' and x.deal_date <= current_date
  group by x.firm_id
  having count(*) >= 10 and case when p_sectors is null then exists (
      select 1 from v2_deals y join v2_startup_sectors ss on ss.startup_id = y.startup_id and ss.is_current join v2_sector sc using (sector_id)
      where y.firm_id = x.firm_id and y.is_current and y.shown and y.deal_date > current_date - interval '3 years' and y.deal_date <= current_date and sc.name <> 'Other'
      group by sc.name having count(*) > 0.5 * (select count(*) from v2_deals z where z.firm_id = x.firm_id and z.is_current and z.shown and z.deal_date > current_date - interval '3 years' and z.deal_date <= current_date))
    else count(*) filter (where exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) > 0.33 * count(*) end),
fst as materialized (
  select x.firm_id, min(x.deal_date) fdate from v2_deals x
  where (select mode from cfg) in ('new', 'first') and x.firm_id in (select firm_id from fp) and x.is_current and x.shown and x.deal_date is not null
    and (p_sectors is null or (select mode from cfg) = 'first' or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors)))
  group by x.firm_id),
d as materialized (
  select d.event_id, d.startup_id, d.deal_date, fst.fdate
  from v2_deals d cross join cfg left join stg on stg.round = d.round::text left join fst on fst.firm_id = d.firm_id
  where d.is_current and d.shown and d.event_id is not null
    and d.firm_id in (select firm_id from fp)
    and d.deal_date_precision::text <> 'year'
    and d.deal_date > current_date - greatest(728, 2 * cfg.days) and d.deal_date <= current_date
    and (p_stages is null or stg.stage = any(p_stages))
    and (cfg.mode <> 'focused' or d.firm_id in (select firm_id from foc))
    and (cfg.mode not in ('new', 'first') or fst.fdate is not null)
    and (cfg.mode <> 'fresh' or d.firm_id in (select firm_id from fresh))
),
fx as materialized (select distinct on (currency) currency, usd_rate from v2_fx_rates order by currency, as_of desc),
ev as materialized (
  -- one row per round: counts in "now" / "before" if at least one of its deals does (same test as the # view)
  select d.event_id, d.startup_id,
    bool_or(d.deal_date > current_date - cfg.days and (cfg.mode not in ('new', 'first') or d.fdate > current_date - cfg.days)) as is_now,
    bool_or(d.deal_date <= current_date - cfg.days and d.deal_date > current_date - 2 * cfg.days and (cfg.mode not in ('new', 'first') or d.fdate > current_date - 2 * cfg.days)) as is_prev,
    max(e.amount * coalesce(fx.usd_rate, case when e.amount_currency is null then 1 end)) as usd
  from d cross join cfg
  join v2_events e on e.event_id = d.event_id and e.kind::text = 'round' and coalesce(e.round, '') <> 'IPO' and e.amount > 0
  left join fx on fx.currency = e.amount_currency
  group by d.event_id, d.startup_id
),
s as (
  select sc.name,
    coalesce(sum(ev.usd) filter (where ev.is_now), 0) as now_usd,
    coalesce(sum(ev.usd) filter (where ev.is_prev), 0) as prev_usd,
    count(*) filter (where ev.is_now) as n
  from ev join v2_startup_sectors ss on ss.startup_id = ev.startup_id and ss.is_current join v2_sector sc using (sector_id)
  where ev.usd is not null and sc.name <> 'Other' and (p_sectors is null or sc.name = any(p_sectors))
  group by sc.name
)
select jsonb_build_object('sectors', coalesce((
  select jsonb_agg(jsonb_build_array(name, round(now_usd), round(prev_usd), n) order by now_usd desc, name) from s where now_usd + prev_usd > 0), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_map_hot_money(text, text, text, integer, text[], text[]) from public';
  execute 'grant execute on function public.v2_map_hot_money(text, text, text, integer, text[], text[]) to anon, authenticated';
end $wrapmoney$;
