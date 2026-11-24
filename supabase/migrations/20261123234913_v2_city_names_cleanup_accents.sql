-- Firm city names, part 2: four cities written with and without accents. The more common spelling wins.
do $wrapci$
begin
  if to_regclass('public.v2_city_cleanup_20261123') is null then
    raise notice 'city clean-up table not present, skipping';
    return;
  end if;
  execute $citymig$
insert into public.v2_city_cleanup_20261123 (firm_id, old_city, new_city)
select f.firm_id, f.hq_city, m.new
from public.v2_firms f
join (values ('Sao Paulo','BR','São Paulo'),('Zürich','CH','Zurich'),('Bogota','CO','Bogotá'),('İstanbul','TR','Istanbul')) as m(old, cc, new)
  on m.old = f.hq_city and m.cc = f.hq_country
on conflict (firm_id) do nothing;

update public.v2_firms f
set hq_city = c.new_city
from public.v2_city_cleanup_20261123 c
where c.firm_id = f.firm_id and f.hq_city = c.old_city;
$citymig$;
end $wrapci$;
