-- A section claim can hold up to 10 unfinished unexpired firms per key per section.
-- Each claim hands out a new firm (most deals first, then lower firm_id). At 10, the
-- bot must finish or mark one done first. done is unchanged. Existing keys keep working.
-- Existing v2_bot_keys rows are read, not rewritten. No new key and no new scope.
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.
-- Not applied to production by this change.
-- Undo: supabase/rollbacks/20261117230000_v2_section_claim_multi.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.firm_summary') is null
     or to_regclass('public.v2_legal_items') is null
     or to_regclass('public.v2_reviews') is null
     or to_regclass('public.v2_interviews') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null
     or to_regclass('public.v2_section_holds') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $fn$
create or replace function public.v2_section_claim(p_key_id uuid, p_section text)
returns jsonb
language plpgsql
security definer
set search_path to public, bots
set statement_timeout to '30s'
set lock_timeout to '5s'
as $body$
declare
  v_ik bots.ingest_keys;
  v_bk public.v2_bot_keys;
  v_bot text;
  v_section text;
  v_fid bigint;
  v_got bigint;
  v_frm public.v2_firms;
  v_skip bigint[] := '{}';
  v_try int;
  v_hold_limit int := 10;
  v_held_ids bigint[] := '{}';
begin
  v_section := lower(btrim(coalesce(p_section, '')));
  if v_section not in ('legal', 'reviews', 'youtube') then
    return jsonb_build_object('ok', false, 'error', 'section must be legal, reviews, or youtube');
  end if;

  select * into v_ik from bots.ingest_keys where id = p_key_id and active;
  if not found or v_ik.bot_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  v_bot := v_ik.bot_id;
  -- Read the existing v2_bot_keys row. Do not rewrite it. Insert only when this bot has none yet.
  select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  if not found then
    insert into public.v2_bot_keys (bot_name, key_hash)
    values (v_bot, v_ik.key_hash)
    on conflict (bot_name) do nothing;
    select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  end if;
  if v_bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', format('Key frozen: %s, %s', coalesce(v_bk.freeze_reason, 'no reason'), to_char(v_bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;

  -- Lock this key's open holds in this section so two claims cannot pass the limit together.
  -- FOR UPDATE cannot be combined with array_agg, so the lock is a separate statement.
  perform 1
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours'
   for update of h;
  select coalesce(array_agg(h.firm_id order by h.claimed_at, h.firm_id), '{}'::bigint[])
    into v_held_ids
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours';
  if cardinality(v_held_ids) >= v_hold_limit then
    return jsonb_build_object(
      'ok', false,
      'bot_id', v_bot,
      'section', v_section,
      'error', format(
        'hold_limit: finish or mark done one of your %s firms first; held_firm_ids: %s',
        v_hold_limit,
        array_to_string(v_held_ids, ', ')),
      'held_firm_ids', to_jsonb(v_held_ids));
  end if;

  for v_try in 1..32 loop
    v_fid := null;
    select f.firm_id into v_fid
      from public.firm_summary s
      join public.v2_firms f on f.firm_id = s.firm_id
     where s.listed
       and s.firm_status = 'Active'
       and not coalesce(f.archived, false)
       and not (f.firm_id = any (v_skip))
       and case v_section
             when 'legal' then not exists (
               select 1 from public.v2_legal_items li
                where li.firm_id = f.firm_id and li.is_current and not li.archived)
             when 'reviews' then not exists (
               select 1 from public.v2_reviews r
                where r.firm_id = f.firm_id and r.is_current and not r.archived)
             else not exists (
               select 1 from public.v2_interviews iv
                where iv.firm_id = f.firm_id and iv.is_current and not iv.archived)
           end
       and not exists (
             select 1 from public.v2_section_holds h
              where h.firm_id = f.firm_id
                and h.section = v_section
                and (h.checked_at is not null or h.claimed_at > now() - interval '6 hours'))
     order by s.deals desc, s.firm_id
     limit 1
     for update of f skip locked;
    if v_fid is null then
      return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
    end if;

    v_got := null;
    insert into public.v2_section_holds (firm_id, section, bot_key_id, claimed_at)
    values (v_fid, v_section, v_bk.bot_key_id, now())
    on conflict (firm_id, section) do update
      set bot_key_id = excluded.bot_key_id,
          claimed_at = excluded.claimed_at
      where v2_section_holds.checked_at is null
        and v2_section_holds.claimed_at <= now() - interval '6 hours'
    returning firm_id into v_got;
    if found then
      exit;
    end if;
    v_skip := v_skip || v_fid;
  end loop;

  if v_got is null then
    return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
  end if;
  select * into v_frm from public.v2_firms where firm_id = v_got;
  return jsonb_build_object(
    'ok', true, 'bot_id', v_bot, 'section', v_section,
    'firm_id', v_frm.firm_id, 'slug', v_frm.slug, 'name', v_frm.display_name, 'website', v_frm.website_url);
end
$body$
$fn$;

  execute 'revoke all on function public.v2_section_claim(uuid, text) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_section_claim(uuid, text) to service_role';
  end if;
end
$mig$;
