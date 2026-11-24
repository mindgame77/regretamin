-- Skipped on databases without the v2 research tables (e.g. the CI test database), like other v2 migrations.
do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_fund_announcements') is null
     or to_regprocedure('public.v2_deal_dates_conflict(date, text, date, text)') is null then
    raise notice 'v2 research tables not present; shared register migration skipped';
    return;
  end if;
  execute $sql$
-- Shared register for things that happened (rounds, fund launches). Tables only; no triggers, no ingest/bot/site changes.
create table public.v2_events (
  event_id bigserial primary key,
  kind text not null check (kind in ('round','fund_launch')),
  startup_id bigint,
  round text,
  round_extension text,
  event_date date,
  event_date_precision text,
  amount numeric,
  amount_currency text,
  firm_id bigint,
  fund_name text,
  seed_deal_id bigint,
  seed_fund_announcement_id bigint,
  sources_disagree boolean not null default false,
  created_by text not null default 'manual',
  created_at timestamptz not null default now()
);
create index v2_events_round_idx on public.v2_events (startup_id, round) where kind = 'round';
create index v2_events_fund_idx on public.v2_events (firm_id, lower(btrim(fund_name))) where kind = 'fund_launch';

create table public.v2_event_firms (
  event_id bigint not null references public.v2_events(event_id) on delete cascade,
  firm_id bigint,
  noted_name text,
  lead boolean not null default false,
  created_at timestamptz not null default now(),
  check (firm_id is not null or noted_name is not null)
);
create unique index v2_event_firms_firm_uq on public.v2_event_firms (event_id, firm_id) where firm_id is not null;
create unique index v2_event_firms_noted_uq on public.v2_event_firms (event_id, lower(btrim(noted_name))) where firm_id is null;
create index v2_event_firms_firm_idx on public.v2_event_firms (firm_id);

create table public.v2_event_sources (
  source_id bigserial primary key,
  event_id bigint not null references public.v2_events(event_id) on delete cascade,
  deal_id bigint,
  fund_announcement_id bigint,
  firm_id bigint,
  source_url text,
  source_level smallint,
  source_date date,
  reported_amount numeric,
  reported_currency text,
  reported_date date,
  reported_date_precision text,
  created_at timestamptz not null default now()
);
create index v2_event_sources_event_idx on public.v2_event_sources (event_id);

alter table public.v2_events enable row level security;
alter table public.v2_event_firms enable row level security;
alter table public.v2_event_sources enable row level security;

alter table public.v2_deals add column event_id bigint references public.v2_events(event_id) on delete set null;
alter table public.firm_fund_announcements add column event_id bigint references public.v2_events(event_id) on delete set null;
create index v2_deals_event_idx on public.v2_deals (event_id) where event_id is not null;
create index firm_fund_announcements_event_idx on public.firm_fund_announcements (event_id) where event_id is not null;

$sql$;
end
$mig$;
