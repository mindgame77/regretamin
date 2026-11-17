-- Section holds for enrichment bots. One row per firm and section (legal, reviews, youtube).
-- claim with a block asks v2_section_claim. done with a block asks v2_section_done.
-- Plain v2_research_claim, v2_research_done, and v2_research_assignments are not replaced.
-- Order is the stored firm_summary.deals count (dated shown deals), most first, then firm_id.
-- Existing v2_bot_keys rows are read, not rewritten. No new key and no new scope.
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.
-- Not applied to production by this change.
-- Undo: supabase/rollbacks/20261117210000_v2_section_claim.sql
do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
  v_next text;
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.firm_summary') is null
     or to_regclass('public.v2_legal_items') is null
     or to_regclass('public.v2_reviews') is null
     or to_regclass('public.v2_interviews') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null
     or to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'firm_summary' and column_name = 'deals'
  ) then
    raise exception 'firm_summary.deals is missing';
  end if;

  execute $ddl$
create table if not exists public.v2_section_holds (
  firm_id bigint not null references public.v2_firms(firm_id) on delete cascade,
  section text not null check (section in ('legal', 'reviews', 'youtube')),
  bot_key_id bigint not null references public.v2_bot_keys(bot_key_id) on delete cascade,
  claimed_at timestamptz not null default now(),
  checked_at timestamptz,
  primary key (firm_id, section)
)
$ddl$;

  execute $cmt$
comment on table public.v2_section_holds is
  'One hold per firm and section for enrichment bots. Checked rows are never claimed again. An unchecked hold older than 6 hours can be taken by another bot.'
$cmt$;
  execute $cmt$
comment on column public.v2_section_holds.bot_key_id is
  'Existing v2_bot_keys.bot_key_id of the holding bot. The same row plain claim already uses.'
$cmt$;
  execute $cmt$
comment on column public.v2_section_holds.checked_at is
  'Set by v2_section_done. A checked firm is not handed out again for this section.'
$cmt$;

  execute 'alter table public.v2_section_holds enable row level security';
  execute 'revoke all on table public.v2_section_holds from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant select, insert, update, delete on table public.v2_section_holds to service_role';
  end if;

  -- Stored deal count, most deals first, then firm_id. Claim walks this instead of counting v2_deals.
  execute $idx$
create index if not exists firm_summary_listed_deals_idx
  on public.firm_summary (deals desc, firm_id)
  where listed and firm_status = 'Active'
$idx$;
  execute $idx$
create index if not exists v2_section_holds_bot_open_idx
  on public.v2_section_holds (bot_key_id, section)
  where checked_at is null
$idx$;
  execute $idx$
create index if not exists v2_legal_items_firm_current_idx
  on public.v2_legal_items (firm_id)
  where is_current and not archived
$idx$;
  execute $idx$
create index if not exists v2_reviews_firm_current_idx
  on public.v2_reviews (firm_id)
  where is_current and not archived
$idx$;
  execute $idx$
create index if not exists v2_interviews_firm_current_idx
  on public.v2_interviews (firm_id)
  where is_current and not archived
$idx$;

  -- Nothing-found rows may omit the content columns. A normal row still needs them.
  execute 'alter table public.v2_reviews alter column quote drop not null';
  execute 'alter table public.v2_reviews alter column review_source_name drop not null';
  execute 'alter table public.v2_reviews drop constraint if exists v2_reviews_found_content_ck';
  execute $ck$
alter table public.v2_reviews add constraint v2_reviews_found_content_ck
  check (nothing_found or (quote is not null and review_source_name is not null))
$ck$;
  execute 'alter table public.v2_interviews alter column interview_url drop not null';
  execute 'alter table public.v2_interviews drop constraint if exists v2_interviews_found_content_ck';
  execute $ck$
alter table public.v2_interviews add constraint v2_interviews_found_content_ck
  check (nothing_found or interview_url is not null)
$ck$;
  execute 'alter table public.v2_legal_items alter column item_group drop not null';
  execute 'alter table public.v2_legal_items drop constraint if exists v2_legal_items_found_content_ck';
  execute $ck$
alter table public.v2_legal_items add constraint v2_legal_items_found_content_ck
  check (nothing_found or item_group is not null)
$ck$;

  select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into v_def;
  if position('nothing_found needs the searches in note' in v_def) > 0 then
    raise notice 'v2_research_submit nothing_found already patched';
  else
    v_old := $old$    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;$old$;
    v_new := $new$    -- Nothing-found for legal, reviews, and interviews. Content fields are not required.
    -- The checks above still require an opened source_url, a source_level, a source_date, and a source_type.
    -- Legal nothing-found uses source_level 1, the only level that table allows.
    IF reason IS NULL
       AND tbl IN ('v2_legal_items', 'v2_reviews', 'v2_interviews')
       AND (
         fact->'nothing_found' = 'true'::jsonb
         OR lower(btrim(coalesce(fact->>'nothing_found', ''))) IN ('true', 't', '1')
       ) THEN
      IF coalesce(it->>'note', fact->>'note', '') !~* 'search' THEN
        reason := 'nothing_found needs the searches in note';
      ELSIF tbl = 'v2_legal_items' AND fact->>'source_level' IS DISTINCT FROM '1' THEN
        reason := 'legal nothing_found needs source_level 1';
      ELSE
        fact := (fact - 'nothing_found' - 'note') || jsonb_build_object('nothing_found', true);
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;$new$;
    if position(v_old in v_def) = 0
       or (length(v_def) - length(replace(v_def, v_old, ''))) <> length(v_old) then
      raise exception 'v2_research_submit: nothing_found anchor missing or not unique';
    end if;
    v_next := replace(v_def, v_old, v_new);
    if v_next = v_def or position('nothing_found needs the searches in note' in v_next) = 0 then
      raise exception 'v2_research_submit: nothing_found patch did not apply';
    end if;
    execute v_next;
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
$body$
$fn$;

  execute $fn$
create or replace function public.v2_section_done(p_key_id uuid, p_section text, p_firm_id bigint)
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
  v_holder bigint;
  v_checked timestamptz;
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

  if p_firm_id is null then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', 'firm_id is required');
  end if;

  select h.bot_key_id, h.checked_at into v_holder, v_checked
    from public.v2_section_holds h
   where h.firm_id = p_firm_id and h.section = v_section
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', 'firm is not held for this section');
  end if;
  if v_holder is distinct from v_bk.bot_key_id then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', 'this firm is not assigned to this bot');
  end if;
  if v_checked is null then
    update public.v2_section_holds
       set checked_at = now()
     where firm_id = p_firm_id and section = v_section;
  end if;
  return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'firm_id', p_firm_id, 'done', true);
end
$body$
$fn$;

  execute 'revoke all on function public.v2_section_claim(uuid, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_section_done(uuid, text, bigint) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_section_claim(uuid, text) to service_role';
    execute 'grant execute on function public.v2_section_done(uuid, text, bigint) to service_role';
  end if;
end
$mig$;
