-- Restore firm_directory_page_v2 from before the activity status filter.
-- Does not drop firm_summary or the directory function.
-- Run only to undo supabase/migrations/20261117120000_investor_activity_filter.sql.

do $mig$
begin
  if to_regprocedure('public.firm_directory_page_v2(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[])') is null then
    raise notice 'firm_directory_page_v2 missing, skipped';
  else
    execute $fn$
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
$fn$;
    execute 'revoke all on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) from public';
    execute 'grant execute on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) to anon, authenticated, service_role';
  end if;
end
$mig$;
