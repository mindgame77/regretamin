-- "Am I ready to pitch?", first working version (founder, 26 Nov 2026: "just do it so we could test it").
-- All new: a private place for decks, one table of reports, one read-only function that picks firms. Nothing existing changes.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.firm_summary') is null or to_regclass('public.v2_investor_principles') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;

  execute $q$
create table if not exists public.ready_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  finished_at timestamptz,
  deck_path text not null,
  deck_name text,
  linkedin text,
  note text,
  status text not null default 'new',
  result jsonb,
  model text,
  tokens_in integer,
  tokens_out integer,
  error text
)$q$;
  execute 'alter table public.ready_reports enable row level security';
  execute 'drop policy if exists ready_reports_owner_select on public.ready_reports';
  execute 'drop policy if exists ready_reports_owner_insert on public.ready_reports';
  execute 'drop policy if exists ready_reports_owner_update on public.ready_reports';
  execute 'create policy ready_reports_owner_select on public.ready_reports for select to authenticated using (user_id = auth.uid())';
  execute 'create policy ready_reports_owner_insert on public.ready_reports for insert to authenticated with check (user_id = auth.uid())';
  execute 'create policy ready_reports_owner_update on public.ready_reports for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())';
  execute 'revoke all on public.ready_reports from anon';
  execute 'grant select, insert, update on public.ready_reports to authenticated';
  execute 'create index if not exists ready_reports_user_idx on public.ready_reports (user_id, created_at desc)';

  if to_regclass('storage.buckets') is not null and to_regclass('storage.objects') is not null then
    execute $q$insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
             values ('decks', 'decks', false, 20971520, array['application/pdf']) on conflict (id) do nothing$q$;
    execute 'drop policy if exists decks_owner_insert on storage.objects';
    execute 'drop policy if exists decks_owner_select on storage.objects';
    execute $q$create policy decks_owner_insert on storage.objects for insert to authenticated
             with check (bucket_id = 'decks' and (storage.foldername(name))[1] = auth.uid()::text)$q$;
    execute $q$create policy decks_owner_select on storage.objects for select to authenticated
             using (bucket_id = 'decks' and (storage.foldername(name))[1] = auth.uid()::text)$q$;
  end if;

  execute $fn$
create or replace function public.v2_ready_firms(p_stage text, p_sector text, p_limit integer default 6)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with st as (select case when lower(coalesce(p_stage,'')) like 'pre%' then array['Pre-seed','Seed'] else array['Seed','Pre-seed'] end as rounds),
sec as (select distinct startup_id from v2_startup_sectors where is_current and industry_name = p_sector),
anysec as (select exists (select 1 from sec) as ok),
d as (
  select v.firm_id, v.startup_id, v.deal_date,
         (v.round = any(st.rounds)) as is_stage,
         (v.startup_id in (select startup_id from sec)) as is_sec,
         a.ok as has_sec
  from v2_deals v cross join st cross join anysec a
  where v.shown and v.deal_date is not null),
x as (
  select fs.firm_id, fs.slug, fs.display_name, fs.hq_city, fs.hq_country, fs.deals,
    count(*) filter (where d.deal_date >= current_date - 365 and d.is_stage and (d.is_sec or not d.has_sec)) as n_fit,
    count(*) filter (where d.deal_date >= current_date - 365) as n12,
    count(*) filter (where d.deal_date >= current_date - 90) as n90,
    round(100.0 * count(*) filter (where d.is_stage) / count(*)) as stage_pct,
    round(100.0 * count(*) filter (where d.is_sec) / count(*)) as sector_pct,
    max(d.deal_date) as last_deal
  from firm_summary fs join d on d.firm_id = fs.firm_id
  where fs.listed
  group by 1, 2, 3, 4, 5, 6),
pick as (
  select * from x where n_fit >= 1 and deals < 150 and last_deal >= current_date - 180
  order by n_fit desc, n90 desc, n12 desc
  limit greatest(1, least(coalesce(p_limit, 6), 12))),
fd as (select firm_id, startup_id, min(deal_date) as f from d group by 1, 2),
lad as (
  select p.display_name as pname, g.firm_id as gid, count(*) as n
  from pick p join fd a on a.firm_id = p.firm_id
  join fd g on g.startup_id = a.startup_id and g.f > a.f and g.firm_id <> p.firm_id
  group by 1, 2),
big as (
  select distinct on (l.gid) gs.display_name, gs.slug, l.pname, l.n, gs.deals
  from lad l join firm_summary gs on gs.firm_id = l.gid
  where gs.listed and gs.deals >= 150 and l.gid not in (select firm_id from pick)
  order by l.gid, l.n desc)
select jsonb_build_object(
  'firms', coalesce((
    select jsonb_agg(jsonb_build_object(
      'slug', p.slug, 'name', p.display_name, 'city', p.hq_city, 'country', p.hq_country,
      'fit', p.n_fit, 'n12', p.n12, 'n90', p.n90, 'stage_pct', p.stage_pct, 'sector_pct', p.sector_pct, 'last_deal', p.last_deal,
      'summary', (
        select jsonb_build_object('text', s.summary, 'who', s.investor_name, 'title', s.investor_title, 'year', extract(year from s.published_at))
        from v2_investor_principles s
        where s.firm_id = p.firm_id and coalesce(s.is_current, true) and not coalesce(s.archived, false) and s.summary is not null
        order by (s.investor_title = 'Firm') desc, s.display_order nulls last limit 1)
    ) order by p.n_fit desc, p.n90 desc, p.n12 desc) from pick p), '[]'::jsonb),
  'then', coalesce((
    select jsonb_agg(jsonb_build_object('name', b.display_name, 'slug', b.slug, 'after', b.pname, 'n', b.n) order by b.n desc, b.deals desc)
    from (select * from big order by n desc, deals desc limit 5) b), '[]'::jsonb),
  'sector_known', (select ok from anysec))
$body$
$fn$;
  execute 'comment on function public.v2_ready_firms(text, text, integer) is ''Am I ready to pitch: firms that fit a stage and sector and are investing now (not the biggest ones), each with its Summary line, and the big firms that later invested where they went first. Read-only.''';
end
$wrapci$;
