-- investors_list_firm_signals (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_firm_signals skipped';
    return;
  end if;
  execute $designmig$
-- Signals for the Investors list (project doc claude/plans/investors-list.md). One row per listed firm, refreshed daily.
-- Adds a table, a refresh function and a daily job. Changes nothing that exists.
create table if not exists public.v2_firm_signals (
  firm_id bigint primary key,
  deals_now int not null default 0,     -- deals in the 12 months ending 30 days ago
  deals_prev int not null default 0,    -- deals in the 12 months before those
  led_now int not null default 0,       -- of deals_now, how many the firm led
  signals text[] not null default '{}', -- any of: up, down, top, chain, lead, spec, fund
  refreshed_at timestamptz not null default now()
);
alter table public.v2_firm_signals enable row level security;
revoke all on public.v2_firm_signals from anon, authenticated;

create or replace function public.v2_refresh_firm_signals()
returns int language plpgsql security definer
set search_path to 'public', 'pg_temp' set statement_timeout to '120s'
as $fn$
declare n int;
begin
  delete from v2_firm_signals;
  with w as (select current_date - 30 as e, current_date - 395 as m, current_date - 760 as s),
  dd as (
    select d.firm_id, d.startup_id, d.deal_date, d.lead
      from v2_deals d
     where d.is_current and d.shown and d.deal_date is not null and d.deal_date <= current_date
       and d.deal_date_precision <> 'year'
  ),
  c as (
    select dd.firm_id,
           count(*) filter (where dd.deal_date > w.m and dd.deal_date <= w.e)::int as now_,
           count(*) filter (where dd.deal_date > w.s and dd.deal_date <= w.m)::int as prev_,
           count(*) filter (where dd.deal_date > w.m and dd.deal_date <= w.e and dd.lead = 'yes')::int as led_
      from dd cross join w group by dd.firm_id
  ),
  top as (
    select t.firm_id from v2_top_firms t
     where t.list_year = (select max(list_year) from v2_top_firms) and t.world_rank is not null
  ),
  fd as (select firm_id, startup_id, min(deal_date) as d from dd group by 1, 2),
  pairs as (
    select a.firm_id as early, b.firm_id as later
      from fd a join fd b on b.startup_id = a.startup_id and b.firm_id <> a.firm_id and b.d > a.d
      join top t on t.firm_id = b.firm_id
     group by 1, 2 having count(*) >= 2
  ),
  chain as (select early as firm_id from pairs group by 1 having count(*) >= 5),
  tot as (
    select firm_id, count(*) as n from v2_deals
     where is_current and shown and deal_date > current_date - interval '3 years' and deal_date <= current_date
     group by 1 having count(*) >= 10
  ),
  spec as (
    select distinct x.firm_id from (
      select d.firm_id, sc.name, count(*) as n
        from v2_deals d
        join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current
        join v2_sector sc using (sector_id)
       where d.is_current and d.shown and d.deal_date > current_date - interval '3 years' and d.deal_date <= current_date
         and sc.name <> 'Other'
       group by 1, 2
    ) x join tot on tot.firm_id = x.firm_id where x.n > 0.5 * tot.n
  ),
  fund as (
    select distinct firm_id from v2_funds
     where is_current and not coalesce(archived, false) and not coalesce(nothing_found, false)
       and closed_on > current_date - 365 and closed_on <= current_date
  )
  insert into v2_firm_signals (firm_id, deals_now, deals_prev, led_now, signals)
  select s.firm_id, coalesce(c.now_, 0), coalesce(c.prev_, 0), coalesce(c.led_, 0),
         array_remove(array[
           case when coalesce(c.now_, 0) - coalesce(c.prev_, 0) >= 10 then 'up' end,
           case when coalesce(c.prev_, 0) - coalesce(c.now_, 0) >= 10 then 'down' end,
           case when exists (select 1 from top where top.firm_id = s.firm_id) then 'top' end,
           case when exists (select 1 from chain where chain.firm_id = s.firm_id) then 'chain' end,
           case when coalesce(c.now_, 0) >= 10 and c.led_ * 2 >= c.now_ then 'lead' end,
           case when exists (select 1 from spec where spec.firm_id = s.firm_id) then 'spec' end,
           case when exists (select 1 from fund where fund.firm_id = s.firm_id) then 'fund' end
         ], null)
    from firm_summary s left join c on c.firm_id = s.firm_id
   where s.listed;
  get diagnostics n = row_count;
  return n;
end $fn$;
revoke all on function public.v2_refresh_firm_signals() from public, anon, authenticated;

select public.v2_refresh_firm_signals();
select cron.schedule('v2-firm-signals', '41 9 * * *', $$select public.v2_refresh_firm_signals()$$);
$designmig$;
end
$wrapci$;
