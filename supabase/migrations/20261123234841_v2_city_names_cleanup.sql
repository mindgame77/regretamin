-- Firm city names: one spelling per city, English names, no district or province extras.
-- Old values are kept in v2_city_cleanup_20261123 so the change can be undone.
do $wrapci$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2_firms not present, skipping city clean-up';
    return;
  end if;
  execute $citymig$
create table if not exists public.v2_city_cleanup_20261123 (
  firm_id bigint primary key,
  old_city varchar,
  new_city varchar not null,
  changed_at timestamptz not null default now()
);
alter table public.v2_city_cleanup_20261123 enable row level security;
comment on table public.v2_city_cleanup_20261123 is
  'Firm city names before and after the 23 Nov 2026 clean-up. To undo: update v2_firms f set hq_city = c.old_city from v2_city_cleanup_20261123 c where c.firm_id = f.firm_id;';

insert into public.v2_city_cleanup_20261123 (firm_id, old_city, new_city)
select f.firm_id, f.hq_city, m.new
from public.v2_firms f
join (values ('Pembroke, Hamilton','BM','Hamilton'),('Calgary, AB','CA','Calgary'),('Halifax, NS','CA','Halifax'),('Montréal, QC','CA','Montreal'),('Montréal','CA','Montreal'),('Toronto, ON','CA','Toronto'),('Vancouver, BC','CA','Vancouver'),('上海','CN','Shanghai'),('上海市','CN','Shanghai'),('北京','CN','Beijing'),('北京市','CN','Beijing'),('南京','CN','Nanjing'),('天津','CN','Tianjin'),('广州','CN','Guangzhou'),('无锡市','CN','Wuxi'),('杭州','CN','Hangzhou'),('深圳','CN','Shenzhen'),('深圳市','CN','Shenzhen'),('福田区','CN','Shenzhen'),('绍兴市','CN','Shaoxing'),('苏州市','CN','Suzhou'),('黄浦区','CN','Shanghai'),('Praha','CZ','Prague'),('Praha 6','CZ','Prague'),('Berlin - Mitte','DE','Berlin'),('Frankenthal (Pfalz)','DE','Frankenthal'),('GUIPAVAS','FR','Guipavas'),('ROUEN','FR','Rouen'),('Chalfont St Giles, Buckinghamshire','GB','Chalfont St Giles'),('London, London','GB','London'),('Tel-Aviv','IL','Tel Aviv'),('Tel Aviv-Yafo','IL','Tel Aviv'),('Herzliya Pituach','IL','Herzliya'),('הרצליה פיתוח','IL','Herzliya'),('三島市','JP','Mishima'),('下京区','JP','Kyoto'),('仙台市','JP','Sendai'),('前橋市','JP','Maebashi'),('北九州市八幡東区','JP','Kitakyushu'),('千代田区','JP','Tokyo'),('千葉市','JP','Chiba'),('名古屋市','JP','Nagoya'),('品川区','JP','Tokyo'),('宇都宮市','JP','Utsunomiya'),('宮崎市','JP','Miyazaki'),('富山','JP','Toyama'),('岐阜市','JP','Gifu'),('岡山市','JP','Okayama'),('左京区','JP','Kyoto'),('広島市','JP','Hiroshima'),('徳島市','JP','Tokushima'),('文京区','JP','Tokyo'),('新宿区','JP','Tokyo'),('札幌市','JP','Sapporo'),('東京','JP','Tokyo'),('横浜市西区','JP','Yokohama'),('江東区','JP','Tokyo'),('渋谷区','JP','Tokyo'),('熊本市','JP','Kumamoto'),('福岡','JP','Fukuoka'),('福岡市','JP','Fukuoka'),('茨木市','JP','Ibaraki'),('長野市','JP','Nagano'),('音更町','JP','Otofuke'),('高山','JP','Takayama'),('鹿児島市','JP','Kagoshima'),('墨田区','JP','Tokyo'),('대구','KR','Daegu'),('서울','KR','Seoul'),('서울특별시','KR','Seoul'),('Camana Bay, Grand Cayman','KY','Camana Bay'),('Georgetown','KY','George Town'),('Port-Louis','MU','Port Louis'),('臺北','TW','Taipei'),('Dar Es Salaam','TZ','Dar es Salaam'),('AUSTIN','US','Austin'),('BELLEVUE','US','Bellevue'),('CHICAGO','US','Chicago'),('Ft Lauderdale','US','Fort Lauderdale'),('Ft. Lauderdale','US','Fort Lauderdale'),('GREENWICH','US','Greenwich'),('HOUSTON','US','Houston'),('LINCOLN','US','Lincoln'),('LOS ANGELES','US','Los Angeles'),('Mc Lean','US','McLean'),('Mclean','US','McLean'),('MCLEAN','US','McLean'),('MENLO PARK','US','Menlo Park'),('MINNEAPOLIS','US','Minneapolis'),('NEW YORK','US','New York'),('PALM BEACH','US','Palm Beach'),('PALO ALTO','US','Palo Alto'),('SAN FRANCISCO','US','San Francisco'),('SANDPOINT','US','Sandpoint'),('St Petersburg','US','St. Petersburg'),('WESTMONT','US','Westmont'),('Road Town, Tortola','VG','Road Town'),('Roadtown, Tortola','VG','Road Town')) as m(old, cc, new)
  on m.old = f.hq_city and m.cc = f.hq_country
on conflict (firm_id) do nothing;

-- Japanese wards that exist in several cities: decided firm by firm from the street address.
insert into public.v2_city_cleanup_20261123 (firm_id, old_city, new_city)
select f.firm_id, f.hq_city, w.new
from public.v2_firms f
join (values (4363, '中区', 'Nagoya'), (3077, '中央区', 'Tokyo'), (3136, '中央区', 'Tokyo'),
             (4316, '中央区', 'Kobe'), (4073, '港区', 'Tokyo'), (4116, '港区', 'Tokyo')) as w(firm_id, old, new)
  on w.firm_id = f.firm_id and w.old = f.hq_city and f.hq_country = 'JP'
on conflict (firm_id) do nothing;

insert into public.v2_city_cleanup_20261123 (firm_id, old_city, new_city)
select f.firm_id, f.hq_city, 'Tokyo'
from public.v2_firms f
where f.hq_country = 'JP' and f.hq_city = '港区' and f.hq_state in ('Tokyo', '東京都')
on conflict (firm_id) do nothing;

update public.v2_firms f
set hq_city = c.new_city
from public.v2_city_cleanup_20261123 c
where c.firm_id = f.firm_id and f.hq_city = c.old_city;
$citymig$;
end $wrapci$;
