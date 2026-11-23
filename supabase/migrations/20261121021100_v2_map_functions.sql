-- v2_map_functions (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_functions skipped';
    return;
  end if;
  execute $designmig$
create or replace view public.v2_map_firm_places with (security_invoker = true) as
with metro(area, st, city) as (values
  ('Bay Area','CA','san francisco'),('Bay Area','CA','menlo park'),('Bay Area','CA','palo alto'),('Bay Area','CA','san mateo'),('Bay Area','CA','mountain view'),
  ('Bay Area','CA','pleasant hill'),('Bay Area','CA','redwood city'),('Bay Area','CA','oakland'),('Bay Area','CA','berkeley'),('Bay Area','CA','san jose'),
  ('Bay Area','CA','sunnyvale'),('Bay Area','CA','los altos'),('Bay Area','CA','woodside'),('Bay Area','CA','burlingame'),('Bay Area','CA','santa clara'),
  ('Bay Area','CA','cupertino'),('Bay Area','CA','mill valley'),('Bay Area','CA','portola valley'),('Bay Area','CA','atherton'),('Bay Area','CA','larkspur'),
  ('Bay Area','CA','san carlos'),('Bay Area','CA','emeryville'),('Bay Area','CA','south san francisco'),('Bay Area','CA','foster city'),('Bay Area','CA','los gatos'),
  ('Bay Area','CA','sausalito'),('Bay Area','CA','danville'),('Bay Area','CA','walnut creek'),('Bay Area','CA','lafayette'),('Bay Area','CA','orinda'),
  ('Bay Area','CA','san rafael'),('Bay Area','CA','tiburon'),('Bay Area','CA','belmont'),('Bay Area','CA','hillsborough'),('Bay Area','CA','saratoga'),
  ('Bay Area','CA','campbell'),('Bay Area','CA','milpitas'),('Bay Area','CA','fremont'),('Bay Area','CA','pleasanton'),('Bay Area','CA','san ramon'),
  ('Bay Area','CA','los altos hills'),('Bay Area','CA','corte madera'),('Bay Area','CA','ross'),('Bay Area','CA','kentfield'),('Bay Area','CA','san bruno'),
  ('Bay Area','CA','millbrae'),('Bay Area','CA','daly city'),('Bay Area','CA','alameda'),('Bay Area','CA','piedmont'),('Bay Area','CA','novato'),
  ('Bay Area','CA','half moon bay'),('Bay Area','CA','stanford'),
  ('New York','NY','new york'),('New York','NY','brooklyn'),('New York','NY','queens'),('New York','NY','long island city'),('New York','NY','larchmont'),
  ('New York','NY','rye'),('New York','NY','white plains'),('New York','NY','scarsdale'),('New York','NY','bronxville'),('New York','NY','purchase'),
  ('New York','NY','armonk'),('New York','NY','harrison'),('New York','NY','mamaroneck'),('New York','NY','great neck'),('New York','NY','garden city'),
  ('New York','CT','norwalk'),('New York','CT','stamford'),('New York','CT','westport'),('New York','CT','greenwich'),('New York','CT','darien'),('New York','CT','new canaan'),
  ('New York','NJ','jersey city'),('New York','NJ','hoboken'),('New York','NJ','summit'),('New York','NJ','short hills'),('New York','NJ','montclair'),('New York','NJ','newark'),
  ('Boston','MA','boston'),('Boston','MA','cambridge'),('Boston','MA','waltham'),('Boston','MA','wellesley'),('Boston','MA','wellesley hills'),('Boston','MA','newton'),
  ('Boston','MA','somerville'),('Boston','MA','lexington'),('Boston','MA','brookline'),('Boston','MA','needham'),('Boston','MA','concord'),('Boston','MA','burlington'),
  ('Boston','MA','woburn'),('Boston','MA','watertown'),('Boston','MA','weston'),('Boston','MA','framingham'),('Boston','MA','dedham'),('Boston','MA','lynn'),
  ('Los Angeles','CA','los angeles'),('Los Angeles','CA','santa monica'),('Los Angeles','CA','beverly hills'),('Los Angeles','CA','venice'),('Los Angeles','CA','culver city'),
  ('Los Angeles','CA','pasadena'),('Los Angeles','CA','el segundo'),('Los Angeles','CA','manhattan beach'),('Los Angeles','CA','west hollywood'),('Los Angeles','CA','malibu'),
  ('Los Angeles','CA','burbank'),('Los Angeles','CA','glendale'),('Los Angeles','CA','long beach'),('Los Angeles','CA','marina del rey'),('Los Angeles','CA','playa vista'),
  ('Los Angeles','CA','sherman oaks'),('Los Angeles','CA','encino'),('Los Angeles','CA','calabasas'),('Los Angeles','CA','pacific palisades'),('Los Angeles','CA','hermosa beach'),
  ('Los Angeles','CA','covina'),('Los Angeles','CA','woodland hills'),('Los Angeles','CA','irvine'),('Los Angeles','CA','newport beach'),('Los Angeles','CA','costa mesa'),('Los Angeles','CA','laguna beach'),
  ('San Diego','CA','san diego'),('San Diego','CA','la jolla'),('San Diego','CA','del mar'),('San Diego','CA','solana beach'),('San Diego','CA','carlsbad'),('San Diego','CA','encinitas'),
  ('Miami','FL','miami'),('Miami','FL','miami beach'),('Miami','FL','coral gables'),('Miami','FL','fort lauderdale'),('Miami','FL','boca raton'),('Miami','FL','aventura'),
  ('Miami','FL','sunny isles beach'),('Miami','FL','west palm beach'),('Miami','FL','palm beach'),('Miami','FL','jupiter'),('Miami','FL','palm beach gardens'),('Miami','FL','delray beach'),
  ('Tampa','FL','tampa'),('Tampa','FL','st. petersburg'),('Tampa','FL','saint petersburg'),
  ('Seattle','WA','seattle'),('Seattle','WA','bellevue'),('Seattle','WA','kirkland'),('Seattle','WA','redmond'),('Seattle','WA','mercer island'),
  ('Washington DC','DC','washington'),('Washington DC','VA','arlington'),('Washington DC','VA','mclean'),('Washington DC','VA','reston'),('Washington DC','VA','alexandria'),
  ('Washington DC','VA','vienna'),('Washington DC','VA','tysons'),('Washington DC','VA','falls church'),('Washington DC','VA','herndon'),('Washington DC','VA','great falls'),
  ('Washington DC','MD','bethesda'),('Washington DC','MD','chevy chase'),('Washington DC','MD','rockville'),('Washington DC','MD','silver spring'),('Washington DC','MD','potomac'),
  ('Denver','CO','denver'),('Denver','CO','boulder'),('Denver','CO','englewood'),('Denver','CO','greenwood village'),('Denver','CO','golden'),('Denver','CO','littleton'),
  ('Philadelphia','PA','philadelphia'),('Philadelphia','PA','bala cynwyd'),('Philadelphia','PA','wayne'),('Philadelphia','PA','radnor'),('Philadelphia','PA','conshohocken'),
  ('Philadelphia','PA','west conshohocken'),('Philadelphia','PA','malvern'),('Philadelphia','PA','king of prussia'),('Philadelphia','PA','bryn mawr'),
  ('Salt Lake City','UT','salt lake city'),('Salt Lake City','UT','lehi'),('Salt Lake City','UT','park city'),('Salt Lake City','UT','provo'),('Salt Lake City','UT','draper'),
  ('Salt Lake City','UT','sandy'),('Salt Lake City','UT','orem'),('Salt Lake City','UT','cottonwood heights'),
  ('Chicago','IL','chicago'),('Chicago','IL','evanston'),('Chicago','IL','northbrook'),('Chicago','IL','oak brook'),('Chicago','IL','lake forest'),
  ('Dallas','TX','dallas'),('Dallas','TX','fort worth'),('Dallas','TX','plano'),('Dallas','TX','irving'),('Dallas','TX','frisco'),('Dallas','TX','southlake'),
  ('Houston','TX','houston'),('Houston','TX','the woodlands'),
  ('Austin','TX','austin'),
  ('Atlanta','GA','atlanta'),('Atlanta','GA','alpharetta'),
  ('Minneapolis','MN','minneapolis'),('Minneapolis','MN','st. paul'),('Minneapolis','MN','saint paul'),('Minneapolis','MN','edina'),('Minneapolis','MN','minnetonka'),
  ('Minneapolis','MN','wayzata'),('Minneapolis','MN','arden hills'),
  ('St. Louis','MO','st. louis'),('St. Louis','MO','saint louis'),('St. Louis','MO','clayton'),
  ('Nashville','TN','nashville'),('Nashville','TN','franklin'),('Nashville','TN','brentwood'),
  ('Las Vegas','NV','las vegas'),('Las Vegas','NV','henderson'),
  ('Indianapolis','IN','indianapolis'),('Indianapolis','IN','carmel'),
  ('Phoenix','AZ','phoenix'),('Phoenix','AZ','scottsdale'),('Phoenix','AZ','tempe'),
  ('Raleigh-Durham','NC','raleigh'),('Raleigh-Durham','NC','durham'),('Raleigh-Durham','NC','chapel hill'),('Raleigh-Durham','NC','cary'),
  ('Cincinnati','OH','cincinnati'),('Cincinnati','KY','covington'),
  ('Portland','OR','portland'),('Vail','CO','vail'),('Oklahoma City','OK','oklahoma city'),('Baltimore','MD','baltimore'),('Des Moines','IA','des moines'),
  ('Kansas City','MO','kansas city'),('Charleston','SC','charleston'),('Jackson','WY','jackson'),('Columbus','OH','columbus'),('Ann Arbor','MI','ann arbor'),
  ('Sacramento','CA','sacramento'),('Sacramento','CA','rocklin'),('Aspen','CO','aspen'),('Memphis','TN','memphis'),('East Lansing','MI','east lansing'),
  ('Chattanooga','TN','chattanooga'),('Omaha','NE','omaha'),('Tulsa','OK','tulsa'),('Bend','OR','bend'),('Providence','RI','providence'),
  ('Santa Barbara','CA','santa barbara'),('Santa Rosa','CA','santa rosa'),('Princeton','NJ','princeton'),('Dover','DE','dover'),('Portsmouth','NH','portsmouth'),
  ('Pittsburgh','PA','pittsburgh'),('Detroit','MI','detroit'),('Charlotte','NC','charlotte'),('Madison','WI','madison'),('Milwaukee','WI','milwaukee')
)
select f.firm_id,
  case
    when f.hq_country = 'US' and f.hq_state in ('CA','WA','OR','NV','AZ','UT','CO','ID','MT','WY','NM','HI','AK') then 'US West'
    when f.hq_country = 'US' and f.hq_state in ('NY','MA','CT','NJ','PA','DC','MD','VA','FL','GA','NC','SC','DE','RI','NH','VT','ME','WV') then 'US East'
    when f.hq_country = 'US' then 'US Central'
    when f.hq_country in ('GB','DE','FR','NL','PL','CH','BE','ES','SE','CZ','DK','UA','LU','IT','PT','FI','NO','GR','AT','EE','HU','BG','IE','LT','CY','RO','LV','IS','SK','RS','MT','HR','SI','MC','LI','AD','GG','JE','IM') then 'Europe'
    when f.hq_country = 'IL' then 'Israel'
    when f.hq_country in ('AE','SA','TR','OM','KW','JO','BH','QA','LB','IQ') then 'Middle East'
    when f.hq_country in ('ZA','KE','NG','EG','MU','MA','GH','SN','TN','RW','ZW','TZ','UG','AO','DZ','NE','ET','BW','NA','MG','ML','CI','SO','GN','CM','CV') then 'Africa'
    when f.hq_country in ('BR','CL','MX','AR','CO','PE','GT','UY','BO','CR','VE','SV','EC','PY','HN') then 'Latin America'
    when f.hq_country = 'IN' then 'India'
    when f.hq_country = 'JP' then 'Japan'
    when f.hq_country = 'KR' then 'South Korea'
    when f.hq_country in ('CN','HK','TW') then 'China, HK, Taiwan'
    when f.hq_country in ('SG','MY','TH','PH','VN','ID') then 'Southeast Asia'
    when f.hq_country = 'CA' then 'Canada'
    when f.hq_country in ('AU','NZ') then 'Australia and NZ'
    when f.hq_country in ('KZ','UZ','AZ','AM','GE') then 'Central Asia and Caucasus'
    when f.hq_country in ('KY','VG','BM') then 'Caribbean'
  end as region,
  case
    when f.hq_country = 'US' then 'us'
    when f.hq_country in ('GB','DE','FR','NL','PL','CH','BE','ES','SE','CZ','DK','UA','LU','IT','PT','FI','NO','GR','AT','EE','HU','BG','IE','LT','CY','RO','LV','IS','SK','RS','MT','HR','SI','MC','LI','AD','GG','JE','IM') then 'eu'
  end as level,
  case
    when f.hq_country = 'US' then coalesce(
      (select m.area from metro m where m.city = lower(btrim(f.hq_city)) and (m.st = f.hq_state or f.hq_state is null) order by (m.st = f.hq_state) desc nulls last limit 1),
      nullif(btrim(f.hq_city), '') || coalesce(', ' || f.hq_state, ''),
      '(no city)')
    else f.hq_country
  end as area
from public.firm_summary f
where f.listed;

revoke all on public.v2_map_firm_places from anon, authenticated;

create or replace function public.v2_map_summary(
  p_from date default date '2021-01-01', p_to date default null,
  p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path = public as $fn$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
d as (
  select d.deal_id, d.startup_id, d.firm_id, p.region, p.level, p.area
  from v2_deals d join v2_map_firm_places p using (firm_id) left join stg on stg.round = d.round::text
  where d.is_current
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
pl as (
  select 'world'::text lvl, region place, deal_id, startup_id, firm_id from d where region is not null
  union all
  select level, area, deal_id, startup_id, firm_id from d where level is not null
),
t as (select lvl, place, count(*) deals, count(distinct firm_id) firms from pl group by 1, 2),
s as (
  select pl.lvl, pl.place, sc.name, count(*) n
  from pl join v2_startup_sectors ss on ss.startup_id = pl.startup_id and ss.is_current join v2_sector sc using (sector_id)
  group by 1, 2, 3
),
k as (
  select s.*, row_number() over (partition by lvl, place order by n desc, name) rk,
    sum(n) over (partition by lvl, place) tot, sum(n) over (partition by lvl, name) sn, sum(n) over (partition by lvl) alln
  from s
),
x as (
  select lvl, place, max(tot) tot,
    jsonb_agg(jsonb_build_array(name, n) order by rk) filter (where rk <= 5) top,
    (array_agg(name order by (n::float8 / tot) / (sn::float8 / alln) desc, n desc) filter (where rk <= 5))[1] standout
  from k group by 1, 2
),
tt as (select lvl, count(distinct deal_id) deals, count(distinct firm_id) firms from pl group by 1)
select jsonb_build_object(
  'from', greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01'),
  'to', coalesce(p_to, current_date),
  'totals', coalesce((select jsonb_object_agg(lvl, jsonb_build_object('deals', deals, 'firms', firms)) from tt), '{}'::jsonb),
  'places', coalesce((
    select jsonb_agg(jsonb_build_object('l', t.lvl, 'p', t.place, 'd', t.deals, 'f', t.firms, 'tot', x.tot, 'top', x.top, 'so', x.standout)
                     order by t.lvl, t.deals desc, t.place)
    from t left join x using (lvl, place)
    where t.place <> '(no city)'), '[]'::jsonb))
$fn$;

create or replace function public.v2_map_firms(
  p_level text, p_place text,
  p_from date default date '2021-01-01', p_to date default null,
  p_stages text[] default null, p_sectors text[] default null, p_limit int default 200)
returns jsonb language sql stable security definer set search_path = public as $fn$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
fp as (
  select p.firm_id from v2_map_firm_places p
  where (p_level = 'world' and p.region = p_place) or (p_level in ('us', 'eu') and p.level = p_level and p.area = p_place)
),
d as (
  select d.firm_id, count(*) deals, count(*) filter (where d.lead::text = 'yes') led
  from v2_deals d join fp using (firm_id) left join stg on stg.round = d.round::text
  where d.is_current
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
  group by d.firm_id
),
w as (select case when extract(month from current_date) <= 5
                  then (date_trunc('year', current_date) - interval '1 year')::date
                  else date_trunc('year', current_date)::date end ws)
select jsonb_build_object(
  'count', (select count(*) from d),
  'firms', coalesce((
    select jsonb_agg(z order by (z->>'deals')::int desc, z->>'name') from (
      select jsonb_build_object('slug', f.slug, 'name', f.display_name, 'deals', d.deals, 'led', d.led,
        'last', (select max(x.deal_date) from v2_deals x where x.firm_id = d.firm_id and x.is_current and x.deal_date <= current_date),
        'status', (select case when count(*) >= 3 then 'Active' when count(*) >= 1 then 'Low activity' else 'Not active' end
                   from v2_deals x, w where x.firm_id = d.firm_id and x.is_current and x.deal_date >= w.ws and x.deal_date <= current_date)) z
      from d join firm_summary f using (firm_id)
      order by d.deals desc, f.display_name limit greatest(1, least(coalesce(p_limit, 200), 500))) q), '[]'::jsonb))
$fn$;

create or replace function public.v2_map_updates(p_limit int default 4)
returns jsonb language sql stable security definer set search_path = public as $fn$
with r as (
  select d.startup_id, d.round::text round, d.deal_date, count(*) investors,
    (array_agg(d.firm_id order by (d.lead::text = 'yes') desc nulls last, f.deals desc nulls last))[1:2] top_firms,
    bool_or(d.lead::text = 'yes') has_lead, count(*) filter (where d.lead::text = 'yes') leads, max(d.created_at) seen
  from v2_deals d join firm_summary f using (firm_id)
  where f.listed and d.is_current and d.deal_date_precision::text = 'full date'
    and d.deal_date <= current_date and d.deal_date >= current_date - 30 and d.round is not null
  group by 1, 2, 3
  order by d.deal_date desc, max(d.created_at) desc
  limit greatest(1, least(coalesce(p_limit, 4), 20))
)
select coalesce(jsonb_agg(jsonb_build_object(
  'startup', s.startup_name, 'round', r.round, 'date', r.deal_date, 'investors', r.investors, 'led', r.has_lead, 'leads', r.leads,
  'firms', (select jsonb_agg(jsonb_build_object('name', f.display_name, 'slug', f.slug) order by o.i)
            from unnest(r.top_firms) with ordinality o(fid, i) join firm_summary f on f.firm_id = o.fid),
  'region', p.region, 'level', p.level, 'area', p.area) order by r.deal_date desc, r.seen desc), '[]'::jsonb)
from r join v2_startups s using (startup_id) left join v2_map_firm_places p on p.firm_id = r.top_firms[1]
$fn$;

grant execute on function public.v2_map_summary(date, date, text[], text[]) to anon, authenticated;
grant execute on function public.v2_map_firms(text, text, date, date, text[], text[], int) to anon, authenticated;
grant execute on function public.v2_map_updates(int) to anon, authenticated;
$designmig$;
end
$wrapci$;
