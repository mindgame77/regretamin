-- SEO for firm pages: one stored title, description, indexable flag and fact list per firm.
-- Stored in a NEW table public.v2_firm_seo. Nothing is added to the bot write path:
--   * no trigger on any bot table (v2_firms, v2_firm_industries, v2_research_submissions, ...);
--   * v2_firms / firm_summary rows are only READ (plain SELECT, no row locks), never updated;
--   * a pg_cron job (every 10 min) recomputes a small batch (default 300 firms), changed firms first,
--     with lock_timeout 1s and statement_timeout 30s, so it can never queue behind or in front of a bot write.
-- Titles and descriptions are templates filled with stored facts. No AI, nothing guessed.
-- manual_edit = true keeps a hand-written seo_title / seo_description; the job still refreshes facts and indexable.
-- Public reads: firm_meta_seo(slug) (firm_meta + the SEO row, one query for the edge) and
-- firm_seo_sitemap(page, size) (indexable firms only, 1,000 per page). firm_meta and firm_sitemap are not changed.
-- On a database without the v2 tables (CI) this is a no-op.
-- Not applied to production by this change. Backfill after applying: see docs/SEO.md.
-- Undo: supabase/rollbacks/20261118120000_v2_firm_seo.sql
do $mig$
begin
  if to_regclass('public.v2_firms') is null or to_regclass('public.v2_firm_live') is null or to_regclass('public.firm_summary') is null
     or to_regclass('public.v2_firm_industries') is null or to_regclass('public.v2_firm_stages') is null
     or to_regclass('public.v2_person_firm_roles') is null or to_regclass('public.v2_people') is null
     or to_regclass('public.v2_firm_registry_ids') is null or to_regclass('public.v2_social_accounts') is null
     or to_regprocedure('public.firm_meta(text)') is null or to_regprocedure('public.v2_is_leader_title(text)') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'firm_summary' and column_name = 'researched') then
    raise notice 'v2 tables missing, v2_firm_seo skipped';
    return;
  end if;

  execute $sql$
create table if not exists public.v2_firm_seo (
  firm_id           bigint primary key,           -- v2_firms.firm_id (no foreign key: nothing here can lock or slow a v2_firms write)
  slug              text,
  seo_title         text,                         -- full <title>, brand included when it fits (<= 60 chars)
  seo_description   text,                         -- <= 160 chars
  seo_indexable     boolean not null default false,
  facts             jsonb not null default '{}',  -- the facts the page already shows, for the server-rendered HTML and JSON-LD
  last_checked_date date,                         -- v2_firms.last_checked_date when computed (sitemap lastmod)
  manual_edit       boolean not null default false,
  seo_updated_at    timestamptz not null default now(),  -- last time title / description / indexable / facts changed
  checked_at        timestamptz not null default now()   -- last time the job looked at this firm
)
$sql$;
  execute 'create index if not exists v2_firm_seo_checked_idx on public.v2_firm_seo (checked_at)';
  execute 'create index if not exists v2_firm_seo_slug_idx on public.v2_firm_seo (slug) where seo_indexable';
  execute 'alter table public.v2_firm_seo enable row level security';
  execute 'revoke all on table public.v2_firm_seo from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then execute 'revoke all on table public.v2_firm_seo from anon'; end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then execute 'revoke all on table public.v2_firm_seo from authenticated'; end if;
  comment on table public.v2_firm_seo is 'SEO title, description, indexable flag and page facts per firm. Written only by v2_firm_seo_refresh() (pg_cron) and by hand (set manual_edit = true to keep a hand-written title/description).';

  -- Stage order used for "seed to Series A". Unknown words (Bridge, Debt, Other, IPO) are left out.
  execute $sql$
create or replace function public.v2_seo_stage_rank(p text) returns int language sql immutable as $fn$
  select case lower(btrim(coalesce(p, '')))
    when 'pre-seed' then 1 when 'seed' then 2 when 'series a' then 3 when 'series b' then 4
    when 'series c' then 5 when 'series c and later' then 5 when 'series d' then 6 when 'series e' then 7 when 'series f' then 8
    when 'growth' then 9 when 'growth stage' then 9 when 'late stage' then 9 when 'expansion' then 9 end
$fn$
$sql$;
  execute $sql$
create or replace function public.v2_seo_stage_label(p int) returns text language sql immutable as $fn$
  select (array['pre-seed', 'seed', 'Series A', 'Series B', 'Series C', 'Series D', 'Series E', 'Series F', 'growth'])[p]
$fn$
$sql$;

  -- Pure read: computes the SEO row for the given firms. Takes no row locks.
  execute $sql$
create or replace function public.v2_firm_seo_compute(p_ids bigint[])
returns table (firm_id bigint, slug text, seo_title text, seo_description text, seo_indexable boolean, facts jsonb, last_checked_date date)
language sql stable security definer set search_path = public, pg_temp as $fn$
-- seo:compute:begin
with ids as (
  select distinct x as firm_id from unnest(p_ids) x
),
b as (
  select f.firm_id, l.slug::text as slug, nullif(btrim(f.display_name), '') as name, nullif(btrim(f.legal_name), '') as legal_name,
         case when f.website_url ~* '^https?://[^\s"<>]+$' then f.website_url end as website,
         nullif(btrim(f.hq_street), '') as street, nullif(btrim(f.hq_postal), '') as postal,
         nullif(btrim(f.hq_state), '') as region,
         case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end as country,
         nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)), '') as hq_text,
         case when nullif(btrim(f.hq_city), '') is not null then
           case when btrim(f.hq_city) = upper(btrim(f.hq_city)) and char_length(btrim(f.hq_city)) > 3
             then initcap(lower(btrim(f.hq_city))) else btrim(f.hq_city) end end as city,
         case when f.founded_year between 1800 and extract(year from current_date)::int then f.founded_year::int end as founded,
         f.last_checked_date,
         coalesce(s.listed, false) and l.slug is not null as listed,
         coalesce(s.researched, false) as researched,
         coalesce(s.investments, 0) as investments, s.latest_deal_date, s.latest_company
    from ids
    join v2_firms f on f.firm_id = ids.firm_id
    left join v2_firm_live l on l.firm_id = f.firm_id
    left join firm_summary s on s.firm_id = f.firm_id
),
ind as (
  select i.firm_id, jsonb_agg(btrim(i.industry_text) order by i.position, i.id) as list,
         (array_agg(btrim(i.industry_text) order by i.position, i.id))[1] as top
    from v2_firm_industries i join ids on ids.firm_id = i.firm_id
   where i.is_current and not i.archived and nullif(btrim(i.industry_text), '') is not null
   group by i.firm_id
),
stg as (
  select x.firm_id, min(x.rk) as lo, max(x.rk) as hi,
         jsonb_agg(x.stage order by x.rk nulls last, x.stage) as list   -- page order: pre-seed, seed, Series A, ..., growth
    from (select distinct st.firm_id, btrim(st.stage) as stage, v2_seo_stage_rank(st.stage) as rk
            from v2_firm_stages st join ids on ids.firm_id = st.firm_id
           where st.is_current and not st.archived and nullif(btrim(st.stage), '') is not null) x
   group by x.firm_id
),
-- Team: the same rows as the page's Team section (v2_firm_page): founders and current leaders, live rows only.
-- The same person stored twice (two person rows, same name) is listed once.
lead as (
  select y.firm_id, jsonb_agg(jsonb_build_object('name', y.name, 'title', y.title, 'founder', y.founder) order by y.row_id) as list
    from (
      select distinct on (r.firm_id, lower(btrim(pe.person_name))) r.firm_id, r.row_id, btrim(pe.person_name) as name,
             nullif(btrim(r.title), '') as title, coalesce(r.is_founder, false) as founder
        from (
          select distinct on (pr.firm_id, pr.person_id) pr.*
            from v2_person_firm_roles pr join ids on ids.firm_id = pr.firm_id
           where pr.is_current and not pr.archived and not pr.nothing_found
             and (pr.is_founder or v2_is_leader_title(pr.title))
           order by pr.firm_id, pr.person_id, pr.is_founder desc, pr.row_id
        ) r
        join v2_people pe on pe.person_id = r.person_id
       where pe.is_current and not pe.archived and not pe.nothing_found and nullif(btrim(pe.person_name), '') is not null
       order by r.firm_id, lower(btrim(pe.person_name)), r.row_id
    ) y
   group by y.firm_id
),
reg as (
  select g.firm_id, jsonb_agg(jsonb_build_object('type', g.registry_type, 'value', g.registry_value,
           'url', case when g.source_url ~* '^https://[^\s"<>]+$' then g.source_url end) order by g.registry_type, g.row_id) as list
    from v2_firm_registry_ids g join ids on ids.firm_id = g.firm_id
   where g.is_current and not g.archived and not g.nothing_found and nullif(btrim(g.registry_value), '') is not null
     and g.registry_type in ('SEC CRD', 'SEC CIK', 'SEC file number', 'LEI', 'Companies House')
   group by g.firm_id
),
-- Social profiles: the same accounts the page header shows (firm's own site, read in the last 12 months).
soc as (
  select a.firm_id, jsonb_agg(distinct a.account_url) as list
    from v2_social_accounts a join ids on ids.firm_id = a.firm_id
   where a.is_current and not a.archived and not a.nothing_found and a.source_level = 2 and a.follower_count is not null
     and a.date_read >= current_date - interval '12 months' and a.account_url ~* '^https://[^\s"<>]+$'
   group by a.firm_id
),
p as (
  select b.*, case when char_length(ind.top) <= 40 then ind.top end as sector, ind.list as sectors,
         case when stg.lo is null then null when stg.lo = stg.hi then v2_seo_stage_label(stg.lo)
              else v2_seo_stage_label(stg.lo) || ' to ' || v2_seo_stage_label(stg.hi) end as stage,
         stg.list as stages, lead.list as leaders, reg.list as registry, soc.list as social
    from b
    left join ind on ind.firm_id = b.firm_id
    left join stg on stg.firm_id = b.firm_id
    left join lead on lead.firm_id = b.firm_id
    left join reg on reg.firm_id = b.firm_id
    left join soc on soc.firm_id = b.firm_id
),
t as (
  select p.*,
    p.name || ': ' || case when p.sector is not null and p.city is not null then p.sector || ' VC in ' || p.city
                           when p.sector is not null then p.sector || ' VC'
                           when p.city is not null then 'VC in ' || p.city
                           else 'Venture Capital Firm' end as t_full,
    p.name || ': ' || coalesce(p.sector || ' VC', 'Venture Capital Firm') as t_nocity,
    -- description parts
    case when p.investments > 0 then p.investments || case when p.investments = 1 then ' investment' else ' investments' end end as inv,
    case when p.latest_deal_date is not null then ', latest ' || to_char(p.latest_deal_date, 'Mon YYYY') end as latest,
    case when p.last_checked_date is not null then 'Checked ' || to_char(p.last_checked_date, 'Mon FMDD, YYYY') || ' against SEC, court and sanctions records.' end as chk,
    (case when p.city is not null then 1 else 0 end + case when p.sector is not null then 1 else 0 end + case when p.stage is not null then 1 else 0 end
     + case when p.founded is not null then 1 else 0 end + case when p.investments > 0 then 1 else 0 end
     + case when jsonb_array_length(coalesce(p.leaders, '[]')) > 0 then 1 else 0 end) as n_facts
  from p
),
d as (
  select t.*,
    -- "<Firm> is a <stage> VC firm in <City>, founded <year>."
    t.name || ' is ' || case when coalesce(t.stage, 'VC') ~* '^[aeiou]' then 'an ' else 'a ' end || coalesce(t.stage || ' ', '') || 'VC firm'
      || coalesce(' in ' || t.city, '') || coalesce(', founded ' || t.founded, '') || '.' as s1,
    t.name || ' is ' || case when coalesce(t.stage, 'VC') ~* '^[aeiou]' then 'an ' else 'a ' end || coalesce(t.stage || ' ', '') || 'VC firm'
      || coalesce(' in ' || t.city, '') || '.' as s1_nofounded,
    t.name || ' is a VC firm' || coalesce(' in ' || t.city, '') || '.' as s1_min
  from t
)
select d.firm_id, d.slug,
  case when d.name is not null then coalesce((
    select c from unnest(array[d.t_full || ' | Regretamin', d.t_full, d.t_nocity, d.name || ': Venture Capital Firm', d.name]) with ordinality u(c, o)
     where c is not null and char_length(c) <= 60 order by o limit 1), d.name) end as seo_title,
  case when d.name is not null then coalesce((
    select c from unnest(array[
      concat_ws(' ', d.s1, d.inv || coalesce(d.latest, '') || '.', d.chk),
      concat_ws(' ', d.s1, d.inv || '.', d.chk),
      concat_ws(' ', d.s1_nofounded, d.inv || '.', d.chk),
      concat_ws(' ', d.s1, d.inv || coalesce(d.latest, '') || '.'),
      concat_ws(' ', d.s1_nofounded, d.inv || '.'),
      d.s1_nofounded, d.s1_min]) with ordinality u(c, o)
     where char_length(c) <= 160 order by o limit 1), left(d.s1_min, 159) || '…') end as seo_description,
  (d.name is not null and d.listed and d.researched and d.n_facts >= 3) as seo_indexable,
  jsonb_strip_nulls(jsonb_build_object(
    'name', d.name, 'legal_name', d.legal_name, 'website', d.website, 'hq', d.hq_text,
    'address', nullif(jsonb_strip_nulls(jsonb_build_object('street', d.street, 'city', d.city, 'region', d.region, 'postal', d.postal, 'country', d.country)), '{}'::jsonb),
    'founded', d.founded, 'sectors', d.sectors, 'stages', d.stages,
    'investments', nullif(d.investments, 0), 'latest_deal_date', d.latest_deal_date, 'latest_company', nullif(btrim(d.latest_company), ''),
    'last_checked', d.last_checked_date, 'leaders', d.leaders, 'registry', d.registry, 'social', d.social)) as facts,
  d.last_checked_date
from d
-- seo:compute:end
$fn$
$sql$;

  -- One batch: changed firms first (new firm, new check date, research finished), then the oldest-checked rows,
  -- so every firm is looked at again within a few hours. Writes v2_firm_seo only.
  execute $sql$
create or replace function public.v2_firm_seo_refresh(p_limit int default 300)
returns int language plpgsql security definer set search_path = public, pg_temp
set lock_timeout = '1s' as $fn$
declare v_ids bigint[]; v_n int := 0;
begin
  -- one run at a time (a slow run and the next tick never overlap)
  if not pg_try_advisory_xact_lock(hashtext('v2_firm_seo_refresh')) then return 0; end if;
  select coalesce(array_agg(x.firm_id), '{}') into v_ids from (
    select f.firm_id
      from v2_firms f
      left join v2_firm_seo s on s.firm_id = f.firm_id
      left join firm_summary fs on fs.firm_id = f.firm_id
     order by (s.firm_id is null) desc,
              (f.last_checked_date is distinct from s.last_checked_date
               or coalesce(fs.researched, false) and not coalesce(s.seo_indexable, false) and s.checked_at < now() - interval '30 minutes') desc,
              s.checked_at nulls first
     limit greatest(1, least(coalesce(p_limit, 300), 2000))
  ) x;
  -- skip rows someone is editing by hand right now (never wait on a lock)
  v_ids := array(select i from unnest(v_ids) i
                 where not exists (select 1 from v2_firm_seo s where s.firm_id = i)
                    or i in (select s.firm_id from v2_firm_seo s where s.firm_id = any(v_ids) for update skip locked));
  insert into v2_firm_seo as s (firm_id, slug, seo_title, seo_description, seo_indexable, facts, last_checked_date, seo_updated_at, checked_at)
  select c.firm_id, c.slug, c.seo_title, c.seo_description, c.seo_indexable, c.facts, c.last_checked_date, now(), now()
    from v2_firm_seo_compute(v_ids) c
  on conflict (firm_id) do update set
    slug = excluded.slug,
    seo_title = case when s.manual_edit then s.seo_title else excluded.seo_title end,
    seo_description = case when s.manual_edit then s.seo_description else excluded.seo_description end,
    seo_indexable = excluded.seo_indexable, facts = excluded.facts, last_checked_date = excluded.last_checked_date,
    seo_updated_at = case when (s.slug, s.seo_indexable, s.facts, s.last_checked_date) is distinct from (excluded.slug, excluded.seo_indexable, excluded.facts, excluded.last_checked_date)
                            or (not s.manual_edit and (s.seo_title, s.seo_description) is distinct from (excluded.seo_title, excluded.seo_description))
                          then now() else s.seo_updated_at end,
    checked_at = now();
  get diagnostics v_n = row_count;
  -- firms that no longer exist
  delete from v2_firm_seo s where s.firm_id in (select s2.firm_id from v2_firm_seo s2 where not exists (select 1 from v2_firms f where f.firm_id = s2.firm_id) limit 500);
  return v_n;
end
$fn$
$sql$;

  -- Edge read: firm_meta plus the SEO row. One query per uncached firm page.
  execute $sql$
create or replace function public.firm_meta_seo(p_slug text)
returns table (slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year integer,
               updated_at timestamptz, indexable boolean, seo_title text, seo_description text, seo_facts jsonb, seo_updated_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $fn$
  select m.slug, m.name, m.short_name, m.hq, m.firm_type, m.legal_name, m.primary_domain, m.founded_year, m.updated_at,
         coalesce(s.seo_indexable, m.indexable), s.seo_title, s.seo_description, s.facts, s.seo_updated_at
    from firm_meta(p_slug) m
    left join v2_firm_live l on l.slug = m.slug
    left join v2_firm_seo s on s.firm_id = l.firm_id
   limit 1
$fn$
$sql$;

  -- Sitemap: indexable firms only, lastmod = the firm's real last checked date. At most 1,000 per page (the API row cap).
  execute $sql$
create or replace function public.firm_seo_sitemap(p_page integer default 1, p_size integer default 1000)
returns table (slug text, lastmod date, total bigint)
language sql stable security definer set search_path = public, pg_temp as $fn$
  with pub as (
    select l.slug::text as slug, s.last_checked_date as lastmod
      from v2_firm_seo s
      join v2_firm_live l on l.firm_id = s.firm_id
      join v2_firms f on f.firm_id = s.firm_id
     where s.seo_indexable and not coalesce(f.archived, false) and f.merged_into_firm_id is null
  )
  select p.slug, p.lastmod, (select count(*) from pub)
    from pub p
   order by p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 1000), 1), 1000)
   limit least(greatest(coalesce(p_size, 1000), 1), 1000)
$fn$
$sql$;

  -- /investors/ plain links for crawlers: listed firms by name, 100 per page.
  execute $sql$
create or replace function public.firm_seo_directory(p_page integer default 1, p_size integer default 100)
returns table (slug text, name text, city text, total bigint)
language sql stable security definer set search_path = public, pg_temp as $fn$
  with pub as (
    select s.slug, s.display_name::text as name, nullif(s.city_label, '') as city
      from firm_summary s where s.listed and s.slug is not null and nullif(btrim(s.display_name), '') is not null
  )
  select p.slug, p.name, p.city, (select count(*) from pub)
    from pub p
   order by lower(p.name), p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 100), 1), 100)
   limit least(greatest(coalesce(p_size, 100), 1), 100)
$fn$
$sql$;

  execute 'revoke all on function public.v2_firm_seo_compute(bigint[]) from public';
  execute 'revoke all on function public.v2_firm_seo_refresh(int) from public';
  execute 'revoke all on function public.firm_meta_seo(text) from public';
  execute 'revoke all on function public.firm_seo_sitemap(integer, integer) from public';
  execute 'revoke all on function public.firm_seo_directory(integer, integer) from public';
  -- Supabase default privileges grant EXECUTE on new functions to anon/authenticated directly,
  -- so revoking from public is not enough for the internal ones.
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_firm_seo_compute(bigint[]) from anon';
    execute 'revoke all on function public.v2_firm_seo_refresh(int) from anon';
    execute 'grant execute on function public.firm_meta_seo(text) to anon';
    execute 'grant execute on function public.firm_seo_sitemap(integer, integer) to anon';
    execute 'grant execute on function public.firm_seo_directory(integer, integer) to anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_firm_seo_compute(bigint[]) from authenticated';
    execute 'revoke all on function public.v2_firm_seo_refresh(int) from authenticated';
    execute 'grant execute on function public.firm_meta_seo(text) to authenticated';
    execute 'grant execute on function public.firm_seo_sitemap(integer, integer) to authenticated';
    execute 'grant execute on function public.firm_seo_directory(integer, integer) to authenticated';
  end if;

  -- Every 10 minutes, one small batch. Short timeouts: on any wait it gives up and the next tick retries.
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $sql$select cron.schedule('v2-firm-seo-refresh', '*/10 * * * *',
      'set statement_timeout = ''30s''; set lock_timeout = ''1s''; select public.v2_firm_seo_refresh(300)')$sql$;
  else
    raise notice 'pg_cron missing: v2-firm-seo-refresh not scheduled';
  end if;
end
$mig$;
