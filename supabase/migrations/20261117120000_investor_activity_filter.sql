-- Investors list: the status menu uses the activity rank the directory already
-- sorts by, which is the same rule as RegretActivity in launch/js/dates.js.
-- 3 Active (deals this year >= 3), 2 Low activity (>= 1), 1 Not active
-- (dated deals > 0), 0 Not checked yet. deals_this_year is the same count the
-- row already returns, so a status filter matches the Activity column.
-- Counts for an unfiltered page come from that same pass. A narrowed page
-- counts the whole directory in one extra pass, skipping firms with no dated
-- deals. Statement timeout stays 5s.
-- Old firm_status values in p_status are ignored. p_legal and p_info stay.
-- Not applied by this change.
-- Rollback: supabase/rollbacks/20261117120000_investor_activity_filter.sql

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
  v_terms text[]; v_regions text[]; v_industries text[]; v_stages text[]; v_legal text[]; v_info text[]; v_ranks int[] := '{}';
  v_y int := extract(year from current_date)::int;
  v_y0 int := extract(year from current_date)::int - case when extract(month from current_date) < 6 then 1 else 0 end;
  v_12m date := current_date - 365;
  v_narrow boolean := false;
  v_total int := 0;
  v_rows json := '[]'::json;
  v_status_facet json := null;
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
  -- Activity ranks only. Old firm_status text is ignored, so an old link does not empty the list.
  select coalesce(array_agg(distinct btrim(t)::int), '{}') into v_ranks
    from unnest(coalesce(p_status, '{}'::text[])) t where btrim(coalesce(t, '')) ~ '^[0-3]$';
  v_narrow := cardinality(v_regions) > 0 or cardinality(v_terms) > 0 or cardinality(v_industries) > 0
    or cardinality(v_stages) > 0 or cardinality(v_legal) > 0 or cardinality(v_info) > 0;

  with scored as materialized (
    select s.*,
           (select count(*) from unnest(s.dated_dates) x
             where extract(year from x) between v_y0 and v_y)::int as deals_this_year
      from firm_summary s
     where s.listed
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
  m as (
    select scored.*,
           case when scored.deals_this_year >= 3 then 3 when scored.deals_this_year >= 1 then 2 when scored.deals > 0 then 1 else 0 end as activity_rank
      from scored
     where cardinality(v_ranks) = 0
        or (case when scored.deals_this_year >= 3 then 3 when scored.deals_this_year >= 1 then 2 when scored.deals > 0 then 1 else 0 end) = any(v_ranks)
  ),
  o as (
    select m.*, count(*) over () as total,
           row_number() over (order by
             case when v_sort = 'name' and v_asc then m.display_name end asc nulls last,
             case when v_sort = 'name' and not v_asc then m.display_name end desc nulls last,
             case when v_sort = 'city' and v_asc then nullif(m.city_label, '') end asc nulls last,
             case when v_sort = 'city' and not v_asc then nullif(m.city_label, '') end desc nulls last,
             case when v_sort = 'deal' and v_asc then m.latest_deal_date end asc nulls last,
             case when v_sort = 'deal' and not v_asc then m.latest_deal_date end desc nulls last,
             case when v_sort = 'deals' and v_asc then nullif(m.investments, 0) end asc nulls last,
             case when v_sort = 'deals' and not v_asc then nullif(m.investments, 0) end desc nulls last,
             case when v_sort = 'activity' and v_asc then m.activity_rank end asc,
             case when v_sort = 'activity' and not v_asc then m.activity_rank end desc,
             case when v_sort = 'activity' and v_asc then m.deals_this_year end asc,
             case when v_sort = 'activity' and not v_asc then m.deals_this_year end desc,
             case when v_sort = 'activity' and v_asc then m.deals end asc,
             case when v_sort = 'activity' and not v_asc then m.deals end desc,
             case when v_sort = 'newest' and v_asc then m.added end asc nulls last,
             case when v_sort = 'newest' and not v_asc then m.added end desc nulls last,
             case when v_asc then m.display_name end asc nulls last,
             case when not v_asc then m.display_name end desc nulls last,
             case when v_asc then m.firm_id end asc nulls last,
             case when not v_asc then m.firm_id end desc nulls last
           ) as ord
      from m
  ),
  page as (
    select coalesce(max(o.total), 0)::int as total,
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
           ) order by o.ord) filter (where o.ord > v_off and o.ord <= v_off + v_lim), '[]'::json) as rows
      from o
  ),
  status_counts as (
    select case when v_off <> 0 or v_narrow then null::json else (
      select json_build_array(
        json_build_object('value', '3', 'count', count(*) filter (where r = 3)),
        json_build_object('value', '2', 'count', count(*) filter (where r = 2)),
        json_build_object('value', '1', 'count', count(*) filter (where r = 1)),
        json_build_object('value', '0', 'count', count(*) filter (where r = 0))
      )
      from (
        select case when deals_this_year >= 3 then 3 when deals_this_year >= 1 then 2 when deals > 0 then 1 else 0 end as r
          from scored
      ) z
    ) end as facet
  )
  select page.total, page.rows, status_counts.facet
    into v_total, v_rows, v_status_facet
    from page cross join status_counts;

  if v_off = 0 and v_status_facet is null then
    select json_build_array(
      json_build_object('value', '3', 'count', count(*) filter (where r = 3)),
      json_build_object('value', '2', 'count', count(*) filter (where r = 2)),
      json_build_object('value', '1', 'count', count(*) filter (where r = 1)),
      json_build_object('value', '0', 'count', count(*) filter (where r = 0))
    )
      into v_status_facet
      from (
        select case
                 when coalesce(s.deals, 0) <= 0 then 0
                 else (
                   select case when n >= 3 then 3 when n >= 1 then 2 else 1 end
                     from (
                       select count(*)::int as n
                         from unnest(s.dated_dates) d
                        where extract(year from d) between v_y0 and v_y
                     ) c
                 )
               end as r
          from firm_summary s
         where s.listed
      ) z;
  end if;

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
      'status', coalesce(v_status_facet, json_build_array(
        json_build_object('value', '3', 'count', 0),
        json_build_object('value', '2', 'count', 0),
        json_build_object('value', '1', 'count', 0),
        json_build_object('value', '0', 'count', 0)
      ))
    )
    into v_facets;
  end if;

  return json_build_object('rows', v_rows, 'total', v_total, 'facets', v_facets);
end
$function$;
$fn$;
    execute $fn$
revoke all on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) from public;
$fn$;
    execute $fn$
grant execute on function public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]) to anon, authenticated, service_role;
$fn$;
  end if;
end
$mig$;
