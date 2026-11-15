-- Investors page speed-up: one ready-made row per firm (firm_summary), kept fresh by triggers,
-- read by firm_directory_page_v2. Additive only: the old firm_directory_page is not touched.
-- Counting rules are copied from firm_directory_page (dated shown deals + undated portfolio-only rows).

create index if not exists v2_deals_startup_id_idx on public.v2_deals (startup_id);
create index if not exists v2_deals_firm_startup_idx on public.v2_deals (firm_id, startup_id);

create table if not exists public.firm_summary (
  firm_id bigint primary key,
  listed boolean not null default false,       -- live, not archived, not merged, not demand_hidden
  slug text,
  live_since timestamptz,
  display_name varchar,
  short_name varchar,
  website_url text,
  hq_city varchar,
  hq_state text,
  hq_country text,                             -- upper(btrim(hq_country))
  firm_status text,                            -- coalesce(nullif(firm_status,''),'Active')
  region text,
  city_label text,
  added timestamptz,                           -- coalesce(last auto-published fact, live_since)
  deals int not null default 0,                -- dated shown deals
  investments int not null default 0,          -- dated deals + undated portfolio-only rows
  dated_dates date[] not null default '{}',    -- one entry per dated deal (activity / 12m counts)
  led_dates date[] not null default '{}',      -- dated deals the firm led
  latest_deal_date date,
  latest_led_date date,
  latest_company varchar,
  latest_round text,
  startups varchar[],
  startup_sites text[],
  startup_search text not null default '',     -- lowercased startup name/domain/site text for search
  industries json,                             -- what the row shows
  industry_labels text[] not null default '{}',-- filter + facet labels
  stages json,
  stage_labels text[] not null default '{}',
  legal_records int not null default 0,
  refreshed_at timestamptz not null default now()
);
create index if not exists firm_summary_listed_idx on public.firm_summary (listed);

alter table public.firm_summary enable row level security;
revoke all on public.firm_summary from anon, authenticated;

create or replace function public.firm_summary_region(p_country text)
returns text language sql immutable as $$
  select case case when upper(btrim(p_country)) ~ '^[A-Z]{2}$' then upper(btrim(p_country)) end
    when 'US' then 'north_america' when 'CA' then 'north_america' when 'MX' then 'north_america'
    when 'GB' then 'europe' when 'CH' then 'europe' when 'IE' then 'europe' when 'DE' then 'europe'
    when 'FR' then 'europe' when 'NL' then 'europe' when 'SE' then 'europe' when 'NO' then 'europe'
    when 'DK' then 'europe' when 'FI' then 'europe' when 'IT' then 'europe' when 'ES' then 'europe'
    when 'AT' then 'europe' when 'BE' then 'europe' when 'PT' then 'europe' when 'UA' then 'europe' when 'PL' then 'europe' when 'LU' then 'europe' when 'EE' then 'europe' when 'BG' then 'europe' when 'IS' then 'europe' when 'CY' then 'europe' when 'CZ' then 'europe' when 'IM' then 'europe' when 'LV' then 'europe' when 'LT' then 'europe' when 'RO' then 'europe' when 'HU' then 'europe' when 'SK' then 'europe' when 'SI' then 'europe' when 'HR' then 'europe' when 'RS' then 'europe' when 'GR' then 'europe' when 'MT' then 'europe' when 'MC' then 'europe' when 'LI' then 'europe' when 'JE' then 'europe' when 'GG' then 'europe' when 'GI' then 'europe' when 'BA' then 'europe' when 'MK' then 'europe' when 'AL' then 'europe' when 'ME' then 'europe' when 'MD' then 'europe' when 'AD' then 'europe' when 'SM' then 'europe'
    when 'KY' then 'latam' when 'BR' then 'latam' when 'AR' then 'latam' when 'CL' then 'latam' when 'CO' then 'latam'
    when 'CN' then 'asia' when 'JP' then 'asia' when 'KR' then 'asia' when 'SG' then 'asia'
    when 'IN' then 'asia' when 'HK' then 'asia' when 'TW' then 'asia'
    when 'ZA' then 'africa' when 'NG' then 'africa' when 'KE' then 'africa' when 'EG' then 'africa'
    when 'AE' then 'middle_east' when 'IL' then 'middle_east' when 'SA' then 'middle_east' when 'QA' then 'middle_east'
    else 'unknown' end
$$;

-- Recompute the rows for the given firms only.
create or replace function public.refresh_firm_summary(p_ids bigint[])
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_ids is null or cardinality(p_ids) = 0 then return; end if;

  delete from firm_summary s
   where s.firm_id = any(p_ids)
     and not exists (select 1 from v2_firms f where f.firm_id = s.firm_id);

  insert into firm_summary as t (
    firm_id, listed, slug, live_since, display_name, short_name, website_url, hq_city, hq_state, hq_country,
    firm_status, region, city_label, added, deals, investments, dated_dates, led_dates, latest_deal_date,
    latest_led_date, latest_company, latest_round, startups, startup_sites, startup_search, industries,
    industry_labels, stages, stage_labels, legal_records, refreshed_at)
  with ids as (
    select distinct f.firm_id from v2_firms f where f.firm_id = any(p_ids)
  ),
  d as (
    select d.firm_id, s.startup_id, s.startup_name, s.domain, s.website_url, s.website_url_norm, d.round, d.deal_date,
           coalesce(d.lead = 'yes', false) as led
      from v2_deals d
      join ids on ids.firm_id = d.firm_id
      join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
     where d.is_current and not d.archived
       and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
  ),
  po as (
    select d.firm_id, s.startup_id, s.startup_name, s.domain, s.website_url, s.website_url_norm
      from v2_deals d
      join ids on ids.firm_id = d.firm_id
      join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
     where d.is_current and not d.archived and not d.nothing_found
       and d.deal_date is null and d.round_amount is null
       and not coalesce(d.shown, true)
       and not exists (
         select 1 from v2_deals x
         where x.firm_id = d.firm_id and x.startup_id = d.startup_id
           and x.is_current and not x.archived and not x.nothing_found
           and coalesce(x.shown, true) and x.deal_date is not null
       )
  ),
  u as (
    select firm_id, startup_id, startup_name, domain, website_url, website_url_norm, deal_date, led, 'dated'::text as src from d
    union all
    select firm_id, startup_id, startup_name, domain, website_url, website_url_norm, null::date, false, 'po'::text from po
  ),
  dagg as (
    select firm_id,
           count(*) filter (where src = 'dated') as deals,
           count(*) as investments,
           coalesce(array_agg(deal_date order by deal_date) filter (where src = 'dated'), '{}') as dated_dates,
           coalesce(array_agg(deal_date order by deal_date) filter (where src = 'dated' and led), '{}') as led_dates,
           max(deal_date) filter (where src = 'dated') as latest_deal_date,
           max(deal_date) filter (where src = 'dated' and led) as latest_led_date,
           array_agg(distinct startup_name) filter (where startup_name is not null) as startups,
           array_agg(distinct domain) filter (where nullif(domain, '') is not null) as startup_sites,
           string_agg(lower(coalesce(startup_name, '')) || chr(1) || lower(coalesce(domain, '')) || chr(1)
                      || lower(coalesce(website_url, '')) || chr(1) || lower(coalesce(website_url_norm, '')), chr(1)) as startup_search
      from u group by firm_id
  ),
  latest as (
    select distinct on (firm_id) firm_id, startup_name, round
      from d order by firm_id, deal_date desc, startup_name
  ),
  fi as (
    select i.firm_id, i.industry_text, i.position, i.id
      from v2_firm_industries i join ids on ids.firm_id = i.firm_id
     where i.is_current and not i.archived and nullif(btrim(i.industry_text), '') is not null
  ),
  inds as (
    select firm_id, json_agg(industry_text order by position, id) as industries,
           array_agg(distinct btrim(industry_text)) as labels
      from fi group by firm_id
  ),
  dsec as (
    select firm_id, json_agg(name order by n desc, name) as industries, array_agg(name::text) as labels from (
      select u.firm_id, sc.name, count(*) n
        from u
        join v2_startup_sectors ss on ss.startup_id = u.startup_id and ss.is_current and not ss.archived
        join v2_sector sc on sc.sector_id = ss.sector_id
       group by 1, 2
    ) x group by firm_id
  ),
  stg as (
    select s.firm_id, json_agg(distinct s.stage) as stages, array_agg(distinct btrim(s.stage)) as labels
      from v2_firm_stages s join ids on ids.firm_id = s.firm_id
     where s.is_current and not s.archived and nullif(btrim(s.stage), '') is not null
     group by s.firm_id
  ),
  leg as (
    select li.firm_id, count(*) as n
      from v2_legal_items li join ids on ids.firm_id = li.firm_id
     where li.is_current and not li.archived and not li.nothing_found and not coalesce(li.lead_only, false)
     group by li.firm_id
  ),
  pub as (
    select p.firm_id, max(p.applied_at) as last_fact
      from v2_auto_published p join ids on ids.firm_id = p.firm_id
     group by p.firm_id
  )
  select f.firm_id,
         (l.firm_id is not null and not coalesce(f.archived, false) and f.merged_into_firm_id is null
            and not coalesce(f.demand_hidden, false)),
         l.slug, l.live_since, f.display_name, f.short_name, f.website_url, f.hq_city, f.hq_state,
         upper(btrim(f.hq_country)),
         coalesce(nullif(f.firm_status, ''), 'Active'),
         firm_summary_region(f.hq_country),
         case
           when nullif(btrim(f.hq_city), '') is not null then
             case when btrim(f.hq_city) = upper(btrim(f.hq_city)) and char_length(btrim(f.hq_city)) > 3
               then initcap(lower(btrim(f.hq_city))) else btrim(f.hq_city) end
           when upper(btrim(f.hq_country)) = 'US' then 'United States'
           when upper(btrim(f.hq_country)) = 'GB' then 'United Kingdom'
           when upper(btrim(f.hq_country)) = 'CH' then 'Switzerland'
           when upper(btrim(f.hq_country)) = 'KY' then 'Cayman Islands'
           else ''
         end,
         coalesce(p.last_fact, l.live_since),
         coalesce(a.deals, 0), coalesce(a.investments, 0),
         coalesce(a.dated_dates, '{}'), coalesce(a.led_dates, '{}'),
         a.latest_deal_date, a.latest_led_date, lt.startup_name, lt.round,
         a.startups, a.startup_sites, coalesce(a.startup_search, ''),
         coalesce(i.industries, ds.industries),
         coalesce(i.labels, ds.labels, '{}'),
         st.stages, coalesce(st.labels, '{}'),
         coalesce(lg.n, 0), now()
    from ids
    join v2_firms f on f.firm_id = ids.firm_id
    left join v2_firm_live l on l.firm_id = f.firm_id
    left join dagg a on a.firm_id = f.firm_id
    left join latest lt on lt.firm_id = f.firm_id
    left join inds i on i.firm_id = f.firm_id
    left join dsec ds on ds.firm_id = f.firm_id
    left join stg st on st.firm_id = f.firm_id
    left join leg lg on lg.firm_id = f.firm_id
    left join pub p on p.firm_id = f.firm_id
  on conflict (firm_id) do update set
    listed = excluded.listed, slug = excluded.slug, live_since = excluded.live_since,
    display_name = excluded.display_name, short_name = excluded.short_name, website_url = excluded.website_url,
    hq_city = excluded.hq_city, hq_state = excluded.hq_state, hq_country = excluded.hq_country,
    firm_status = excluded.firm_status, region = excluded.region, city_label = excluded.city_label,
    added = excluded.added, deals = excluded.deals, investments = excluded.investments,
    dated_dates = excluded.dated_dates, led_dates = excluded.led_dates,
    latest_deal_date = excluded.latest_deal_date, latest_led_date = excluded.latest_led_date,
    latest_company = excluded.latest_company, latest_round = excluded.latest_round,
    startups = excluded.startups, startup_sites = excluded.startup_sites, startup_search = excluded.startup_search,
    industries = excluded.industries, industry_labels = excluded.industry_labels,
    stages = excluded.stages, stage_labels = excluded.stage_labels,
    legal_records = excluded.legal_records, refreshed_at = excluded.refreshed_at;
end
$$;

create or replace function public.refresh_firm_summary_all()
returns void language sql security definer set search_path = public, pg_temp as $$
  select refresh_firm_summary(array(select firm_id from v2_firms));
  delete from firm_summary s where not exists (select 1 from v2_firms f where f.firm_id = s.firm_id);
$$;

-- Trigger helpers. A failure here never blocks the original write: it only logs a warning,
-- and the hourly full refresh repairs the row.
create or replace function public.firm_summary_by_firm_trg()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare ids bigint[];
begin
  begin
    if tg_op = 'INSERT' then
      select array_agg(distinct firm_id) into ids from new_rows;
    elsif tg_op = 'DELETE' then
      select array_agg(distinct firm_id) into ids from old_rows;
    else
      select array_agg(distinct firm_id) into ids
        from (select firm_id from new_rows union select firm_id from old_rows) x;
    end if;
    perform refresh_firm_summary(array_remove(ids, null));
  exception when others then
    raise warning 'firm_summary refresh skipped (%): %', tg_table_name, sqlerrm;
  end;
  return null;
end
$$;

create or replace function public.firm_summary_by_startup_trg()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare sids bigint[]; ids bigint[];
begin
  begin
    if tg_op = 'INSERT' then
      select array_agg(distinct startup_id) into sids from new_rows;
    elsif tg_op = 'DELETE' then
      select array_agg(distinct startup_id) into sids from old_rows;
    else
      select array_agg(distinct startup_id) into sids
        from (select startup_id from new_rows union select startup_id from old_rows) x;
    end if;
    select array_agg(distinct d.firm_id) into ids from v2_deals d where d.startup_id = any(sids);
    perform refresh_firm_summary(array_remove(ids, null));
  exception when others then
    raise warning 'firm_summary refresh skipped (%): %', tg_table_name, sqlerrm;
  end;
  return null;
end
$$;

create or replace function public.firm_summary_all_trg()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  begin
    perform refresh_firm_summary_all();
  exception when others then
    raise warning 'firm_summary refresh skipped (%): %', tg_table_name, sqlerrm;
  end;
  return null;
end
$$;

do $$
declare t text; k text; r record;
begin
  for r in select * from (values
      ('v2_deals', 'firm'), ('v2_firms', 'firm'), ('v2_firm_live', 'firm'), ('v2_firm_industries', 'firm'),
      ('v2_firm_stages', 'firm'), ('v2_legal_items', 'firm'), ('v2_auto_published', 'firm'),
      ('v2_startups', 'startup'), ('v2_startup_sectors', 'startup')) v(tbl, keycol)
  loop
    t := r.tbl; k := r.keycol;
    execute format('drop trigger if exists firm_summary_ins on public.%I', t);
    execute format('drop trigger if exists firm_summary_upd on public.%I', t);
    execute format('drop trigger if exists firm_summary_del on public.%I', t);
    execute format('create trigger firm_summary_ins after insert on public.%I referencing new table as new_rows for each statement execute function public.firm_summary_by_%s_trg()', t, k);
    execute format('create trigger firm_summary_upd after update on public.%I referencing old table as old_rows new table as new_rows for each statement execute function public.firm_summary_by_%s_trg()', t, k);
    execute format('create trigger firm_summary_del after delete on public.%I referencing old table as old_rows for each statement execute function public.firm_summary_by_%s_trg()', t, k);
  end loop;
end
$$;

drop trigger if exists firm_summary_sector on public.v2_sector;
create trigger firm_summary_sector after insert or update or delete on public.v2_sector
  for each statement execute function public.firm_summary_all_trg();

revoke all on function public.refresh_firm_summary(bigint[]) from public, anon, authenticated;
revoke all on function public.refresh_firm_summary_all() from public, anon, authenticated;

-- Fill it now.
select public.refresh_firm_summary_all();

-- Safety net: full refresh every hour (repairs anything a trigger skipped).
select cron.schedule('firm-summary-refresh', '23 * * * *', 'select public.refresh_firm_summary_all()');

-- Same inputs and output as firm_directory_page, but reads firm_summary instead of counting deals.
create or replace function public.firm_directory_page_v2(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0, p_sort text DEFAULT 'newest'::text, p_asc boolean DEFAULT false, p_search text[] DEFAULT NULL::text[], p_region text[] DEFAULT NULL::text[], p_industry text[] DEFAULT NULL::text[], p_stage text[] DEFAULT NULL::text[], p_legal text[] DEFAULT NULL::text[], p_info text[] DEFAULT NULL::text[], p_status text[] DEFAULT NULL::text[])
returns json
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '5s'
as $function$
declare
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 100);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_sort text := case when p_sort in ('newest', 'name', 'city', 'deal', 'deals', 'activity') then p_sort else 'newest' end;
  v_asc boolean := coalesce(p_asc, false);
  v_terms text[]; v_regions text[]; v_industries text[]; v_stages text[]; v_legal text[]; v_info text[]; v_status text[];
  v_y int := extract(year from current_date)::int;
  v_y0 int := extract(year from current_date)::int - case when extract(month from current_date) < 6 then 1 else 0 end;
  v_12m date := current_date - 365;
  v_total int := 0;
  v_rows json := '[]'::json;
  v_facets json := null;
begin
  select coalesce(array_agg(distinct left(lower(btrim(t)), 80)), '{}') into v_terms
    from unnest(coalesce(p_search, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct btrim(t)), '{}') into v_regions
    from unnest(coalesce(p_region, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct lower(btrim(t))), '{}') into v_industries
    from unnest(coalesce(p_industry, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct lower(btrim(t))), '{}') into v_stages
    from unnest(coalesce(p_stage, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct btrim(t)), '{}') into v_legal
    from unnest(coalesce(p_legal, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct btrim(t)), '{}') into v_info
    from unnest(coalesce(p_info, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';
  select coalesce(array_agg(distinct btrim(t)), '{}') into v_status
    from unnest(coalesce(p_status, '{}'::text[])) t where btrim(coalesce(t, '')) <> '';

  with m as (
    select s.*,
           (select count(*) from unnest(s.dated_dates) x
             where extract(year from x) between v_y0 and v_y)::int as deals_this_year
      from firm_summary s
     where s.listed
       and (cardinality(v_status) = 0 or s.firm_status = any(v_status))
       and (cardinality(v_regions) = 0 or s.region = any(v_regions))
       and (cardinality(v_terms) = 0 or exists (
             select 1 from unnest(v_terms) term
              where strpos(lower(coalesce(s.display_name, '')), term) > 0
                 or strpos(lower(coalesce(s.short_name, '')), term) > 0
                 or strpos(lower(coalesce(s.website_url, '')), term) > 0
                 or strpos(s.startup_search, term) > 0))
       and (cardinality(v_industries) = 0 or exists (
             select 1 from unnest(s.industry_labels) x where lower(x) = any(v_industries)))
       and (cardinality(v_stages) = 0 or exists (
             select 1 from unnest(s.stage_labels) x where lower(x) = any(v_stages)))
       and (cardinality(v_legal) = 0
            or ('has' = any(v_legal) and s.legal_records > 0)
            or ('unknown' = any(v_legal) and s.legal_records = 0))
       and (not ('deals' = any(v_info)) or s.latest_deal_date >= v_12m)
       and (not ('lead' = any(v_info)) or s.latest_led_date >= v_12m)
       and (not ('legal' = any(v_info)) or s.legal_records > 0)
  ),
  o as (
    select m.*, count(*) over () as total,
           row_number() over (order by
             -- name
             case when v_sort = 'name' and v_asc then m.display_name end asc nulls last,
             case when v_sort = 'name' and not v_asc then m.display_name end desc nulls last,
             -- city
             case when v_sort = 'city' and v_asc then nullif(m.city_label, '') end asc nulls last,
             case when v_sort = 'city' and not v_asc then nullif(m.city_label, '') end desc nulls last,
             -- latest deal
             case when v_sort = 'deal' and v_asc then m.latest_deal_date end asc nulls last,
             case when v_sort = 'deal' and not v_asc then m.latest_deal_date end desc nulls last,
             -- investments
             case when v_sort = 'deals' and v_asc then nullif(m.investments, 0) end asc nulls last,
             case when v_sort = 'deals' and not v_asc then nullif(m.investments, 0) end desc nulls last,
             -- activity
             case when v_sort = 'activity' and v_asc then
               case when m.deals_this_year >= 3 then 3 when m.deals_this_year >= 1 then 2 when m.deals > 0 then 1 else 0 end end asc,
             case when v_sort = 'activity' and not v_asc then
               case when m.deals_this_year >= 3 then 3 when m.deals_this_year >= 1 then 2 when m.deals > 0 then 1 else 0 end end desc,
             case when v_sort = 'activity' and v_asc then m.deals_this_year end asc,
             case when v_sort = 'activity' and not v_asc then m.deals_this_year end desc,
             case when v_sort = 'activity' and v_asc then m.deals end asc,
             case when v_sort = 'activity' and not v_asc then m.deals end desc,
             -- newest
             case when v_sort = 'newest' and v_asc then m.added end asc nulls last,
             case when v_sort = 'newest' and not v_asc then m.added end desc nulls last,
             -- tie-breakers (same for every sort)
             case when v_asc then m.display_name end asc nulls last,
             case when not v_asc then m.display_name end desc nulls last,
             case when v_asc then m.firm_id end asc nulls last,
             case when not v_asc then m.firm_id end desc nulls last
           ) as ord
      from m
  )
  select coalesce(max(o.total), 0)::int,
         coalesce(json_agg(json_build_object(
           'slug', o.slug, 'name', o.display_name, 'short_name', nullif(o.short_name, ''), 'website', o.website_url,
           'city', o.hq_city, 'state', o.hq_state, 'country', case when o.hq_country ~ '^[A-Z]{2}$' then o.hq_country end,
           'added', o.added, 'firm_status', o.firm_status,
           'industries', coalesce(o.industries, '[]'::json),
           'stages', coalesce(o.stages, '[]'::json),
           'deals', o.deals, 'investments', o.investments, 'deals_this_year', o.deals_this_year,
           'deals_12m', (select count(*) from unnest(o.dated_dates) x where x >= v_12m),
           'led_12m', (select count(*) from unnest(o.led_dates) x where x >= v_12m),
           'latest_company', o.latest_company, 'latest_round', o.latest_round, 'latest_deal_date', o.latest_deal_date,
           'legal_records', o.legal_records, 'legal_status', case when o.legal_records > 0 then 'has' else 'unknown' end,
           'startups', coalesce(to_json(o.startups), '[]'::json), 'startup_sites', coalesce(to_json(o.startup_sites), '[]'::json)
         ) order by o.ord) filter (where o.ord > v_off and o.ord <= v_off + v_lim), '[]'::json)
    into v_total, v_rows
    from o;

  -- Sidebar counts for the first page only. They are the whole directory, not the filtered page.
  if v_off = 0 then
    with live as (select * from firm_summary where listed)
    select json_build_object(
      'region', coalesce((
        select json_agg(json_build_object('value', region, 'count', n))
          from (select region, count(*) as n from live group by 1) r
      ), '[]'::json),
      'industry', coalesce((
        select json_agg(json_build_object('value', value, 'label', label, 'count', n) order by n desc, label)
          from (
            select lower(x) as value,
                   (array_agg(x order by (x = lower(x)), length(x) desc))[1] as label,
                   count(distinct lv.firm_id) as n
              from live lv cross join unnest(lv.industry_labels) x
             group by lower(x)
          ) ind
      ), '[]'::json),
      'stage', coalesce((
        select json_agg(json_build_object('value', value, 'label', label, 'count', n) order by n desc, label)
          from (
            select lower(x) as value,
                   (array_agg(x order by (x = lower(x)), length(x) desc))[1] as label,
                   count(distinct lv.firm_id) as n
              from live lv cross join unnest(lv.stage_labels) x
             group by lower(x)
          ) st
      ), '[]'::json),
      'legal', json_build_array(
        json_build_object('value', 'has', 'count', (select count(*) from live where legal_records > 0)),
        json_build_object('value', 'unknown', 'count', (select count(*) from live where legal_records = 0)),
        json_build_object('value', 'none', 'count', 0)
      ),
      'info', json_build_array(
        json_build_object('value', 'deals', 'count', (select count(*) from live where latest_deal_date >= v_12m)),
        json_build_object('value', 'lead', 'count', (select count(*) from live where latest_led_date >= v_12m)),
        json_build_object('value', 'legal', 'count', (select count(*) from live where legal_records > 0))
      ),
      'status', coalesce((
        select json_agg(json_build_object('value', firm_status, 'label', firm_status, 'count', n) order by n desc, firm_status)
          from (select firm_status, count(*) as n from live group by firm_status) st
      ), '[]'::json)
    )
    into v_facets;
  end if;

  return json_build_object('rows', v_rows, 'total', v_total, 'facets', v_facets);
end
$function$;

revoke all on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) from public;
grant execute on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) to anon, authenticated, service_role;
