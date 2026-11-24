-- Skipped on databases without the v2 research tables (e.g. the CI test database), like other v2 migrations.
do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_fund_announcements') is null
     or to_regprocedure('public.v2_deal_dates_conflict(date, text, date, text)') is null then
    raise notice 'v2 research tables not present; shared register migration skipped';
    return;
  end if;
  execute $sql$
-- Auto-link new or changed deals and fund announcements to the shared register.
-- BEFORE ROW trigger that only sets NEW.event_id (no second UPDATE, so the existing deal triggers and shown are never re-run or touched).
-- Any linking error is logged and the save goes ahead.
create table if not exists public.v2_event_link_errors (
  id bigserial primary key, table_name text not null, row_id bigint, error text, created_at timestamptz not null default now());
alter table public.v2_event_link_errors enable row level security;

create or replace function public.v2_event_find_round(p_startup bigint, p_round text, p_ext text, p_date date, p_prec text, p_amount numeric, p_only bigint default null)
returns bigint language sql stable set search_path to 'public' as $$
  select ev.event_id from public.v2_events ev
   where ev.kind = 'round' and ev.startup_id = p_startup and ev.round = public.v2_deal_round_norm(p_round)
     and (p_only is null or ev.event_id = p_only)
     and not (nullif(lower(btrim(ev.round_extension)), '') is not null and nullif(lower(btrim(p_ext)), '') is not null
              and lower(btrim(ev.round_extension)) <> lower(btrim(p_ext)))
     and not public.v2_deal_dates_conflict(ev.event_date, ev.event_date_precision, p_date, p_prec)
     and not (ev.round in ('Bridge','Debt','Grant','Other') and ev.amount is not null and p_amount is not null and ev.amount <> p_amount)
   order by ev.event_id limit 1
$$;

create or replace function public.v2_deals_event_link_trg() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare e bigint;
begin
  begin
    if new.is_current and not new.archived and not coalesce(new.nothing_found, false) and new.round is not null and new.startup_id is not null then
      if new.event_id is not null then
        e := public.v2_event_find_round(new.startup_id, new.round, new.round_extension, new.deal_date, new.deal_date_precision, new.round_amount, new.event_id);
      end if;
      if e is null then
        e := public.v2_event_find_round(new.startup_id, new.round, new.round_extension, new.deal_date, new.deal_date_precision, new.round_amount);
      end if;
      if e is null then
        insert into public.v2_events (kind, startup_id, round, round_extension, event_date, event_date_precision, amount, amount_currency, seed_deal_id, created_by)
        values ('round', new.startup_id, public.v2_deal_round_norm(new.round), nullif(btrim(new.round_extension), ''), new.deal_date, new.deal_date_precision,
                new.round_amount, new.amount_currency, new.deal_id, 'autolink')
        returning event_id into e;
      end if;
      delete from public.v2_event_sources where deal_id = new.deal_id;
      insert into public.v2_event_sources (event_id, deal_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
      values (e, new.deal_id, new.firm_id, new.source_url, new.source_level, new.source_date, new.round_amount, new.amount_currency, new.deal_date, new.deal_date_precision);
      if new.firm_id is not null then
        insert into public.v2_event_firms (event_id, firm_id, lead) values (e, new.firm_id, coalesce(new.lead::text, '') in ('true','t'))
        on conflict (event_id, firm_id) where firm_id is not null do update set lead = v2_event_firms.lead or excluded.lead;
      end if;
      update public.v2_events set sources_disagree = true
       where event_id = e and not sources_disagree and amount is not null and new.round_amount is not null and amount <> new.round_amount;
      new.event_id := e;
    elsif new.event_id is not null then
      delete from public.v2_event_sources where deal_id = new.deal_id;
      new.event_id := null;
    end if;
  exception when others then
    insert into public.v2_event_link_errors (table_name, row_id, error) values ('v2_deals', new.deal_id, sqlerrm);
  end;
  return new;
end $$;

create or replace function public.v2_ffa_event_link_trg() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare e bigint;
begin
  begin
    if new.is_current and not new.archived and nullif(btrim(new.name), '') is not null and new.firm_id is not null then
      select ev.event_id into e from public.v2_events ev
       where ev.kind = 'fund_launch' and ev.firm_id = new.firm_id and lower(btrim(ev.fund_name)) = lower(btrim(new.name))
       order by ev.event_id limit 1;
      if e is null then
        insert into public.v2_events (kind, firm_id, fund_name, amount, amount_currency, event_date, event_date_precision, seed_fund_announcement_id, created_by)
        values ('fund_launch', new.firm_id, new.name, new.amount_usd, 'USD', new.announced_on, case when new.announced_on is null then null else 'day' end, new.id, 'autolink')
        returning event_id into e;
      end if;
      delete from public.v2_event_sources where fund_announcement_id = new.id;
      insert into public.v2_event_sources (event_id, fund_announcement_id, firm_id, source_url, source_level, source_date, reported_amount, reported_currency, reported_date, reported_date_precision)
      values (e, new.id, new.firm_id, coalesce(new.source_url, new.url), new.source_level, new.source_date, new.amount_usd, 'USD', new.announced_on, 'day');
      insert into public.v2_event_firms (event_id, firm_id) values (e, new.firm_id) on conflict (event_id, firm_id) where firm_id is not null do nothing;
      update public.v2_events set sources_disagree = true
       where event_id = e and not sources_disagree and amount is not null and new.amount_usd is not null and amount <> new.amount_usd;
      new.event_id := e;
    elsif new.event_id is not null then
      delete from public.v2_event_sources where fund_announcement_id = new.id;
      new.event_id := null;
    end if;
  exception when others then
    insert into public.v2_event_link_errors (table_name, row_id, error) values ('firm_fund_announcements', new.id, sqlerrm);
  end;
  return new;
end $$;

revoke all on function public.v2_deals_event_link_trg() from public, anon, authenticated;
revoke all on function public.v2_ffa_event_link_trg() from public, anon, authenticated;

create trigger zz_v2_deals_event_link before insert or update of startup_id, round, round_extension, deal_date, deal_date_precision, round_amount, amount_currency, is_current, archived, nothing_found, firm_id, lead, source_url
  on public.v2_deals for each row execute function public.v2_deals_event_link_trg();
create trigger zz_ffa_event_link before insert or update of firm_id, name, amount_usd, announced_on, is_current, archived, source_url
  on public.firm_fund_announcements for each row execute function public.v2_ffa_event_link_trg();

$sql$;
end
$mig$;
