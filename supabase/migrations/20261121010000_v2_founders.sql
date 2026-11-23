-- Founders collected by research bots, linked only to public.v2_startups.
-- Preview only. Apply on "make it live". No existing table, page or site output changes.
--
-- public.v2_founders: one row per person.
--   founder_id, name (as written in the source), name_norm (lowercase, Latin accents folded,
--   spaces collapsed; punctuation stays, so "Ada-Lovelace" and "Ada Lovelace" differ),
--   linkedin_url (optional, as written), linkedin_norm (linkedin.com/in/<slug>, unique when present),
--   added_by (bot id), created_at.
-- public.v2_founder_facts: one row per fact.
--   fact is one of role, current_city, current_country, previous_city, previous_country,
--   university, founded_before, past_job.
--   startup_id references public.v2_startups. It is required for role and optional otherwise.
--   This is the only foreign key. Deleting a startup that still has facts is refused.
--   source_url is required (http or https). company_website is only for past_job.
--   current_country and previous_country are 2-letter uppercase codes (US, GB).
--   past_job value is the company name (required). job_role is optional, only for past_job:
--   the role at that company, up to 300 characters. The door sends it as "role" on the fact.
--   founded_before value is yes or no, or yes: Earlier Company / no: Earlier Company
--   (the earlier company as written, after a colon and one space). No year column.
--   The same founder + fact + normalized value + startup is not stored twice.
-- A founder row cannot be committed without at least one role fact that has a startup_id
-- and a source_url (deferred constraint). A startup may have zero founders. One person may
-- have a role at more than one startup (one role row each).
-- Door: add_founder, and lookup with {"founder":{"name","linkedin_url"}}.
-- The hand-out list is a separate migration (20261121020000_founderlist).
-- Rollback: supabase/rollbacks/20261121010000_v2_founders.sql
--   (run the founderlist rollback first if that list is installed).
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_startups') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regprocedure('public.v2_work_bot(uuid)') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$
create or replace function public.v2_founder_fold(p text)
 returns text
 language sql
 immutable
 parallel safe
 set search_path = pg_catalog
 as $function$
  select btrim(regexp_replace(translate(
    replace(replace(replace(lower(coalesce(p, '')), 'æ', 'ae'), 'œ', 'oe'), 'ß', 'ss'),
    'àáâãäåāăąçćčĉċďđèéêëēĕėęěìíîïĩīĭįıłñńňòóôõöōŏőøùúûüũūŭůűýÿŷžźż',
    'aaaaaaaaacccccddeeeeeeeeeiiiiiiiiilnnnooooooooouuuuuuuuuyyyzzz'),
    '[[:space:]]+', ' ', 'g'))
$function$
$ddl$;

  -- Profile links only. "https://uk.linkedin.com/in/Ada/?trk=1" -> linkedin.com/in/ada
  execute $ddl$
create or replace function public.v2_founder_linkedin(p text)
 returns text
 language sql
 immutable
 parallel safe
 set search_path = pg_catalog
 as $function$
  select 'linkedin.com/in/' || slug
    from (
      select (regexp_match(
        regexp_replace(lower(btrim(coalesce(p, ''))), '[?#].*$', ''),
        '^(?:https?://)?(?:[a-z0-9-]+\.)*linkedin\.com/in/([^/]+)/?$'))[1] as slug
    ) s
   where slug ~ '^[a-z0-9_-]{2,100}$'
$function$
$ddl$;

  execute $ddl$
create or replace function public.v2_founder_set_norm()
 returns trigger
 language plpgsql
 set search_path = public, pg_catalog
 as $function$
begin
  if tg_table_name = 'v2_founders' then
    new.name_norm := public.v2_founder_fold(new.name);
    new.linkedin_norm := public.v2_founder_linkedin(new.linkedin_url);
  else
    new.value_norm := public.v2_founder_fold(coalesce(new.value, ''));
  end if;
  return new;
end
$function$
$ddl$;

  execute $ddl$
create table if not exists public.v2_founders (
  founder_id bigserial primary key,
  name text not null check (btrim(name) <> '' and length(name) <= 200),
  name_norm text not null default '' check (name_norm <> ''),
  linkedin_url text,
  linkedin_norm text,
  added_by text not null check (btrim(added_by) <> '' and length(added_by) <= 200),
  created_at timestamptz not null default now(),
  check (linkedin_url is null or (length(linkedin_url) <= 500 and linkedin_norm is not null)),
  check (linkedin_norm is null or linkedin_norm ~ '^linkedin\.com/in/[a-z0-9_-]{2,100}$')
)
$ddl$;
  execute 'create unique index if not exists v2_founders_linkedin_uq on public.v2_founders (linkedin_norm) where linkedin_norm is not null';
  execute 'create index if not exists v2_founders_name_norm_idx on public.v2_founders (name_norm)';
  execute 'comment on table public.v2_founders is ''One person. Research bots only. Not read by the site.''';
  execute 'comment on column public.v2_founders.name is ''As written in the source. name_norm is for matching.''';
  execute 'comment on column public.v2_founders.linkedin_norm is ''linkedin.com/in/<slug>. Unique when present.''';

  execute $ddl$
create table if not exists public.v2_founder_facts (
  fact_id bigserial primary key,
  founder_id bigint not null references public.v2_founders (founder_id) on delete cascade,
  startup_id bigint references public.v2_startups (startup_id) on delete restrict,
  fact text not null check (fact in (
    'role', 'current_city', 'current_country', 'previous_city', 'previous_country',
    'university', 'founded_before', 'past_job')),
  value text check (value is null or length(value) <= 300),
  value_norm text not null default '',
  company_website text,
  job_role text,
  source_url text not null check (source_url ~* '^https?://[^[:space:]]+$' and length(source_url) <= 2000),
  added_by text not null check (btrim(added_by) <> '' and length(added_by) <= 200),
  created_at timestamptz not null default now(),
  check (fact <> 'role' or startup_id is not null),
  check (fact = 'role' or (value is not null and btrim(value) <> '')),
  check (fact <> 'past_job' or btrim(value) <> ''),
  check (fact not in ('current_country', 'previous_country') or value ~ '^[A-Z]{2}$'),
  check (fact <> 'founded_before' or value ~ '^(yes|no)(: \S.*)?$'),
  check (company_website is null or (
    fact = 'past_job' and company_website ~* '^https?://[^[:space:]]+$' and length(company_website) <= 500)),
  check (job_role is null or (fact = 'past_job' and length(job_role) <= 300 and btrim(job_role) <> '')),
  constraint v2_founder_facts_no_copies unique nulls not distinct (founder_id, fact, value_norm, startup_id)
)
$ddl$;
  execute 'comment on column public.v2_founder_facts.value is ''As written, except countries are 2-letter uppercase codes and founded_before is yes, no, or yes: Earlier Company / no: Earlier Company. past_job value is the company name. No year.''';
  execute 'comment on column public.v2_founder_facts.job_role is ''Optional. Only for past_job: the role at that company, as written, up to 300 characters.''';
  execute 'create index if not exists v2_founder_facts_founder_idx on public.v2_founder_facts (founder_id, fact)';
  execute 'create index if not exists v2_founder_facts_role_startup_idx on public.v2_founder_facts (startup_id, created_at) where fact = ''role''';

  execute 'drop trigger if exists v2_founders_norm on public.v2_founders';
  execute 'create trigger v2_founders_norm before insert or update of name, linkedin_url on public.v2_founders for each row execute function public.v2_founder_set_norm()';
  execute 'drop trigger if exists v2_founder_facts_norm on public.v2_founder_facts';
  execute 'create trigger v2_founder_facts_norm before insert or update of value on public.v2_founder_facts for each row execute function public.v2_founder_set_norm()';

  -- A founder that still exists must have a role. Checked at commit so the person and the role
  -- can be inserted in one transaction. Deleting the person (facts cascade) is allowed.
  execute $ddl$
create or replace function public.v2_founder_require_role()
 returns trigger
 language plpgsql
 set search_path = public, pg_catalog
 as $function$
declare
  v_id bigint := coalesce(new.founder_id, old.founder_id);
begin
  if not exists (select 1 from public.v2_founders p where p.founder_id = v_id) then
    return null;
  end if;
  if not exists (
    select 1 from public.v2_founder_facts f
     where f.founder_id = v_id and f.fact = 'role'
       and f.startup_id is not null
       and f.source_url is not null and btrim(f.source_url) <> '') then
    raise exception 'a founder must have at least one role fact with a startup_id and a source_url'
      using errcode = '23514';
  end if;
  return null;
end
$function$
$ddl$;

  execute 'drop trigger if exists v2_founders_need_role on public.v2_founders';
  execute 'create constraint trigger v2_founders_need_role after insert on public.v2_founders deferrable initially deferred for each row execute function public.v2_founder_require_role()';
  execute 'drop trigger if exists v2_founder_facts_keep_role on public.v2_founder_facts';
  execute 'create constraint trigger v2_founder_facts_keep_role after insert or update or delete on public.v2_founder_facts deferrable initially deferred for each row execute function public.v2_founder_require_role()';

  execute 'alter table public.v2_founders enable row level security';
  execute 'alter table public.v2_founder_facts enable row level security';
  execute 'revoke all on table public.v2_founders, public.v2_founder_facts from public';
  execute 'revoke all on sequence public.v2_founders_founder_id_seq, public.v2_founder_facts_fact_id_seq from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on table public.v2_founders, public.v2_founder_facts from anon';
    execute 'revoke all on sequence public.v2_founders_founder_id_seq, public.v2_founder_facts_fact_id_seq from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on table public.v2_founders, public.v2_founder_facts from authenticated';
    execute 'revoke all on sequence public.v2_founders_founder_id_seq, public.v2_founder_facts_fact_id_seq from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on table public.v2_founders, public.v2_founder_facts from service_role';
    execute 'revoke all on sequence public.v2_founders_founder_id_seq, public.v2_founder_facts_fact_id_seq from service_role';
  end if;

  -- add_founder. One transaction: the person (new, or founder_id to reuse), the role at p_startup_id, then facts.
  -- p_founder {"name","linkedin_url","founder_id"}, p_role {"value","source_url"},
  -- p_facts [{fact,value,company_website,source_url,role}]  role is only for past_job and is stored in job_role
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
    if v_fact <> 'past_job' and v_item ? 'role' and nullif(btrim(coalesce(v_item->>'role', '')), '') is not null then
      return jsonb_build_object('ok', false, 'bot_id', v_bot.bot_name, 'error', 'role on a fact is only for past_job');
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
        'fact', v_fact, 'value', v_store, 'company_website', v_site, 'job_role', v_job, 'source_url', v_src));
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
        insert into public.v2_founder_facts (founder_id, fact, value, company_website, job_role, source_url, added_by)
        values (v_id, v_fact, v_store, nullif(v_item->>'company_website', ''), nullif(v_item->>'job_role', ''), v_item->>'source_url', v_bot.bot_name)
        returning fact_id into v_fid;
        v_saved := v_saved || jsonb_build_array(jsonb_build_object('fact_id', v_fid, 'fact', v_fact, 'value', v_store));
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

  -- Read-only same-person check. Up to 5. LinkedIn match first, then the same normalized name.
  -- Each match includes startups (from role rows) and past jobs (company name plus job_role).
  execute $ddl$
create or replace function public.v2_founder_lookup(p_key uuid, p_name text, p_linkedin text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path = public, bots, pg_catalog
 as $function$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_raw text := btrim(coalesce(p_linkedin, ''));
  v_norm text;
  v_li text;
  v_total integer;
  v_rows jsonb;
begin
  if not exists (select 1 from bots.ingest_keys k where k.id = p_key and k.active) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if length(v_name) > 200 or length(v_raw) > 500 then
    return jsonb_build_object('ok', false, 'error', 'name is up to 200 characters and linkedin_url up to 500');
  end if;
  if v_raw <> '' then
    v_li := public.v2_founder_linkedin(v_raw);
    if v_li is null then
      return jsonb_build_object('ok', false, 'error', 'linkedin_url must be a LinkedIn profile link like https://www.linkedin.com/in/name');
    end if;
  end if;
  v_norm := public.v2_founder_fold(v_name);
  if v_norm = '' and v_li is null then
    return jsonb_build_object('ok', false, 'error', 'send a name or a LinkedIn link');
  end if;

  with hit as (
    select f.founder_id, f.name, f.linkedin_url,
           case when v_li is not null and f.linkedin_norm = v_li then 1 else 2 end as rank,
           case when v_li is not null and f.linkedin_norm = v_li then 'linkedin' else 'name' end as reason
      from public.v2_founders f
     where (v_li is not null and f.linkedin_norm = v_li)
        or (v_norm <> '' and f.name_norm = v_norm)
  )
  select (select count(*)::int from hit),
         coalesce((
           select jsonb_agg(jsonb_build_object(
                    'founder_id', t.founder_id,
                    'name', t.name,
                    'linkedin_url', t.linkedin_url,
                    'match_reason', t.reason,
                    'startups', coalesce((
                      select jsonb_agg(jsonb_build_object('id', x.startup_id, 'name', x.startup_name) order by x.startup_id)
                        from (
                          select distinct f.startup_id, s.startup_name::text as startup_name
                            from public.v2_founder_facts f
                            left join public.v2_startups s on s.startup_id = f.startup_id
                           where f.founder_id = t.founder_id and f.fact = 'role' and f.startup_id is not null
                        ) x
                    ), '[]'::jsonb),
                    'past_jobs', coalesce((
                      select jsonb_agg(jsonb_build_object('company', p.value, 'job_role', p.job_role) order by p.value, p.job_role)
                        from (
                          select distinct f.value, f.job_role
                            from public.v2_founder_facts f
                           where f.founder_id = t.founder_id and f.fact = 'past_job' and f.value is not null
                        ) p
                    ), '[]'::jsonb))
                    order by t.rank, t.founder_id)
             from (select * from hit order by rank, founder_id limit 5) t
         ), '[]'::jsonb)
    into v_total, v_rows;

  return jsonb_build_object(
    'ok', true, 'kind', 'founder',
    'searched', jsonb_build_object('name_key', nullif(v_norm, ''), 'linkedin', v_li),
    'found', v_total > 0, 'total', v_total, 'matches', v_rows);
end
$function$
$ddl$;

  execute 'revoke all on function public.v2_founder_fold(text) from public';
  execute 'revoke all on function public.v2_founder_linkedin(text) from public';
  execute 'revoke all on function public.v2_founder_set_norm() from public';
  execute 'revoke all on function public.v2_founder_require_role() from public';
  execute 'revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from public';
  execute 'revoke all on function public.v2_founder_lookup(uuid, text, text) from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from anon';
    execute 'revoke all on function public.v2_founder_lookup(uuid, text, text) from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) from authenticated';
    execute 'revoke all on function public.v2_founder_lookup(uuid, text, text) from authenticated';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb) to service_role';
    execute 'grant execute on function public.v2_founder_lookup(uuid, text, text) to service_role';
  end if;
end
$mig$;
