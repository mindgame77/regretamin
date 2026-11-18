-- Feedback inbox for research bots. The Regretamin team leaves a short note for one bot key.
-- research-ingest-v2 adds that key's unread notes to every successful claim reply as `notes`,
-- and has two new actions: notes (read without claiming) and notes_ack (mark read).
-- New table bots.bot_notes and two new functions. No existing table, function, key or page changes.
-- Acks never touch v2_research_submissions, so they are not rejections and never count toward freezes.
-- Service role only: RLS on with no policies, no grants to anon or authenticated.
-- On a database without bots.ingest_keys (CI) this is a no-op.
-- Not applied to production by this change.
-- Undo: supabase/rollbacks/20261118040000_v2_bot_notes.sql
do $mig$
begin
  if to_regclass('bots.ingest_keys') is null then
    raise notice 'bots.ingest_keys missing, skipped';
    return;
  end if;

  execute $sql$
create table if not exists bots.bot_notes (
  note_id    uuid primary key default gen_random_uuid(),
  bot_key_id uuid not null references bots.ingest_keys(id) on delete cascade,
  bot_id     text,
  body       text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  created_by text not null default 'regretamin-team',
  read_at    timestamptz,
  ack_text   text check (ack_text is null or length(ack_text) <= 500)
)
$sql$;
  execute 'create index if not exists bot_notes_unread_idx on bots.bot_notes (bot_key_id, created_at) where read_at is null';
  execute 'alter table bots.bot_notes enable row level security';
  execute 'revoke all on table bots.bot_notes from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table bots.bot_notes from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table bots.bot_notes from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table bots.bot_notes to service_role';
  end if;

  -- Unread notes for one key, oldest first, at most 20.
  execute $fn$
create or replace function public.v2_bot_notes_unread(p_key_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to public, bots
set statement_timeout to '5s'
as $body$
  select coalesce(jsonb_agg(jsonb_build_object('note_id', n.note_id, 'body', n.body, 'created_at', n.created_at)
                            order by n.created_at, n.note_id), '[]'::jsonb)
    from (select note_id, body, created_at
            from bots.bot_notes
           where bot_key_id = p_key_id and read_at is null
           order by created_at, note_id
           limit 20) n
$body$
$fn$;

  -- Mark notes read for this key only. Ids that are not this key's unread notes are reported, not changed.
  execute $fn$
create or replace function public.v2_bot_notes_ack(p_key_id uuid, p_note_ids uuid[], p_ack_text text default 'read')
returns jsonb
language plpgsql
security definer
set search_path to public, bots
set statement_timeout to '5s'
set lock_timeout to '2s'
as $body$
declare
  v_acked uuid[];
  v_ids uuid[];
begin
  v_ids := array(select distinct unnest(coalesce(p_note_ids, '{}')));
  if cardinality(v_ids) = 0 or cardinality(v_ids) > 50 then
    return jsonb_build_object('ok', false, 'error', 'note_ids must list 1-50 note ids');
  end if;
  with u as (
    update bots.bot_notes
       set read_at = now(),
           ack_text = left(coalesce(nullif(btrim(p_ack_text), ''), 'read'), 500)
     where bot_key_id = p_key_id and read_at is null and note_id = any(v_ids)
    returning note_id)
  select coalesce(array_agg(note_id), '{}') into v_acked from u;
  return jsonb_build_object(
    'ok', true,
    'acked', to_jsonb(v_acked),
    'not_found', to_jsonb(array(select x from unnest(v_ids) x where not (x = any(v_acked)))));
end
$body$
$fn$;

  execute 'revoke all on function public.v2_bot_notes_unread(uuid) from public';
  execute 'revoke all on function public.v2_bot_notes_ack(uuid, uuid[], text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_bot_notes_unread(uuid) from anon';
    execute 'revoke all on function public.v2_bot_notes_ack(uuid, uuid[], text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_bot_notes_unread(uuid) from authenticated';
    execute 'revoke all on function public.v2_bot_notes_ack(uuid, uuid[], text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_bot_notes_unread(uuid) to service_role';
    execute 'grant execute on function public.v2_bot_notes_ack(uuid, uuid[], text) to service_role';
  end if;
end
$mig$;
