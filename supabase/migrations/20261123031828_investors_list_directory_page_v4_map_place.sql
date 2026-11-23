-- investors_list_directory_page_v4_map_place (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_directory_page_v4_map_place skipped';
    return;
  end if;
  execute $designmig$
-- Investors list, version 4: a copy of firm_directory_page_v3 with one more optional filter, "place on the map"
-- (the same places the map uses, from v2_map_firm_places). v3 is left untouched. Nothing else changes.
do $$
declare s text; n text;
begin
  s := pg_get_functiondef((select oid from pg_proc where proname = 'firm_directory_page_v3' and pronamespace = 'public'::regnamespace));
  n := replace(s, 'public.firm_directory_page_v3(', 'public.firm_directory_page_v4(');
  n := replace(n, 'p_deals_year text DEFAULT NULL::text)', 'p_deals_year text DEFAULT NULL::text, p_place_level text DEFAULT NULL::text, p_place text DEFAULT NULL::text)');
  n := replace(n, E'  v_facets json := null;\nbegin', E'  v_facets json := null;\n  v_plevel text := case when p_place_level in (''world'', ''us'', ''eu'') then p_place_level end;\n  v_place text := case when p_place_level in (''world'', ''us'', ''eu'') then nullif(btrim(coalesce(p_place, '''')), '''') end;\nbegin');
  n := replace(n, 'v_narrow := cardinality(v_signals) > 0 or', 'v_narrow := v_place is not null or cardinality(v_signals) > 0 or');
  n := replace(n, E'     where s.listed\n       and (cardinality(v_signals) = 0', E'     where s.listed\n       and (v_place is null or s.firm_id in (select mp.firm_id from v2_map_firm_places mp where (v_plevel = ''world'' and mp.region = v_place) or (v_plevel in (''us'', ''eu'') and mp.level = v_plevel and mp.area = v_place)))\n       and (cardinality(v_signals) = 0');
  if position('firm_directory_page_v4(' in n) = 0 or position('p_place text DEFAULT' in n) = 0 or position('v_plevel text :=' in n) = 0
     or position('v_narrow := v_place is not null' in n) = 0 or position('from v2_map_firm_places mp' in n) = 0 then
    raise exception 'firm_directory_page_v3 no longer has the expected text; v4 was not created';
  end if;
  execute n;
end $$;
revoke all on function public.firm_directory_page_v4(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[], text[], text, text, text) from public;
grant execute on function public.firm_directory_page_v4(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[], text[], text, text, text) to anon, authenticated, service_role;
$designmig$;
end
$wrapci$;
