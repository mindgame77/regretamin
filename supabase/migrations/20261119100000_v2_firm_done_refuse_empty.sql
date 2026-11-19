-- v2 work: firm_done refuses an empty close in job missing_details.
-- Built on Alex's OK (2026-11-19). Preview only; apply only on "make it live".
-- Why: on 2026-11-19 bot 7 marked 29 missing_details firms done without saving anything,
-- so they left the list with every gap still open.
-- v2_firm_done(p_key_id, p_job, p_firm_id): for job missing_details only, the call is
-- refused (ok false, claim stays open, done_at stays null) when BOTH
--   a) the bot has no v2_research_submissions row (any status, nothing_found included)
--      for this firm received since its claim's claimed_at, and
--   b) v2_job_firms_missing_details(p_firm_id) still lists missing items for the firm.
-- Otherwise firm_done works exactly as before. Other jobs (deal_gaps) are unchanged.
-- Rollback: supabase/rollbacks/20261119100000_v2_firm_done_refuse_empty.sql
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_work_claims') is null
     or to_regclass('public.v2_research_submissions') is null
     or to_regprocedure('public.v2_firm_done(uuid, text, bigint)') is null
     or to_regprocedure('public.v2_job_firms_missing_details(bigint)') is null then
    raise notice 'v2 work tables missing, skipped';
    return;
  end if;

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
  v_cur text := public.v2_work_current_job();
  v_jobs text[];
  j text;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  -- The job the bot sent first (a hold from before a switch), then the current job.
  v_jobs := array_remove(array[case when public.v2_work_job_fn(p_job) is not null then p_job end,
                               case when v_cur is distinct from p_job then v_cur end], null);
  if cardinality(v_jobs) = 0 then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'unknown job');
  end if;
  foreach j in array v_jobs loop
    -- missing_details: refuse done when the bot saved nothing for this firm during its
    -- open claim (no submission of any status, nothing_found included) and the firm
    -- still has missing items. The claim stays open.
    if j = 'missing_details' then
      select * into c from public.v2_work_claims w
       where w.job = j and w.firm_id = p_firm_id and w.bot_key_id = bk.bot_key_id and w.done_at is null;
      if found
         and not exists (select 1 from public.v2_research_submissions s
                          where s.bot_key_id = bk.bot_key_id and s.firm_id = p_firm_id
                            and s.received_at >= c.claimed_at)
         and exists (select 1 from public.v2_job_firms_missing_details(p_firm_id) m
                      where jsonb_array_length(coalesce(m.info->'missing', '[]'::jsonb)) > 0) then
        return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'job', j, 'firm_id', p_firm_id,
          'error', 'firm_done refused: you saved nothing for this firm. Research the missing fields first, or save nothing_found for each field you searched.');
      end if;
    end if;
    update public.v2_work_claims w set done_at = now()
     where w.job = j and w.firm_id = p_firm_id and w.bot_key_id = bk.bot_key_id and w.done_at is null
    returning * into c;
    if found then
      return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', j, 'firm_id', p_firm_id, 'done_at', c.done_at);
    end if;
  end loop;
  foreach j in array v_jobs loop
    select * into c from public.v2_work_claims w
     where w.job = j and w.firm_id = p_firm_id and w.bot_key_id = bk.bot_key_id;
    if found then
      return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', j, 'firm_id', p_firm_id, 'done_at', c.done_at, 'already_done', true);
    end if;
  end loop;
  return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'this firm is not claimed by you for this job');
end
$function$
$ddl$;

  -- create or replace keeps the grants; restated so a fresh database ends the same.
  execute 'revoke all on function public.v2_firm_done(uuid, text, bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_firm_done(uuid, text, bigint) to service_role';
  end if;
end
$mig$;
