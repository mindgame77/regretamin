-- Rollback of supabase/migrations/20261125163000_roundlist_finish_done_check.sql
-- Restores the previous finish_round (done needed only an accepted v2_deals
-- submission since the claim). Drops the new helpers. Does not drop the
-- round list, and does not delete any pending-firm rows already saved.
-- After this, deploy the previous research-ingest-v2 (finish_round without
-- source_url / report).

do $undo$
begin
  drop function if exists public.roundlist_finish_round(uuid, bigint, text, text, text, jsonb);
  drop function if exists public.roundlist_finish_round(uuid, bigint, text, text);
  drop function if exists roundlist.done_check(bigint, text, text, jsonb);
  drop function if exists roundlist.save_pending_firms(jsonb, bigint, text);

  if to_regclass('roundlist.rounds') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null then
    raise notice 'roundlist or v2_work_bot missing, stopped after dropping the new functions';
    return;
  end if;

  execute $ddl$
CREATE OR REPLACE FUNCTION public.roundlist_finish_round(p_key_id uuid, p_round_id bigint, p_result text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'roundlist', 'public', 'bots', 'pg_catalog'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
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
;
  $ddl$;

  execute 'revoke all on function public.roundlist_finish_round(uuid, bigint, text, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.roundlist_finish_round(uuid, bigint, text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.roundlist_finish_round(uuid, bigint, text, text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.roundlist_finish_round(uuid, bigint, text, text) to service_role';
  end if;
end
$undo$;
