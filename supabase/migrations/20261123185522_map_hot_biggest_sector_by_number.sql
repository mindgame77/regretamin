-- map_hot_biggest_sector_by_number (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: map_hot_biggest_sector_by_number skipped';
    return;
  end if;
  execute $designmig$
-- "Hot right now": each place also gets its biggest rise and biggest fall counted in deals ('hotn', 'coldn'),
-- next to the existing 'hot' and 'cold' (picked by percentage). Used when the map's unit switch is on "#".
-- Everything the two v2_map_hot functions returned before is unchanged.
do $$
declare r record; s text; n text;
begin
  for r in select oid from pg_proc where proname = 'v2_map_hot' and pronamespace = 'public'::regnamespace loop
    s := pg_get_functiondef(r.oid);
    n := replace(s, E'         order by lvl, place, (n - p)::float8 / greatest(p, 3) asc, p desc),\n',
      E'         order by lvl, place, (n - p)::float8 / greatest(p, 3) asc, p desc),\nhotn as (select distinct on (lvl, place) lvl, place, jsonb_build_array(name, n, p) j from s where n + p >= 10 and n > p\n         order by lvl, place, (n - p) desc, n desc, name),\ncoldn as (select distinct on (lvl, place) lvl, place, jsonb_build_array(name, n, p) j from s where n + p >= 10 and n < p\n          order by lvl, place, (n - p) asc, p desc, name),\n');
    n := replace(n, '''hot'', hot.j, ''cold'', cold.j)', '''hot'', hot.j, ''cold'', cold.j, ''hotn'', hotn.j, ''coldn'', coldn.j)');
    n := replace(n, 'from t left join hot using (lvl, place) left join cold using (lvl, place)', 'from t left join hot using (lvl, place) left join cold using (lvl, place) left join hotn using (lvl, place) left join coldn using (lvl, place)');
    if position('hotn as (select' in n) = 0 or position('''coldn'', coldn.j)' in n) = 0 or position('left join coldn using' in n) = 0 then
      raise exception 'v2_map_hot does not have the expected text; nothing was changed';
    end if;
    execute n;
  end loop;
end $$;
notify pgrst, 'reload schema';
$designmig$;
end
$wrapci$;
