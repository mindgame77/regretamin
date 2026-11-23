-- v2_top_firms_2026 (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_top_firms_2026 skipped';
    return;
  end if;
  execute $designmig$
create table if not exists public.v2_top_firms (
  list_year   int    not null,
  firm_id     bigint not null,
  region      text,
  led         int    not null default 0,
  deals       int    not null default 0,
  world_rank  int,
  region_rank int,
  us_rank     int,
  eu_rank     int,
  added_by    text   not null default 'ranking',
  note        text,
  created_at  timestamptz not null default now(),
  primary key (list_year, firm_id)
);

comment on table public.v2_top_firms is
  'Regretamin Top Firms: frozen yearly list. Ranked by rounds led in the three years before the list was made. See docs/top-firms.md.';

alter table public.v2_top_firms enable row level security;
revoke all on public.v2_top_firms from anon, authenticated;

insert into public.v2_top_firms (list_year, firm_id, region, led, deals, world_rank, region_rank, us_rank, eu_rank)
with fp as materialized (select firm_id, region from v2_map_firm_places where region is not null),
r as (
  select d.firm_id,
         count(distinct d.startup_id || '|' || coalesce(d.round::text, '')) filter (where d.lead::text = 'yes') as led,
         count(*) as deals
  from v2_deals d
  where d.is_current
    and d.deal_date >= date '2026-11-21' - interval '3 years'
    and d.deal_date <= date '2026-11-21'
    and d.firm_id in (select firm_id from fp)
  group by 1
),
k as (
  select r.firm_id, fp.region, r.led, r.deals,
         row_number() over (order by r.led desc, r.deals desc, s.display_name) as w,
         row_number() over (partition by fp.region order by r.led desc, r.deals desc, s.display_name) as g,
         row_number() over (partition by (fp.region like 'US %') order by r.led desc, r.deals desc, s.display_name) as u,
         row_number() over (partition by (fp.region = 'Europe') order by r.led desc, r.deals desc, s.display_name) as e
  from r join fp using (firm_id) join firm_summary s using (firm_id)
  where r.led > 0
)
select 2026, firm_id, region, led, deals,
       case when w <= 100 then w end,
       case when g <= 25 then g end,
       case when region like 'US %' and u <= 100 then u end,
       case when region = 'Europe' and e <= 100 then e end
from k
where w <= 100 or g <= 25 or (region like 'US %' and u <= 100) or (region = 'Europe' and e <= 100)
on conflict (list_year, firm_id) do nothing;
$designmig$;
end
$wrapci$;
