-- Which firms count on the map: one place for the rule, and a register of every change to it (founder, 25 Nov:
-- "we're counting on VC only ... keep all the rules in one place ... a register of what we change in the rules").
--
-- THE RULE lives in v2_map_type_rules: one row per firm type, on_map yes or no.
--   On the map:  VC, Corporate VC, Growth, Angel group, University fund, Angel investor
--   Off the map: Accelerator, Incubator, PE, Hedge fund
-- A firm counts when it has no type at all, or at least one of its current types is on the map.
-- A firm that is off the map still shows in the Investors list and on its own page, and a round it took part in still
-- counts through the other firms in it. Founders ("Who invested") is not touched and keeps them.
--
-- TO CHANGE THE RULE later, one statement, for example:
--   update v2_map_type_rules set on_map = true, note = 'why' where firm_type_id = (select firm_type_id from v2_firm_type where name = 'PE');
--   select v2_refresh_map_cache();   -- or wait up to 15 minutes for the map's ready-made answers
-- THE REGISTER is v2_map_rules_log: every insert, update or delete in the rules table is written there by itself
-- (what, was, now, why, when). The seven retags below are written there too.
--
-- HOW THE MAP READS IT: the view v2_map_counted_places is v2_map_firm_places without the firms that are off the map.
-- The functions that count for the map read that view: v2_map_summary, v2_map_firms (both), v2_map_firm_ids,
-- v2_map_hot (both), v2_map_hot_detail, v2_map_place_sectors. Nothing else is changed: the Investors list
-- (firm_directory_page_v5), firm pages, place hints and Latest updates still read v2_map_firm_places.
--
-- RETAGGED from VC to Accelerator on his word: 500 Global, Seedcamp Investment Management, Plug and Play,
-- Entrepreneurs Roundtable Accelerator, Techstars, Antler Korea, SOSV Investments. Old values are kept in
-- v2_firm_type_retag_20261125; to undo one:
--   update v2_firm_types_firms t set firm_type_id = b.old_firm_type_id, source_type = b.old_source_type, source_owner = b.old_source_owner, source_date = b.old_source_date
--   from v2_firm_type_retag_20261125 b where t.row_id = b.row_id;
do $wrapci$
declare
  r record;
begin
  if to_regclass('public.v2_map_firm_places') is null or to_regclass('public.v2_firm_types_firms') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;

  create table if not exists public.v2_map_type_rules (
    firm_type_id integer primary key references public.v2_firm_type(firm_type_id),
    on_map boolean not null,
    note text,
    updated_at timestamptz not null default now()
  );
  create table if not exists public.v2_map_rules_log (
    log_id bigint generated always as identity primary key,
    changed_at timestamptz not null default now(),
    what text not null,
    was text,
    now_is text,
    why text
  );
  alter table public.v2_map_type_rules enable row level security;
  alter table public.v2_map_rules_log enable row level security;
  comment on table public.v2_map_type_rules is 'Which firm types count on the map (Money flow, Trends). Change on_map and say why in note; every change is logged in v2_map_rules_log. Then run select v2_refresh_map_cache().';
  comment on table public.v2_map_rules_log is 'Register of every change to the map''s rules (v2_map_type_rules) and of firms retagged for it. Written automatically.';

  execute $fn$
create or replace function public.v2_map_type_rules_log() returns trigger language plpgsql security definer set search_path to 'public' as $body$
begin
  insert into v2_map_rules_log (what, was, now_is, why)
  values ('firm type "' || coalesce((select name from v2_firm_type where firm_type_id = coalesce(new.firm_type_id, old.firm_type_id)), '?') || '" counts on the map',
          case when tg_op = 'INSERT' then null when old.on_map then 'yes' else 'no' end,
          case when tg_op = 'DELETE' then null when new.on_map then 'yes' else 'no' end,
          case when tg_op = 'DELETE' then old.note else new.note end);
  if tg_op = 'DELETE' then return old; end if;
  new.updated_at := now();
  return new;
end
$body$
  $fn$;
  drop trigger if exists v2_map_type_rules_log on public.v2_map_type_rules;
  create trigger v2_map_type_rules_log before insert or update or delete on public.v2_map_type_rules for each row execute function public.v2_map_type_rules_log();

  insert into public.v2_map_type_rules (firm_type_id, on_map, note)
  select t.firm_type_id, t.name not in ('Accelerator', 'Incubator', 'PE', 'Hedge fund'),
         case when t.name in ('Accelerator', 'Incubator') then 'founder, 25 Nov 2026: not VC, off the map; they stay in the Investors list'
              when t.name in ('PE', 'Hedge fund') then 'founder, 25 Nov 2026: not on the map for now'
              else 'founder, 25 Nov 2026: counts on the map' end
  from public.v2_firm_type t
  on conflict (firm_type_id) do nothing;

  execute $v$
create or replace view public.v2_map_counted_places as
select p.*
from public.v2_map_firm_places p
where not exists (select 1 from public.v2_firm_types_firms tf
                  where tf.firm_id = p.firm_id and coalesce(tf.is_current, true) and not coalesce(tf.archived, false))
   or exists (select 1 from public.v2_firm_types_firms tf left join public.v2_map_type_rules r using (firm_type_id)
              where tf.firm_id = p.firm_id and coalesce(tf.is_current, true) and not coalesce(tf.archived, false) and coalesce(r.on_map, true))
  $v$;
  comment on view public.v2_map_counted_places is 'v2_map_firm_places without the firms whose types are all off the map (v2_map_type_rules). The map''s counting functions read this.';
  revoke all on public.v2_map_counted_places from anon, authenticated;

  -- the seven firms retagged as accelerators; old values kept
  create table if not exists public.v2_firm_type_retag_20261125 (
    row_id bigint primary key, firm_id bigint not null, old_firm_type_id integer not null, new_firm_type_id integer not null,
    old_source_type text, old_source_owner text, old_source_date date, note text, changed_at timestamptz not null default now());
  alter table public.v2_firm_type_retag_20261125 enable row level security;
  comment on table public.v2_firm_type_retag_20261125 is 'Old type tags of firms retagged on 25 Nov 2026 (founder: these are accelerators). Undo: update v2_firm_types_firms t set firm_type_id = b.old_firm_type_id, source_type = b.old_source_type, source_owner = b.old_source_owner, source_date = b.old_source_date from v2_firm_type_retag_20261125 b where t.row_id = b.row_id;';
  for r in
    select tf.row_id, tf.firm_id, tf.firm_type_id, tf.source_type, tf.source_owner, tf.source_date, s.display_name
    from public.v2_firm_types_firms tf join public.firm_summary s using (firm_id)
    where s.display_name in ('500 Global', 'Seedcamp Investment Management', 'Plug and Play', 'Entrepreneurs Roundtable Accelerator', 'Techstars', 'Antler Korea', 'SOSV Investments')
      and tf.firm_type_id = (select firm_type_id from public.v2_firm_type where name = 'VC')
      and coalesce(tf.is_current, true) and not coalesce(tf.archived, false)
      and not exists (select 1 from public.v2_firm_types_firms x where x.firm_id = tf.firm_id and x.firm_type_id = (select firm_type_id from public.v2_firm_type where name = 'Accelerator'))
  loop
    insert into public.v2_firm_type_retag_20261125 (row_id, firm_id, old_firm_type_id, new_firm_type_id, old_source_type, old_source_owner, old_source_date, note)
    values (r.row_id, r.firm_id, r.firm_type_id, (select firm_type_id from public.v2_firm_type where name = 'Accelerator'), r.source_type, r.source_owner, r.source_date, 'founder, 25 Nov 2026: retag as accelerator')
    on conflict (row_id) do nothing;
    update public.v2_firm_types_firms
       set firm_type_id = (select firm_type_id from public.v2_firm_type where name = 'Accelerator'),
           source_type = 'Founder decision, 25 Nov 2026: accelerator', source_owner = 'claude-website', source_date = current_date
     where row_id = r.row_id;
    insert into public.v2_map_rules_log (what, was, now_is, why)
    values ('firm "' || r.display_name || '" type', 'VC', 'Accelerator', 'founder, 25 Nov 2026: retag as accelerator (so it is off the map)');
  end loop;

  -- the map's counting functions read the counted view
  for r in
    select p.oid from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('v2_map_summary', 'v2_map_firms', 'v2_map_firm_ids', 'v2_map_hot', 'v2_map_hot_detail', 'v2_map_place_sectors')
      and p.prosrc like '%v2_map_firm_places%'
  loop
    execute replace(pg_get_functiondef(r.oid), 'v2_map_firm_places', 'v2_map_counted_places');
  end loop;
end $wrapci$;
