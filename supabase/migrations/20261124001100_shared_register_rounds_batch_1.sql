create schema if not exists shared_register_20261123;
create table if not exists shared_register_20261123.batch_links (batch text not null, deal_id bigint primary key, event_id bigint not null, created_at timestamptz default now());
-- Rounds backfill batch 1: startups 3..23470 (~10,000 rounds). Same rule as the 5-day fill.
set local statement_timeout = '15min';
drop table if exists m;
create temp table m (deal_id bigint primary key, event_id bigint not null);
do $$
declare s record; e bigint;
begin
  for s in
    select d.* from public.v2_deals d
     where d.startup_id between 3 and 23470 and d.event_id is null
       and d.is_current and not d.archived and not coalesce(d.nothing_found, false) and d.round is not null
     order by d.deal_id
  loop
    if exists (select 1 from m where m.deal_id = s.deal_id) then continue; end if;
    e := null;
    select ev.event_id into e from public.v2_events ev
     where ev.kind = 'round' and ev.startup_id = s.startup_id and ev.round = public.v2_deal_round_norm(s.round)
       and not (nullif(lower(btrim(ev.round_extension)), '') is not null and nullif(lower(btrim(s.round_extension)), '') is not null
                and lower(btrim(ev.round_extension)) <> lower(btrim(s.round_extension)))
       and not public.v2_deal_dates_conflict(ev.event_date, ev.event_date_precision, s.deal_date, s.deal_date_precision)
       and not (ev.round in ('Bridge','Debt','Grant','Other') and ev.amount is not null and s.round_amount is not null and ev.amount <> s.round_amount)
     order by ev.event_id limit 1;
    if e is null then
      insert into public.v2_events (kind, startup_id, round, round_extension, event_date, event_date_precision, amount, amount_currency, seed_deal_id, created_by)
      values ('round', s.startup_id, public.v2_deal_round_norm(s.round), nullif(btrim(s.round_extension), ''), s.deal_date, s.deal_date_precision,
              s.round_amount, s.amount_currency, s.deal_id, 'backfill-b1-20261123')
      returning event_id into e;
    end if;
    insert into m (deal_id, event_id)
    select d.deal_id, e from public.v2_deals d
     where d.event_id is null and not exists (select 1 from m where m.deal_id = d.deal_id) and d.startup_id = s.startup_id
       and d.is_current and not d.archived and not coalesce(d.nothing_found, false)
       and public.v2_deal_round_norm(d.round) = public.v2_deal_round_norm(s.round)
       and not (nullif(lower(btrim(d.round_extension)), '') is not null and nullif(lower(btrim(s.round_extension)), '') is not null
                and lower(btrim(d.round_extension)) <> lower(btrim(s.round_extension)))
       and not public.v2_deal_dates_conflict(d.deal_date, d.deal_date_precision, s.deal_date, s.deal_date_precision)
       and not (public.v2_deal_round_norm(s.round) in ('Bridge','Debt','Grant','Other') and d.round_amount is not null and s.round_amount is not null
                and d.round_amount <> s.round_amount);
  end loop;
end $$;
insert into shared_register_20261123.batch_links (batch, deal_id, event_id) select 'b1', deal_id, event_id from m;
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
select d.event_id, d.firm_id, bool_or(coalesce(d.lead::text, '') in ('true','t'))
  from public.v2_deals d join m using (deal_id) where d.firm_id is not null group by 1, 2
on conflict (event_id, firm_id) where firm_id is not null do update set lead = v2_event_firms.lead or excluded.lead;
insert into public.v2_event_sources (event_id, deal_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
select d.event_id, d.deal_id, d.firm_id, d.source_url, d.source_level, d.source_date, d.round_amount, d.amount_currency, d.deal_date, d.deal_date_precision
  from public.v2_deals d join m using (deal_id);
update public.v2_events ev set sources_disagree = true
 where ev.event_id in (select distinct event_id from m) and not ev.sources_disagree
   and (select count(distinct s.reported_amount) from public.v2_event_sources s where s.event_id = ev.event_id) > 1;
