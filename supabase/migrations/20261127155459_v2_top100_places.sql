-- Home page map, the "Top 100" view (founder, 27 Nov 2026): its Map button draws one circle per place.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_places(text[]);
--
-- Where each of the given firms sits on the map, taken from the same table the map counts places from (v2_map_counted_places).
-- Answer: [[slug, level, region, area], ...], one item per firm: level is 'us', 'eu' or null (a firm outside both zooms);
-- region is the world-map place ("US West", "Europe", "Japan"); area is the US city or the European country code.
-- The page adds up each chart's own numbers per place, so the same function serves every chart. At most 300 slugs.
do $wraptop$
begin
  if to_regclass('public.v2_map_counted_places') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_places(p_slugs text[])
returns jsonb language sql stable security definer set search_path to 'public' as $body$
select coalesce(jsonb_agg(jsonb_build_array(x.slug, x.level, x.region, x.area) order by x.slug), '[]'::jsonb)
from (
  select distinct on (fs.slug) fs.slug, p.level, p.region, p.area
  from firm_summary fs join v2_map_counted_places p on p.firm_id = fs.firm_id
  where fs.slug = any((select coalesce(array_agg(s), '{}') from (select s from unnest(p_slugs) s limit 300) t)::text[])
  order by fs.slug, p.area
) x
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_places(text[]) from public';
  execute 'grant execute on function public.v2_top100_places(text[]) to anon, authenticated';
end $wraptop$;
