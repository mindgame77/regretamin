-- Startup HQ location: fill an EMPTY st_country / st_city on an existing startup, plus a separate
-- location hand-out on the founder list for startups whose founders are already done.
-- Preview only; apply only on "make it live". Teardown: supabase/rollbacks/20261121060000_v2_startup_location_fill.sql
--
-- What this adds (nothing existing is replaced or changed in behaviour):
--   * public.v2_startup_location_sources   new table: one row per filled value (or correction request) with its source.
--   * public.v2_location_fill_on()          switch: v2_work_setting 'location_fill' on/off (default off until go-live).
--   * public.v2_startup_location_fill(...)  door action fill_startup_location. Writes only an empty st_country / st_city,
--                                           never overwrites. A different saved value is refused; the bot may send
--                                           correction=true, which is stored as a request only (nothing changes).
--   * founderlist.startups: new nullable columns loc_status / loc_taken_by / loc_taken_at / loc_finished_at / loc_notes.
--     NULL = not on the location list. The founder columns (status, taken_by, ...) and founder functions are untouched.
--   * founderlist.loc_release_expired(), founderlist.loc_row_json(...)
--   * public.founderlist_claim_next_location_startups(uuid, int) / public.founderlist_finish_location_startup(uuid, bigint, text, text)
--     Only bots named in v2_work_setting 'location_list_bots' (default bots 26 and 27). Up to 10 held, 2-hour hold,
--     order pick_group (1 YC, 2 US, 3 EU, 4 other) then biggest round (pick_amount desc).
--   Provenance: every fill writes one v2_research_submissions row (box F14, status Accepted), one v2_change_log row
--   (old and new value) and one v2_startup_location_sources row per field (url, level, date, type, owner, bot).
--   The row is not sent to the Checker queue on purpose: the existing auto-publish for v2_startups changed-key-fact
--   only knows website_url and would mis-apply a location item.
-- The list is filled by a separate statement (location-list-load.sql in the pull request), not here.
-- On a database without the v2 / founderlist tables (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_startups') is null
     or to_regclass('public.v2_work_setting') is null
     or to_regclass('public.v2_research_submissions') is null
     or to_regclass('public.v2_change_log') is null
     or to_regclass('founderlist.startups') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null then
    raise notice 'v2 / founderlist tables missing: location fill skipped';
    return;
  end if;

  -- 1. Source table --------------------------------------------------------------------------
  execute $ddl$
create table if not exists public.v2_startup_location_sources (
  loc_source_id bigserial primary key,
  startup_id bigint not null check (startup_id > 0),
  field text not null check (field in ('st_country', 'st_city')),
  value text not null check (btrim(value) <> '' and length(value) <= 100),
  old_value text,
  kind text not null default 'fill' check (kind in ('fill', 'correction')),
  status text not null default 'applied' check (status in ('applied', 'requested', 'accepted', 'declined', 'undone')),
  source_url text not null check (source_url ~* '^https?://' and length(source_url) <= 1000),
  source_level smallint check (source_level between 1 and 3),
  source_date date,
  source_type text check (source_type is null or length(source_type) <= 100),
  source_owner text check (source_owner is null or length(source_owner) <= 200),
  note text check (note is null or length(note) <= 2000),
  bot text not null,
  submission_id bigint,
  created_at timestamptz not null default now()
)
$ddl$;
  execute 'create index if not exists v2_startup_location_sources_startup_idx on public.v2_startup_location_sources (startup_id, field)';
  execute 'create index if not exists v2_startup_location_sources_bot_idx on public.v2_startup_location_sources (bot, created_at)';
  execute 'alter table public.v2_startup_location_sources enable row level security';
  execute 'revoke all on table public.v2_startup_location_sources from public';
  execute 'revoke all on sequence public.v2_startup_location_sources_loc_source_id_seq from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table public.v2_startup_location_sources from anon';
    execute 'revoke all on sequence public.v2_startup_location_sources_loc_source_id_seq from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table public.v2_startup_location_sources from authenticated';
    execute 'revoke all on sequence public.v2_startup_location_sources_loc_source_id_seq from authenticated';
  end if;

  -- 2. Switches ------------------------------------------------------------------------------
  execute 'insert into public.v2_work_setting (name, value) values (''location_fill'', ''off'') on conflict (name) do nothing';
  execute 'insert into public.v2_work_setting (name, value) values (''location_list_bots'', ''external-research-bot-26,external-research-bot-27'') on conflict (name) do nothing';

  execute $ddl$
create or replace function public.v2_location_fill_on()
 returns boolean
 language sql
 stable
 set search_path = pg_catalog
 as $function$
  select coalesce((select lower(btrim(s.value)) from public.v2_work_setting s where s.name = 'location_fill'), 'off') in ('on', 'true', '1')
$function$
$ddl$;

  -- 3. Door action: fill_startup_location ----------------------------------------------------
  execute $ddl$
create or replace function public.v2_startup_location_fill(
  p_key_id uuid, p_startup_id bigint, p_country text, p_city text, p_source jsonb,
  p_correction boolean default false, p_note text default null, p_dry_run boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  v_bot public.v2_bot_keys;
  v_country text := upper(nullif(btrim(coalesce(p_country, '')), ''));
  v_city text := nullif(regexp_replace(btrim(coalesce(p_city, '')), '\s+', ' ', 'g'), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_url text; v_level smallint; v_date date; v_type text; v_owner text;
  v_cur_country text; v_cur_city text; v_found boolean;
  v_fill jsonb := '{}'::jsonb; v_same jsonb := '{}'::jsonb; v_conflict jsonb := '{}'::jsonb;
  v_sid bigint; v_src jsonb;
begin
  v_bot := public.v2_work_bot(p_key_id);
  if v_bot.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bot.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(v_bot.freeze_reason, 'no reason'), to_char(v_bot.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if not public.v2_location_fill_on() then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'location fill is switched off - stop and report');
  end if;
  if p_startup_id is null or p_startup_id <= 0 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id must be a positive number');
  end if;
  if v_country is null and v_city is null then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'send country, city, or both');
  end if;
  if v_country is not null then
    if v_country = 'UK' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'country must be the 2-letter ISO code: use GB for the United Kingdom');
    end if;
    if v_country !~ '^[A-Z]{2}$' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'country must be the 2-letter ISO code, like US, GB, DE');
    end if;
  end if;
  if v_city is not null then
    if length(v_city) > 100 or v_city ~ '[0-9@/\\,;:|<>{}\[\]]' or v_city ~* '^https?' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name,
        'error', 'city must be the city name only, in English (no street, postcode, state, country or link), up to 100 characters');
    end if;
    if v_city ~ '^[A-Z]{2}$' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'city must be the full city name, not a code');
    end if;
  end if;

  if p_source is null or jsonb_typeof(p_source) <> 'object' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'source must be an object with source_url (the page that states the HQ)');
  end if;
  v_url := nullif(btrim(coalesce(p_source->>'source_url', '')), '');
  if v_url is null or v_url !~* '^https?://[^\s/]+\.[^\s]+$' or length(v_url) > 1000 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'source.source_url is required: the http(s) link that states this location');
  end if;
  if p_source ? 'source_level' and jsonb_typeof(p_source->'source_level') <> 'null' then
    if (p_source->>'source_level') !~ '^[123]$' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'source.source_level must be 1, 2 or 3');
    end if;
    v_level := (p_source->>'source_level')::smallint;
  end if;
  if nullif(p_source->>'source_date', '') is not null then
    begin
      v_date := (p_source->>'source_date')::date;
    exception when others then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'source.source_date must be YYYY-MM-DD');
    end;
    if v_date > current_date then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'source.source_date cannot be in the future');
    end if;
  end if;
  v_type := left(nullif(btrim(coalesce(p_source->>'source_type', '')), ''), 100);
  v_owner := left(nullif(btrim(coalesce(p_source->>'source_owner', '')), ''), 200);
  v_src := jsonb_build_object('url', v_url, 'level', v_level, 'date', v_date, 'type', v_type, 'owner', v_owner);

  select nullif(btrim(s.st_country), ''), nullif(btrim(s.st_city), ''), true
    into v_cur_country, v_cur_city, v_found
    from public.v2_startups s where s.startup_id = p_startup_id and not s.archived
    for update;
  if v_found is null then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('startup_id %s not found', p_startup_id));
  end if;

  -- Correction: stored as a request only. Nothing on the startup changes.
  if coalesce(p_correction, false) then
    if v_note is null or length(v_note) > 2000 then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'a correction needs a note (up to 2000 characters): what is wrong and why');
    end if;
    if (v_country is not null and v_cur_country is null) or (v_city is not null and v_cur_city is null) then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'that field is empty: send it without correction to fill it');
    end if;
    if exists (select 1 from public.v2_startup_location_sources x
                where x.startup_id = p_startup_id and x.kind = 'correction' and x.status = 'requested'
                  and x.bot = v_bot.bot_name
                  and ((v_country is not null and x.field = 'st_country') or (v_city is not null and x.field = 'st_city'))) then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'you already sent a correction for this startup; one is enough');
    end if;
    if p_dry_run then
      return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'dry_run', true, 'startup_id', p_startup_id, 'status', 'correction would be stored for review');
    end if;
    insert into public.v2_startup_location_sources (startup_id, field, value, old_value, kind, status, source_url, source_level, source_date, source_type, source_owner, note, bot)
    select p_startup_id, f.field, f.val, f.old, 'correction', 'requested', v_url, v_level, v_date, v_type, v_owner, v_note, v_bot.bot_name
      from (values ('st_country', v_country, v_cur_country), ('st_city', v_city, v_cur_city)) f(field, val, old)
     where f.val is not null;
    insert into public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
    values (v_bot.bot_name, null, 'F14', 'v2_startups', p_startup_id, null,
            jsonb_build_object('st_country', v_cur_country, 'st_city', v_cur_city),
            jsonb_strip_nulls(jsonb_build_object('st_country', v_country, 'st_city', v_city, 'location_source', v_src, 'note', v_note)),
            'Held: location correction waits for review');
    return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'startup_id', p_startup_id, 'status', 'correction stored for review; nothing changed yet');
  end if;

  -- Fill: each sent field must be empty, or already the same value.
  if v_country is not null then
    if v_cur_country is null then v_fill := v_fill || jsonb_build_object('st_country', v_country);
    elsif upper(v_cur_country) = v_country then v_same := v_same || jsonb_build_object('st_country', v_cur_country);
    else v_conflict := v_conflict || jsonb_build_object('st_country', v_cur_country);
    end if;
  end if;
  if v_city is not null then
    if v_cur_city is null then v_fill := v_fill || jsonb_build_object('st_city', v_city);
    elsif lower(v_cur_city) = lower(v_city) then v_same := v_same || jsonb_build_object('st_city', v_cur_city);
    else v_conflict := v_conflict || jsonb_build_object('st_city', v_cur_city);
    end if;
  end if;
  if v_conflict <> '{}'::jsonb then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'startup_id', p_startup_id, 'already_set', v_conflict,
      'error', 'location already saved with a different value; it is never overwritten. If the saved value is wrong, send the same call once with "correction":true and a "note". Nothing was written.');
  end if;
  if v_fill = '{}'::jsonb then
    return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'startup_id', p_startup_id, 'already_stored', v_same,
      'status', 'already stored with the same value; nothing changed');
  end if;
  if p_dry_run then
    return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'dry_run', true, 'startup_id', p_startup_id,
      'would_fill', v_fill, 'already_stored', v_same);
  end if;

  insert into public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload, status)
  values (nextval('public.v2_batch_seq'), null, v_bot.bot_key_id, 'F14',
          jsonb_build_object('action', 'fill_startup_location', 'table', 'v2_startups', 'startup_id', p_startup_id,
                             'fill', v_fill, 'source', v_src),
          'Accepted')
  returning submission_id into v_sid;

  update public.v2_startups s
     set st_country = coalesce(nullif(btrim(s.st_country), ''), v_fill->>'st_country'),
         st_city    = coalesce(nullif(btrim(s.st_city), ''), v_fill->>'st_city')
   where s.startup_id = p_startup_id and not s.archived;

  insert into public.v2_startup_location_sources (startup_id, field, value, kind, status, source_url, source_level, source_date, source_type, source_owner, bot, submission_id)
  select p_startup_id, e.key, e.value #>> '{}', 'fill', 'applied', v_url, v_level, v_date, v_type, v_owner, v_bot.bot_name, v_sid
    from jsonb_each(v_fill) e;

  insert into public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
  values (v_bot.bot_name, null, 'F14', 'v2_startups', p_startup_id, v_sid,
          jsonb_build_object('st_country', v_cur_country, 'st_city', v_cur_city),
          v_fill || jsonb_build_object('location_source', v_src), 'Accepted');

  return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'startup_id', p_startup_id, 'submission_id', v_sid,
    'filled', v_fill, 'already_stored', v_same, 'status', 'Accepted');
end
$function$
$ddl$;

  -- 4. Location hand-out on the founder list -------------------------------------------------
  execute 'alter table founderlist.startups add column if not exists loc_status text';
  execute 'alter table founderlist.startups add column if not exists loc_taken_by text';
  execute 'alter table founderlist.startups add column if not exists loc_taken_at timestamptz';
  execute 'alter table founderlist.startups add column if not exists loc_finished_at timestamptz';
  execute 'alter table founderlist.startups add column if not exists loc_notes text';
  if not exists (select 1 from pg_constraint where conname = 'founderlist_loc_status_chk') then
    execute $ddl$alter table founderlist.startups add constraint founderlist_loc_status_chk check (
      (loc_status is null or loc_status in ('open', 'taken', 'done', 'rejected'))
      and (loc_status is distinct from 'taken' or (loc_taken_by is not null and loc_taken_at is not null))
      and (loc_notes is null or length(loc_notes) <= 4000)) not valid$ddl$;
    execute 'alter table founderlist.startups validate constraint founderlist_loc_status_chk';
  end if;
  execute 'create index if not exists founderlist_loc_pick_idx on founderlist.startups (pick_group, pick_amount desc nulls last, added_at, list_id) where loc_status = ''open''';
  execute 'create index if not exists founderlist_loc_taken_idx on founderlist.startups (loc_taken_by) where loc_status = ''taken''';

  execute $ddl$
create or replace function founderlist.loc_release_expired()
 returns integer
 language plpgsql
 security definer
 set search_path = founderlist, pg_catalog
 as $function$
declare
  v_n integer;
begin
  with o as (
    select x.list_id, x.startup_id, x.loc_taken_by, x.loc_taken_at from founderlist.startups x
     where x.loc_status = 'taken' and x.loc_taken_at <= now() - interval '2 hours'
     for update skip locked
  ), r as (
    update founderlist.startups x
       set loc_status = 'open', loc_taken_by = null, loc_taken_at = null
      from o
     where x.list_id = o.list_id
    returning x.list_id, x.startup_id, o.loc_taken_by, o.loc_taken_at
  ), e as (
    insert into founderlist.events (list_id, startup_id, bot, action, detail)
    select r.list_id, r.startup_id, null, 'loc_released',
           jsonb_build_object('was_taken_by', r.loc_taken_by, 'was_taken_at', r.loc_taken_at) from r
    returning 1
  )
  select count(*) into v_n from e;
  return v_n;
end
$function$
$ddl$;

  execute $ddl$
create or replace function founderlist.loc_row_json(r founderlist.startups)
 returns jsonb
 language sql
 stable
 security definer
 set search_path = founderlist, public, pg_catalog
 as $function$
  select jsonb_build_object(
    'list_id', r.list_id, 'startup_id', r.startup_id, 'startup_name', r.startup_name,
    'startup_website', r.startup_website, 'pick_group', r.pick_group,
    'loc_status', r.loc_status, 'loc_taken_by', r.loc_taken_by, 'loc_taken_at', r.loc_taken_at,
    'expires_at', case when r.loc_status = 'taken' then r.loc_taken_at + interval '2 hours' end,
    'loc_finished_at', r.loc_finished_at, 'loc_notes', r.loc_notes,
    'current_country', (select nullif(btrim(s.st_country), '') from public.v2_startups s where s.startup_id = r.startup_id and not s.archived),
    'current_city', (select nullif(btrim(s.st_city), '') from public.v2_startups s where s.startup_id = r.startup_id and not s.archived))
$function$
$ddl$;

  execute $ddl$
create or replace function public.founderlist_location_bot_ok(p_bot text)
 returns boolean
 language sql
 stable
 set search_path = pg_catalog
 as $function$
  select p_bot = any (string_to_array(regexp_replace(coalesce(
    (select s.value from public.v2_work_setting s where s.name = 'location_list_bots'), ''), '\s', '', 'g'), ','))
$function$
$ddl$;

  execute $ddl$
create or replace function public.founderlist_claim_next_location_startups(p_key_id uuid, p_count integer default 1)
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
  if not public.v2_location_fill_on() then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'location fill is switched off - stop and report');
  end if;
  if not public.founderlist_location_bot_ok(v_bot.bot_name) then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'this bot is not on the location list job');
  end if;
  if p_count is null or p_count < 1 or p_count > v_cap then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'count must be 1-10');
  end if;
  perform pg_advisory_xact_lock(hashtext('founderlist:loc'), v_bot.bot_key_id::int);
  perform founderlist.loc_release_expired();

  select coalesce(array_agg(x.startup_id order by x.loc_taken_at, x.list_id), '{}') into v_held
    from founderlist.startups x where x.loc_status = 'taken' and x.loc_taken_by = v_bot.bot_name;
  if cardinality(v_held) >= v_cap then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'held_count', cardinality(v_held),
      'held_startup_ids', to_jsonb(v_held),
      'error', format('you already hold %s startups (the most is %s): %s. Finish one with finish_location_startup before you ask for more.',
                      cardinality(v_held), v_cap, array_to_string(v_held, ', ')));
  end if;
  v_want := least(p_count, v_cap - cardinality(v_held));

  for v_row in
    select * from founderlist.startups x
     where x.loc_status = 'open'
     order by x.pick_group, x.pick_amount desc nulls last, x.added_at, x.list_id
     limit v_want
     for update skip locked
  loop
    update founderlist.startups x set loc_status = 'taken', loc_taken_by = v_bot.bot_name, loc_taken_at = now()
     where x.list_id = v_row.list_id
    returning * into v_row;
    insert into founderlist.events (list_id, startup_id, bot, action) values (v_row.list_id, v_row.startup_id, v_bot.bot_name, 'loc_taken');
    v_new := v_new || jsonb_build_array(founderlist.loc_row_json(v_row));
    v_held := v_held || v_row.startup_id;
  end loop;

  return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name,
    'startup', v_new->0, 'startups', v_new, 'claimed_count', jsonb_array_length(v_new),
    'held_count', cardinality(v_held), 'held_startup_ids', to_jsonb(v_held), 'max_held', v_cap);
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.founderlist_finish_location_startup(p_key_id uuid, p_startup_id bigint, p_result text, p_note text)
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
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id must be the startup from claim_next_location_startups');
  end if;
  if p_result is null or p_result not in ('done', 'rejected') then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'result must be done or rejected');
  end if;
  if v_note is null or length(v_note) > 4000 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'note is required (up to 4000 characters): what you saved, or why nothing was found');
  end if;
  perform founderlist.loc_release_expired();

  select * into v_row from founderlist.startups x where x.startup_id = p_startup_id for update;
  if not found or v_row.loc_status is null then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id is not on the location list');
  end if;
  if v_row.loc_status in ('done', 'rejected') and v_row.loc_taken_by = v_bot.bot_name then
    return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'already_finished', true, 'startup', founderlist.loc_row_json(v_row));
  end if;
  if v_row.loc_status <> 'taken' or v_row.loc_taken_by is distinct from v_bot.bot_name then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name,
      'error', 'this startup is not held by you (it may have gone back to the list after 2 hours); ask for claim_next_location_startups');
  end if;
  if p_result = 'done' and not exists (
       select 1 from public.v2_startup_location_sources l
        where l.startup_id = v_row.startup_id and l.bot = v_bot.bot_name
          and l.created_at >= v_row.loc_taken_at) then
    insert into founderlist.events (list_id, startup_id, bot, action, detail)
    values (v_row.list_id, v_row.startup_id, v_bot.bot_name, 'loc_done_refused', jsonb_build_object('note', v_note));
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'startup_id', v_row.startup_id,
      'error', 'finish_location_startup done refused: you saved no country or city (or correction) for this startup since you took it. Save it with fill_startup_location first, or finish it as rejected with the reason.');
  end if;

  update founderlist.startups x set loc_status = p_result, loc_finished_at = now(), loc_notes = v_note
   where x.list_id = v_row.list_id
  returning * into v_row;
  insert into founderlist.events (list_id, startup_id, bot, action, detail)
  values (v_row.list_id, v_row.startup_id, v_bot.bot_name, 'loc_' || p_result, jsonb_build_object('note', v_note));
  return jsonb_build_object('ok', true, 'bot_id', v_bot.bot_name, 'startup', founderlist.loc_row_json(v_row));
end
$function$
$ddl$;

  -- 5. Grants: only the door (service_role) may call the bot entry points ------------------
  execute 'revoke all on function public.v2_location_fill_on(), public.founderlist_location_bot_ok(text), founderlist.loc_release_expired(), founderlist.loc_row_json(founderlist.startups) from public';
  execute 'revoke all on function public.v2_startup_location_fill(uuid, bigint, text, text, jsonb, boolean, text, boolean), public.founderlist_claim_next_location_startups(uuid, integer), public.founderlist_finish_location_startup(uuid, bigint, text, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_location_fill_on(), public.founderlist_location_bot_ok(text), public.v2_startup_location_fill(uuid, bigint, text, text, jsonb, boolean, text, boolean), public.founderlist_claim_next_location_startups(uuid, integer), public.founderlist_finish_location_startup(uuid, bigint, text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_location_fill_on(), public.founderlist_location_bot_ok(text), public.v2_startup_location_fill(uuid, bigint, text, text, jsonb, boolean, text, boolean), public.founderlist_claim_next_location_startups(uuid, integer), public.founderlist_finish_location_startup(uuid, bigint, text, text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_startup_location_fill(uuid, bigint, text, text, jsonb, boolean, text, boolean) to service_role';
    execute 'grant execute on function public.founderlist_claim_next_location_startups(uuid, integer) to service_role';
    execute 'grant execute on function public.founderlist_finish_location_startup(uuid, bigint, text, text) to service_role';
  end if;
end
$mig$;
