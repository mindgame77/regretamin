-- Read-only public API. New schema and functions only.
-- Does not change v2 tables, firm_summary, existing functions, RLS, or bots.bot_key_pickup.
-- The API switch starts off. Rollback: supabase/rollbacks/20261117190000_public_read_api.sql
--
-- Activity labels use the Investors list rule: firm_directory_page_v2's year window
-- (current_date, previous UTC year included through May) and RegretActivity in launch/js/dates.js.
-- Undated deals are not in firm_summary.deals or dated_dates, so they do not affect the label.

create schema if not exists api;

create table api.settings (
  id smallint primary key check (id = 1),
  api_enabled boolean not null default false
);

create table api.keys (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_note text,
  key_hash text not null unique,
  active boolean not null default true,
  daily_limit integer not null default 1000,
  created_at timestamptz not null default now(),
  constraint api_keys_hash check (key_hash ~ '^[0-9a-f]{64}$'),
  constraint api_keys_name check (char_length(name) between 1 and 80),
  constraint api_keys_note check (owner_note is null or char_length(owner_note) <= 500),
  constraint api_keys_limit check (daily_limit between 1 and 100000)
);

create table api.key_usage (
  key_id uuid not null references api.keys (id) on delete cascade,
  day date not null,
  calls integer not null,
  primary key (key_id, day),
  constraint api_key_usage_calls check (calls >= 0)
);

create table api.call_log (
  id bigint generated always as identity primary key,
  key_id uuid not null references api.keys (id) on delete cascade,
  endpoint text not null,
  status integer not null,
  duration_ms integer not null,
  created_at timestamptz not null default now(),
  constraint api_call_log_endpoint check (endpoint in ('firms', 'firm', 'deals', 'updated')),
  constraint api_call_log_status check (status between 100 and 599),
  constraint api_call_log_ms check (duration_ms between 0 and 600000)
);

create index api_call_log_key_created_idx on api.call_log (key_id, created_at desc);
create index api_call_log_created_idx on api.call_log (created_at desc);

-- One sealed copy of a new key until the holder takes it. Same shape as bots.bot_key_pickup.
-- Do not select pickup_key. The apply function returns it once, then clears it.
create table api.key_pickup (
  key_id uuid primary key references api.keys (id) on delete cascade,
  pickup_key text,
  proof_hash text,
  status text,
  applied_at timestamptz,
  constraint api_key_pickup_status check (status is null or status in ('pending', 'approved', 'delivered')),
  constraint api_key_pickup_wiped check (status is distinct from 'delivered' or pickup_key is null),
  constraint api_key_pickup_proof check (proof_hash is null or proof_hash ~ '^[0-9a-f]{64}$'),
  constraint api_key_pickup_key check (pickup_key is null or (char_length(pickup_key) between 20 and 200 and pickup_key ~ '^[A-Za-z0-9_-]+$'))
);

comment on table api.settings is 'Single row. api_enabled starts false. The public API reads firms only while it is true.';
comment on table api.keys is 'Public API keys. key_hash is SHA-256 hex. The raw key is never stored here.';
comment on column api.key_pickup.pickup_key is 'Raw key until the one-time pickup. Do not select this column.';
comment on table api.call_log is 'One small row per accepted API call. No key, no query string, no response body.';

insert into api.settings (id, api_enabled) values (1, false);

alter table api.settings enable row level security;
alter table api.keys enable row level security;
alter table api.key_usage enable row level security;
alter table api.call_log enable row level security;
alter table api.key_pickup enable row level security;

revoke all on schema api from PUBLIC, anon, authenticated, service_role;
revoke all on all tables in schema api from PUBLIC, anon, authenticated, service_role;

-- Investors list year window (firm_directory_page_v2) plus RegretActivity.label.
-- current_date is the database clock, the same clock the Investors list count uses.
create or replace function public.api_activity_label(p_deals integer, p_dates date[])
returns text
language sql
stable
set search_path to 'pg_temp'
as $$
  with bounds as (
    select extract(year from current_date)::integer as y1,
           extract(year from current_date)::integer
             - case when extract(month from current_date) < 6 then 1 else 0 end as y0
  ),
  counted as (
    select count(*)::integer as year_n
      from unnest(coalesce(p_dates, '{}'::date[])) as d(day)
      cross join bounds b
     where d.day is not null
       and extract(year from d.day) between b.y0 and b.y1
  )
  select case
    when year_n >= 3 then 'Active'
    when year_n >= 1 then 'Low activity'
    when coalesce(p_deals, 0) > 0 then 'Not active'
    else 'Not checked yet'
  end
  from counted;
$$;

create or replace function public.api_is_enabled()
returns boolean
language sql
stable
security definer
set search_path to 'api', 'pg_temp'
as $$
  select coalesce((select s.api_enabled from api.settings s where s.id = 1), false);
$$;

create or replace function public.api_set_enabled(p_on boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
begin
  if p_on is null then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  insert into api.settings (id, api_enabled) values (1, p_on)
  on conflict (id) do update set api_enabled = excluded.api_enabled;
  return jsonb_build_object('ok', true, 'api_enabled', p_on);
end
$$;

create or replace function public.api_set_key_active(p_key_id uuid, p_active boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
declare n integer;
begin
  if p_key_id is null or p_active is null then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  update api.keys set active = p_active where id = p_key_id;
  get diagnostics n = row_count;
  if n <> 1 then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  return jsonb_build_object('ok', true, 'key_id', p_key_id, 'active', p_active);
end
$$;

-- Owner runs this in the SQL editor. The result has the key id only, never the raw key.
-- The raw key is sealed for one pickup and is not written to the result or a notice.
create or replace function public.create_api_key(p_name text, p_owner_note text, p_daily_limit integer default 1000)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_limit integer := coalesce(p_daily_limit, 1000);
  v_raw text;
  v_hash text;
  v_id uuid;
begin
  if v_name !~ '^[A-Za-z0-9][A-Za-z0-9 ._()''-]{0,79}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  if p_owner_note is not null and char_length(p_owner_note) > 500 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  if v_limit < 1 or v_limit > 100000 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  v_raw := 'rg_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_hash := encode(extensions.digest(v_raw, 'sha256'), 'hex');
  insert into api.keys (name, owner_note, key_hash, daily_limit)
  values (v_name, nullif(btrim(coalesce(p_owner_note, '')), ''), v_hash, v_limit)
  returning id into v_id;
  insert into api.key_pickup (key_id, pickup_key) values (v_id, v_raw);
  return jsonb_build_object('ok', true, 'key_id', v_id, 'name', v_name, 'daily_limit', v_limit, 'status', 'sealed');
exception when others then
  return jsonb_build_object('ok', false, 'error', 'refused');
end
$$;

create or replace function public.api_key_apply(p_key_id uuid, p_proof_hash text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
declare k api.keys; p api.key_pickup; v_key text;
begin
  if p_key_id is null or p_proof_hash is null or p_proof_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('api_key_pickup:' || p_key_id::text));
  select * into k from api.keys where id = p_key_id and active for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into p from api.key_pickup where key_id = k.id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  if p.pickup_key is null or length(p.pickup_key) = 0 then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p.status is null then
    update api.key_pickup
       set proof_hash = p_proof_hash, status = 'pending', applied_at = now()
     where key_id = k.id;
    return jsonb_build_object('ok', true, 'status', 'pending', 'proof_prefix', left(p_proof_hash, 8));
  end if;
  if p.status = 'pending' then
    if p.proof_hash is distinct from p_proof_hash then
      return jsonb_build_object('ok', false, 'error', 'pending_locked');
    end if;
    return jsonb_build_object('ok', true, 'status', 'pending', 'proof_prefix', left(p_proof_hash, 8));
  end if;
  if p.status = 'approved' then
    if p.proof_hash is distinct from p_proof_hash then
      return jsonb_build_object('ok', false, 'error', 'unauthorized');
    end if;
    v_key := p.pickup_key;
    update api.key_pickup
       set pickup_key = null, proof_hash = null, status = 'delivered'
     where key_id = k.id and status = 'approved';
    if not found then
      return jsonb_build_object('ok', false, 'error', 'unauthorized');
    end if;
    return jsonb_build_object('ok', true, 'status', 'delivered', 'key', v_key);
  end if;
  return jsonb_build_object('ok', false, 'error', 'unauthorized');
end
$$;

create or replace function public.approve_api_key_pickup(p_key_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
declare k api.keys; p api.key_pickup;
begin
  if p_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('api_key_pickup:' || p_key_id::text));
  select * into k from api.keys where id = p_key_id and active for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into p from api.key_pickup where key_id = k.id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  if p.status = 'approved' and p.pickup_key is not null and p.proof_hash is not null then
    return jsonb_build_object('ok', true, 'key_id', p_key_id, 'status', 'approved');
  end if;
  if p.status is distinct from 'pending' or p.pickup_key is null or p.proof_hash is null then
    return jsonb_build_object('ok', false, 'error', 'not_pending');
  end if;
  update api.key_pickup set status = 'approved' where key_id = k.id and status = 'pending';
  return jsonb_build_object('ok', true, 'key_id', p_key_id, 'status', 'approved');
end
$$;

create or replace function public.clear_api_key_pickup(p_key_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
as $$
declare k api.keys; p api.key_pickup;
begin
  if p_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  perform pg_advisory_xact_lock(hashtext('api_key_pickup:' || p_key_id::text));
  select * into k from api.keys where id = p_key_id and active for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into p from api.key_pickup where key_id = k.id for update;
  if not found or p.pickup_key is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p.status = 'delivered' then
    return jsonb_build_object('ok', false, 'error', 'already_delivered');
  end if;
  update api.key_pickup
     set proof_hash = null, status = null, applied_at = null
   where key_id = k.id and status is distinct from 'delivered';
  return jsonb_build_object('ok', true, 'key_id', p_key_id, 'status', 'cleared');
end
$$;

create or replace function public.pending_api_key_pickups()
returns table (key_id uuid, name text, status text, applied_at timestamptz, proof_prefix text)
language sql
stable
security definer
set search_path to 'api', 'pg_temp'
as $$
  select k.id, k.name, p.status, p.applied_at, left(p.proof_hash, 8)
    from api.key_pickup p
    join api.keys k on k.id = p.key_id
   where k.active
     and p.status in ('pending', 'approved')
   order by p.applied_at nulls last, k.name;
$$;

create or replace function public.api_authorize(p_key_hash text)
returns jsonb
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
set statement_timeout to '2s'
as $$
declare
  k api.keys;
  v_day date;
  v_reset timestamptz;
  v_calls integer;
  v_reset_text text;
begin
  -- Off switch first. Do not read keys, usage, or firm tables.
  if not public.api_is_enabled() then
    return jsonb_build_object('ok', false, 'error', 'off');
  end if;
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  select * into k from api.keys where key_hash = p_key_hash for update;
  if not found or not k.active then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  v_day := (now() at time zone 'utc')::date;
  v_reset := ((v_day + 1)::timestamp) at time zone 'utc';
  v_reset_text := to_char(v_reset at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  insert into api.key_usage as u (key_id, day, calls)
  values (k.id, v_day, 1)
  on conflict (key_id, day) do update
    set calls = u.calls + 1
    where u.calls < k.daily_limit
  returning u.calls into v_calls;
  if not found then
    return jsonb_build_object(
      'ok', false, 'error', 'rate_limited', 'key_id', k.id,
      'limit', k.daily_limit, 'remaining', 0, 'reset_at', v_reset_text);
  end if;
  return jsonb_build_object(
    'ok', true, 'key_id', k.id, 'limit', k.daily_limit,
    'remaining', k.daily_limit - v_calls, 'reset_at', v_reset_text);
end
$$;

create or replace function public.api_log(p_key_id uuid, p_endpoint text, p_status integer, p_ms integer)
returns void
language plpgsql
volatile
security definer
set search_path to 'api', 'pg_temp'
set statement_timeout to '1s'
as $$
begin
  if not public.api_is_enabled() then
    return;
  end if;
  if p_key_id is null or p_endpoint is null or p_status is null or p_ms is null then
    return;
  end if;
  if p_endpoint not in ('firms', 'firm', 'deals', 'updated') then
    return;
  end if;
  if p_status < 100 or p_status > 599 or p_ms < 0 then
    return;
  end if;
  insert into api.call_log (key_id, endpoint, status, duration_ms)
  values (p_key_id, p_endpoint, p_status, least(p_ms, 600000));
end
$$;

create or replace function public.api_cursor_pack(p_kind text, p_a text, p_b text)
returns text
language sql
immutable
set search_path to 'pg_temp'
as $$
  select p_kind || '.' || rtrim(translate(encode(convert_to(json_build_array(coalesce(p_a, ''), coalesce(p_b, ''))::text, 'utf8'), 'base64'), '+/', '-_'), '=');
$$;

create or replace function public.api_cursor_unpack(p_kind text, p_cursor text)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_temp'
as $$
declare
  raw text;
  pad integer;
  js jsonb;
begin
  if p_cursor is null or btrim(p_cursor) = '' then
    return null;
  end if;
  if p_kind is null or length(p_cursor) > 2000 or p_cursor not like p_kind || '.%' then
    return '"bad"'::jsonb;
  end if;
  raw := translate(substr(p_cursor, length(p_kind) + 2), '-_', '+/');
  if raw = '' or raw ~ '[^A-Za-z0-9+/]' then
    return '"bad"'::jsonb;
  end if;
  pad := (4 - length(raw) % 4) % 4;
  begin
    js := convert_from(decode(raw || repeat('=', pad), 'base64'), 'utf8')::jsonb;
  exception when others then
    return '"bad"'::jsonb;
  end;
  if jsonb_typeof(js) is distinct from 'array' or jsonb_array_length(js) is distinct from 2 then
    return '"bad"'::jsonb;
  end if;
  if coalesce(js->>1, '') !~ '^[0-9]+$' then
    return '"bad"'::jsonb;
  end if;
  return js;
end
$$;

-- Listed, live, not archived, not merged, not demand_hidden.
-- p_firm_id null reads the directory. A firm id reads that one row.
create or replace function public.api_visible_firms(p_firm_id bigint default null)
returns table (
  firm_id bigint,
  slug text,
  name text,
  short_name text,
  website text,
  country text,
  activity text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
begin
  if not public.api_is_enabled() then
    return;
  end if;
  if to_regclass('public.firm_summary') is null
     or to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_firm_live') is null then
    return;
  end if;
  return query
  select f.firm_id,
         l.slug::text,
         coalesce(f.display_name, '')::text,
         f.short_name::text,
         f.website_url,
         case when s.hq_country ~ '^[A-Z]{2}$' then s.hq_country end,
         public.api_activity_label(s.deals, s.dated_dates),
         coalesce(s.added, l.live_since)
    from public.firm_summary s
    join public.v2_firms f on f.firm_id = s.firm_id
    join public.v2_firm_live l on l.firm_id = s.firm_id
   where (p_firm_id is null or f.firm_id = p_firm_id)
     and s.listed
     and not coalesce(f.archived, false)
     and f.merged_into_firm_id is null
     and not coalesce(f.demand_hidden, false);
end
$$;

create or replace function public.api_activity_text(p_raw text)
returns text
language sql
immutable
set search_path to 'pg_temp'
as $$
  select case lower(btrim(coalesce(p_raw, '')))
    when '' then null
    when 'active' then 'Active'
    when 'low' then 'Low activity'
    when 'low activity' then 'Low activity'
    when 'not_active' then 'Not active'
    when 'not active' then 'Not active'
    when 'inactive' then 'Not active'
    when 'not_checked' then 'Not checked yet'
    when 'not checked yet' then 'Not checked yet'
    when 'unchecked' then 'Not checked yet'
    else 'bad'
  end;
$$;

create or replace function public.api_firms(
  p_q text,
  p_country text,
  p_activity text,
  p_cursor text,
  p_limit integer
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
declare
  v_lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_q text := lower(btrim(coalesce(p_q, '')));
  v_country text := upper(btrim(coalesce(p_country, '')));
  v_act text := public.api_activity_text(p_activity);
  v_cur jsonb;
  v_name text;
  v_id bigint;
  v_rows jsonb;
  v_extra boolean;
  v_last_name text;
  v_last_id bigint;
begin
  if not public.api_is_enabled() then
    return jsonb_build_object('ok', false, 'error', 'off');
  end if;
  if to_regclass('public.firm_summary') is null then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;
  if length(v_q) > 80 or (v_country <> '' and v_country !~ '^[A-Z]{2}$') or v_act = 'bad' then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  v_cur := public.api_cursor_unpack('n', p_cursor);
  if v_cur = '"bad"'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'bad_cursor');
  end if;
  if v_cur is not null then
    v_name := coalesce(v_cur->>0, '');
    v_id := (v_cur->>1)::bigint;
  end if;
  with page as (
    select v.firm_id, v.slug, v.name, v.website, v.country, v.activity
      from public.api_visible_firms(null) v
     where (v_q = '' or strpos(lower(v.name), v_q) > 0
            or strpos(lower(coalesce(v.short_name, '')), v_q) > 0
            or strpos(lower(coalesce(v.website, '')), v_q) > 0
            or strpos(lower(v.slug), v_q) > 0)
       and (v_country = '' or v.country = v_country)
       and (v_act is null or v.activity = v_act)
       and (v_cur is null or (v.name, v.firm_id) > (v_name, v_id))
     order by v.name, v.firm_id
     limit v_lim + 1
  ),
  numbered as (
    select row_number() over (order by name, firm_id) as rn, page.* from page
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', firm_id, 'slug', slug, 'name', name, 'website', website,
           'country', country, 'activity', activity
         ) order by rn) filter (where rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(rn = v_lim + 1), false),
         (array_agg(name order by rn) filter (where rn = v_lim))[1],
         (array_agg(firm_id order by rn) filter (where rn = v_lim))[1]
    into v_rows, v_extra, v_last_name, v_last_id
    from numbered;
  return jsonb_build_object(
    'ok', true,
    'firms', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', case when v_extra then public.api_cursor_pack('n', v_last_name, v_last_id::text) end);
end
$$;

create or replace function public.api_firms_updated(p_cursor text, p_limit integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
declare
  v_lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_cur jsonb;
  v_ts timestamptz;
  v_id bigint;
  v_rows jsonb;
  v_extra boolean;
  v_last_ts timestamptz;
  v_last_id bigint;
begin
  if not public.api_is_enabled() then
    return jsonb_build_object('ok', false, 'error', 'off');
  end if;
  if to_regclass('public.firm_summary') is null then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;
  v_cur := public.api_cursor_unpack('u', p_cursor);
  if v_cur = '"bad"'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'bad_cursor');
  end if;
  if v_cur is not null then
    begin
      v_ts := (v_cur->>0)::timestamptz;
    exception when others then
      return jsonb_build_object('ok', false, 'error', 'bad_cursor');
    end;
    if v_ts is null then
      return jsonb_build_object('ok', false, 'error', 'bad_cursor');
    end if;
    v_id := (v_cur->>1)::bigint;
  end if;
  with page as (
    select v.firm_id, v.slug, v.name, v.website, v.country, v.activity, v.updated_at
      from public.api_visible_firms(null) v
     where v_cur is null or (v.updated_at, v.firm_id) < (v_ts, v_id)
     order by v.updated_at desc, v.firm_id desc
     limit v_lim + 1
  ),
  numbered as (
    select row_number() over (order by updated_at desc, firm_id desc) as rn, page.* from page
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', firm_id, 'slug', slug, 'name', name, 'website', website,
           'country', country, 'activity', activity,
           'updated_at', to_char(updated_at at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
         ) order by rn) filter (where rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(rn = v_lim + 1), false),
         (array_agg(updated_at order by rn) filter (where rn = v_lim))[1],
         (array_agg(firm_id order by rn) filter (where rn = v_lim))[1]
    into v_rows, v_extra, v_last_ts, v_last_id
    from numbered;
  return jsonb_build_object(
    'ok', true,
    'firms', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', case when v_extra then public.api_cursor_pack(
      'u', to_char(v_last_ts at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), v_last_id::text) end);
end
$$;

-- Resolve a public slug. Follows the live merge rule when _v2_live_id exists, then
-- keeps the firm only if it is still listed and not hidden.
create or replace function public.api_open_firm(p_slug text)
returns table (
  firm_id bigint,
  slug text,
  name text,
  short_name text,
  website text,
  country text,
  activity text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
declare
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  fid bigint;
begin
  if not public.api_is_enabled() then
    return;
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(v_slug) > 80 then
    return;
  end if;
  if to_regclass('public.firm_summary') is null then
    return;
  end if;
  if to_regprocedure('public._v2_live_id(text)') is not null then
    fid := public._v2_live_id(v_slug);
  else
    select v.firm_id into fid from public.api_visible_firms(null) v where v.slug = v_slug;
  end if;
  if fid is null then
    return;
  end if;
  return query select * from public.api_visible_firms(fid);
end
$$;

create or replace function public.api_firm(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
declare
  f record;
  v_firm bigint;
  v_name text;
  v_team jsonb := '[]'::jsonb;
  v_legal jsonb := '[]'::jsonb;
begin
  if not public.api_is_enabled() then
    return jsonb_build_object('ok', false, 'error', 'off');
  end if;
  if to_regclass('public.firm_summary') is null then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;
  select * into f from public.api_open_firm(p_slug);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  v_firm := f.firm_id;
  v_name := f.name;
  if to_regclass('public.v2_person_firm_roles') is not null
     and to_regclass('public.v2_people') is not null
     and to_regprocedure('public.v2_is_leader_title(text)') is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', q.person_name, 'title', q.title, 'founder', q.is_founder
           ) order by q.ord), '[]'::jsonb)
      into v_team
      from (
        select r.row_id as ord, pe.person_name::text as person_name, r.title::text as title, r.is_founder
          from (
            select distinct on (person_id) row_id, person_id, title, is_founder
              from public.v2_person_firm_roles
             where firm_id = v_firm
               and is_current and not archived and not nothing_found
               and (is_founder or public.v2_is_leader_title(title))
             order by person_id, is_founder desc, row_id
          ) r
          join public.v2_people pe on pe.person_id = r.person_id
         where pe.is_current and not pe.archived and not pe.nothing_found
         limit 200
      ) q;
  end if;
  if to_regclass('public.v2_legal_items') is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'title', q.title, 'status', q.status, 'case_type', q.case_type,
             'filed_year', q.filed_year, 'court', q.court, 'summary', q.summary,
             'source_url', q.source_url
           ) order by q.filed_year desc nulls last, q.legal_item_id desc), '[]'::jsonb)
      into v_legal
      from (
        select l.legal_item_id,
               trim(both from concat_ws(' ',
                 coalesce(nullif(btrim(l.other_party), ''), nullif(btrim(l.regulator_name), ''), 'Record'),
                 'v.', v_name)) as title,
               l.status, l.case_type, l.filed_year, l.court::text as court,
               l.case_summary::text as summary, nullif(btrim(l.source_url), '') as source_url
          from public.v2_legal_items l
         where l.firm_id = v_firm
           and l.is_current and not l.archived and not l.nothing_found
           and not coalesce(l.lead_only, false)
         order by l.filed_year desc nulls last, l.legal_item_id desc
         limit 200
      ) q;
  end if;
  return jsonb_build_object(
    'ok', true,
    'firm', jsonb_build_object(
      'id', f.firm_id, 'slug', f.slug, 'name', f.name, 'website', f.website,
      'country', f.country, 'activity', f.activity,
      'team', coalesce(v_team, '[]'::jsonb),
      'legal', coalesce(v_legal, '[]'::jsonb)));
end
$$;

create or replace function public.api_firm_deals(p_slug text, p_cursor text, p_limit integer)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $$
declare
  f record;
  v_firm bigint;
  v_lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_cur jsonb;
  v_date date;
  v_id bigint;
  v_undated boolean := false;
  v_rows jsonb;
  v_extra boolean;
  v_last_date date;
  v_last_id bigint;
begin
  if not public.api_is_enabled() then
    return jsonb_build_object('ok', false, 'error', 'off');
  end if;
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_startups') is null then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;
  select * into f from public.api_open_firm(p_slug);
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  v_firm := f.firm_id;
  v_cur := public.api_cursor_unpack('d', p_cursor);
  if v_cur = '"bad"'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'bad_cursor');
  end if;
  if v_cur is not null then
    v_undated := coalesce(v_cur->>0, '') = '';
    if not v_undated then
      begin
        v_date := (v_cur->>0)::date;
      exception when others then
        return jsonb_build_object('ok', false, 'error', 'bad_cursor');
      end;
      if v_date is null then
        return jsonb_build_object('ok', false, 'error', 'bad_cursor');
      end if;
    end if;
    v_id := (v_cur->>1)::bigint;
  end if;
  -- firm_id uses v2_deals_firm_id_idx. Same published-deal filter as _v2_deals.
  -- A null deal_date stays in the list and is not an activity date.
  with page as (
    select d.deal_id, s.startup_name::text as startup, d.round, d.deal_date, nullif(btrim(d.source_url), '') as source_url
      from public.v2_deals d
      join public.v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
     where d.firm_id = v_firm
       and d.is_current and not d.archived
       and coalesce(d.shown, true) and not d.nothing_found
       and (
         v_cur is null
         or (v_date is not null and (
              d.deal_date < v_date
              or (d.deal_date = v_date and d.deal_id < v_id)
              or d.deal_date is null))
         or (v_undated and d.deal_date is null and d.deal_id < v_id)
       )
     order by d.deal_date desc nulls last, d.deal_id desc
     limit v_lim + 1
  ),
  numbered as (
    select row_number() over (order by deal_date desc nulls last, deal_id desc) as rn, page.* from page
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'startup', startup, 'round', round,
           'date', deal_date, 'source_url', source_url
         ) order by rn) filter (where rn <= v_lim), '[]'::jsonb),
         coalesce(bool_or(rn = v_lim + 1), false),
         (array_agg(deal_date order by rn) filter (where rn = v_lim))[1],
         (array_agg(deal_id order by rn) filter (where rn = v_lim))[1]
    into v_rows, v_extra, v_last_date, v_last_id
    from numbered;
  return jsonb_build_object(
    'ok', true,
    'deals', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', case when v_extra then public.api_cursor_pack(
      'd', coalesce(v_last_date::text, ''), v_last_id::text) end);
end
$$;

revoke all on function public.api_activity_label(integer, date[]) from PUBLIC, anon, authenticated;
revoke all on function public.api_is_enabled() from PUBLIC, anon, authenticated;
revoke all on function public.api_set_enabled(boolean) from PUBLIC, anon, authenticated;
revoke all on function public.api_set_key_active(uuid, boolean) from PUBLIC, anon, authenticated;
revoke all on function public.create_api_key(text, text, integer) from PUBLIC, anon, authenticated;
revoke all on function public.api_key_apply(uuid, text) from PUBLIC, anon, authenticated;
revoke all on function public.approve_api_key_pickup(uuid) from PUBLIC, anon, authenticated;
revoke all on function public.clear_api_key_pickup(uuid) from PUBLIC, anon, authenticated;
revoke all on function public.pending_api_key_pickups() from PUBLIC, anon, authenticated;
revoke all on function public.api_authorize(text) from PUBLIC, anon, authenticated;
revoke all on function public.api_log(uuid, text, integer, integer) from PUBLIC, anon, authenticated;
revoke all on function public.api_cursor_pack(text, text, text) from PUBLIC, anon, authenticated;
revoke all on function public.api_cursor_unpack(text, text) from PUBLIC, anon, authenticated;
revoke all on function public.api_visible_firms(bigint) from PUBLIC, anon, authenticated;
revoke all on function public.api_activity_text(text) from PUBLIC, anon, authenticated;
revoke all on function public.api_firms(text, text, text, text, integer) from PUBLIC, anon, authenticated;
revoke all on function public.api_firms_updated(text, integer) from PUBLIC, anon, authenticated;
revoke all on function public.api_open_firm(text) from PUBLIC, anon, authenticated;
revoke all on function public.api_firm(text) from PUBLIC, anon, authenticated;
revoke all on function public.api_firm_deals(text, text, integer) from PUBLIC, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'bot_writer') then
    revoke all on schema api from bot_writer;
    revoke all on all tables in schema api from bot_writer;
    revoke all on function public.api_activity_label(integer, date[]) from bot_writer;
    revoke all on function public.api_is_enabled() from bot_writer;
    revoke all on function public.api_set_enabled(boolean) from bot_writer;
    revoke all on function public.api_set_key_active(uuid, boolean) from bot_writer;
    revoke all on function public.create_api_key(text, text, integer) from bot_writer;
    revoke all on function public.api_key_apply(uuid, text) from bot_writer;
    revoke all on function public.approve_api_key_pickup(uuid) from bot_writer;
    revoke all on function public.clear_api_key_pickup(uuid) from bot_writer;
    revoke all on function public.pending_api_key_pickups() from bot_writer;
    revoke all on function public.api_authorize(text) from bot_writer;
    revoke all on function public.api_log(uuid, text, integer, integer) from bot_writer;
    revoke all on function public.api_cursor_pack(text, text, text) from bot_writer;
    revoke all on function public.api_cursor_unpack(text, text) from bot_writer;
    revoke all on function public.api_visible_firms(bigint) from bot_writer;
    revoke all on function public.api_activity_text(text) from bot_writer;
    revoke all on function public.api_firms(text, text, text, text, integer) from bot_writer;
    revoke all on function public.api_firms_updated(text, integer) from bot_writer;
    revoke all on function public.api_open_firm(text) from bot_writer;
    revoke all on function public.api_firm(text) from bot_writer;
    revoke all on function public.api_firm_deals(text, text, integer) from bot_writer;
  end if;
end $$;

grant execute on function public.api_activity_label(integer, date[]) to service_role;
grant execute on function public.api_is_enabled() to service_role;
grant execute on function public.api_set_enabled(boolean) to service_role;
grant execute on function public.api_set_key_active(uuid, boolean) to service_role;
grant execute on function public.create_api_key(text, text, integer) to service_role;
grant execute on function public.api_key_apply(uuid, text) to service_role;
grant execute on function public.approve_api_key_pickup(uuid) to service_role;
grant execute on function public.clear_api_key_pickup(uuid) to service_role;
grant execute on function public.pending_api_key_pickups() to service_role;
grant execute on function public.api_authorize(text) to service_role;
grant execute on function public.api_log(uuid, text, integer, integer) to service_role;
grant execute on function public.api_cursor_pack(text, text, text) to service_role;
grant execute on function public.api_cursor_unpack(text, text) to service_role;
grant execute on function public.api_visible_firms(bigint) to service_role;
grant execute on function public.api_activity_text(text) to service_role;
grant execute on function public.api_firms(text, text, text, text, integer) to service_role;
grant execute on function public.api_firms_updated(text, integer) to service_role;
grant execute on function public.api_open_firm(text) to service_role;
grant execute on function public.api_firm(text) to service_role;
grant execute on function public.api_firm_deals(text, text, integer) to service_role;
