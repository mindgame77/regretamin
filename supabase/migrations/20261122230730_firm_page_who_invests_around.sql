-- firm_page_who_invests_around (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: firm_page_who_invests_around skipped';
    return;
  end if;
  execute $designmig$
-- "Who invests around them" card on the firm page: firms that keep appearing in the same startups, grouped by whether they
-- usually got there before, together with, or after this firm. Read-only; adds one function, changes nothing that exists.
create or replace function public.v2_firm_around(p_slug text)
returns json language sql stable security definer
set search_path to 'public', 'pg_temp' set statement_timeout to '4s'
as $fn$
  with me as (select s.firm_id from firm_summary s where s.listed and s.slug = left(btrim(coalesce(p_slug, '')), 120) limit 1),
  mine as (
    select d.startup_id, min(d.deal_date) as d
      from v2_deals d join me on me.firm_id = d.firm_id
     where d.is_current and d.shown and d.deal_date is not null and d.deal_date <= current_date and d.deal_date_precision <> 'year'
     group by 1
  ),
  port as (select count(*)::int as n from mine),
  oth as (
    select d.firm_id, d.startup_id, min(d.deal_date) as d
      from v2_deals d join mine m on m.startup_id = d.startup_id
     where d.firm_id <> (select firm_id from me)
       and d.is_current and d.shown and d.deal_date is not null and d.deal_date <= current_date and d.deal_date_precision <> 'year'
     group by 1, 2
  ),
  agg as (
    select o.firm_id, count(*)::int as n,
           count(*) filter (where o.d < m.d)::int as b,
           count(*) filter (where o.d = m.d)::int as w,
           count(*) filter (where o.d > m.d)::int as a
      from oth o join mine m on m.startup_id = o.startup_id
     group by 1
  ),
  top as (select t.firm_id from v2_top_firms t where t.list_year = (select max(list_year) from v2_top_firms) and t.world_rank is not null),
  kept as (
    select s.display_name as name, s.slug, g.n,
           case when g.b >= g.w and g.b >= g.a then 'before' when g.w >= g.a then 'with' else 'after' end as grp
      from agg g join firm_summary s on s.firm_id = g.firm_id and s.listed, port
     where g.n >= 3 or (g.n >= 2 and g.n >= 0.1 * port.n) or (g.a >= 2 and exists (select 1 from top where top.firm_id = g.firm_id))
  ),
  grp as (
    select k.grp, count(*)::int as firms,
           json_agg(json_build_object('name', k.name, 'slug', k.slug, 'n', k.n) order by k.n desc, k.name) as list
      from kept k group by 1
  )
  select case when (select firm_id from me) is null then null else json_build_object(
    'startups', (select n from port),
    'before', coalesce((select json_build_object('firms', firms, 'list', list) from grp where grp = 'before'), json_build_object('firms', 0, 'list', '[]'::json)),
    'with', coalesce((select json_build_object('firms', firms, 'list', list) from grp where grp = 'with'), json_build_object('firms', 0, 'list', '[]'::json)),
    'after', coalesce((select json_build_object('firms', firms, 'list', list) from grp where grp = 'after'), json_build_object('firms', 0, 'list', '[]'::json))
  ) end
$fn$;
revoke all on function public.v2_firm_around(text) from public;
grant execute on function public.v2_firm_around(text) to anon, authenticated;
$designmig$;
end
$wrapci$;
