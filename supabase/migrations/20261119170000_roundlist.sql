-- Round list: a separate hand-out list of 2026 funding rounds for the deals bots (replaces the Google Sheet).
-- Built on Alex's OK (2026-11-19, "build it"). Preview only; apply only on "make it live".
-- Separate from the main database on purpose:
--   * Everything lives in its own schema `roundlist` (table rounds + event log + helpers).
--   * No foreign keys to v2_firms, v2_deals, v2_startups or anything else. No page, view or site
--     function reads it.
--   * The three bot entry points are public.roundlist_* (the v2 door calls public functions).
--     They only read public.v2_work_bot (same key -> bot lookup as next_firm/firm_done) and
--     public.v2_research_submissions (to check a saved deal before "done"). They write only
--     to roundlist.*.
--   * Teardown in one command: supabase/rollbacks/20261119170000_roundlist.sql
-- Bot flow (through the v2 door, same x-ingest-key as submit/next_firm):
--   add_round        list bots add a round; a copy (same startup + round + date) is refused.
--   claim_next_round deal bots get the oldest open round(s) (FIFO by added_at); count 1-10, default 1.
--                    A bot holds at most 10 taken rounds; at 10 the call is refused with its held round_ids.
--   finish_round     the holder marks it done or rejected with a note. done needs at least one
--                    Accepted v2_deals submission by that bot since it took the round.
-- Each taken round goes back to open 2 hours after its own taken_at (same hold as v2_work_claims).
-- Release is done on every bot call, and by roundlist.release_expired().
-- Bots cannot delete or edit rows: the schema and tables have no grants for public/anon/authenticated
-- (and the schema is not exposed to the REST API). Only the security definer functions change rows,
-- and only as above.
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.

do $mig$
begin
  if to_regprocedure('public.v2_work_bot(uuid)') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('public.v2_research_submissions') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute 'create schema if not exists roundlist';
  execute 'revoke all on schema roundlist from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema roundlist from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema roundlist from authenticated';
  end if;

  -- Website -> bare domain (lowercase, no scheme, no www, no port, no path). Null if it does not look like a domain.
  execute $ddl$
create or replace function roundlist.norm_site(p text)
 returns text
 language sql
 immutable
 set search_path = pg_catalog
 as $function$
  select case when d ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' then d end
    from (select regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                   lower(btrim(coalesce(p, ''))),
                   '^[a-z][a-z0-9+.-]*://', ''), '^www\.', ''), '[/?#].*$', ''), ':[0-9]+$', '') as d) s
$function$
$ddl$;

  -- Letters and digits only, lowercase: "Pre-seed" = "Pre Seed" = "preseed"; "Series A" = "series-a".
  execute $ddl$
create or replace function roundlist.norm_text(p text)
 returns text
 language sql
 immutable
 set search_path = pg_catalog
 as $function$
  select regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', '', 'g')
$function$
$ddl$;

  -- The startup part of the copy check: the website domain, or the name when there is no usable website.
  execute $ddl$
create or replace function roundlist.startup_key(p_website text, p_name text)
 returns text
 language sql
 immutable
 set search_path = pg_catalog
 as $function$
  select coalesce('site:' || roundlist.norm_site(p_website), 'name:' || roundlist.norm_text(p_name))
$function$
$ddl$;

  execute $ddl$
create table if not exists roundlist.rounds (
  round_id bigserial primary key,
  startup_name text not null check (btrim(startup_name) <> '' and length(startup_name) <= 300),
  startup_website text check (length(startup_website) <= 500),
  country text check (length(country) <= 100),
  round text not null check (btrim(round) <> '' and length(round) <= 100),
  round_date date not null,
  source_url text check (length(source_url) <= 2000),
  added_by text not null,
  added_at timestamptz not null default now(),
  status text not null default 'open' check (status in ('open', 'taken', 'done', 'rejected')),
  taken_by text,
  taken_at timestamptz,
  finished_at timestamptz,
  notes text check (length(notes) <= 4000),
  startup_key text generated always as (roundlist.startup_key(startup_website, startup_name)) stored,
  round_key text generated always as (roundlist.norm_text(round)) stored,
  check (status <> 'taken' or (taken_by is not null and taken_at is not null)),
  check (round_key <> ''),
  constraint rounds_no_copies unique (startup_key, round_key, round_date)
)
$ddl$;
  execute 'create index if not exists rounds_open_idx on roundlist.rounds (added_at, round_id) where status = ''open''';
  execute 'create index if not exists rounds_taken_idx on roundlist.rounds (taken_by) where status = ''taken''';

  -- Every bot action, for checking later. Insert-only from the functions.
  execute $ddl$
create table if not exists roundlist.events (
  event_id bigserial primary key,
  at timestamptz not null default now(),
  round_id bigint,
  bot text,
  action text not null,
  detail jsonb
)
$ddl$;

  execute 'alter table roundlist.rounds enable row level security';
  execute 'alter table roundlist.events enable row level security';
  execute 'revoke all on table roundlist.rounds, roundlist.events from public';
  execute 'revoke all on sequence roundlist.rounds_round_id_seq, roundlist.events_event_id_seq from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table roundlist.rounds, roundlist.events from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table roundlist.rounds, roundlist.events from authenticated';
  end if;

  -- Taken rounds held longer than 2 hours go back to open. Returns how many.
  execute $ddl$
create or replace function roundlist.release_expired()
 returns integer
 language plpgsql
 security definer
 set search_path = roundlist, pg_catalog
 as $function$
declare
  n integer;
begin
  with o as (
    select x.round_id, x.taken_by, x.taken_at from roundlist.rounds x
     where x.status = 'taken' and x.taken_at <= now() - interval '2 hours'
     for update skip locked
  ), r as (
    update roundlist.rounds x
       set status = 'open', taken_by = null, taken_at = null
      from o
     where x.round_id = o.round_id
    returning x.round_id, o.taken_by, o.taken_at
  ), e as (
    insert into roundlist.events (round_id, bot, action, detail)
    select r.round_id, null, 'released', jsonb_build_object('was_taken_by', r.taken_by, 'was_taken_at', r.taken_at) from r
    returning 1
  )
  select count(*) into n from e;
  return n;
end
$function$
$ddl$;

  execute $ddl$
create or replace function roundlist.round_json(r roundlist.rounds)
 returns jsonb
 language sql
 stable
 set search_path = roundlist, pg_catalog
 as $function$
  select jsonb_build_object(
    'round_id', r.round_id, 'startup_name', r.startup_name, 'startup_website', r.startup_website,
    'country', r.country, 'round', r.round, 'round_date', r.round_date, 'source_url', r.source_url,
    'added_by', r.added_by, 'added_at', r.added_at, 'status', r.status, 'taken_by', r.taken_by,
    'taken_at', r.taken_at,
    'expires_at', case when r.status = 'taken' then r.taken_at + interval '2 hours' end,
    'finished_at', r.finished_at, 'notes', r.notes)
$function$
$ddl$;

  -- add_round: p_round = {"startup_name","startup_website","country","round","round_date":"YYYY-MM-DD","source_url"}
  execute $ddl$
create or replace function public.roundlist_add_round(p_key_id uuid, p_round jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path = roundlist, public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  bk public.v2_bot_keys;
  v_name text;
  v_site text;
  v_country text;
  v_round text;
  v_date date;
  v_src text;
  r roundlist.rounds;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_round is null or jsonb_typeof(p_round) <> 'object' then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'round must be an object with startup_name, startup_website, country, round, round_date, source_url');
  end if;
  v_name := nullif(btrim(p_round->>'startup_name'), '');
  v_site := nullif(btrim(p_round->>'startup_website'), '');
  v_country := nullif(btrim(p_round->>'country'), '');
  v_round := nullif(btrim(p_round->>'round'), '');
  v_src := nullif(btrim(p_round->>'source_url'), '');
  if v_name is null or length(v_name) > 300 then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'startup_name is required (up to 300 characters)');
  end if;
  if v_round is null or length(v_round) > 100 or roundlist.norm_text(v_round) = '' then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'round is required, e.g. Seed or Series A');
  end if;
  if coalesce(p_round->>'round_date', '') !~ '^\d{4}-\d{2}-\d{2}$' then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'round_date must be YYYY-MM-DD');
  end if;
  begin
    v_date := (p_round->>'round_date')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'round_date must be a real date (YYYY-MM-DD)');
  end;
  if v_site is not null and (length(v_site) > 500 or roundlist.norm_site(v_site) is null) then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'startup_website must be a website like https://example.com, or leave it out');
  end if;
  if v_src is null or v_src !~* '^https?://' or length(v_src) > 2000 then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'source_url is required (the http(s) link to the announcement)');
  end if;
  if length(v_country) > 100 then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'country must be up to 100 characters');
  end if;
  perform roundlist.release_expired();

  insert into roundlist.rounds (startup_name, startup_website, country, round, round_date, source_url, added_by)
  values (v_name, v_site, v_country, v_round, v_date, v_src, bk.bot_name)
  on conflict on constraint rounds_no_copies do nothing
  returning * into r;
  if found then
    insert into roundlist.events (round_id, bot, action) values (r.round_id, bk.bot_name, 'added');
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'added', true, 'round', roundlist.round_json(r));
  end if;

  select * into r from roundlist.rounds x
   where x.startup_key = roundlist.startup_key(v_site, v_name)
     and x.round_key = roundlist.norm_text(v_round) and x.round_date = v_date;
  insert into roundlist.events (round_id, bot, action, detail)
  values (r.round_id, bk.bot_name, 'add_refused', jsonb_build_object('round', p_round));
  return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'duplicate', true,
    'error', format('this round is already on the list (round_id %s: %s %s %s, added by %s, status %s); not added again',
                    r.round_id, r.startup_name, r.round, r.round_date, r.added_by, r.status),
    'existing_round_id', r.round_id, 'existing_status', r.status);
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.roundlist_claim_next_round(p_key_id uuid, p_count integer default 1)
 returns jsonb
 language plpgsql
 security definer
 set search_path = roundlist, public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  bk public.v2_bot_keys;
  r roundlist.rounds;
  v_cap constant integer := 10;
  v_held bigint[];
  v_new jsonb := '[]'::jsonb;
  v_want integer;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_count is null or p_count < 1 or p_count > v_cap then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'count must be 1-10');
  end if;
  -- One call at a time per bot, so parallel calls from the same bot can never go over 10 held rounds.
  perform pg_advisory_xact_lock(hashtext('roundlist:bot'), bk.bot_key_id::int);
  perform roundlist.release_expired();

  select coalesce(array_agg(x.round_id order by x.taken_at, x.round_id), '{}') into v_held
    from roundlist.rounds x where x.status = 'taken' and x.taken_by = bk.bot_name;
  if cardinality(v_held) >= v_cap then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'held_count', cardinality(v_held),
      'held_round_ids', to_jsonb(v_held),
      'error', format('you already hold %s rounds (the most is %s): %s. Finish one with finish_round before you ask for more.',
                      cardinality(v_held), v_cap, array_to_string(v_held, ', ')));
  end if;
  v_want := least(p_count, v_cap - cardinality(v_held));

  for r in
    select * from roundlist.rounds x
     where x.status = 'open'
     order by x.added_at, x.round_id
     limit v_want
     for update skip locked
  loop
    update roundlist.rounds x set status = 'taken', taken_by = bk.bot_name, taken_at = now()
     where x.round_id = r.round_id
    returning * into r;
    insert into roundlist.events (round_id, bot, action) values (r.round_id, bk.bot_name, 'taken');
    v_new := v_new || jsonb_build_array(roundlist.round_json(r));
    v_held := v_held || r.round_id;
  end loop;

  -- round: the first new round (null when none is open). rounds: every round given in this call.
  return jsonb_build_object('ok', true, 'bot_id', bk.bot_name,
    'round', v_new->0, 'rounds', v_new, 'claimed_count', jsonb_array_length(v_new),
    'held_count', cardinality(v_held), 'held_round_ids', to_jsonb(v_held), 'max_held', v_cap);
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.roundlist_finish_round(p_key_id uuid, p_round_id bigint, p_result text, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path = roundlist, public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  bk public.v2_bot_keys;
  r roundlist.rounds;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_result is null or p_result not in ('done', 'rejected') then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'result must be done or rejected');
  end if;
  if v_note is null or length(v_note) > 4000 then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'note is required (up to 4000 characters): what you saved, or why the round is rejected');
  end if;
  perform roundlist.release_expired();

  select * into r from roundlist.rounds x where x.round_id = p_round_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'round not found');
  end if;
  if r.status in ('done', 'rejected') and r.taken_by = bk.bot_name then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'already_finished', true, 'round', roundlist.round_json(r));
  end if;
  if r.status <> 'taken' or r.taken_by is distinct from bk.bot_name then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name,
      'error', 'this round is not held by you (it may have gone back to the list after 2 hours); ask for claim_next_round');
  end if;
  if p_result = 'done' and not exists (
       select 1 from public.v2_research_submissions s
        where s.bot_key_id = bk.bot_key_id
          and s.received_at >= r.taken_at
          and s.status = 'Accepted'
          and s.payload->>'target_table' = 'v2_deals') then
    insert into roundlist.events (round_id, bot, action, detail)
    values (r.round_id, bk.bot_name, 'done_refused', jsonb_build_object('note', v_note));
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'round_id', r.round_id,
      'error', 'finish_round done refused: you have no accepted deal saved since you took this round. Save the deals first, or finish it as rejected with the reason.');
  end if;

  update roundlist.rounds x set status = p_result, finished_at = now(), notes = v_note
   where x.round_id = r.round_id
  returning * into r;
  insert into roundlist.events (round_id, bot, action, detail)
  values (r.round_id, bk.bot_name, p_result, jsonb_build_object('note', v_note));
  return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'round', roundlist.round_json(r));
end
$function$
$ddl$;

  -- Server only: the door calls the three entry points with the service role. Helpers have no grants.
  execute 'revoke all on function roundlist.norm_site(text), roundlist.norm_text(text), roundlist.startup_key(text, text), roundlist.release_expired(), roundlist.round_json(roundlist.rounds) from public';
  execute 'revoke all on function public.roundlist_add_round(uuid, jsonb), public.roundlist_claim_next_round(uuid, integer), public.roundlist_finish_round(uuid, bigint, text, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.roundlist_add_round(uuid, jsonb), public.roundlist_claim_next_round(uuid, integer), public.roundlist_finish_round(uuid, bigint, text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.roundlist_add_round(uuid, jsonb), public.roundlist_claim_next_round(uuid, integer), public.roundlist_finish_round(uuid, bigint, text, text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.roundlist_add_round(uuid, jsonb) to service_role';
    execute 'grant execute on function public.roundlist_claim_next_round(uuid, integer) to service_role';
    execute 'grant execute on function public.roundlist_finish_round(uuid, bigint, text, text) to service_role';
  end if;
end
$mig$;
