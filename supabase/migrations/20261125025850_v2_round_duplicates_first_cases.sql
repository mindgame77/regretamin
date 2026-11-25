-- The same round recorded more than once (founder, 24 Nov: "Anthropic's $30B round, Waymo's $16B ... fix it").
-- First cases only: 9 deal rows of Anthropic, Waymo and Anduril. A row that names no round and has only a year
-- ("2026") gets the round name and the day of the round it belongs to; a round filed as "Other" gets the name the
-- other sources give it. The database's own trigger then links the row to that round. Old values are kept.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null then
    raise notice 'v2_deals not present, skipping';
    return;
  end if;
  create table if not exists public.v2_round_dedupe_20261124 (
    deal_id bigint primary key, old_round text, old_deal_date date, old_precision text, old_event_id bigint,
    new_round text, new_deal_date date, new_precision text, note text, changed_at timestamptz not null default now());
  alter table public.v2_round_dedupe_20261124 enable row level security;
  comment on table public.v2_round_dedupe_20261124 is
    'Old values of deal rows whose round name or date was changed because the same round was recorded more than once. Undo: update v2_deals d set round = b.old_round, deal_date = b.old_deal_date, deal_date_precision = b.old_precision from v2_round_dedupe_20261124 b where d.deal_id = b.deal_id;';

  with fix(deal_id, new_round, new_date, note) as (values
    (3068::bigint, 'Series G', date '2026-02-12', 'Anthropic $30B: year-only row, same round as Series G of 12 Feb 2026'),
    (4865, 'Series G', date '2026-02-12', 'Anthropic $30B: year-only row, same round as Series G of 12 Feb 2026'),
    (3069, 'Series H', date '2026-05-28', 'Anthropic $65B: year-only row, same round as Series H of 28 May 2026'),
    (4866, 'Series H', date '2026-05-28', 'Anthropic $65B: year-only row, same round as Series H of 28 May 2026'),
    (3684, 'Series D', date '2026-02-02', 'Waymo $16B: year-only row, same round as Series D of 2 Feb 2026'),
    (4391, 'Series D', date '2026-02-02', 'Waymo $16B: year-only row, same round as Series D of 2 Feb 2026'),
    (368782, 'Series D', date '2026-02-02', 'Waymo $16B: filed as Other on the same day as the Series D'),
    (4862, 'Series H', date '2026-05-13', 'Anduril $5B: year-only row, same round as Series H of 13 May 2026'),
    (324109, 'Series H', date '2026-05-13', 'Anduril $5B: same Series H, dated one day later by its source')),
  saved as (
    insert into public.v2_round_dedupe_20261124 (deal_id, old_round, old_deal_date, old_precision, old_event_id, new_round, new_deal_date, new_precision, note)
    select d.deal_id, d.round, d.deal_date, d.deal_date_precision, d.event_id, f.new_round, f.new_date, 'full date', f.note
    from fix f join public.v2_deals d using (deal_id)
    where d.is_current and (d.round is distinct from f.new_round or d.deal_date is distinct from f.new_date)
    on conflict (deal_id) do nothing
    returning deal_id, new_round, new_deal_date)
  update public.v2_deals d set round = s.new_round, deal_date = s.new_deal_date, deal_date_precision = 'full date'
  from saved s where d.deal_id = s.deal_id;
end $wrapci$;
