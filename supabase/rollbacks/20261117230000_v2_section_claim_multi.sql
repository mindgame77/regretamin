-- Undo 20261117230000_v2_section_claim_multi.
-- Puts back the previous v2_section_claim: a key gets back its own unfinished unexpired
-- hold for that section, so it can hold only one firm at a time. Holds and firm rows stay.
-- done is not changed.
CREATE OR REPLACE FUNCTION public.v2_section_claim(p_key_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
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

  select h.firm_id into v_fid
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours'
   order by h.claimed_at, h.firm_id
   limit 1
   for update of h;
  if v_fid is not null then
    select * into v_frm from public.v2_firms where firm_id = v_fid;
    return jsonb_build_object(
      'ok', true, 'bot_id', v_bot, 'section', v_section,
      'firm_id', v_frm.firm_id, 'slug', v_frm.slug, 'name', v_frm.display_name, 'website', v_frm.website_url);
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
$function$

revoke all on function public.v2_section_claim(uuid, text) from public, anon, authenticated;
do $g$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_section_claim(uuid, text) to service_role';
  end if;
end
$g$;
