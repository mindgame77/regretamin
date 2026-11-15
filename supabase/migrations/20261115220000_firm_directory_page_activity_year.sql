-- Activity year for deals_this_year: previous UTC calendar year from January
-- through May 31, current UTC year from June 1 on. A YYYY-01-01 date counts
-- for that year. Only that comparison changes. Not applied by this change.

do $mig$
begin
  if to_regclass('public.v2_auto_published') is not null and to_regclass('public.v2_deals') is not null and to_regclass('public.v2_firm_industries') is not null and to_regclass('public.v2_firm_live') is not null and to_regclass('public.v2_firm_stages') is not null and to_regclass('public.v2_firms') is not null and to_regclass('public.v2_legal_items') is not null and to_regclass('public.v2_sector') is not null and to_regclass('public.v2_startup_sectors') is not null and to_regclass('public.v2_startups') is not null then
    execute $fn$
create or replace function public.firm_directory_page(
  p_limit int default 100,
  p_offset int default 0,
  p_sort text default 'newest',
  p_asc boolean default false,
  p_search text[] default null,
  p_region text[] default null,
  p_industry text[] default null,
  p_stage text[] default null,
  p_legal text[] default null,
  p_info text[] default null,
  p_status text[] default null
) returns json
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
set statement_timeout to '3s'
as $body$
declare
  v_lim int := least(greatest(coalesce(p_limit, 100), 1), 100);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_sort text := case when p_sort in ('newest', 'name', 'city', 'deal', 'deals', 'activity') then p_sort else 'newest' end;
  v_asc boolean := coalesce(p_asc, false);
  v_terms text[] := '{}';
  v_regions text[] := '{}';
  v_industries text[] := '{}';
  v_stages text[] := '{}';
  v_legal text[] := '{}';
  v_info text[] := '{}';
  v_status text[] := '{}';
  v_startup_ids bigint[] := '{}';
  v_ind_ids bigint[] := '{}';
  v_stage_ids bigint[] := '{}';
  v_legal_ids bigint[] := '{}';
  v_deals_ids bigint[] := '{}';
  v_led_ids bigint[] := '{}';
  v_matched bigint[] := '{}';
  v_page bigint[] := '{}';
  v_total int := 0;
  v_rows json := '[]'::json;
  v_facets json := null;
begin
  select coalesce(array_agg(distinct left(lower(btrim(t)), 80)), '{}')
    into v_terms
  from unnest(coalesce(p_search, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct btrim(t)), '{}') into v_regions
  from unnest(coalesce(p_region, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct lower(btrim(t))), '{}') into v_industries
  from unnest(coalesce(p_industry, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct lower(btrim(t))), '{}') into v_stages
  from unnest(coalesce(p_stage, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct btrim(t)), '{}') into v_legal
  from unnest(coalesce(p_legal, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct btrim(t)), '{}') into v_info
  from unnest(coalesce(p_info, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  select coalesce(array_agg(distinct btrim(t)), '{}') into v_status
  from unnest(coalesce(p_status, '{}'::text[])) t
  where btrim(coalesce(t, '')) <> '';

  -- One pass over deals for a startup/site search. A per-firm lookup has no firm_id index and is slow.
  if cardinality(v_terms) > 0 then
    select coalesce(array_agg(distinct d.firm_id), '{}')
      into v_startup_ids
    from v2_deals d
    join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
    where d.is_current and not d.archived
      and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
      and exists (
        select 1 from unnest(v_terms) term
        where strpos(lower(coalesce(s.startup_name, '')), term) > 0
           or strpos(lower(coalesce(s.domain, '')), term) > 0
      );
  end if;

  -- Industries on the firm win. Deal sectors count only when the firm has none. Same rule as firm_directory.
  if cardinality(v_industries) > 0 then
    select coalesce(array_agg(distinct firm_id), '{}')
      into v_ind_ids
    from (
      select i.firm_id
        from v2_firm_industries i
       where i.is_current and not i.archived
         and nullif(btrim(i.industry_text), '') is not null
         and lower(btrim(i.industry_text)) = any(v_industries)
      union
      select d.firm_id
        from v2_deals d
        join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
        join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current and not ss.archived
        join v2_sector sc on sc.sector_id = ss.sector_id
       where d.is_current and not d.archived
         and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
         and lower(sc.name) = any(v_industries)
         and not exists (
           select 1 from v2_firm_industries i
            where i.firm_id = d.firm_id and i.is_current and not i.archived
              and nullif(btrim(i.industry_text), '') is not null
         )
    ) hits;
  end if;

  if cardinality(v_stages) > 0 then
    select coalesce(array_agg(distinct s.firm_id), '{}')
      into v_stage_ids
    from v2_firm_stages s
    where s.is_current and not s.archived
      and nullif(btrim(s.stage), '') is not null
      and lower(btrim(s.stage)) = any(v_stages);
  end if;

  if cardinality(v_legal) > 0 or 'legal' = any(v_info) or v_off = 0 then
    select coalesce(array_agg(distinct firm_id), '{}')
      into v_legal_ids
    from v2_legal_items
    where is_current and not archived and not nothing_found and not coalesce(lead_only, false);
  end if;

  if 'deals' = any(v_info) or 'lead' = any(v_info) or v_off = 0 then
    select coalesce(array_agg(firm_id) filter (where deals_12m > 0), '{}'),
           coalesce(array_agg(firm_id) filter (where led_12m > 0), '{}')
      into v_deals_ids, v_led_ids
    from (
      select d.firm_id,
             count(*) filter (where d.deal_date >= current_date - 365) as deals_12m,
             count(*) filter (where d.deal_date >= current_date - 365 and coalesce(d.lead = 'yes', false)) as led_12m
        from v2_deals d
        join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
       where d.is_current and not d.archived
         and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
         and d.deal_date >= current_date - 365
       group by d.firm_id
    ) x;
  end if;

  select coalesce(array_agg(f.firm_id), '{}')
    into v_matched
  from v2_firm_live l
  join v2_firms f on f.firm_id = l.firm_id
  where not coalesce(f.archived, false) and f.merged_into_firm_id is null and not coalesce(f.demand_hidden, false)
    and (cardinality(v_status) = 0 or coalesce(nullif(f.firm_status, ''), 'Active') = any(v_status))
    and (
      cardinality(v_regions) = 0
      or (
        case case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end
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
          else 'unknown'
        end
      ) = any(v_regions)
    )
    and (
      cardinality(v_terms) = 0
      or exists (
        select 1 from unnest(v_terms) term
        where strpos(lower(coalesce(f.display_name, '')), term) > 0
           or strpos(lower(coalesce(f.short_name, '')), term) > 0
           or strpos(lower(coalesce(f.website_url, '')), term) > 0
      )
      or f.firm_id = any(v_startup_ids)
    )
    and (cardinality(v_industries) = 0 or f.firm_id = any(v_ind_ids))
    and (cardinality(v_stages) = 0 or f.firm_id = any(v_stage_ids))
    and (
      cardinality(v_legal) = 0
      or ('has' = any(v_legal) and f.firm_id = any(v_legal_ids))
      or ('unknown' = any(v_legal) and not (f.firm_id = any(v_legal_ids)))
    )
    and (not ('deals' = any(v_info)) or f.firm_id = any(v_deals_ids))
    and (not ('lead' = any(v_info)) or f.firm_id = any(v_led_ids))
    and (not ('legal' = any(v_info)) or f.firm_id = any(v_legal_ids));

  v_total := cardinality(v_matched);

  if v_sort = 'name' then
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select f.firm_id,
             row_number() over (
               order by
                 case when v_asc then f.display_name end asc nulls last,
                 case when not v_asc then f.display_name end desc nulls last,
                 case when v_asc then f.firm_id end asc nulls last,
                 case when not v_asc then f.firm_id end desc nulls last
             ) as ord
        from unnest(v_matched) m(firm_id)
        join v2_firms f on f.firm_id = m.firm_id
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  elsif v_sort = 'city' then
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select f.firm_id,
             row_number() over (
               order by
                 case when v_asc then nullif(s.city_label, '') end asc nulls last,
                 case when not v_asc then nullif(s.city_label, '') end desc nulls last,
                 case when v_asc then f.display_name end asc nulls last,
                 case when not v_asc then f.display_name end desc nulls last,
                 case when v_asc then f.firm_id end asc nulls last,
                 case when not v_asc then f.firm_id end desc nulls last
             ) as ord
        from (
          select f.firm_id, f.display_name,
                 case
                   when nullif(btrim(f.hq_city), '') is not null then
                     case when btrim(f.hq_city) = upper(btrim(f.hq_city)) and char_length(btrim(f.hq_city)) > 3
                       then initcap(lower(btrim(f.hq_city))) else btrim(f.hq_city) end
                   when upper(btrim(f.hq_country)) = 'US' then 'United States'
                   when upper(btrim(f.hq_country)) = 'GB' then 'United Kingdom'
                   when upper(btrim(f.hq_country)) = 'CH' then 'Switzerland'
                   when upper(btrim(f.hq_country)) = 'KY' then 'Cayman Islands'
                   else ''
                 end as city_label
            from unnest(v_matched) m(firm_id)
            join v2_firms f on f.firm_id = m.firm_id
        ) s
        join v2_firms f on f.firm_id = s.firm_id
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  elsif v_sort = 'deal' then
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select f.firm_id,
             row_number() over (
               order by
                 case when v_asc then lt.deal_date end asc nulls last,
                 case when not v_asc then lt.deal_date end desc nulls last,
                 case when v_asc then f.display_name end asc nulls last,
                 case when not v_asc then f.display_name end desc nulls last,
                 case when v_asc then f.firm_id end asc nulls last,
                 case when not v_asc then f.firm_id end desc nulls last
             ) as ord
        from unnest(v_matched) m(firm_id)
        join v2_firms f on f.firm_id = m.firm_id
        left join (
          select d.firm_id, max(d.deal_date) as deal_date
            from v2_deals d
            join v2_startups su on su.startup_id = d.startup_id and su.is_current and not su.archived
           where d.firm_id = any(v_matched)
             and d.is_current and not d.archived
             and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
           group by d.firm_id
        ) lt on lt.firm_id = f.firm_id
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  elsif v_sort = 'deals' then
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select f.firm_id,
             row_number() over (
               order by
                 case when v_asc then dc.deals end asc nulls last,
                 case when not v_asc then dc.deals end desc nulls last,
                 case when v_asc then f.display_name end asc nulls last,
                 case when not v_asc then f.display_name end desc nulls last,
                 case when v_asc then f.firm_id end asc nulls last,
                 case when not v_asc then f.firm_id end desc nulls last
             ) as ord
        from unnest(v_matched) m(firm_id)
        join v2_firms f on f.firm_id = m.firm_id
        left join (
          select d.firm_id, count(*) as deals
            from v2_deals d
            join v2_startups su on su.startup_id = d.startup_id and su.is_current and not su.archived
           where d.firm_id = any(v_matched)
             and d.is_current and not d.archived
             and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
           group by d.firm_id
        ) dc on dc.firm_id = f.firm_id
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  elsif v_sort = 'activity' then
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select s.firm_id,
             row_number() over (
               order by
                 case when v_asc then s.activity_rank end asc,
                 case when not v_asc then s.activity_rank end desc,
                 case when v_asc then s.deals_this_year end asc,
                 case when not v_asc then s.deals_this_year end desc,
                 case when v_asc then s.deals end asc,
                 case when not v_asc then s.deals end desc,
                 case when v_asc then s.display_name end asc nulls last,
                 case when not v_asc then s.display_name end desc nulls last,
                 case when v_asc then s.firm_id end asc,
                 case when not v_asc then s.firm_id end desc
             ) as ord
        from (
          select f.firm_id, f.display_name,
                 coalesce(dc.deals, 0) as deals,
                 coalesce(dc.deals_this_year, 0) as deals_this_year,
                 case
                   when coalesce(dc.deals_this_year, 0) >= 3 then 3
                   when coalesce(dc.deals_this_year, 0) >= 1 then 2
                   when coalesce(dc.deals, 0) > 0 then 1
                   else 0
                 end as activity_rank
            from unnest(v_matched) m(firm_id)
            join v2_firms f on f.firm_id = m.firm_id
            left join (
              select d.firm_id,
                     count(*) as deals,
                     count(*) filter (where extract(year from d.deal_date) = extract(year from current_date) - case when extract(month from current_date) < 6 then 1 else 0 end) as deals_this_year
                from v2_deals d
                join v2_startups su on su.startup_id = d.startup_id and su.is_current and not su.archived
               where d.firm_id = any(v_matched)
                 and d.is_current and not d.archived
                 and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
               group by d.firm_id
            ) dc on dc.firm_id = f.firm_id
        ) s
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  else
    select coalesce(array_agg(s.firm_id order by s.ord), '{}')
      into v_page
    from (
      select f.firm_id,
             row_number() over (
               order by
                 case when v_asc then coalesce(p.last_fact, l.live_since) end asc nulls last,
                 case when not v_asc then coalesce(p.last_fact, l.live_since) end desc nulls last,
                 case when v_asc then f.display_name end asc nulls last,
                 case when not v_asc then f.display_name end desc nulls last,
                 case when v_asc then f.firm_id end asc nulls last,
                 case when not v_asc then f.firm_id end desc nulls last
             ) as ord
        from unnest(v_matched) m(firm_id)
        join v2_firms f on f.firm_id = m.firm_id
        join v2_firm_live l on l.firm_id = m.firm_id
        left join (
          select firm_id, max(applied_at) as last_fact
            from v2_auto_published
           where firm_id = any(v_matched)
           group by firm_id
        ) p on p.firm_id = f.firm_id
    ) s
    where s.ord > v_off and s.ord <= v_off + v_lim;
  end if;

  if cardinality(v_page) > 0 then
    select coalesce(json_agg(row_obj order by ord), '[]'::json)
      into v_rows
    from (
      with page as (
        select u.firm_id, u.ord
          from unnest(v_page) with ordinality as u(firm_id, ord)
      ),
      live as (
        select u.ord, f.firm_id, l.slug, l.live_since, f.display_name, f.short_name, f.website_url,
               f.hq_city, f.hq_state, upper(btrim(f.hq_country)) as hq_country,
               coalesce(nullif(f.firm_status, ''), 'Active') as firm_status
          from page u
          join v2_firm_live l on l.firm_id = u.firm_id
          join v2_firms f on f.firm_id = u.firm_id
      ),
      d as (
        select d.firm_id, s.startup_id, s.startup_name, s.domain, d.round, d.deal_date,
               coalesce(d.lead = 'yes', false) as led
          from v2_deals d
          join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
         where d.firm_id = any(v_page) and d.is_current and not d.archived
           and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
      ),
      dagg as (
        select firm_id, count(*) as deals,
               count(*) filter (where extract(year from deal_date) = extract(year from current_date) - case when extract(month from current_date) < 6 then 1 else 0 end) as deals_this_year,
               count(*) filter (where deal_date >= current_date - 365) as deals_12m,
               count(*) filter (where deal_date >= current_date - 365 and led) as led_12m,
               array_agg(distinct startup_name) filter (where startup_name is not null) as startups,
               array_agg(distinct domain) filter (where nullif(domain, '') is not null) as startup_sites
          from d group by firm_id
      ),
      latest as (
        select distinct on (firm_id) firm_id, startup_name, round, deal_date
          from d order by firm_id, deal_date desc, startup_name
      ),
      inds as (
        select i.firm_id, json_agg(i.industry_text order by i.position, i.id) as industries
          from v2_firm_industries i
         where i.firm_id = any(v_page) and i.is_current and not i.archived
           and nullif(btrim(i.industry_text), '') is not null
         group by i.firm_id
      ),
      dsec as (
        select firm_id, json_agg(name order by n desc, name) as industries from (
          select d.firm_id, sc.name, count(*) n
            from d
            join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current and not ss.archived
            join v2_sector sc on sc.sector_id = ss.sector_id
           group by 1, 2
        ) x group by firm_id
      ),
      stg as (
        select firm_id, json_agg(distinct stage) as stages
          from v2_firm_stages
         where firm_id = any(v_page) and is_current and not archived and nullif(btrim(stage), '') is not null
         group by firm_id
      ),
      leg as (
        select firm_id, count(*) as n from v2_legal_items
         where firm_id = any(v_page) and is_current and not archived and not nothing_found and not coalesce(lead_only, false)
         group by firm_id
      ),
      pub as (
        select firm_id, max(applied_at) as last_fact
          from v2_auto_published
         where firm_id = any(v_page)
         group by firm_id
      )
      select l.ord,
             json_build_object(
               'slug', l.slug, 'name', l.display_name, 'short_name', nullif(l.short_name, ''), 'website', l.website_url,
               'city', l.hq_city, 'state', l.hq_state, 'country', case when l.hq_country ~ '^[A-Z]{2}$' then l.hq_country end,
               'added', coalesce(p.last_fact, l.live_since), 'firm_status', l.firm_status,
               'industries', coalesce(i.industries, ds.industries, '[]'::json),
               'stages', coalesce(st.stages, '[]'::json),
               'deals', coalesce(a.deals, 0), 'deals_this_year', coalesce(a.deals_this_year, 0),
               'deals_12m', coalesce(a.deals_12m, 0), 'led_12m', coalesce(a.led_12m, 0),
               'latest_company', lt.startup_name, 'latest_round', lt.round, 'latest_deal_date', lt.deal_date,
               'legal_records', coalesce(lg.n, 0), 'legal_status', case when lg.n > 0 then 'has' else 'unknown' end,
               'startups', coalesce(to_json(a.startups), '[]'::json), 'startup_sites', coalesce(to_json(a.startup_sites), '[]'::json)
             ) as row_obj
        from live l
        left join dagg a on a.firm_id = l.firm_id
        left join latest lt on lt.firm_id = l.firm_id
        left join inds i on i.firm_id = l.firm_id
        left join dsec ds on ds.firm_id = l.firm_id
        left join stg st on st.firm_id = l.firm_id
        left join leg lg on lg.firm_id = l.firm_id
        left join pub p on p.firm_id = l.firm_id
    ) built;
  end if;

  -- Sidebar counts for the first page only. They are the whole directory, not the filtered page.
  if v_off = 0 then
    with live as (
      select f.firm_id,
             coalesce(nullif(f.firm_status, ''), 'Active') as firm_status,
             case when upper(btrim(f.hq_country)) ~ '^[A-Z]{2}$' then upper(btrim(f.hq_country)) end as country
        from v2_firm_live l
        join v2_firms f on f.firm_id = l.firm_id
       where not coalesce(f.archived, false) and f.merged_into_firm_id is null and not coalesce(f.demand_hidden, false)
    )
    select json_build_object(
      'region', coalesce((
        select json_agg(json_build_object('value', value, 'count', n))
          from (
            select case country
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
                     else 'unknown'
                   end as value,
                   count(*) as n
              from live
             group by 1
          ) r
      ), '[]'::json),
      'industry', coalesce((
        select json_agg(json_build_object('value', value, 'label', label, 'count', n) order by n desc, label)
          from (
            select value,
                   (array_agg(label order by (label = lower(label)), length(label) desc))[1] as label,
                   count(distinct firm_id) as n
              from (
                select i.firm_id, lower(btrim(i.industry_text)) as value, btrim(i.industry_text) as label
                  from v2_firm_industries i
                  join live lv on lv.firm_id = i.firm_id
                 where i.is_current and not i.archived and nullif(btrim(i.industry_text), '') is not null
                union all
                select d.firm_id, lower(sc.name), sc.name
                  from v2_deals d
                  join live lv on lv.firm_id = d.firm_id
                  join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
                  join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current and not ss.archived
                  join v2_sector sc on sc.sector_id = ss.sector_id
                 where d.is_current and not d.archived
                   and coalesce(d.shown, true) and not d.nothing_found and d.deal_date is not null
                   and not exists (
                     select 1 from v2_firm_industries i
                      where i.firm_id = d.firm_id and i.is_current and not i.archived
                        and nullif(btrim(i.industry_text), '') is not null
                   )
              ) names
             group by value
          ) ind
      ), '[]'::json),
      'stage', coalesce((
        select json_agg(json_build_object('value', value, 'label', label, 'count', n) order by n desc, label)
          from (
            select lower(btrim(s.stage)) as value,
                   (array_agg(btrim(s.stage) order by (btrim(s.stage) = lower(btrim(s.stage))), length(btrim(s.stage)) desc))[1] as label,
                   count(distinct s.firm_id) as n
              from v2_firm_stages s
              join live lv on lv.firm_id = s.firm_id
             where s.is_current and not s.archived and nullif(btrim(s.stage), '') is not null
             group by lower(btrim(s.stage))
          ) st
      ), '[]'::json),
      'legal', json_build_array(
        json_build_object('value', 'has', 'count', (select count(*) from live lv where lv.firm_id = any(v_legal_ids))),
        json_build_object('value', 'unknown', 'count', (select count(*) from live lv where not (lv.firm_id = any(v_legal_ids)))),
        json_build_object('value', 'none', 'count', 0)
      ),
      'info', json_build_array(
        json_build_object('value', 'deals', 'count', (select count(*) from live lv where lv.firm_id = any(v_deals_ids))),
        json_build_object('value', 'lead', 'count', (select count(*) from live lv where lv.firm_id = any(v_led_ids))),
        json_build_object('value', 'legal', 'count', (select count(*) from live lv where lv.firm_id = any(v_legal_ids)))
      ),
      'status', coalesce((
        select json_agg(json_build_object('value', firm_status, 'label', firm_status, 'count', n) order by n desc, firm_status)
          from (
            select firm_status, count(*) as n from live group by firm_status
          ) st
      ), '[]'::json)
    )
    into v_facets;
  end if;

  return json_build_object('rows', coalesce(v_rows, '[]'::json), 'total', v_total, 'facets', v_facets);
end
$body$
$fn$;
    execute 'revoke all on function public.firm_directory_page(int, int, text, boolean, text[], text[], text[], text[], text[], text[], text[]) from public';
    execute 'grant execute on function public.firm_directory_page(int, int, text, boolean, text[], text[], text[], text[], text[], text[], text[]) to anon, authenticated';
    execute $cmt$comment on function public.firm_directory_page(int, int, text, boolean, text[], text[], text[], text[], text[], text[], text[]) is 'One page of the investors directory. Same row fields as firm_directory(). Does not replace it.'$cmt$;
  end if;
end
$mig$;
