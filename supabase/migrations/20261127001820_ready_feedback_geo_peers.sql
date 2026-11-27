-- "Am I ready to pitch?": three additions asked for by the founder on 26 Nov 2026. All new; nothing existing changes.
--   1. ready_feedback: what a founder writes in the feedback box (what is good, what is missing, what is wrong). Own rows only.
--   2. v2_ready_firms_geo: the firms to pitch, now led by firms that invest where the founder is ("you're a Ukrainian startup,
--      here is the fund that invests in Ukraine"): firms that backed a startup from that country or are based there, then firms
--      of the same region. With no country it answers as v2_ready_firms does.
--      Each firm also carries the size of the rounds it usually joins at the stage (the middle half of its dollar rounds of the
--      last three years, when we hold five or more).
--   3. v2_ready_ask_peers: among rounds at the stage and field of at least the founder's ask, what the founders had
--      (a known university, a known employer, a company built before), so a high ask can be seen against who raised it.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_summary') is null or to_regclass('public.v2_startups') is null or to_regclass('public.v2_founder_facts') is null or to_regclass('public.v2_founder_org_aliases') is null or to_regclass('public.v2_investor_principles') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $q$
create table if not exists public.ready_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  report_id uuid,
  created_at timestamptz not null default now(),
  good text check (char_length(good) <= 4000),
  missing text check (char_length(missing) <= 4000),
  wrong text check (char_length(wrong) <= 4000))
$q$;
  execute 'alter table public.ready_feedback enable row level security';
  execute 'drop policy if exists ready_feedback_owner_insert on public.ready_feedback';
  execute 'create policy ready_feedback_owner_insert on public.ready_feedback for insert to authenticated with check (user_id = auth.uid())';
  execute 'drop policy if exists ready_feedback_owner_select on public.ready_feedback';
  execute 'create policy ready_feedback_owner_select on public.ready_feedback for select to authenticated using (user_id = auth.uid())';
  execute 'revoke all on public.ready_feedback from anon, public';
  execute 'grant select, insert on public.ready_feedback to authenticated';
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
         when x.n_cty > 0 or upper(x.hq_country) = cc.c then 2
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
  execute $fn$
create or replace function public.v2_ready_ask_peers(p_stage text, p_sector text, p_ask numeric)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $body$
with sec as (select distinct startup_id from v2_startup_sectors where is_current and industry_name = p_sector),
anysec as (select exists (select 1 from sec) as ok),
rr as (
  select coalesce(d.event_id::text, 'd' || d.deal_id::text) as k, max(d.startup_id) as startup_id, max(d.round_amount) as amt
  from v2_deals d cross join anysec a
  where d.shown and d.deal_date >= current_date - 730
    and d.round = (case when lower(coalesce(p_stage, '')) like 'pre%' then 'Pre-seed' else 'Seed' end)
    and d.round_amount > 0 and d.amount_currency = 'USD'
    and (not a.ok or d.startup_id in (select startup_id from sec))
  group by 1),
big as (select distinct startup_id from rr where amt >= p_ask),
fo as (
  select distinct b.startup_id, f.founder_id
  from big b join v2_founder_facts f on f.startup_id = b.startup_id and f.fact = 'role'),
ff as (
  select fo.startup_id, f.fact, f.value, a.name as known
  from fo join v2_founder_facts f on f.founder_id = fo.founder_id and f.fact in ('past_job', 'university', 'founded_before')
  left join v2_founder_org_aliases a on a.value_norm = f.value_norm
       and a.kind = case f.fact when 'university' then 'uni' when 'past_job' then 'co' end)
select jsonb_build_object(
  'rounds', (select count(*) from big),
  'known', (select count(distinct startup_id) from fo),
  'uni', (select count(distinct startup_id) from ff where fact = 'university' and known is not null),
  'co', (select count(distinct startup_id) from ff where fact = 'past_job' and known is not null),
  'built', (select count(distinct startup_id) from ff where fact = 'founded_before' and value ilike 'yes:%'),
  'unis', coalesce((select jsonb_agg(u.known) from (select known from ff where fact = 'university' and known is not null group by known order by count(distinct startup_id) desc, known limit 3) u), '[]'::jsonb),
  'cos', coalesce((select jsonb_agg(u.known) from (select known from ff where fact = 'past_job' and known is not null group by known order by count(distinct startup_id) desc, known limit 3) u), '[]'::jsonb))
$body$
$fn$;
  execute 'revoke all on function public.v2_ready_firms_geo(text, text, text, integer) from public, anon';
  execute 'grant execute on function public.v2_ready_firms_geo(text, text, text, integer) to authenticated, service_role';
  execute 'revoke all on function public.v2_ready_ask_peers(text, text, numeric) from public, anon';
  execute 'grant execute on function public.v2_ready_ask_peers(text, text, numeric) to authenticated, service_role';
end
$wrapci$;
