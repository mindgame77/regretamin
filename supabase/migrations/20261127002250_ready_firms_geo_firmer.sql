-- "Am I ready to pitch?": a firmer meaning of "invests in your country" (26 Nov 2026). A firm counts when it is based in the
-- founder's country or has backed two startups from it; one startup is enough only for a country where we know fewer than 200
-- startups (so a fund in India that once backed a US startup is no longer offered to US founders). Also: signed-in users may
-- only read and add their own feedback rows, nothing else on that table.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_summary') is null or to_regclass('public.v2_startups') is null or to_regclass('public.v2_founder_facts') is null or to_regclass('public.v2_investor_principles') is null or to_regclass('public.ready_feedback') is null then
    raise notice 'tables not present, skipping';
    return;
  end if;
  execute 'revoke update, delete, truncate, references, trigger on public.ready_feedback from authenticated';
  execute $fn$
create or replace function public.v2_ready_firms_geo(p_stage text, p_sector text, p_country text, p_limit integer default 6)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $body$
with st as (select case when lower(coalesce(p_stage,'')) like 'pre%' then array['Pre-seed','Seed'] else array['Seed','Pre-seed'] end as rounds),
cc as (select nullif(upper(btrim(coalesce(p_country, ''))), '') as c),
sec as (select distinct startup_id from v2_startup_sectors where is_current and industry_name = p_sector),
anysec as (select exists (select 1 from sec) as ok),
cs as (
  select s.startup_id from v2_startups s, cc where s.is_current and upper(s.st_country) = cc.c
  union
  select r.startup_id from v2_founder_facts r join v2_founder_facts c on c.founder_id = r.founder_id and c.fact = 'current_country', cc
  where r.fact = 'role' and r.startup_id is not null and upper(btrim(c.value)) = cc.c),
reg as (
  select fs.region from firm_summary fs, cc
  where fs.listed and upper(fs.hq_country) = cc.c and fs.region is not null and fs.region <> 'unknown'
  group by fs.region order by count(*) desc limit 1),
d as (
  select v.firm_id, v.startup_id, v.deal_date,
         (v.round = any(st.rounds)) as is_stage,
         (v.startup_id in (select startup_id from sec)) as is_sec,
         a.ok as has_sec,
         (v.startup_id in (select startup_id from cs)) as is_cty,
         (v.round = (case when lower(coalesce(p_stage, '')) like 'pre%' then 'Pre-seed' else 'Seed' end)) as is_exact,
         case when v.amount_currency = 'USD' and v.round_amount > 0 and v.deal_date >= current_date - 1095 then v.round_amount end as amt
  from v2_deals v cross join st cross join anysec a
  where v.shown and v.deal_date is not null),
x as (
  select fs.firm_id, fs.slug, fs.display_name, fs.hq_city, fs.hq_country, fs.region, fs.deals,
    count(*) filter (where d.deal_date >= current_date - 365 and d.is_stage and (d.is_sec or not d.has_sec)) as n_fit,
    count(*) filter (where d.deal_date >= current_date - 365 and d.is_stage) as n_stage,
    count(*) filter (where d.deal_date >= current_date - 365) as n12,
    count(*) filter (where d.deal_date >= current_date - 90) as n90,
    round(100.0 * count(*) filter (where d.is_stage) / count(*)) as stage_pct,
    round(100.0 * count(*) filter (where d.is_sec) / count(*)) as sector_pct,
    max(d.deal_date) as last_deal,
    count(distinct d.startup_id) filter (where d.is_cty) as n_cty,
    count(d.amt) filter (where d.is_exact) as n_amt,
    percentile_cont(0.25) within group (order by d.amt) filter (where d.is_exact) as amt_lo,
    percentile_cont(0.75) within group (order by d.amt) filter (where d.is_exact) as amt_hi
  from firm_summary fs join d on d.firm_id = fs.firm_id
  where fs.listed
  group by 1, 2, 3, 4, 5, 6, 7),
g as (
  select x.*,
    case when cc.c is null then 0
         when upper(x.hq_country) = cc.c or x.n_cty >= 2 then 2
         when x.n_cty = 1 and (select count(*) from cs) < 200 then 2
         when x.region = (select region from reg) then 1
         else 0 end as geo
  from x cross join cc),
pick as (
  select g.* from g cross join cc
  where g.deals < 150 and g.last_deal >= current_date - 180
    and ((cc.c is null and g.n_fit >= 1)
      or (g.geo = 2 and g.n_stage >= 1 and (g.sector_pct > 0 or not (select ok from anysec)))
      or (g.geo = 1 and g.n_fit >= 1))
  order by g.geo desc, g.n_fit desc, g.n_cty desc, g.n90 desc, g.n12 desc
  limit greatest(1, least(coalesce(p_limit, 6), 12))),
fd as (select firm_id, startup_id, min(deal_date) as f from d group by 1, 2),
lad as (
  select p.display_name as pname, gg.firm_id as gid, count(*) as n
  from pick p join fd a on a.firm_id = p.firm_id
  join fd gg on gg.startup_id = a.startup_id and gg.f > a.f and gg.firm_id <> p.firm_id
  group by 1, 2),
big as (
  select distinct on (l.gid) gs.display_name, gs.slug, l.pname, l.n, gs.deals
  from lad l join firm_summary gs on gs.firm_id = l.gid
  where gs.listed and gs.deals >= 150 and l.gid not in (select firm_id from pick)
  order by l.gid, l.n desc)
select jsonb_build_object(
  'firms', coalesce((
    select jsonb_agg(jsonb_build_object(
      'slug', p.slug, 'name', p.display_name, 'city', p.hq_city, 'country', p.hq_country,
      'fit', p.n_fit, 'n12', p.n12, 'n90', p.n90, 'stage_pct', p.stage_pct, 'sector_pct', p.sector_pct, 'last_deal', p.last_deal,
      'geo', case p.geo when 2 then 'country' when 1 then 'region' end,
      'n_country', p.n_cty, 'hq_same', (upper(p.hq_country) = (select c from cc)),
      'rounds', case when p.n_amt >= 5 then jsonb_build_object('n', p.n_amt, 'lo', p.amt_lo, 'hi', p.amt_hi) end,
      'summary', (
        select jsonb_build_object('text', s.summary, 'who', s.investor_name, 'title', s.investor_title, 'year', extract(year from s.published_at))
        from v2_investor_principles s
        where s.firm_id = p.firm_id and coalesce(s.is_current, true) and not coalesce(s.archived, false) and s.summary is not null
        order by (s.investor_title = 'Firm') desc, s.display_order nulls last limit 1)
    ) order by p.geo desc, p.n_fit desc, p.n_cty desc, p.n90 desc, p.n12 desc) from pick p), '[]'::jsonb),
  'then', coalesce((
    select jsonb_agg(jsonb_build_object('name', b.display_name, 'slug', b.slug, 'after', b.pname, 'n', b.n) order by b.n desc, b.deals desc)
    from (select * from big order by n desc, deals desc limit 5) b), '[]'::jsonb),
  'sector_known', (select ok from anysec),
  'country', (select c from cc))
$body$
$fn$;
end
$wrapci$;
