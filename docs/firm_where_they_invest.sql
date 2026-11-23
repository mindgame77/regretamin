-- Applied 23 Nov 2026 as migration `firm_page_where_they_invest` (founder's yes the same day). Not yet in supabase/migrations/.
-- Timed as anon: about 0.6 s for one firm (it reads the map-places view once). Sequoia: US map, Bay Area 65, New York 31.
--
-- Where the startups a firm backed are based, grouped by the map's places. Read-only; nothing existing is changed.
-- Returns null when the city is known for fewer than 5 of the firm's startups.
-- A startup's US city is placed in a map area by looking at where listed firms in that city sit (most common area);
-- a country is placed in a world region the same way. The picture uses the US map when 60% or more of the known startups
-- are in US areas, the Europe map when 60% or more are in European countries, the world map otherwise.
create function public.v2_firm_invests_where(p_slug text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
with f as (select firm_id from firm_summary where slug = p_slug and listed limit 1),
mp as materialized (select p.firm_id, p.region, p.level, p.area from v2_map_firm_places p),
fc as materialized (
  select lower(btrim(coalesce(s.hq_city, ''))) city, upper(btrim(coalesce(s.hq_country, ''))) country, mp.level, mp.area, mp.region
  from firm_summary s join mp using (firm_id) where s.listed),
c0 as (select city, area, min(region) region, count(*) n from fc where level = 'us' and country = 'US' and city <> '' and area is not null group by 1, 2),
cm as (select distinct on (city) city, area, region from c0 order by city, n desc, area),
r0 as (select country, region, count(*) n from fc where country <> 'US' and country ~ '^[A-Z]{2}$' and region is not null group by 1, 2),
rm as (select distinct on (country) country, region from r0 order by country, n desc, region),
eu as (select distinct area code from mp where level = 'eu' and area is not null),
st as (select distinct d.startup_id from v2_deals d join f using (firm_id) where d.is_current and d.shown),
s as (select lower(btrim(coalesce(x.st_city, ''))) city, upper(btrim(coalesce(x.st_country, ''))) country from st join v2_startups x using (startup_id)),
j as (
  select s.city, s.country,
    case when s.country = 'US' then cm.area end us_area,
    case when s.country in (select code from eu) then s.country end eu_code,
    case when s.country = 'US' then cm.region else rm.region end region
  from s left join cm on s.country = 'US' and cm.city = s.city left join rm on rm.country = s.country),
k as (
  select count(*) total, count(*) filter (where city <> '') known,
    count(*) filter (where city <> '' and us_area is not null) us_n,
    count(*) filter (where city <> '' and eu_code is not null) eu_n
  from j),
lv as (select case when us_n >= 0.6 * known then 'us' when eu_n >= 0.6 * known then 'eu' else 'world' end level from k)
select case when (select known from k) < 5 then null else jsonb_build_object(
  'startups', (select total from k),
  'known', (select known from k),
  'level', (select level from lv),
  'places', coalesce((
    select jsonb_agg(jsonb_build_object('p', t.p, 'n', t.n) order by t.n desc, t.p) from (
      select case (select level from lv) when 'us' then us_area when 'eu' then eu_code else region end p, count(*) n
      from j where city <> '' group by 1) t
    where t.p is not null), '[]'::jsonb)) end
$fn$;
revoke all on function public.v2_firm_invests_where(text) from public;
grant execute on function public.v2_firm_invests_where(text) to anon, authenticated, service_role;
