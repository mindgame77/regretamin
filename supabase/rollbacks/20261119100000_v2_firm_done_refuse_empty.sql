-- Undo 20261119100000_v2_firm_done_refuse_empty.sql.
-- Restores v2_firm_done to its 20261118310000 definition (firm_done always closes the claim).

do $rb$
begin
  if to_regprocedure('public.v2_firm_done(uuid, text, bigint)') is null
     or to_regclass('public.v2_work_claims') is null then
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
$rb$;
