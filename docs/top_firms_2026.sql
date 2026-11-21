-- Regretamin Top Firms, 2026 edition.
-- Applied to production on 2026-11-21 at the founder's request. Not yet in supabase/migrations/.
-- Plain-words explanation: docs/top-firms.md.
--
-- What this is: a frozen, once-a-year list of the venture firms we call "top".
-- How a firm gets on it: by the number of rounds it LED in the three years before the list was made
-- (2023-11-21 to 2026-11-21). Leading means the firm set the terms of the round. Accelerators do
-- hundreds of small deals but almost never lead, so they fall out on their own; that is why the list
-- is not ranked by plain deal count.
--
-- One row per firm per year. A firm can hold up to four ranks:
--   world_rank   1..100  top 100 of all listed firms
--   region_rank  1..25   top 25 inside its own map region (the 17 regions of the main map)
--   us_rank      1..100  top 100 among firms based in the United States
--   eu_rank      1..100  top 100 among firms based in Europe
-- Ties are broken by total deals in the same three years, then by name.
-- A firm needs at least one led round to be ranked, so small regions can have fewer than 25.
--
-- The list does not change during the year. Next year: run the insert again with list_year = 2027.
-- Hand edits: insert or delete a row and set added_by = 'hand' and a note saying why.

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

-- Nobody reads this table directly from the website; the map functions (security definer) read it.
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
