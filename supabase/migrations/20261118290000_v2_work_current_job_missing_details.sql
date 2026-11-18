-- v2 work handout: one setting picks the job next_firm hands out.
-- 1) v2_work_setting (name, value). Row current_job = 'missing_details'.
--    v2_work_current_job() returns it when it names a real job function.
--    To swap jobs later (e.g. youtube): add v2_job_firms_youtube(bigint) and
--    update v2_work_setting set value = 'youtube' where name = 'current_job'.
-- 2) v2_job_firms_missing_details(bigint): live firms (not archived, not merged)
--    missing any of: hq_country, hq_city, a contact row (v2_firm_contacts),
--    a social account (v2_social_accounts), a person linked by a role who has
--    linkedin_url. A row in those tables counts when not archived (live,
--    waiting for the Checker, or nothing_found). sort_key = missing field count.
--    info: missing (list), missing_count, needs_country, and for one firm
--    saved_people (person_id, name, has_linkedin) so bots do not resend people.
-- 3) v2_next_firm hands out the current job, whatever job the bot sends
--    (reply job = the current job; asked_job when it differs). Region filter:
--    North America / Europe as before, plus firms with blank hq_country when
--    the job says needs_country. The reopen pass only runs for deal_gaps, so a
--    firm marked done for missing_details is not handed out again, and deal
--    gaps are not handed out while another job is current.
-- 4) v2_firm_done marks the bot's claim in the job it sent, else in the current job.
-- 5) v2_renew_deal_gap_holds renews this bot's open claim on the firm in any job.
-- Same calls, same 10-hold cap, 2-hour holds, notes. No new endpoint.
-- Rollback: supabase/rollbacks/20261118290000_v2_work_current_job_missing_details.sql
-- The v2 schema is not created by repo migrations. On a database without
-- v2_work_claims (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_work_claims') is null
     or to_regprocedure('public.v2_work_job_fn(text)') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null
     or to_regprocedure('public.v2_work_hq_na_europe(text)') is null then
    raise notice 'v2_work_claims missing, skipped';
    return;
  end if;

  execute $ddl$
create table if not exists public.v2_work_setting (
  name text primary key,
  value text not null,
  updated_at timestamptz not null default now()
)
$ddl$;
  execute 'alter table public.v2_work_setting enable row level security';
  execute 'revoke all on table public.v2_work_setting from public, anon, authenticated';

  execute $ddl$
create or replace function public.v2_job_firms_missing_details(p_firm_id bigint default null)
 returns table(firm_id bigint, sort_key bigint, info jsonb)
 language sql
 stable
 set search_path = public, bots
 as $fn$
  select x.firm_id, x.n::bigint as sort_key, jsonb_build_object(
           'missing', to_jsonb(array_remove(array[
              case when x.no_country then 'hq_country' end,
              case when x.no_city then 'hq_city' end,
              case when x.no_contact then 'contact' end,
              case when x.no_social then 'socials' end,
              case when x.no_linkedin then 'people_linkedin' end], null)),
           'missing_count', x.n,
           'needs_country', x.no_country)
         || case when p_firm_id is null then '{}'::jsonb else jsonb_build_object('saved_people', coalesce((
              select jsonb_agg(jsonb_build_object('person_id', p.person_id, 'name', p.person_name,
                                                  'has_linkedin', nullif(btrim(p.linkedin_url), '') is not null)
                               order by p.person_id)
                from public.v2_people p
               where not p.archived
                 and p.person_id in (select r.person_id from public.v2_person_firm_roles r
                                      where r.firm_id = x.firm_id and not r.archived)), '[]'::jsonb)) end as info
    from (
      select y.*, (y.no_country::int + y.no_city::int + y.no_contact::int + y.no_social::int + y.no_linkedin::int) as n
        from (
          select f.firm_id,
                 nullif(btrim(f.hq_country), '') is null as no_country,
                 nullif(btrim(f.hq_city), '') is null as no_city,
                 c.firm_id is null as no_contact,
                 s.firm_id is null as no_social,
                 l.firm_id is null as no_linkedin
            from public.v2_firms f
            left join (select distinct firm_id from public.v2_firm_contacts
                        where not archived and (p_firm_id is null or firm_id = p_firm_id)) c on c.firm_id = f.firm_id
            left join (select distinct firm_id from public.v2_social_accounts
                        where not archived and (p_firm_id is null or firm_id = p_firm_id)) s on s.firm_id = f.firm_id
            left join (select distinct r.firm_id from public.v2_person_firm_roles r
                         join public.v2_people p on p.person_id = r.person_id and not p.archived
                                                and nullif(btrim(p.linkedin_url), '') is not null
                        where not r.archived and (p_firm_id is null or r.firm_id = p_firm_id)) l on l.firm_id = f.firm_id
           where not coalesce(f.archived, false) and f.merged_into_firm_id is null
             and (p_firm_id is null or f.firm_id = p_firm_id)
        ) y
    ) x
   where p_firm_id is not null or x.n > 0
$fn$
$ddl$;
  execute 'revoke all on function public.v2_job_firms_missing_details(bigint) from public, anon, authenticated';

  execute $ddl$
create or replace function public.v2_work_current_job()
 returns text
 language sql
 stable
 set search_path = public
 as $fn$
  select s.value from public.v2_work_setting s
   where s.name = 'current_job' and public.v2_work_job_fn(s.value) is not null
$fn$
$ddl$;
  execute 'revoke all on function public.v2_work_current_job() from public, anon, authenticated';

  insert into public.v2_work_setting (name, value) values ('current_job', 'missing_details')
    on conflict (name) do update set value = excluded.value, updated_at = now();

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
  v_job text := coalesce(public.v2_work_current_job(), p_job);
  fn text := public.v2_work_job_fn(v_job);
  c public.v2_work_claims;
  r record;
  held boolean := true;
  n_held int;
  v_held jsonb;
  v_info jsonb;
  frm public.v2_firms;
  v_extra jsonb := '{}'::jsonb;
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
  if p_job is not null and p_job <> v_job then
    v_extra := jsonb_build_object('asked_job', p_job);
  end if;

  -- One call per key at a time, so parallel helpers of one bot never go past 10.
  perform pg_advisory_xact_lock(hashtext('v2_work_keys:' || v_job), bk.bot_key_id::int);

  -- A bot may hold up to 10 live claims for this job. At 10 it gets its oldest one back.
  select count(*) into n_held from public.v2_work_claims w
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if n_held >= 10 then
    select * into c from public.v2_work_claims w
     where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now()
     order by w.claimed_at, w.firm_id limit 1;
  else
    held := false;
    for r in execute format(
      'select g.firm_id from public.%I(null) g
         join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
        where (public.v2_work_hq_na_europe(f.hq_country)
               or (nullif(btrim(f.hq_country), '''') is null and coalesce((g.info->>''needs_country'')::boolean, false)))
          and not exists (select 1 from public.v2_work_claims w
                           where w.job = $1 and w.firm_id = g.firm_id
                             and (w.done_at is not null or w.expires_at > now()))
        order by g.sort_key desc, g.firm_id
        limit 50', fn) using v_job
    loop
      -- Skip a firm another bot is claiming right now (no waiting).
      continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
      insert into public.v2_work_claims as w (job, firm_id, bot_key_id, claimed_at, expires_at, done_at)
      values (v_job, r.firm_id, bk.bot_key_id, now(), now() + interval '2 hours', null)
      on conflict (job, firm_id) do update
         set bot_key_id = excluded.bot_key_id, claimed_at = excluded.claimed_at, expires_at = excluded.expires_at
       where w.done_at is null and w.expires_at <= now()
      returning * into c;
      exit when found;
    end loop;

    -- deal_gaps only: reopen a done-but-still-gappy firm someone else finished.
    if c.firm_id is null and v_job = 'deal_gaps' then
      for r in execute format(
        'select g.firm_id from public.%I(null) g
           join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
           join public.v2_work_claims w on w.job = $1 and w.firm_id = g.firm_id
          where public.v2_work_hq_na_europe(f.hq_country)
            and w.done_at is not null
            and w.bot_key_id is distinct from $2
          order by (g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)) desc, g.firm_id
          limit 50', fn) using v_job, bk.bot_key_id
      loop
        continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
        update public.v2_work_claims as w
           set bot_key_id = bk.bot_key_id, claimed_at = now(), expires_at = now() + interval '2 hours', done_at = null
         where w.job = v_job and w.firm_id = r.firm_id
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
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if c.firm_id is null then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'firm', null,
      'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held)) || v_extra;
  end if;

  execute format('select info from public.%I($1)', fn) into v_info using c.firm_id;
  select * into frm from public.v2_firms where firm_id = c.firm_id;
  return jsonb_build_object(
    'ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'held', held,
    'claimed_at', c.claimed_at, 'expires_at', c.expires_at,
    'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held),
    'firm', jsonb_build_object('firm_id', frm.firm_id, 'name', frm.display_name, 'slug', frm.slug, 'website', frm.website_url)
            || coalesce(v_info, '{}'::jsonb)) || v_extra;
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

  if to_regprocedure('public.v2_renew_deal_gap_holds()') is not null then
    execute $ddl$
create or replace function public.v2_renew_deal_gap_holds()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.status = 'Accepted' and new.firm_id is not null and new.bot_key_id is not null then
    update public.v2_work_claims
       set expires_at = now() + interval '2 hours'
     where firm_id = new.firm_id
       and bot_key_id = new.bot_key_id
       and done_at is null;
  end if;
  return new;
end
$fn$
$ddl$;
    execute 'revoke all on function public.v2_renew_deal_gap_holds() from public, anon, authenticated';
  end if;

  -- create or replace keeps the grants; restated so a fresh database ends the same.
  execute 'revoke all on function public.v2_next_firm(uuid, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_firm_done(uuid, text, bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_next_firm(uuid, text) to service_role';
    execute 'grant execute on function public.v2_firm_done(uuid, text, bigint) to service_role';
  end if;
end
$mig$;
