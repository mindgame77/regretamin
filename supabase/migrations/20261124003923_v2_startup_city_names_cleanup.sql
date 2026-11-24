-- Startup city names cleaned the same way as firm cities, plus the last Tokyo districts on firms.
-- Old values are kept in v2_startup_city_cleanup_20261123 and v2_city_cleanup_20261123.
do $wrapci$
begin
  if to_regclass('public.v2_city_cleanup_20261123') is null or to_regclass('public.v2_startups') is null then
    raise notice 'v2 tables not present, skipping startup city clean-up';
    return;
  end if;
  execute $citymig$
create table if not exists public.v2_startup_city_cleanup_20261123 (
  startup_id bigint primary key,
  old_city varchar,
  new_city varchar not null,
  changed_at timestamptz not null default now()
);
alter table public.v2_startup_city_cleanup_20261123 enable row level security;
comment on table public.v2_startup_city_cleanup_20261123 is
  'Startup city names before and after the 23 Nov 2026 clean-up. To undo: update v2_startups s set st_city = c.old_city from v2_startup_city_cleanup_20261123 c where c.startup_id = s.startup_id;';

insert into public.v2_startup_city_cleanup_20261123 (startup_id, old_city, new_city)
select s.startup_id, s.st_city, m.new
from public.v2_startups s
join (values ('いわき市','JP','Iwaki'),('つくば市','JP','Tsukuba'),('京都市','JP','Kyoto'),('仙台市','JP','Sendai'),('佐久市','JP','Saku'),('八潮市','JP','Yashio'),('前橋市','JP','Maebashi'),('千代田区','JP','Tokyo'),('台東区','JP','Tokyo'),('名古屋市','JP','Nagoya'),('大津市','JP','Otsu'),('宝塚市','JP','Takarazuka'),('宮崎市','JP','Miyazaki'),('岐阜市','JP','Gifu'),('川崎市','JP','Kawasaki'),('府中市','JP','Fuchu'),('恩納村','JP','Onna'),('新宿区','JP','Tokyo'),('杉並区','JP','Tokyo'),('横浜市','JP','Yokohama'),('毛呂山町','JP','Moroyama'),('江東区','JP','Tokyo'),('浜松市','JP','Hamamatsu'),('渋谷区','JP','Tokyo'),('港区','JP','Tokyo'),('熊本市','JP','Kumamoto'),('目黒区','JP','Tokyo'),('石巻市','JP','Ishinomaki'),('神戸市','JP','Kobe'),('花巻市','JP','Hanamaki'),('諏訪市','JP','Suwa'),('豊島区','JP','Tokyo'),('豊田市','JP','Toyota'),('那覇市','JP','Naha'),('酒田市','JP','Sakata'),('金沢市','JP','Kanazawa'),('長岡京市','JP','Nagaokakyo'),('館林市','JP','Tatebayashi'),('高崎市','JP','Takasaki'),('鹿児島市','JP','Kagoshima'),('鹿沼市','JP','Kanuma'),('墨田区','JP','Tokyo'),('Chiyoda','JP','Tokyo'),('Minato','JP','Tokyo'),('Minato-ku','JP','Tokyo'),('Shibuya','JP','Tokyo'),('Shibuya-ku','JP','Tokyo'),('Shinagawa','JP','Tokyo'),('Shinjuku','JP','Tokyo'),('Toshima','JP','Tokyo'),('Cordoba','AR','Córdoba'),('Florianopolis','BR','Florianópolis'),('Sao Paulo','BR','São Paulo'),('Zürich','CH','Zurich'),('Bogota','CO','Bogotá'),('Medellin','CO','Medellín'),('Modiin','IL','Modi''in'),('Rosh Ha''Ayin','IL','Rosh HaAyin'),('Tel Aviv-Yafo','IL','Tel Aviv'),('Reykjavik','IS','Reykjavík'),('Wroclaw','PL','Wrocław'),('İstanbul','TR','Istanbul')) as m(old, cc, new)
  on m.old = s.st_city and m.cc = s.st_country
on conflict (startup_id) do nothing;

update public.v2_startups s
set st_city = c.new_city
from public.v2_startup_city_cleanup_20261123 c
where c.startup_id = s.startup_id and s.st_city = c.old_city;

-- Firms: Tokyo districts written in English.
insert into public.v2_city_cleanup_20261123 (firm_id, old_city, new_city)
select f.firm_id, f.hq_city, 'Tokyo'
from public.v2_firms f
where f.hq_country = 'JP' and f.hq_city in ('Minato', 'Minato-ku', 'Shibuya', 'Shinjuku')
on conflict (firm_id) do nothing;

update public.v2_firms f
set hq_city = c.new_city
from public.v2_city_cleanup_20261123 c
where c.firm_id = f.firm_id and f.hq_city = c.old_city;
$citymig$;
end $wrapci$;
