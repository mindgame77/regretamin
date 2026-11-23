-- Puts back the add_founder function from
-- supabase/migrations/20261121040000_v2_founder_founded_before_exit.sql.
-- A matching founded_before row is skipped again, and an exit in that call is ignored.
-- Does not drop columns, does not change lookup, and does not change
-- v2_founder_require_role. Founder rows stay. An exit already written stays.
-- Run this before rolling back 20261121040000. The door does not need a redeploy:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261121050000_v2_founder_founded_before_exit_fill.sql

do $undo$
begin
  if to_regclass('public.v2_founder_facts') is null
     or to_regprocedure('public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb)') is null
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_founder_facts' and column_name = 'exit_outcome') then
    raise notice 'v2 founder exit columns missing, skipped';
    return;
  end if;

  execute $ddl$
create or replace function public.v2_founder_add(p_key_id uuid, p_startup_id bigint, p_founder jsonb, p_role jsonb, p_facts jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public, bots, pg_catalog
 set statement_timeout = '30s'
 set lock_timeout = '5s'
 as $function$
declare
  v_bot public.v2_bot_keys;
  v_name text;
  v_li_raw text;
  v_li text;
  v_reuse bigint;
  v_role_value text;
  v_role_src text;
  v_role_id bigint;
  v_role_skipped boolean := false;
  v_facts jsonb := coalesce(p_facts, '[]'::jsonb);
  v_item jsonb;
  v_i integer;
  v_fact text;
  v_value text;
  v_store text;
  v_yn text;
  v_body text;
  v_site text;
  v_job text;
  v_exit text;
  v_buyer text;
  v_exit_src text;
  v_src text;
  v_clean jsonb := '[]'::jsonb;
  v_seen text[] := '{}';
  v_key text;
  v_saved jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
  v_fid bigint;
  v_id bigint;
  v_created boolean := false;
  v_person public.v2_founders;
  v_other_id bigint;
  v_other_name text;
  v_allowed constant text := 'current_city, current_country, previous_city, previous_country, university, founded_before, past_job';
begin
  v_bot := public.v2_work_bot(p_key_id);
  if v_bot.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bot.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(v_bot.freeze_reason, 'no reason'), to_char(v_bot.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if p_startup_id is null or p_startup_id <= 0 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'startup_id is required');
  end if;
  if not exists (select 1 from public.v2_startups s where s.startup_id = p_startup_id) then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('startup_id %s not found', p_startup_id));
  end if;
  if p_founder is null or jsonb_typeof(p_founder) <> 'object' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founder must be an object with name, and linkedin_url or founder_id when reusing a person');
  end if;
  if p_role is null or jsonb_typeof(p_role) <> 'object' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role must be an object with source_url');
  end if;
  if p_founder ? 'founder_id' and nullif(btrim(coalesce(p_founder->>'founder_id', '')), '') is not null then
    if (p_founder->>'founder_id') !~ '^[1-9][0-9]*$' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founder_id must be a positive integer');
    end if;
    v_reuse := (p_founder->>'founder_id')::bigint;
  end if;
  if p_founder ? 'name' and p_founder->>'name' is not null and jsonb_typeof(p_founder->'name') <> 'string' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'name must be text up to 200 characters');
  end if;
  v_name := nullif(btrim(coalesce(p_founder->>'name', '')), '');
  if v_name is not null and length(v_name) > 200 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'name must be text up to 200 characters');
  end if;
  if v_reuse is null and (v_name is null or public.v2_founder_fold(v_name) = '') then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founder name is required (up to 200 characters)');
  end if;
  if p_founder ? 'linkedin_url' and p_founder->>'linkedin_url' is not null and jsonb_typeof(p_founder->'linkedin_url') <> 'string' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'linkedin_url must be a LinkedIn profile link like https://www.linkedin.com/in/name, or leave it out');
  end if;
  v_li_raw := nullif(btrim(coalesce(p_founder->>'linkedin_url', '')), '');
  if v_li_raw is not null then
    if length(v_li_raw) > 500 then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'linkedin_url must be a LinkedIn profile link like https://www.linkedin.com/in/name, or leave it out');
    end if;
    v_li := public.v2_founder_linkedin(v_li_raw);
    if v_li is null then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'linkedin_url must be a LinkedIn profile link like https://www.linkedin.com/in/name, or leave it out');
    end if;
  end if;
  v_role_src := nullif(btrim(coalesce(p_role->>'source_url', '')), '');
  if v_role_src is null or v_role_src !~* '^https?://[^[:space:]]+$' or length(v_role_src) > 2000 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role source_url is required (an http(s) link)');
  end if;
  if p_role ? 'value' and p_role->'value' is not null and jsonb_typeof(p_role->'value') <> 'null' and jsonb_typeof(p_role->'value') <> 'string' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role value must be text up to 300 characters');
  end if;
  v_role_value := nullif(btrim(coalesce(p_role->>'value', '')), '');
  if v_role_value is not null and length(v_role_value) > 300 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role value must be text up to 300 characters');
  end if;
  if jsonb_typeof(v_facts) <> 'array' then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'facts must be a list');
  end if;
  if jsonb_array_length(v_facts) > 30 then
    return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'facts can list at most 30');
  end if;

  for v_i in 0 .. jsonb_array_length(v_facts) - 1 loop
    v_item := v_facts -> v_i;
    if v_item is null or jsonb_typeof(v_item) <> 'object' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('facts[%s] must be an object with fact, value and source_url', v_i + 1));
    end if;
    if v_item ? 'fact' and v_item->'fact' is not null and jsonb_typeof(v_item->'fact') <> 'string' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('unknown fact type ''''; allowed: %s', v_allowed));
    end if;
    v_fact := lower(btrim(coalesce(v_item->>'fact', '')));
    if v_fact = 'role' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'send the startup role in role, not in facts');
    end if;
    if v_fact not in ('current_city', 'current_country', 'previous_city', 'previous_country', 'university', 'founded_before', 'past_job') then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('unknown fact type ''%s''; allowed: %s', left(coalesce(v_item->>'fact', ''), 40), v_allowed));
    end if;
    v_src := nullif(btrim(coalesce(v_item->>'source_url', '')), '');
    if v_src is null or v_src !~* '^https?://[^[:space:]]+$' or length(v_src) > 2000 then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('facts[%s] needs a source_url (an http(s) link)', v_i + 1));
    end if;
    if v_item ? 'value' and v_item->'value' is not null and jsonb_typeof(v_item->'value') <> 'null' and jsonb_typeof(v_item->'value') <> 'string' then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('%s needs a value', v_fact));
    end if;
    v_value := btrim(coalesce(v_item->>'value', ''));
    v_site := null;
    v_job := null;
    v_exit := null;
    v_buyer := null;
    v_exit_src := null;
    if v_fact <> 'past_job' and v_item ? 'role' and nullif(btrim(coalesce(v_item->>'role', '')), '') is not null then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role on a fact is only for past_job');
    end if;
    if v_fact <> 'founded_before' then
      if nullif(btrim(coalesce(v_item->>'exit_outcome', '')), '') is not null then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_outcome is only for founded_before');
      end if;
      if nullif(btrim(coalesce(v_item->>'exit_acquirer', '')), '') is not null then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_acquirer is only for founded_before');
      end if;
      if nullif(btrim(coalesce(v_item->>'exit_source_url', '')), '') is not null then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_source_url is only for founded_before');
      end if;
    end if;
    if v_fact = 'past_job' then
      if v_value = '' or length(v_value) > 300 then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'past_job needs a company name in value');
      end if;
      v_store := v_value;
      if v_item ? 'role' and v_item->'role' is not null and jsonb_typeof(v_item->'role') <> 'null' then
        if jsonb_typeof(v_item->'role') <> 'string' then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'past_job role must be text up to 300 characters, or leave it out');
        end if;
        v_job := nullif(btrim(v_item->>'role'), '');
        if v_job is not null and length(v_job) > 300 then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'past_job role must be text up to 300 characters, or leave it out');
        end if;
      end if;
      if v_item ? 'company_website' and nullif(btrim(coalesce(v_item->>'company_website', '')), '') is not null then
        if jsonb_typeof(v_item->'company_website') <> 'string' then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'past_job company_website must be an http(s) link, or leave it out');
        end if;
        v_site := btrim(v_item->>'company_website');
        if v_site !~* '^https?://[^[:space:]]+$' or length(v_site) > 500 then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'past_job company_website must be an http(s) link, or leave it out');
        end if;
      end if;
    elsif v_item ? 'company_website' and nullif(btrim(coalesce(v_item->>'company_website', '')), '') is not null then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'company_website is only for past_job');
    elsif v_fact in ('current_country', 'previous_country') then
      v_store := upper(v_value);
      if v_store !~ '^[A-Z]{2}$' then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('%s must be a 2-letter country code (for example US)', v_fact));
      end if;
    elsif v_fact = 'founded_before' then
      if v_value = '' or lower(v_value) !~ '^(yes|no)(:.*)?$' then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founded_before value must be yes or no, optionally followed by the earlier company (yes: Earlier Company)');
      end if;
      v_yn := substring(lower(v_value) from '^(yes|no)');
      v_body := btrim(substr(v_value, char_length(v_yn) + 1));
      if v_body = '' then
        v_store := v_yn;
      elsif left(v_body, 1) = ':' then
        v_body := btrim(substr(v_body, 2));
        if v_body = '' or length(v_yn) + 2 + length(v_body) > 300 then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founded_before value must be yes or no, optionally followed by the earlier company (yes: Earlier Company)');
        end if;
        v_store := v_yn || ': ' || v_body;
      else
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'founded_before value must be yes or no, optionally followed by the earlier company (yes: Earlier Company)');
      end if;
      if v_item ? 'exit_outcome' and v_item->'exit_outcome' is not null and jsonb_typeof(v_item->'exit_outcome') <> 'null' then
        if jsonb_typeof(v_item->'exit_outcome') <> 'string' then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_outcome must be acquired, ipo or shut_down, or leave it out');
        end if;
        v_exit := lower(nullif(btrim(v_item->>'exit_outcome'), ''));
        if v_exit is not null and v_exit not in ('acquired', 'ipo', 'shut_down') then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_outcome must be acquired, ipo or shut_down, or leave it out');
        end if;
      end if;
      if v_item ? 'exit_acquirer' and v_item->'exit_acquirer' is not null and jsonb_typeof(v_item->'exit_acquirer') <> 'null' then
        if jsonb_typeof(v_item->'exit_acquirer') <> 'string' then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_acquirer must be text up to 300 characters, or leave it out');
        end if;
        v_buyer := nullif(btrim(v_item->>'exit_acquirer'), '');
        if v_buyer is not null and length(v_buyer) > 300 then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_acquirer must be text up to 300 characters, or leave it out');
        end if;
      end if;
      if v_buyer is not null and v_exit is distinct from 'acquired' then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_acquirer is only allowed when exit_outcome is acquired');
      end if;
      if v_item ? 'exit_source_url' and v_item->'exit_source_url' is not null and jsonb_typeof(v_item->'exit_source_url') <> 'null' then
        if jsonb_typeof(v_item->'exit_source_url') <> 'string' then
          if v_exit is null then
            return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_source_url is only allowed when exit_outcome is set');
          end if;
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_source_url is required when exit_outcome is set (an http(s) link)');
        end if;
        v_exit_src := nullif(btrim(v_item->>'exit_source_url'), '');
      end if;
      if v_exit is null and v_exit_src is not null then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_source_url is only allowed when exit_outcome is set');
      end if;
      if v_exit is not null and (v_exit_src is null or v_exit_src !~* '^https?://[^[:space:]]+$' or length(v_exit_src) > 2000) then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'exit_source_url is required when exit_outcome is set (an http(s) link)');
      end if;
    else
      if v_value = '' or length(v_value) > 300 then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('%s needs a value', v_fact));
      end if;
      v_store := v_value;
    end if;
    v_key := v_fact || chr(1) || public.v2_founder_fold(coalesce(v_store, ''));
    if v_key = any (v_seen) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('fact', v_fact, 'value', v_store, 'reason', 'already stored'));
    else
      v_seen := v_seen || v_key;
      v_clean := v_clean || jsonb_build_array(jsonb_build_object(
        'fact', v_fact, 'value', v_store, 'company_website', v_site, 'job_role', v_job,
        'exit_outcome', v_exit, 'exit_acquirer', v_buyer, 'exit_source_url', v_exit_src, 'source_url', v_src));
    end if;
  end loop;

  if v_reuse is not null then
    select * into v_person from public.v2_founders where founder_id = v_reuse for update;
    if not found then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', format('founder_id %s not found', v_reuse));
    end if;
    if v_li is not null and v_person.linkedin_norm is not null and v_person.linkedin_norm is distinct from v_li then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'founder_id', v_person.founder_id,
        'error', format('this founder already has a different LinkedIn (%s); not changed', v_person.linkedin_url));
    end if;
    if v_li is not null and v_person.linkedin_norm is null then
      select f.founder_id, f.name into v_other_id, v_other_name
        from public.v2_founders f where f.linkedin_norm = v_li and f.founder_id <> v_person.founder_id;
      if found then
        return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'duplicate', true, 'founder_id', v_other_id,
          'error', format('a founder with this LinkedIn already exists (founder_id %s: %s); send founder_id %s to reuse that person',
                          v_other_id, v_other_name, v_other_id));
      end if;
    end if;
  elsif v_li is not null then
    select f.founder_id, f.name into v_other_id, v_other_name from public.v2_founders f where f.linkedin_norm = v_li;
    if found then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'duplicate', true, 'founder_id', v_other_id,
        'error', format('a founder with this LinkedIn already exists (founder_id %s: %s); send founder_id %s to reuse that person',
                        v_other_id, v_other_name, v_other_id));
    end if;
  end if;

  begin
    if v_reuse is not null then
      v_id := v_person.founder_id;
      if v_li is not null and v_person.linkedin_norm is null then
        update public.v2_founders set linkedin_url = v_li_raw where founder_id = v_id and linkedin_norm is null;
      end if;
    else
      insert into public.v2_founders (name, linkedin_url, added_by)
      values (v_name, v_li_raw, v_bot.bot_name)
      returning founder_id into v_id;
      v_created := true;
    end if;

    select f.fact_id into v_role_id
      from public.v2_founder_facts f
     where f.founder_id = v_id and f.fact = 'role' and f.startup_id = p_startup_id
       and f.value_norm = public.v2_founder_fold(coalesce(v_role_value, ''));
    if found then
      v_role_skipped := true;
    else
      insert into public.v2_founder_facts (founder_id, startup_id, fact, value, source_url, added_by)
      values (v_id, p_startup_id, 'role', v_role_value, v_role_src, v_bot.bot_name)
      returning fact_id into v_role_id;
    end if;

    for v_i in 0 .. jsonb_array_length(v_clean) - 1 loop
      v_item := v_clean -> v_i;
      v_fact := v_item->>'fact';
      v_store := v_item->>'value';
      select f.fact_id into v_fid
        from public.v2_founder_facts f
       where f.founder_id = v_id and f.fact = v_fact and f.startup_id is null
         and f.value_norm = public.v2_founder_fold(coalesce(v_store, ''));
      if found then
        v_skipped := v_skipped || jsonb_build_array(jsonb_build_object('fact', v_fact, 'value', v_store, 'reason', 'already stored'));
      else
        insert into public.v2_founder_facts (founder_id, fact, value, company_website, job_role, exit_outcome, exit_acquirer, exit_source_url, source_url, added_by)
        values (v_id, v_fact, v_store, nullif(v_item->>'company_website', ''), nullif(v_item->>'job_role', ''),
          nullif(v_item->>'exit_outcome', ''), nullif(v_item->>'exit_acquirer', ''), nullif(v_item->>'exit_source_url', ''),
          v_item->>'source_url', v_bot.bot_name)
        returning fact_id into v_fid;
        if v_fact = 'founded_before' then
          v_saved := v_saved || jsonb_build_array(jsonb_build_object(
            'fact_id', v_fid, 'fact', v_fact, 'value', v_store,
            'exit_outcome', nullif(v_item->>'exit_outcome', ''),
            'exit_acquirer', nullif(v_item->>'exit_acquirer', ''),
            'exit_source_url', nullif(v_item->>'exit_source_url', '')));
        else
          v_saved := v_saved || jsonb_build_array(jsonb_build_object('fact_id', v_fid, 'fact', v_fact, 'value', v_store));
        end if;
      end if;
    end loop;

    select * into v_person from public.v2_founders where founder_id = v_id;
    return jsonb_build_object(
      'ok', true, 'bot_id', v_bot.bot_name, 'founder_id', v_id, 'created', v_created,
      'founder', jsonb_build_object('founder_id', v_person.founder_id, 'name', v_person.name, 'linkedin_url', v_person.linkedin_url),
      'role', jsonb_build_object('fact_id', v_role_id, 'startup_id', p_startup_id, 'value', v_role_value, 'source_url', v_role_src, 'skipped', v_role_skipped),
      'facts', v_saved, 'skipped', v_skipped);
  exception
    when unique_violation then
      if v_li is not null then
        select f.founder_id, f.name into v_other_id, v_other_name from public.v2_founders f where f.linkedin_norm = v_li;
        if found then
          return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'duplicate', true, 'founder_id', v_other_id,
            'error', format('a founder with this LinkedIn already exists (founder_id %s: %s); send founder_id %s to reuse that person',
                            v_other_id, v_other_name, v_other_id));
        end if;
      end if;
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'this founder fact is already stored; send it again to refresh nothing');
  end;
end
$function$
$ddl$;

  revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from public;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) to service_role';
  end if;
end
$undo$;
