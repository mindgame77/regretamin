-- Admin analytics (28 Nov 2026, claude/plans/admin-analytics.md): Alex's own numbers, readable by his accounts only.
--   * admins: who may read them (the same four accounts as OWNER_IDS in supabase/functions/create-checkout). No client access.
--   * track_events: one row per page open, 15-second beat, map view change or Top 100 chart pick. No client access; rows older than 90 days
--     are deleted every night.
--   * track_visit(anon, events): the only door for visitors. Capped: 10 events per call, 40 events a minute per visitor, 20000 an hour
--     in all, short text, whitelisted kinds. Admins' own visits are dropped.
--   * analytics_is_admin(): true for an admin, false for everyone else. Changes nothing.
--   * admin_report(days): every number of the page in one answer (1, 7 or 30 days). Checks the caller first; anyone else gets null.
-- Additive only. Skips itself on a database without the tables it reads.
do $wrapaa$
begin
  if to_regclass('public.check_balances') is null or to_regclass('public.ready_reports') is null
     or to_regclass('public.payments') is null or to_regclass('public.check_events') is null
     or to_regclass('public.firm_requests') is null or to_regclass('public.firm_request_emails') is null or to_regclass('public.firms') is null then
    raise notice 'tables not present, skipping';
    return;
  end if;

  execute 'create table if not exists public.admins (user_id uuid primary key)';
  execute 'alter table public.admins enable row level security';
  execute 'revoke all on table public.admins from public, anon, authenticated';
  execute $s$insert into public.admins (user_id) values
    ('71b72d7b-5899-45e2-a5cb-81b39a02a418'), ('808da6a4-2ba5-40ae-861d-e01ef0724275'),
    ('6040d146-11ce-44aa-a7ac-d2b9bbc8df49'), ('cd85552c-2b85-4ef7-b3a1-ef1442af4304') on conflict do nothing$s$;

  execute $t$
create table if not exists public.track_events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  anon_id uuid not null,
  kind text not null check (kind in ('view', 'beat', 'map', 'chart')),
  path text,
  view text,
  src text,
  code text,
  device text,
  secs integer
)$t$;
  execute 'create index if not exists track_events_at on public.track_events(at)';
  execute 'create index if not exists track_events_anon on public.track_events(anon_id, at)';
  execute 'alter table public.track_events enable row level security';
  execute 'revoke all on table public.track_events from public, anon, authenticated';

  execute $f$
create or replace function public.analytics_is_admin() returns boolean
language sql stable security definer set search_path = public as
$b$ select exists (select 1 from public.admins where user_id = auth.uid()) $b$$f$;
  execute 'revoke all on function public.analytics_is_admin() from public';
  execute 'grant execute on function public.analytics_is_admin() to anon, authenticated';

  execute $f$
create or replace function public.track_visit(p_anon uuid, p_events jsonb) returns void
language plpgsql security definer set search_path = public as
$b$
begin
  if p_anon is null or p_events is null or jsonb_typeof(p_events) <> 'array' then return; end if;
  if public.analytics_is_admin() then return; end if;
  if (select count(*) from public.track_events where anon_id = p_anon and at > now() - interval '1 minute') >= 40 then return; end if;
  if (select count(*) from public.track_events where at > now() - interval '1 hour') >= 20000 then return; end if;
  insert into public.track_events (anon_id, kind, path, view, src, code, device, secs)
  select p_anon, e->>'k', left(e->>'p', 120), left(e->>'v', 40), left(e->>'s', 80), left(e->>'c', 40),
         case when e->>'d' in ('phone', 'computer') then e->>'d' end,
         case when (e->>'t') ~ '^[0-9]{1,2}$' then least((e->>'t')::int, 60) end
  from (select value as e from jsonb_array_elements(p_events) with ordinality as x(value, n) order by n limit 10) q
  where e->>'k' in ('view', 'beat', 'map', 'chart');
end $b$$f$;
  execute 'revoke all on function public.track_visit(uuid, jsonb) from public';
  execute 'grant execute on function public.track_visit(uuid, jsonb) to anon, authenticated';

  execute $f$
create or replace function public.admin_report(p_days integer default 7) returns jsonb
language plpgsql stable security definer set search_path = public as
$b$
declare
  d integer := case when p_days in (1, 7, 30) then p_days else 7 end;
  t1 timestamptz := now(); t0 timestamptz; tp timestamptz;
  step interval; res jsonb;
begin
  if not public.analytics_is_admin() then return null; end if;
  t0 := t1 - make_interval(days => d); tp := t0 - make_interval(days => d);
  step := case when d = 1 then interval '1 hour' else interval '1 day' end;

  select jsonb_build_object(
    'days', d, 'from', t0, 'to', t1,
    'numbers', (
      select jsonb_build_object(
        'visitors', jsonb_build_array(
          (select count(distinct anon_id) from public.track_events where kind = 'view' and at >= t0),
          (select count(distinct anon_id) from public.track_events where kind = 'view' and at >= tp and at < t0)),
        'registrations', jsonb_build_array(
          (select count(*) from auth.users where created_at >= t0),
          (select count(*) from auth.users where created_at >= tp and created_at < t0)),
        'invites', jsonb_build_array(0, 0),
        'decks', jsonb_build_array(
          (select count(*) from public.ready_reports where created_at >= t0),
          (select count(*) from public.ready_reports where created_at >= tp and created_at < t0)),
        'researches', jsonb_build_array(
          (select count(*) from public.ready_reports where created_at >= t0 and result ? 'research'),
          (select count(*) from public.ready_reports where created_at >= tp and created_at < t0 and result ? 'research')),
        'revenue', jsonb_build_array(
          (select coalesce(sum(amount), 0) from public.payments where status = 'paid' and created_at >= t0),
          (select coalesce(sum(amount), 0) from public.payments where status = 'paid' and created_at >= tp and created_at < t0)))),
    'chart', (
      select coalesce(jsonb_agg(jsonb_build_object('t', g, 'visitors', (select count(distinct anon_id) from public.track_events where kind = 'view' and at >= g and at < g + step),
        'registrations', (select count(*) from auth.users where created_at >= g and created_at < g + step)) order by g), '[]')
      from generate_series(date_trunc(case when d = 1 then 'hour' else 'day' end, t0), t1, step) g),
    'maps', (
      select coalesce(jsonb_agg(jsonb_build_object('view', v, 'secs', s, 'visits', n) order by s desc), '[]')
      from (select view v, sum(secs) s, count(distinct (anon_id::text || date_trunc('day', at)::text)) n
            from public.track_events where kind = 'beat' and path like '/map%' and view is not null and at >= t0 group by view) m),
    'sources', (
      select coalesce(jsonb_agg(jsonb_build_object('source', s, 'visitors', n, 'registered', r) order by n desc), '[]')
      from (select f.s, count(*) n, count(*) filter (where exists (select 1 from public.check_balances b join auth.users u on u.id = b.user_id
                    where b.anon_id = f.anon_id and u.created_at >= t0)) r
            from (select distinct on (anon_id) anon_id, coalesce(src, 'direct') s from public.track_events
                  where kind = 'view' and at >= t0 order by anon_id, at) f group by f.s order by n desc limit 12) x),
    'funnel', jsonb_build_object(
      'visited', (select count(distinct anon_id) from public.track_events where kind = 'view' and at >= t0),
      'registered', (select count(*) from auth.users where created_at >= t0),
      'opened', (select count(distinct balance_id) from public.check_events where kind in ('spend_free', 'spend_paid') and firm_id is not null and created_at >= t0),
      'deck', (select count(distinct user_id) from public.ready_reports where created_at >= t0),
      'paid', (select count(distinct user_id) from public.payments where status = 'paid' and created_at >= t0)),
    'registrations', (
      select coalesce(jsonb_agg(r order by (r->>'at') desc), '[]') from (
        select jsonb_build_object('at', u.created_at, 'email', u.email,
          'src', (select coalesce(e.src, 'direct') from public.track_events e join public.check_balances b on b.anon_id = e.anon_id
                  where b.user_id = u.id and e.kind = 'view' order by e.at limit 1),
          'invite', null,
          'opened', (select count(*) from public.check_events c join public.check_balances b on b.id = c.balance_id
                     where b.user_id = u.id and c.kind in ('spend_free', 'spend_paid') and c.firm_id is not null),
          'decks', (select count(*) from public.ready_reports x where x.user_id = u.id),
          'paid', (select coalesce(sum(p.amount), 0) from public.payments p where p.user_id = u.id and p.status = 'paid')) r
        from auth.users u where u.created_at >= t0 order by u.created_at desc limit 100) q),
    'deckrows', (
      select coalesce(jsonb_agg(r order by (r->>'at') desc), '[]') from (
        select jsonb_build_object('at', x.created_at, 'email', u.email, 'file', x.deck_name, 'status', x.status,
          'stage', x.result->'company'->>'stage', 'sector', x.result->'company'->>'sector',
          'score', x.result->'scores'->>'deck', 'verdict', x.result->>'verdict', 'research', (x.result ? 'research')) r
        from public.ready_reports x left join auth.users u on u.id = x.user_id
        where x.created_at >= t0 order by x.created_at desc limit 100) q),
    'invites', '[]'::jsonb,
    'requests', (
      select coalesce(jsonb_agg(r order by (r->>'at') desc), '[]') from (
        select jsonb_build_object('firm', fr.name, 'at', e.created_at, 'by', e.email) r
        from public.firm_request_emails e join public.firm_requests fr on fr.id = e.request_id
        where e.created_at >= t0 order by e.created_at desc limit 50) q),
    'firms', (
      select coalesce(jsonb_agg(jsonb_build_object('firm', name, 'slug', slug, 'opens', n) order by n desc), '[]') from (
        select f.name, f.slug, count(*) n from public.check_events c join public.firms f on f.id = c.firm_id
        where c.kind in ('spend_free', 'spend_paid') and c.created_at >= t0 group by f.name, f.slug order by n desc limit 10) q),
    'cost', (
      select jsonb_build_object('reports', count(*) filter (where status = 'done'),
        'researches', count(*) filter (where result ? 'research'),
        'model_usd', round((coalesce(sum(tokens_in), 0) * 4 + coalesce(sum(tokens_out), 0) * 20) / 1000000.0, 2),
        'revenue_usd', (select coalesce(sum(amount), 0) / 100.0 from public.payments where status = 'paid' and created_at >= t0))
      from public.ready_reports where created_at >= t0)
  ) into res;
  return res;
end $b$$f$;
  execute 'revoke all on function public.admin_report(integer) from public';
  execute 'grant execute on function public.admin_report(integer) to authenticated';

  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('track_events_cleanup', '17 3 * * *', $c$delete from public.track_events where at < now() - interval '90 days'$c$);
  end if;
end $wrapaa$;
