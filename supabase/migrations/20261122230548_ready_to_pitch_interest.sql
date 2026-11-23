-- ready_to_pitch_interest (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: ready_to_pitch_interest skipped';
    return;
  end if;
  execute $designmig$
-- "Am I ready for this firm?" is not built yet. The button opens a "coming soon, leave your email" box; this stores those emails.
-- Adds one table and one function. Changes nothing that exists.
create table if not exists public.v2_ready_interest (
  id bigint generated always as identity primary key,
  email text not null,
  firm_slug text,
  created_at timestamptz not null default now(),
  unique (email, firm_slug)
);
alter table public.v2_ready_interest enable row level security;
revoke all on public.v2_ready_interest from anon, authenticated;

create or replace function public.v2_ready_interest_add(p_email text, p_slug text default null)
returns json language plpgsql security definer
set search_path to 'public', 'pg_temp' set statement_timeout to '3s'
as $fn$
declare v_email text := lower(left(btrim(coalesce(p_email, '')), 200));
        v_slug text := nullif(left(btrim(coalesce(p_slug, '')), 120), '');
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return json_build_object('status', 'bad_email'); end if;
  -- A simple brake: no more than 300 new addresses an hour in total.
  if (select count(*) from v2_ready_interest where created_at > now() - interval '1 hour') >= 300 then
    return json_build_object('status', 'rate_limited');
  end if;
  if v_slug is not null and not exists (select 1 from firm_summary s where s.listed and s.slug = v_slug) then v_slug := null; end if;
  insert into v2_ready_interest (email, firm_slug) values (v_email, v_slug) on conflict do nothing;
  return json_build_object('status', 'ok');
end $fn$;
revoke all on function public.v2_ready_interest_add(text, text) from public;
grant execute on function public.v2_ready_interest_add(text, text) to anon, authenticated;
$designmig$;
end
$wrapci$;
