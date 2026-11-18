-- v2 door next_firm: same as 20261118260000, except the fresh and reopen
-- passes hand out a firm with any known (non-blank) v2_firms.hq_country, in
-- any region. Null/blank country stays excluded. The 10-hold cap, 2-hour
-- hold, advisory locks, firm_done, reply shape, and reopen-to-a-different-bot
-- rule are unchanged.
-- Rollback: supabase/rollbacks/20261118300000_v2_next_firm_all_known_hq.sql
-- The v2 schema is not created by repo migrations. On a database without
-- v2_work_claims (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_work_claims') is null
     or to_regprocedure('public.v2_work_job_fn(text)') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null then
    raise notice 'v2_work_claims missing, skipped';
    return;
  end if;

  execute $ddl$
create or replace function public.v2_work_hq_known(p_country text)
 returns boolean
 language sql
 immutable
 set search_path = public
 as $fn$
  select btrim(coalesce(p_country, '')) <> '';
$fn$
$ddl$;

  execute 'revoke all on function public.v2_work_hq_known(text) from public, anon, authenticated';

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
  n_held int;
  v_held jsonb;
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

  -- One call per key at a time, so parallel helpers of one bot never go past 10.
  perform pg_advisory_xact_lock(hashtext('v2_work_keys:' || p_job), bk.bot_key_id::int);

  -- A bot may hold up to 10 live claims for this job. At 10 it gets its oldest one back.
  select count(*) into n_held from public.v2_work_claims w
   where w.job = p_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if n_held >= 10 then
    select * into c from public.v2_work_claims w
     where w.job = p_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now()
     order by w.claimed_at, w.firm_id limit 1;
  else
    held := false;
    for r in execute format(
      'select g.firm_id from public.%I(null) g
         join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
        where public.v2_work_hq_known(f.hq_country)
          and not exists (select 1 from public.v2_work_claims w
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

    -- No fresh firm: reopen a done-but-still-gappy firm someone else finished.
    if c.firm_id is null then
      for r in execute format(
        'select g.firm_id from public.%I(null) g
           join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
           join public.v2_work_claims w on w.job = $1 and w.firm_id = g.firm_id
          where public.v2_work_hq_known(f.hq_country)
            and w.done_at is not null
            and w.bot_key_id is distinct from $2
          order by (g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)) desc, g.firm_id
          limit 50', fn) using p_job, bk.bot_key_id
      loop
        continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || p_job), r.firm_id::int);
        update public.v2_work_claims as w
           set bot_key_id = bk.bot_key_id, claimed_at = now(), expires_at = now() + interval '2 hours', done_at = null
         where w.job = p_job and w.firm_id = r.firm_id
           and w.done_at is not null
           and w.bot_key_id is distinct from bk.bot_key_id
        returning * into c;
        exit when found;
      end loop;
    end if;
  end if;

  -- The key's live claims for this job after this call.
  select coalesce(jsonb_agg(w.firm_id order by w.claimed_at, w.firm_id), '[]'::jsonb) into v_held
    from public.v2_work_claims w
   where w.job = p_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if c.firm_id is null then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'firm', null,
      'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held));
  end if;

  execute format('select info from public.%I($1)', fn) into v_info using c.firm_id;
  select * into frm from public.v2_firms where firm_id = c.firm_id;
  return jsonb_build_object(
    'ok', true, 'bot_id', bk.bot_name, 'job', p_job, 'held', held,
    'claimed_at', c.claimed_at, 'expires_at', c.expires_at,
    'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held),
    'firm', jsonb_build_object('firm_id', frm.firm_id, 'name', frm.display_name, 'slug', frm.slug, 'website', frm.website_url)
            || coalesce(v_info, '{}'::jsonb));
end
$function$
$ddl$;

  -- create or replace keeps the grants; restated so a fresh database ends the same.
  execute 'revoke all on function public.v2_next_firm(uuid, text) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_next_firm(uuid, text) to service_role';
  end if;

  execute 'drop function if exists public.v2_work_hq_na_europe(text)';
end
$mig$;
