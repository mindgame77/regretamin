-- v2_map_fold_crown_dependencies_into_gb (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_fold_crown_dependencies_into_gb skipped';
    return;
  end if;
  execute $designmig$
-- Guernsey, Jersey and the Isle of Man are registration addresses. On the Europe view of the map their firms
-- are shown as part of the United Kingdom. Only the "area" of the view changes; region and level stay as they were.
do $mig$
declare d text; n text;
begin
  d := pg_get_viewdef('public.v2_map_firm_places'::regclass, true);
  n := regexp_replace(d, 'ELSE hq_country(\s+)END AS area',
       E'ELSE CASE WHEN hq_country::text = ANY (ARRAY[''GG'', ''JE'', ''IM'']) THEN ''GB'' ELSE hq_country::text END\\1END AS area');
  if n = d then raise exception 'v2_map_firm_places: expected text not found, nothing changed'; end if;
  execute 'create or replace view public.v2_map_firm_places with (security_invoker = true) as ' || n;
end
$mig$;
$designmig$;
end
$wrapci$;
