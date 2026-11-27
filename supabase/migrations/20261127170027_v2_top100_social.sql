-- Home page map, the "Top 100" view (founder, 26 Nov 2026), chart "Most social reach" (built 27 Nov). Same idea as v2_top100_active, other numbers.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_social(integer);
--
-- Most social reach = the firms with the most followers in total, across the accounts we know of (X, LinkedIn, YouTube, Instagram, Substack).
--   * source: v2_social_accounts, only rows that are current, not archived and have a follower count above zero; a firm's followers on a
--     platform are added up when it has more than one account there (none do today)
--   * only firms the map counts (v2_map_counted_places)
--   * there is only one reading per account so far, so there is no last-year number and no rank last year (the page draws no moves)
-- Answer: {asof, n (firms with a follower count), firms: [[slug, name, total followers, null, null, country or null, {platform: followers, ...}], ...]}
-- in rank order, at most p_n firms (1 to 200, default 100).
do $wraptop$
begin
  if to_regclass('public.v2_social_accounts') is null or to_regclass('public.v2_map_counted_places') is null then
    raise notice 'social tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_social(p_n integer default 100)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (select current_date as t1, greatest(1, least(coalesce(p_n, 100), 200)) as lim),
counted as materialized (select distinct firm_id from v2_map_counted_places),
pf as materialized (
  select a.firm_id, a.platform, sum(a.follower_count)::bigint as f
  from v2_social_accounts a
  where a.is_current and not a.archived and a.follower_count > 0 and a.firm_id in (select firm_id from counted)
  group by a.firm_id, a.platform
),
tot as materialized (
  select pf.firm_id, sum(pf.f)::bigint as t, jsonb_object_agg(pf.platform, pf.f) as parts, fs.slug, fs.display_name as name, fs.hq_country as cc
  from pf join firm_summary fs on fs.firm_id = pf.firm_id
  group by pf.firm_id, fs.slug, fs.display_name, fs.hq_country
),
rk as materialized (select firm_id, row_number() over (order by t desc, name, firm_id) as r from tot)
select jsonb_build_object(
  'asof', (select t1 from cfg),
  'n', (select count(*) from tot),
  'firms', coalesce((
    select jsonb_agg(jsonb_build_array(tot.slug, tot.name, tot.t, null, null, tot.cc, tot.parts) order by rk.r)
    from rk join tot using (firm_id) where rk.r <= (select lim from cfg)), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_social(integer) from public';
  execute 'grant execute on function public.v2_top100_social(integer) to anon, authenticated';
end $wraptop$;
