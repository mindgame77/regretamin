-- map_functions_count_only_shown_deals (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: map_functions_count_only_shown_deals skipped';
    return;
  end if;
  execute $designmig$
do $$
declare r record; o text; s text; n int := 0;
begin
  for r in select p.oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public' and p.proname in ('v2_map_firms','v2_map_hot','v2_map_hot_detail','v2_map_summary','v2_map_updates') loop
    o := pg_get_functiondef(r.oid);
    if o like '%.shown%' then raise exception 'already has shown: %', r.oid::regprocedure; end if;
    s := regexp_replace(o, '\m([dxyz])\.is_current', '\1.is_current and \1.shown', 'g');
    if s = o then raise exception 'nothing changed: %', r.oid::regprocedure; end if;
    execute s; n := n + 1;
  end loop;
  if n <> 7 then raise exception 'expected 7 functions, got %', n; end if;
end $$;
$designmig$;
end
$wrapci$;
