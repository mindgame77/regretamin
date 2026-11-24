-- Fill the register from data saved in the last 5 days only (plus other firms' existing deals for the same rounds).
-- Setting event_id must not change shown or rerun summaries, so the row/statement triggers on v2_deals are paused for this transaction only.
set local statement_timeout = '15min';
drop table if exists m;
create temp table m (deal_id bigint primary key, event_id bigint not null);

do $$
declare s record; e bigint;
begin
  for s in
    select d.* from public.v2_deals d
     where d.created_at >= now() - interval '5 days'
       and d.is_current and not d.archived and not coalesce(d.nothing_found, false)
       and d.round is not null and d.startup_id is not null
     order by d.deal_id
  loop
    if exists (select 1 from m where m.deal_id = s.deal_id) then continue; end if;
    e := null;
    select ev.event_id into e from public.v2_events ev
     where ev.kind = 'round' and ev.startup_id = s.startup_id
       and ev.round = public.v2_deal_round_norm(s.round)
       and not (nullif(lower(btrim(ev.round_extension)), '') is not null and nullif(lower(btrim(s.round_extension)), '') is not null
                and lower(btrim(ev.round_extension)) <> lower(btrim(s.round_extension)))
       and not public.v2_deal_dates_conflict(ev.event_date, ev.event_date_precision, s.deal_date, s.deal_date_precision)
       and not (ev.round in ('Bridge','Debt','Grant','Other') and ev.amount is not null and s.round_amount is not null and ev.amount <> s.round_amount)
     order by ev.event_id limit 1;
    if e is null then
      insert into public.v2_events (kind, startup_id, round, round_extension, event_date, event_date_precision, amount, amount_currency, seed_deal_id, created_by)
      values ('round', s.startup_id, public.v2_deal_round_norm(s.round), nullif(btrim(s.round_extension), ''), s.deal_date, s.deal_date_precision,
              s.round_amount, s.amount_currency, s.deal_id, 'backfill-5d-20261123')
      returning event_id into e;
    end if;
    insert into m (deal_id, event_id)
    select d.deal_id, e from public.v2_deals d
     where not exists (select 1 from m where m.deal_id = d.deal_id) and d.startup_id = s.startup_id
       and d.is_current and not d.archived and not coalesce(d.nothing_found, false)
       and public.v2_deal_round_norm(d.round) = public.v2_deal_round_norm(s.round)
       and not (nullif(lower(btrim(d.round_extension)), '') is not null and nullif(lower(btrim(s.round_extension)), '') is not null
                and lower(btrim(d.round_extension)) <> lower(btrim(s.round_extension)))
       and not public.v2_deal_dates_conflict(d.deal_date, d.deal_date_precision, s.deal_date, s.deal_date_precision)
       and not (public.v2_deal_round_norm(s.round) in ('Bridge','Debt','Grant','Other') and d.round_amount is not null and s.round_amount is not null
                and d.round_amount <> s.round_amount);
  end loop;
end $$;

-- One update, triggers paused only around it (short lock).
set local lock_timeout = '20s';
alter table public.v2_deals disable trigger v2_deals_pre2021;
alter table public.v2_deals disable trigger v2_deals_date;
alter table public.v2_deals disable trigger v2_deals_srcdate;
alter table public.v2_deals disable trigger firm_summary_upd;
alter table public.v2_deals disable trigger v2_deals_founder_park_upd;
update public.v2_deals d set event_id = m.event_id from m where m.deal_id = d.deal_id;
alter table public.v2_deals enable trigger v2_deals_pre2021;
alter table public.v2_deals enable trigger v2_deals_date;
alter table public.v2_deals enable trigger v2_deals_srcdate;
alter table public.v2_deals enable trigger firm_summary_upd;
alter table public.v2_deals enable trigger v2_deals_founder_park_upd;

insert into public.v2_event_firms (event_id, firm_id, lead)
select event_id, firm_id, bool_or(coalesce(lead::text, '') in ('true','t'))
  from public.v2_deals where event_id is not null and firm_id is not null group by 1, 2;

insert into public.v2_event_sources (event_id, deal_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
select event_id, deal_id, firm_id, source_url, source_level, source_date, round_amount, amount_currency, deal_date, deal_date_precision
  from public.v2_deals where event_id is not null;

update public.v2_events ev set sources_disagree = true
 where ev.kind = 'round' and (select count(distinct s.reported_amount) from public.v2_event_sources s where s.event_id = ev.event_id) > 1;

-- Fund launches (last 5 days of fund announcements), one event per firm + fund name.
with g as (
  select firm_id, lower(btrim(name)) k, min(id) seed, max(name) fund_name, max(amount_usd) amt, min(announced_on) d,
         count(distinct amount_usd) > 1 disagree
    from public.firm_fund_announcements
   where created_at >= now() - interval '5 days' and is_current and not archived and name is not null
   group by 1, 2
)
insert into public.v2_events (kind, firm_id, fund_name, amount, amount_currency, event_date, event_date_precision, seed_fund_announcement_id, sources_disagree, created_by)
select 'fund_launch', firm_id, fund_name, amt, 'USD', d, case when d is null then null else 'day' end, seed, disagree, 'backfill-5d-20261123' from g;

update public.firm_fund_announcements a set event_id = ev.event_id
  from public.v2_events ev
 where ev.kind = 'fund_launch' and ev.created_by = 'backfill-5d-20261123'
   and a.firm_id = ev.firm_id and lower(btrim(a.name)) = lower(btrim(ev.fund_name))
   and a.is_current and not a.archived and a.event_id is null;

insert into public.v2_event_firms (event_id, firm_id)
select event_id, firm_id from public.v2_events where kind = 'fund_launch' and created_by = 'backfill-5d-20261123';

insert into public.v2_event_sources (event_id, fund_announcement_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
select event_id, id, firm_id, coalesce(source_url, url), source_level, source_date, amount_usd, 'USD', announced_on, 'day'
  from public.firm_fund_announcements where event_id is not null;

