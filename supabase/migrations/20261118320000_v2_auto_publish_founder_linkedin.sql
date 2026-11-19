-- Founder LinkedIn fills go live like firm fields do.
-- A bot's linkedin_url fill on an existing person (v2_research_submit holds it as
-- "Held: empty person url waits for the Checker" and queues a changed-key-fact
-- on v2_people) is now auto-published by v2_auto_publish_apply_queue:
--   * only into an empty v2_people.linkedin_url (never overwrite),
--   * skipped when another live person already has the same link (v2_norm_url),
--   * still behind v2_auto_publish_on(firm) and all v2_research_submit checks (unchanged).
-- v2_auto_publish_take_down / restore_one learn to revert / re-apply that link
-- (before, a pull would have fallen through to hiding the whole person row).
-- x_url fills and every other path are unchanged. Submission statuses are not rewritten.
-- Includes a one-time backfill of the fills held today.
-- Rollback: supabase/rollbacks/20261118320000_v2_auto_publish_founder_linkedin.sql
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.

do $mig$
declare
  r record;
  msg text;
  v_pub int := 0;
  v_skip int := 0;
begin
  if to_regclass('public.v2_people') is null
     or to_regclass('public.v2_auto_published') is null
     or to_regprocedure('public.v2_auto_publish_apply_queue(bigint)') is null
     or to_regprocedure('public.v2_norm_url(text)') is null then
    raise notice 'v2 auto-publish missing, skipped';
    return;
  end if;

  execute $ddl$
CREATE OR REPLACE FUNCTION public.v2_auto_publish_apply_queue(p_queue_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
declare
  q public.v2_checker_queue;
  sub public.v2_research_submissions;
  cur jsonb;
  arch boolean;
  iscur boolean;
  shown boolean;
  pk text;
  prior jsonb;
  n int;
begin
  select * into q from public.v2_checker_queue where queue_id = p_queue_id for update;
  if not found then
    return 'skipped: queue missing';
  end if;
  if q.archived or q.status is distinct from 'open' then
    return 'skipped: not open';
  end if;
  if not public.v2_auto_publish_on(q.firm_id) then
    return 'off';
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    where ap.queue_id = q.queue_id and ap.pulled_at is not null
  ) then
    return 'skipped: pulled';
  end if;
  if exists (
    select 1 from public.v2_auto_published ap
    where ap.queue_id = q.queue_id and ap.live
  ) then
    return 'already';
  end if;
  select * into sub from public.v2_research_submissions where submission_id = q.submission_id;
  if not found or sub.status like 'Rejected:%' then
    return 'skipped: rejected';
  end if;
  if q.kind = 'new-firm' then
    return 'skipped: new firm stays with the Checker';
  end if;

  if q.kind = 'changed-key-fact' and q.table_name = 'v2_deals' then
    prior := jsonb_build_object('deal_change',bots.v2_apply_deal_change(q.queue_id));
  elsif q.kind = 'changed-key-fact' and q.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = q.firm_id for update;
    if cur is null then
      return 'skipped: firm missing';
    end if;
    prior := jsonb_build_object('before', (
      select coalesce(jsonb_object_agg(k, cur->k), '{}'::jsonb)
      from jsonb_object_keys(q.new_value) k
      where k = any(array[
        'legal_name','legal_name_source','founded_year','founded_year_source',
        'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
        'hq_postal','hq_country','hq_source','website_url','short_name'])
    ), 'applied', (
      select coalesce(jsonb_object_agg(k, q.new_value->k), '{}'::jsonb)
      from jsonb_object_keys(q.new_value) k
      where k = any(array[
        'legal_name','legal_name_source','founded_year','founded_year_source',
        'thesis_text','thesis_source','hq_street','hq_suite','hq_city','hq_state',
        'hq_postal','hq_country','hq_source','website_url','short_name'])
    ));
    if prior->'applied' = '{}'::jsonb then
      return 'skipped: no firm field';
    end if;
    n := public.v2_auto_publish_write_firm(q.firm_id, prior->'applied');
    if n = 0 then
      return 'skipped: firm not updated';
    end if;
  elsif q.kind = 'changed-key-fact' and q.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s
     where s.startup_id = q.row_id and not s.archived for update;
    if cur is null then
      return 'skipped: startup missing';
    end if;
    if coalesce(cur->>'website_url','') <> '' and cur->>'website_url' is distinct from (q.new_value->>'website_url') then
      return 'skipped: website already set';
    end if;
    update public.v2_startups s
       set website_url = q.new_value->>'website_url',
           website_source = q.new_value->'website_source'
     where s.startup_id = q.row_id and not s.archived;
    prior := jsonb_build_object(
      'before', jsonb_build_object('website_url', cur->'website_url', 'website_source', cur->'website_source'),
      'applied', jsonb_build_object('website_url', q.new_value->'website_url', 'website_source', q.new_value->'website_source'));
  elsif q.kind = 'changed-key-fact' and q.table_name = 'v2_people' then
    -- Founder LinkedIn fill: only into an empty linkedin_url, never overwrite,
    -- and never a link another live person already has.
    if nullif(btrim(q.new_value->>'linkedin_url'), '') is null then
      return 'skipped: no linkedin_url';
    end if;
    select to_jsonb(p) into cur from public.v2_people p
     where p.person_id = q.row_id and not p.archived for update;
    if cur is null then
      return 'skipped: person missing';
    end if;
    if nullif(btrim(cur->>'linkedin_url'), '') is not null then
      return 'skipped: linkedin already set';
    end if;
    if exists (
      select 1 from public.v2_people p2
       where p2.person_id <> q.row_id and not p2.archived
         and nullif(btrim(p2.linkedin_url), '') is not null
         and public.v2_norm_url(p2.linkedin_url) = public.v2_norm_url(q.new_value->>'linkedin_url')
    ) then
      return 'skipped: linkedin on another person';
    end if;
    update public.v2_people p
       set linkedin_url = q.new_value->>'linkedin_url'
     where p.person_id = q.row_id and not p.archived
       and nullif(btrim(p.linkedin_url), '') is null;
    get diagnostics n = row_count;
    if n = 0 then
      return 'skipped: person not updated';
    end if;
    prior := jsonb_build_object(
      'before', jsonb_build_object('linkedin_url', cur->'linkedin_url'),
      'applied', jsonb_build_object('linkedin_url', q.new_value->'linkedin_url'));
  elsif q.kind in ('accepted-item','name-only') then
    if not public.v2_auto_publish_allowed(q.table_name) then
      return 'skipped: table not allowed';
    end if;
    pk := public.v2_auto_publish_pk(q.table_name);
    execute format(
      'select archived, is_current from public.%I where %I = $1',
      q.table_name, pk
    ) into arch, iscur using q.row_id;
    if arch is null then
      return 'skipped: row missing';
    end if;
    if arch then
      return 'skipped: archived';
    end if;
    shown := null;
    if q.table_name = 'v2_deals' then
      select d.shown into shown from public.v2_deals d where d.row_id = q.row_id;
    end if;
    n := public.v2_auto_publish_show_row(q.table_name, q.row_id);
    if n = 0 then
      return 'skipped: row not updated';
    end if;
    prior := jsonb_build_object('is_current', iscur, 'shown', shown, 'archived', arch);
  else
    return 'skipped: kind';
  end if;

  insert into public.v2_auto_published (
    queue_id, submission_id, firm_id, bot_key_id, table_name, row_id, kind, prior, live, pulled_at
  ) values (
    q.queue_id, q.submission_id, q.firm_id, sub.bot_key_id, q.table_name, q.row_id, q.kind, prior, true, null
  )
  on conflict (queue_id) do update
    set live = true,
        pulled_at = null,
        prior = excluded.prior,
        applied_at = now(),
        bot_key_id = excluded.bot_key_id
  where public.v2_auto_published.pulled_at is null;
  return 'published';
end
$function$
$ddl$;

  execute $ddl$
CREATE OR REPLACE FUNCTION public.v2_auto_publish_take_down(p_queue_id bigint, p_mode text, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ap public.v2_auto_published;
  cur jsonb;
  built jsonb;
  n int;
  outcome text;
begin
  if p_mode not in ('pull','reject') then
    return 'skipped: mode';
  end if;
  select * into ap from public.v2_auto_published where queue_id = p_queue_id for update;
  if not found then
    return 'missing';
  end if;
  if p_mode = 'pull' and ap.pulled_at is not null then
    return 'already';
  end if;
  if ap.prior ? 'deal_change' and ap.table_name='v2_deals' then
    outcome:=bots.v2_undo_deal_change(p_queue_id);
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = ap.firm_id for update;
    built := public.v2_auto_publish_field_patch(cur, ap.prior, 'before');
    if coalesce((built->>'wrote')::int, 0) > 0 then
      perform public.v2_auto_publish_write_firm(ap.firm_id, built->'patch');
      outcome := 'reverted';
    else
      outcome := 'conflict';
    end if;
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s where s.startup_id = ap.row_id for update;
    built := public.v2_auto_publish_field_patch(cur, ap.prior, 'before');
    if coalesce((built->>'wrote')::int, 0) > 0 then
      update public.v2_startups s
         set website_url = case when built->'patch' ? 'website_url' then built#>>'{patch,website_url}' else s.website_url end,
             website_source = case when built->'patch' ? 'website_source' then built#>'{patch,website_source}' else s.website_source end
       where s.startup_id = ap.row_id;
      outcome := 'reverted';
    else
      outcome := 'conflict';
    end if;
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_people' then
    -- Put the old (empty) link back only if the link we wrote is still there.
    select to_jsonb(p) into cur from public.v2_people p where p.person_id = ap.row_id for update;
    if cur is not null and cur->'linkedin_url' is not distinct from ap.prior#>'{applied,linkedin_url}' then
      update public.v2_people p
         set linkedin_url = ap.prior#>>'{before,linkedin_url}'
       where p.person_id = ap.row_id;
      outcome := 'reverted';
    else
      outcome := 'conflict';
    end if;
  elsif public.v2_auto_publish_shared(ap.table_name, ap.row_id, ap.firm_id) then
    outcome := 'left_shared';
  elsif p_mode = 'reject' then
    n := public.v2_auto_publish_hide_row(ap.table_name, ap.row_id, true, coalesce(p_reason, 'Checker rejected'));
    outcome := case when n > 0 then 'archived' else 'skipped' end;
  else
    n := public.v2_auto_publish_hide_row(ap.table_name, ap.row_id, false, null);
    outcome := case when n > 0 then 'hidden' else 'skipped' end;
  end if;
  update public.v2_auto_published
     set live = false,
         pulled_at = case when p_mode = 'pull' then now() else pulled_at end
   where queue_id = p_queue_id;
  return outcome;
end
$function$
$ddl$;

  execute $ddl$
CREATE OR REPLACE FUNCTION public.v2_auto_publish_restore_one(p_queue_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  ap public.v2_auto_published;
  q public.v2_checker_queue;
  sub public.v2_research_submissions;
  cur jsonb;
  arch boolean;
  built jsonb;
  n int;
  pk text;
begin
  select * into ap from public.v2_auto_published where queue_id = p_queue_id for update;
  if not found or ap.pulled_at is null then
    return 'skipped: not pulled';
  end if;
  select * into q from public.v2_checker_queue where queue_id = p_queue_id;
  select * into sub from public.v2_research_submissions where submission_id = ap.submission_id;
  if q.status = 'failed' or q.archived or coalesce(sub.status,'') like 'Rejected:%' then
    return 'skipped: checker closed';
  end if;
  if ap.prior ? 'applied' and ap.table_name = 'v2_firms' then
    select to_jsonb(f) into cur from public.v2_firms f where f.firm_id = ap.firm_id for update;
    built := public.v2_auto_publish_field_patch(
      cur,
      jsonb_build_object('applied', ap.prior->'before', 'before', ap.prior->'applied'),
      'before');
    -- field_patch treats "applied" as the value that must still be on the row.
    -- After a pull, that value is `before`. The value to write back is the original `applied`,
    -- which field_patch returns when p_use is before and we swap the two sides above.
    if coalesce((built->>'wrote')::int, 0) = 0 then
      return 'conflict';
    end if;
    perform public.v2_auto_publish_write_firm(ap.firm_id, built->'patch');
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_startups' then
    select to_jsonb(s) into cur from public.v2_startups s where s.startup_id = ap.row_id for update;
    built := public.v2_auto_publish_field_patch(
      cur,
      jsonb_build_object('applied', ap.prior->'before', 'before', ap.prior->'applied'),
      'before');
    if coalesce((built->>'wrote')::int, 0) = 0 then
      return 'conflict';
    end if;
    update public.v2_startups s
       set website_url = case when built->'patch' ? 'website_url' then built#>>'{patch,website_url}' else s.website_url end,
           website_source = case when built->'patch' ? 'website_source' then built#>'{patch,website_source}' else s.website_source end
     where s.startup_id = ap.row_id;
  elsif ap.prior ? 'applied' and ap.table_name = 'v2_people' then
    select to_jsonb(p) into cur from public.v2_people p where p.person_id = ap.row_id for update;
    if cur is null or cur->'linkedin_url' is distinct from ap.prior#>'{before,linkedin_url}' then
      return 'conflict';
    end if;
    update public.v2_people p
       set linkedin_url = ap.prior#>>'{applied,linkedin_url}'
     where p.person_id = ap.row_id;
  else
    if not public.v2_auto_publish_allowed(ap.table_name) then
      return 'skipped: table not allowed';
    end if;
    pk := public.v2_auto_publish_pk(ap.table_name);
    execute format('select archived from public.%I where %I = $1', ap.table_name, pk)
      into arch using ap.row_id;
    if arch is null then
      return 'skipped: row missing';
    end if;
    if arch then
      return 'skipped: archived';
    end if;
    n := public.v2_auto_publish_show_row(ap.table_name, ap.row_id);
    if n = 0 then
      return 'skipped: row not updated';
    end if;
  end if;
  update public.v2_auto_published
     set live = true, pulled_at = null
   where queue_id = p_queue_id;
  return 'restored';
end
$function$
$ddl$;

  -- create or replace keeps the grants; restated so a fresh database ends the same.
  execute 'revoke all on function public.v2_auto_publish_apply_queue(bigint) from public, anon, authenticated';
  execute 'revoke all on function public.v2_auto_publish_take_down(bigint, text, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_auto_publish_restore_one(bigint) from public, anon, authenticated';

  -- One-time backfill: publish the founder LinkedIn fills that are held today,
  -- oldest first, under the same rule (empty link only, no duplicates).
  for r in
    select q.queue_id
      from public.v2_checker_queue q
      join public.v2_research_submissions s on s.submission_id = q.submission_id
     where q.kind = 'changed-key-fact' and q.table_name = 'v2_people'
       and q.status = 'open' and not q.archived
       and s.status like 'Held: empty person url%'
     order by q.queue_id
  loop
    msg := public.v2_auto_publish_apply_queue(r.queue_id);
    if msg = 'published' then v_pub := v_pub + 1; else v_skip := v_skip + 1; end if;
  end loop;
  raise notice 'founder linkedin backfill: % published, % skipped', v_pub, v_skip;
end
$mig$;
