-- Universal firm claims for research bots on the v2 door (actions next_firm and firm_done).
-- One table, v2_work_claims, holds one claim per (job, firm_id). A bot asks for the next firm
-- for a job; it gets one firm no other bot holds for that job. A claim lasts 2 hours; after that
-- any bot can take the firm again. firm_done closes the claim (only the bot's own claim).
-- Which firms qualify for a job lives in one function per job:
--   public.v2_job_firms_<job>(p_firm_id bigint) returns table(firm_id bigint, sort_key bigint, info jsonb)
-- Biggest sort_key first. Adding a job (legal, reviews, ...) means adding just that function.
-- A job with no such function is rejected as unknown. Only deal_gaps exists now.
-- deal_gaps: more than 20 distinct startups in current deals, and fewer than half of them
-- have a deal with a date or a round (same rows as the deals lookup).
-- Rollback: supabase/rollbacks/20261118200000_v2_work_claims.sql
-- The v2 schema is not created by repo migrations. On a database without v2 (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$
create table if not exists public.v2_work_claims (
  job text not null check (job ~ '^[a-z][a-z0-9_]{0,40}$'),
  firm_id bigint not null references public.v2_firms(firm_id) on delete cascade,
  bot_key_id bigint not null references public.v2_bot_keys(bot_key_id) on delete cascade,
  claimed_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '2 hours',
  done_at timestamptz,
  primary key (job, firm_id)
)
$ddl$;
  execute 'create index if not exists v2_work_claims_bot_idx on public.v2_work_claims (job, bot_key_id) where done_at is null';
  execute 'alter table public.v2_work_claims enable row level security';
  execute 'revoke all on table public.v2_work_claims from public, anon, authenticated';

  -- Job deal_gaps. p_firm_id null: every qualifying firm. Not null: that firm's numbers (even if it no longer qualifies).
  execute $ddl$
create or replace function public.v2_job_firms_deal_gaps(p_firm_id bigint default null)
 returns table(firm_id bigint, sort_key bigint, info jsonb)
 language sql
 stable
 set search_path = public, bots
 as $function$
  select g.firm_id, g.st, jsonb_build_object(
           'startups', g.st,
           'dated_or_staged', g.good,
           'next', jsonb_build_object('action', 'deals', 'firm_id', g.firm_id, 'only_gaps', true))
    from (
      select d.firm_id,
             count(distinct d.startup_id) as st,
             count(distinct d.startup_id) filter (
               where d.deal_date is not null or nullif(btrim(d.round), '') is not null) as good
        from public.v2_deals d
       where d.is_current and not d.archived and not coalesce(d.nothing_found, false)
         and (p_firm_id is null or d.firm_id = p_firm_id)
       group by d.firm_id
    ) g
   where p_firm_id is not null or (g.st > 20 and g.good * 2 < g.st)
$function$
$ddl$;

  -- The bot behind an ingest key (same as claim: links v2_bot_keys by bot_name).
  execute $ddl$
create or replace function public.v2_work_bot(p_key_id uuid)
 returns public.v2_bot_keys
 language plpgsql
 security definer
 set search_path = public, bots
 as $function$
declare
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
begin
  select * into ik from bots.ingest_keys where id = p_key_id and active;
  if not found or ik.bot_id is null then
    return null;
  end if;
  select * into bk from public.v2_bot_keys where bot_name = ik.bot_id;
  if not found or bk.key_hash is distinct from ik.key_hash then
    insert into public.v2_bot_keys (bot_name, key_hash) values (ik.bot_id, ik.key_hash)
      on conflict (bot_name) do update set key_hash = excluded.key_hash returning * into bk;
  end if;
  return bk;
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.v2_work_job_fn(p_job text)
 returns text
 language sql
 stable
 set search_path = public
 as $function$
  select case when p_job ~ '^[a-z][a-z0-9_]{0,40}$'
               and to_regprocedure(format('public.v2_job_firms_%s(bigint)', p_job)) is not null
              then format('v2_job_firms_%s', p_job) end
$function$
$ddl$;

  execute $ddl$
create or replace function public.v2_next_firm(p_key_id uuid, p_job text)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public, bots
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  bk public.v2_bot_keys;
  fn text := public.v2_work_job_fn(p_job);
  c public.v2_work_claims;
  r record;
  held boolean := true;
  v_info jsonb;
  frm public.v2_firms;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if fn is null then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'unknown job');
  end if;

  -- A bot that already holds a live claim for this job gets the same firm back.
  select * into c from public.v2_work_claims w
   where w.job = p_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now()
   order by w.claimed_at, w.firm_id limit 1;

  if not found then
    held := false;
    for r in execute format(
      'select g.firm_id from public.%I(null) g
         join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
        where not exists (select 1 from public.v2_work_claims w
                           where w.job = $1 and w.firm_id = g.firm_id
                             and (w.done_at is not null or w.expires_at > now()))
        order by g.sort_key desc, g.firm_id
        limit 50', fn) using p_job
    loop
      -- Skip a firm another bot is claiming right now (no waiting).
      continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || p_job), r.firm_id::int);
      insert into public.v2_work_claims as w (job, firm_id, bot_key_id, claimed_at, expires_at, done_at)
      values (p_job, r.firm_id, bk.bot_key_id, now(), now() + interval '2 hours', null)
      on conflict (job, firm_id) do update
         set bot_key_id = excluded.bot_key_id, claimed_at = excluded.claimed_at, expires_at = excluded.expires_at
       where w.done_at is null and w.expires_at <= now()
      returning * into c;
      exit when found;
    end loop;
    if c.firm_id is null then
      return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'firm', null);
    end if;
  end if;

  execute format('select info from public.%I($1)', fn) into v_info using c.firm_id;
  select * into frm from public.v2_firms where firm_id = c.firm_id;
  return jsonb_build_object(
    'ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'held', held,
    'claimed_at', c.claimed_at, 'expires_at', c.expires_at,
    'firm', jsonb_build_object('firm_id', frm.firm_id, 'name', frm.display_name, 'slug', frm.slug, 'website', frm.website_url)
            || coalesce(v_info, '{}'::jsonb));
end
$function$
$ddl$;

  execute $ddl$
create or replace function public.v2_firm_done(p_key_id uuid, p_job text, p_firm_id bigint)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public, bots
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  bk public.v2_bot_keys;
  c public.v2_work_claims;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if public.v2_work_job_fn(p_job) is null then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'unknown job');
  end if;
  update public.v2_work_claims w set done_at = now()
   where w.job = p_job and w.firm_id = p_firm_id and w.bot_key_id = bk.bot_key_id and w.done_at is null
  returning * into c;
  if found then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'firm_id', p_firm_id, 'done_at', c.done_at);
  end if;
  select * into c from public.v2_work_claims w
   where w.job = p_job and w.firm_id = p_firm_id and w.bot_key_id = bk.bot_key_id;
  if found then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'firm_id', p_firm_id, 'done_at', c.done_at, 'already_done', true);
  end if;
  return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'this firm is not claimed by you for this job');
end
$function$
$ddl$;

  -- Server only: the door calls them with the service role.
  execute 'revoke all on function public.v2_job_firms_deal_gaps(bigint) from public, anon, authenticated';
  execute 'revoke all on function public.v2_work_bot(uuid) from public, anon, authenticated';
  execute 'revoke all on function public.v2_work_job_fn(text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_next_firm(uuid, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_firm_done(uuid, text, bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_next_firm(uuid, text) to service_role';
    execute 'grant execute on function public.v2_firm_done(uuid, text, bigint) to service_role';
  end if;
end
$mig$;
