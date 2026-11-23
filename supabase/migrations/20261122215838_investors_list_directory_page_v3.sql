-- investors_list_directory_page_v3 (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_directory_page_v3 skipped';
    return;
  end if;
  execute $designmig$
-- firm_directory_page_v3: a copy of firm_directory_page_v2 with signals, the "Deals this year" filter and name-only search.
-- firm_directory_page_v2 is not touched; the live site keeps using it.
do $$
declare s text; o text;
  procedure_dummy int;
begin
  s := pg_get_functiondef('public.firm_directory_page_v2(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[])'::regprocedure);

  o := s; s := replace(s, 'FUNCTION public.firm_directory_page_v2(', 'FUNCTION public.firm_directory_page_v3(');
  if s = o then raise exception 'step 1'; end if;
  o := s; s := replace(s, 'p_status text[] DEFAULT NULL::text[])', 'p_status text[] DEFAULT NULL::text[], p_signals text[] DEFAULT NULL::text[], p_deals_year text DEFAULT NULL::text)');
  if s = o then raise exception 'step 2'; end if;
  o := s; s := replace(s, E'  v_total int := 0;\n', E'  v_total int := 0;\n  v_signals text[] := ''{}'';\n  v_dy text := case when p_deals_year in (''lt5'', ''5'', ''10'', ''25'') then p_deals_year end;\n');
  if s = o then raise exception 'step 3'; end if;
  o := s; s := replace(s, E'  v_narrow := cardinality(v_regions) > 0',
    E'  select coalesce(array_agg(distinct btrim(t)), ''{}'') into v_signals\n    from unnest(coalesce(p_signals, ''{}''::text[])) t where btrim(coalesce(t, '''')) in (''up'', ''down'', ''top'', ''chain'', ''lead'', ''spec'', ''fund'');\n  v_narrow := cardinality(v_signals) > 0 or v_dy is not null or cardinality(v_regions) > 0');
  if s = o then raise exception 'step 4'; end if;
  o := s; s := replace(s, E'    select s.*,\n           (select count(*) from unnest(s.dated_dates) x',
    E'    select s.*, coalesce(g.signals, ''{}''::text[]) as signals, coalesce(g.deals_now, 0) as deals_now, coalesce(g.deals_prev, 0) as deals_prev, coalesce(g.led_now, 0) as led_now,\n           (select count(*) from unnest(s.dated_dates) x');
  if s = o then raise exception 'step 5'; end if;
  o := s; s := replace(s, E'      from firm_summary s\n     where s.listed\n       and (cardinality(v_regions) = 0',
    E'      from firm_summary s left join v2_firm_signals g on g.firm_id = s.firm_id\n     where s.listed\n       and (cardinality(v_signals) = 0 or coalesce(g.signals, ''{}''::text[]) @> v_signals)\n       and (v_dy is null or case v_dy when ''lt5'' then coalesce(g.deals_now, 0) < 5 when ''5'' then coalesce(g.deals_now, 0) >= 5 when ''10'' then coalesce(g.deals_now, 0) >= 10 else coalesce(g.deals_now, 0) >= 25 end)\n       and (cardinality(v_regions) = 0');
  if s = o then raise exception 'step 6'; end if;
  o := s; s := replace(s, E'\n                 or strpos(s.startup_search, term) > 0', '');
  if s = o then raise exception 'step 7'; end if;
  o := s; s := replace(s, E'''startups'', coalesce(to_json(o.startups), ''[]''::json), ''startup_sites'', coalesce(to_json(o.startup_sites), ''[]''::json)',
    E'''signals'', to_json(o.signals), ''deals_now'', o.deals_now, ''deals_prev'', o.deals_prev, ''led_now'', o.led_now');
  if s = o then raise exception 'step 8'; end if;
  o := s; s := replace(s, E'      ''status'', coalesce(v_status_facet, json_build_array(',
    E'      ''signals'', (select json_agg(json_build_object(''value'', k, ''count'', (select count(*) from v2_firm_signals g join live lv on lv.firm_id = g.firm_id where k = any(g.signals)))) from unnest(array[''up'', ''down'', ''top'', ''chain'', ''lead'', ''spec'', ''fund'']) k),\n      ''deals_year'', (select json_build_array(\n        json_build_object(''value'', ''lt5'', ''count'', count(*) filter (where coalesce(g.deals_now, 0) < 5)),\n        json_build_object(''value'', ''5'', ''count'', count(*) filter (where coalesce(g.deals_now, 0) >= 5)),\n        json_build_object(''value'', ''10'', ''count'', count(*) filter (where coalesce(g.deals_now, 0) >= 10)),\n        json_build_object(''value'', ''25'', ''count'', count(*) filter (where coalesce(g.deals_now, 0) >= 25))) from live lv left join v2_firm_signals g on g.firm_id = lv.firm_id),\n      ''status'', coalesce(v_status_facet, json_build_array(');
  if s = o then raise exception 'step 9'; end if;
  execute s;
end $$;
revoke all on function public.firm_directory_page_v3(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text) from public;
grant execute on function public.firm_directory_page_v3(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text) to anon, authenticated;
$designmig$;
end
$wrapci$;
