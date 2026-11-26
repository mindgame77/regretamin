-- "Am I ready to pitch?", the full research (founder, 26 Nov 2026: "What's next? Full research.").
-- New and read-only; nothing existing changes. For the competitors a report names (found on the web), it answers from our own
-- data: who funded each one we hold, which listed firms hold a competitor, and how large rounds like the founder's have been.
-- A competitor is matched by its website's domain; by name only when exactly one startup carries that name (4,800 names are shared).
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_summary') is null or to_regclass('public.v2_startups') is null or to_regclass('public.v2_startup_sectors') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_ready_research(p_names text[], p_domains text[], p_stage text, p_sector text)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $body$
with inp as (
  select i as ord, p_names[i] as asked, lower(btrim(p_names[i])) as nm,
         nullif(lower(btrim(coalesce(p_domains[i], ''))), '') as dom
  from generate_subscripts(p_names, 1) i
  where i <= 12 and btrim(coalesce(p_names[i], '')) <> ''),
st as (
  select s.startup_id, s.startup_name, lower(s.startup_name) as nm, nullif(lower(s.domain), '') as dom
  from v2_startups s
  where s.is_current and not coalesce(s.archived, false)),
uniq as (
  select nm, min(startup_id) as startup_id, min(dom) as dom
  from st where nm in (select nm from inp) group by nm having count(*) = 1),
m as (
  select i.ord, i.asked,
    coalesce(
      (select s.startup_id from st s where i.dom is not null and s.dom = i.dom order by s.startup_id limit 1),
      (select u.startup_id from uniq u where u.nm = i.nm and (i.dom is null or u.dom is null or u.dom = i.dom))) as startup_id
  from inp i),
hit as (select m.ord, m.asked, m.startup_id, s.startup_name from m join st s on s.startup_id = m.startup_id),
dl as (
  select d.startup_id, d.firm_id, d.round, d.deal_date, d.round_amount, d.amount_currency
  from v2_deals d
  where d.shown and d.startup_id in (select startup_id from hit)),
last_round as (
  select distinct on (startup_id) startup_id, round, deal_date, round_amount, amount_currency
  from dl where deal_date is not null
  order by startup_id, deal_date desc, round_amount desc nulls last),
backers as (
  select dl.startup_id, fs.firm_id, fs.slug, fs.display_name, fs.deals
  from dl join firm_summary fs on fs.firm_id = dl.firm_id
  where fs.listed
  group by 1, 2, 3, 4, 5),
skip as (
  select b.firm_id, b.slug, b.display_name, b.deals, count(*) as n,
         array_agg(h.startup_name order by h.ord) as backed
  from backers b join hit h on h.startup_id = b.startup_id
  group by 1, 2, 3, 4),
sec as (select distinct startup_id from v2_startup_sectors where is_current and industry_name = p_sector),
anysec as (select exists (select 1 from sec) as ok),
rr as (
  select coalesce(d.event_id::text, 'd' || d.deal_id::text) as k, max(d.round_amount) as amt
  from v2_deals d cross join anysec a
  where d.shown and d.deal_date >= current_date - 730
    and d.round = (case when lower(coalesce(p_stage, '')) like 'pre%' then 'Pre-seed' else 'Seed' end)
    and d.round_amount > 0 and d.amount_currency = 'USD'
    and (not a.ok or d.startup_id in (select startup_id from sec))
  group by 1)
select jsonb_build_object(
  'competitors', coalesce((
    select jsonb_agg(jsonb_build_object(
      'asked', h.asked, 'name', h.startup_name,
      'round', lr.round, 'date', lr.deal_date, 'amount', lr.round_amount, 'currency', btrim(lr.amount_currency),
      'backers', coalesce((
        select jsonb_agg(jsonb_build_object('slug', b.slug, 'name', b.display_name) order by b.deals desc)
        from (select * from backers b0 where b0.startup_id = h.startup_id order by b0.deals desc limit 8) b), '[]'::jsonb)
    ) order by h.ord)
    from hit h left join last_round lr on lr.startup_id = h.startup_id), '[]'::jsonb),
  'skip', coalesce((
    select jsonb_agg(jsonb_build_object('slug', s.slug, 'name', s.display_name, 'backed', to_jsonb(s.backed)) order by s.n desc, s.deals desc)
    from (select * from skip order by n desc, deals desc limit 12) s), '[]'::jsonb),
  'rounds', (
    select jsonb_build_object(
      'n', count(*),
      'p25', percentile_cont(0.25) within group (order by amt),
      'p50', percentile_cont(0.5) within group (order by amt),
      'p75', percentile_cont(0.75) within group (order by amt),
      'p90', percentile_cont(0.9) within group (order by amt))
    from rr),
  'stage', (case when lower(coalesce(p_stage, '')) like 'pre%' then 'Pre-seed' else 'Seed' end),
  'sector_known', (select ok from anysec))
$body$
$fn$;
  execute 'revoke all on function public.v2_ready_research(text[], text[], text, text) from public, anon';
  execute 'grant execute on function public.v2_ready_research(text[], text[], text, text) to authenticated, service_role';
  execute 'comment on function public.v2_ready_research(text[], text[], text, text) is ''Am I ready to pitch, full research: for named competitors, who funded them (our data), the listed firms that hold one, and the range of rounds at the stage and sector in the last 24 months. Read-only.''';
end
$wrapci$;
