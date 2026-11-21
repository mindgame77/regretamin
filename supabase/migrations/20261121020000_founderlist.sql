-- Founder hand-out: startups to research for founders. Separate from the founder tables on purpose.
-- Built the same way as the round list (schema roundlist). Preview only; apply only on "make it live".
--   * Everything lives in schema founderlist (table startups + event log + helpers).
--   * startup_id is a plain number, not a foreign key. The name and website are a copy, so the
--     list does not join public.v2_startups. No page, view or site function reads it.
--   * The two bot entry points are public.founderlist_claim_next_founder_startups and
--     public.founderlist_finish_founder_startup. They read public.v2_work_bot (same key -> bot
--     lookup as next_firm) and, for "done", public.v2_founder_facts (a role for this startup_id
--     saved by this bot since the claim). They write only to founderlist.*.
--   * Teardown: supabase/rollbacks/20261121020000_founderlist.sql
--     (drops this list only; founder rows stay).
-- Bot flow (v2 door, same x-ingest-key):
--   claim_next_founder_startups  oldest open rows, count 1-10. A bot holds at most 10.
--   finish_founder_startup       the holder marks done or rejected with a note.
--                                done needs a role fact for that startup_id, added by this bot,
--                                with created_at at or after taken_at.
-- Each taken row goes back to open 2 hours after its own taken_at.
-- Rows are loaded by a separate insert (see the pull request), not by a bot action.
-- The v2 founder tables are not created here. On a database without them (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_founder_facts') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null then
    raise notice 'v2 founders missing, skipped';
    return;
  end if;

  execute 'create schema if not exists founderlist';
  execute 'revoke all on schema founderlist from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema founderlist from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema founderlist from authenticated';
  end if;

  execute $ddl$
create table if not exists founderlist.startups (
  list_id bigserial primary key,
  startup_id bigint not null check (startup_id > 0),
  startup_name text not null check (btrim(startup_name) <> '' and length(startup_name) <= 300),
  startup_website text check (startup_website is null or length(startup_website) <= 500),
  added_by text not null check (btrim(added_by) <> '' and length(added_by) <= 200),
  added_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'taken', 'done', 'rejected')),
  taken_by text,
  taken_at timestamptz,
  finished_at timestamptz,
  notes text check (notes is null or length(notes) <= 4000),
  check (status <> 'taken' or (taken_by is not null and taken_at is not null)),
  constraint founderlist_one_startup unique (startup_id)
)
$ddl$;
  execute 'create index if not exists founderlist_open_idx on founderlist.startups (added_at, list_id) where status = ''open''';
  execute 'create index if not exists founderlist_taken_idx on founderlist.startups (taken_by) where status = ''taken''';
  execute 'comment on column founderlist.startups.startup_id is ''Copied startup number. This list does not point at another table.''';

  execute $ddl$
create table if not exists founderlist.events (
  event_id bigserial primary key,
  at timestamptz not null default now(),
  list_id bigint,
  startup_id bigint,
  bot text,
  action text not null,
  detail jsonb
)
$ddl$;

  execute 'alter table founderlist.startups enable row level security';
  execute 'alter table founderlist.events enable row level security';
  execute 'revoke all on table founderlist.startups, founderlist.events from public';
  execute 'revoke all on sequence founderlist.startups_list_id_seq, founderlist.events_event_id_seq from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table founderlist.startups, founderlist.events from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table founderlist.startups, founderlist.events from authenticated';
  end if;

  execute $ddl$
create or replace function founderlist.release_expired()
 returns integer
 language plpgsql
 security definer
 set search_path = founderlist, pg_catalog
 as $function$
declare
  v_n integer;
begin
  with o as (
    select x.list_id, x.startup_id, x.taken_by, x.taken_at from founderlist.startups x
     where x.status = 'taken' and x.taken_at <= now() - interval '2 hours'
     for update skip locked
  ), r as (
    update founderlist.startups x
       set status = 'open', taken_by = null, taken_at = null
      from o
     where x.list_id = o.list_id
    returning x.list_id, x.startup_id, o.taken_by, o.taken_at
  ), e as (
    insert into founderlist.events (list_id, startup_id, bot, action, detail)
    select r.list_id, r.startup_id, null, 'released',
           jsonb_build_object('was_taken_by', r.taken_by, 'was_taken_at', r.taken_at) from r
    returning 1
  )
  select count(*) into v_n from e;
  return v_n;
end
$function$
$ddl$;

  execute $ddl$
create or replace function founderlist.row_json(r founderlist.startups)
 returns jsonb
 language sql
 stable
 set search_path = founderlist, pg_catalog
 as $function$
  select jsonb_build_object(
    'list_id', r.list_id, 'startup_id', r.startup_id, 'startup_name', r.startup_name,
    'startup_website', r.startup_website, 'added_by', r.added_by, 'added_at', r.added_at,
    'status', r.status, 'taken_by', r.taken_by, 'taken_at', r.taken_at,
    'expires_at', case when r.status = 'taken' then r.taken_at + interval '2 hours' end,
    'finished_at', r.finished_at, 'notes', r.notes)
$function$
$ddl$;

  execute $ddl$
create or replace function public.founderlist_claim_next_founder_startups(p_key_id uuid, p_count integer default 1)
 returns jsonb
 language plpgsql
 security definer
 set search_path = founderlist, public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  v_bot public.v2_bot_keys;
  v_row founderlist.startups;
  v_cap constant integer := 10;
  v_held bigint[];
  v_new jsonb := '[]'::jsonb;
  v_want integer;
begin
  v_bot := public.v2_work_bot(p_key_id);
  if v_bot.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bot.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(v_bot.freeze_reason, 'no reason'), to_char(v_bot.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_count is null or p_count < 1 or p_count > v_cap then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'count must be 1-10');
  end if;
  perform pg_advisory_xact_lock(hashtext('founderlist:bot'), v_bot.bot_key_id::int);
  perform founderlist.release_expired();

  select coalesce(array_agg(x.startup_id order by x.taken_at, x.list_id), '{}') into v_held
    from founderlist.startups x where x.status = 'taken' and x.taken_by = v_bot.bot_name;
  if cardinality(v_held) >= v_cap then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'held_count', cardinality(v_held),
      'held_startup_ids', to_jsonb(v_held),
      'error', format('you already hold %s startups (the most is %s): %s. Finish one with finish_founder_startup before you ask for more.',
                      cardinality(v_held), v_cap, array_to_string(v_held, ', ')));
  end if;
  v_want := least(p_count, v_cap - cardinality(v_held));

  for v_row in
    select * from founderlist.startups x
     where x.status = 'open'
     order by x.added_at, x.list_id
     limit v_want
     for update skip locked
  loop
    update founderlist.startups x set status = 'taken', taken_by = v_bot.bot_name, taken_at = now()
     where x.list_id = v_row.list_id
    returning * into v_row;
    insert into founderlist.events (list_id, startup_id, bot, action) values (v_row.list_id, v_row.startup_id, v_bot.bot_name, 'taken');
    v_new := v_new || jsonb_build_array(founderlist.row_json(v_row));
    v_held := v_held || v_row.startup_id;
  end loop;

  return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name,
    'startup', v_new->0, 'startups', v_new, 'claimed_count', jsonb_array_length(v_new),
    'held_count', cardinality(v_held), 'held_startup_ids', to_jsonb(v_held), 'max_held', v_cap);
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.founderlist_finish_founder_startup(p_key_id uuid, p_startup_id bigint, p_result text, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path = founderlist, public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  v_bot public.v2_bot_keys;
  v_row founderlist.startups;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  v_bot := public.v2_work_bot(p_key_id);
  if v_bot.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bot.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(v_bot.freeze_reason, 'no reason'), to_char(v_bot.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_startup_id is null or p_startup_id <= 0 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id must be the startup from claim_next_founder_startups');
  end if;
  if p_result is null or p_result not in ('done', 'rejected') then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'result must be done or rejected');
  end if;
  if v_note is null or length(v_note) > 4000 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'note is required (up to 4000 characters): what you saved, or why it is rejected');
  end if;
  perform founderlist.release_expired();

  select * into v_row from founderlist.startups x where x.startup_id = p_startup_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id is not on the founder list');
  end if;
  if v_row.status in ('done', 'rejected') and v_row.taken_by = v_bot.bot_name then
    return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'already_finished', true, 'startup', founderlist.row_json(v_row));
  end if;
  if v_row.status <> 'taken' or v_row.taken_by is distinct from v_bot.bot_name then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name,
      'error', 'this startup is not held by you (it may have gone back to the list after 2 hours); ask for claim_next_founder_startups');
  end if;
  if p_result = 'done' and not exists (
       select 1 from public.v2_founder_facts f
        where f.fact = 'role'
          and f.startup_id = v_row.startup_id
          and f.created_at >= v_row.taken_at
          and f.added_by = v_bot.bot_name) then
    insert into founderlist.events (list_id, startup_id, bot, action, detail)
    values (v_row.list_id, v_row.startup_id, v_bot.bot_name, 'done_refused', jsonb_build_object('note', v_note));
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'startup_id', v_row.startup_id,
      'error', 'finish_founder_startup done refused: you have no founder role saved for this startup since you took it. Save the founders with add_founder first, or finish it as rejected with the reason.');
  end if;

  update founderlist.startups x set status = p_result, finished_at = now(), notes = v_note
   where x.list_id = v_row.list_id
  returning * into v_row;
  insert into founderlist.events (list_id, startup_id, bot, action, detail)
  values (v_row.list_id, v_row.startup_id, v_bot.bot_name, p_result, jsonb_build_object('note', v_note));
  return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'startup', founderlist.row_json(v_row));
end
$function$
$ddl$;

  execute 'revoke all on function founderlist.release_expired(), founderlist.row_json(founderlist.startups) from public';
  execute 'revoke all on function public.founderlist_claim_next_founder_startups(uuid, integer), public.founderlist_finish_founder_startup(uuid, bigint, text, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.founderlist_claim_next_founder_startups(uuid, integer), public.founderlist_finish_founder_startup(uuid, bigint, text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.founderlist_claim_next_founder_startups(uuid, integer), public.founderlist_finish_founder_startup(uuid, bigint, text, text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.founderlist_claim_next_founder_startups(uuid, integer) to service_role';
    execute 'grant execute on function public.founderlist_finish_founder_startup(uuid, bigint, text, text) to service_role';
  end if;
end
$mig$;
