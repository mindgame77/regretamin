-- Undo 20261118220000_v2_next_firm_hold_10: put back v2_next_firm exactly as it was in production
-- before (pg_get_functiondef, 2026-11-18): one live claim per key per job, a repeat call returns the same firm.
-- Claims stay as they are. A key that holds several firms gets its oldest one back until it marks them done
-- or they expire (2 hours). Grants are kept by create or replace.
CREATE OR REPLACE FUNCTION public.v2_next_firm(p_key_id uuid, p_job text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
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
$function$;
