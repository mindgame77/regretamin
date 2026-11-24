-- Skipped on databases without the v2 research tables (e.g. the CI test database), like other v2 migrations.
do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_fund_announcements') is null
     or to_regprocedure('public.v2_deal_dates_conflict(date, text, date, text)') is null then
    raise notice 'v2 research tables not present; shared register migration skipped';
    return;
  end if;
  execute $sql$
-- Rest of firm_fund_announcements: link to existing fund_launch events (same firm + fund name), else one new event per firm + name.
drop table if exists fm;
create temp table fm as select id from public.firm_fund_announcements where event_id is null and is_current and not archived and name is not null;
with g as (
  select a.firm_id, lower(btrim(a.name)) k, min(a.id) seed, max(a.name) fund_name, max(a.amount_usd) amt, min(a.announced_on) d, count(distinct a.amount_usd) > 1 disagree
    from public.firm_fund_announcements a join fm using (id)
   where not exists (select 1 from public.v2_events ev where ev.kind = 'fund_launch' and ev.firm_id = a.firm_id and lower(btrim(ev.fund_name)) = lower(btrim(a.name)))
   group by 1, 2)
insert into public.v2_events (kind, firm_id, fund_name, amount, amount_currency, event_date, event_date_precision, seed_fund_announcement_id, sources_disagree, created_by)
select 'fund_launch', firm_id, fund_name, amt, 'USD', d, case when d is null then null else 'day' end, seed, disagree, 'backfill-funds-rest-20261123' from g;
update public.firm_fund_announcements a set event_id = ev.event_id from public.v2_events ev, fm
 where fm.id = a.id and ev.kind = 'fund_launch' and a.firm_id = ev.firm_id and lower(btrim(a.name)) = lower(btrim(ev.fund_name));
insert into public.v2_event_firms (event_id, firm_id)
select distinct a.event_id, a.firm_id from public.firm_fund_announcements a join fm using (id) where a.event_id is not null
on conflict (event_id, firm_id) where firm_id is not null do nothing;
insert into public.v2_event_sources (event_id, fund_announcement_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
select a.event_id, a.id, a.firm_id, coalesce(a.source_url, a.url), a.source_level, a.source_date, a.amount_usd, 'USD', a.announced_on, 'day'
  from public.firm_fund_announcements a join fm using (id) where a.event_id is not null;
update public.v2_events ev set sources_disagree = true where ev.kind = 'fund_launch' and not ev.sources_disagree
   and (select count(distinct s.reported_amount) from public.v2_event_sources s where s.event_id = ev.event_id) > 1;
create schema if not exists shared_register_20261123;
create table if not exists shared_register_20261123.funds_rest_links as select a.id, a.event_id from public.firm_fund_announcements a join fm using (id) where a.event_id is not null;

$sql$;
end
$mig$;
