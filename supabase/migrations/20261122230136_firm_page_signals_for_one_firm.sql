-- firm_page_signals_for_one_firm (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: firm_page_signals_for_one_firm skipped';
    return;
  end if;
  execute $designmig$
-- One firm's signals for its page (the icons in the status tile). Read-only; adds one function, changes nothing that exists.
create or replace function public.v2_firm_signals_for(p_slug text)
returns json language sql stable security definer
set search_path to 'public', 'pg_temp' set statement_timeout to '3s'
as $fn$
  select json_build_object('signals', coalesce(to_json(g.signals), '[]'::json), 'deals_now', coalesce(g.deals_now, 0),
                           'deals_prev', coalesce(g.deals_prev, 0), 'led_now', coalesce(g.led_now, 0))
    from firm_summary s left join v2_firm_signals g on g.firm_id = s.firm_id
   where s.listed and s.slug = left(btrim(coalesce(p_slug, '')), 120)
   limit 1
$fn$;
revoke all on function public.v2_firm_signals_for(text) from public;
grant execute on function public.v2_firm_signals_for(text) to anon, authenticated;
$designmig$;
end
$wrapci$;
