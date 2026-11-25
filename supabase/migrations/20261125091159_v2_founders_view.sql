-- The "Founders" view of the home page map (founder, 25 Nov 2026: "Founders sounds good. Build it live.").
-- New and read-only for the rest of the database: three small tables of its own and two functions. Nothing that
-- exists is changed. v2_founders_data() gives the page one answer: every funded startup with a founder whose
-- country, university or former employer we know, with its sector, rounds and investors; the page does the counting.
-- The answer is kept for 30 minutes in v2_founders_cache, so a visitor does not wait for the full query.
-- Universities and companies are matched by the names in v2_founder_org_aliases (120 universities, 128 companies to
-- start with; add a row to count another spelling, add an org to show another one).
do $wrapci$
begin
  if to_regclass('public.v2_founder_facts') is null or to_regclass('public.v2_deals') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  create table if not exists public.v2_founder_orgs (kind text not null check (kind in ('uni', 'co')), name text not null, primary key (kind, name));
  create table if not exists public.v2_founder_org_aliases (kind text not null, value_norm text not null, name text not null, primary key (kind, value_norm),
    foreign key (kind, name) references public.v2_founder_orgs (kind, name) on update cascade on delete cascade);
  create table if not exists public.v2_founders_cache (id int primary key check (id = 1), data jsonb not null, made_at timestamptz not null default now());
  alter table public.v2_founder_orgs enable row level security;
  alter table public.v2_founder_org_aliases enable row level security;
  alter table public.v2_founders_cache enable row level security;
  comment on table public.v2_founder_orgs is 'Universities (uni) and former employers (co) shown in the Founders view of the map. Positions and logos live with the site (launch/assets/founders/orgs.json), matched by name.';
  comment on table public.v2_founder_org_aliases is 'Which stored spelling (v2_founder_facts.value_norm of a university or past_job fact) counts as which name in v2_founder_orgs.';
  comment on table public.v2_founders_cache is 'The last answer of v2_founders_build(), kept 30 minutes for v2_founders_data(). Safe to empty.';

  -- one entry per university (u) or company (c): kind|name shown|stored spellings separated by ";"
  with src as (select split_part(x, '|', 1) k, split_part(x, '|', 2) name, split_part(x, '|', 3) al from regexp_split_to_table($seed$u|Stanford|stanford university;stanford graduate school of business~u|MIT|massachusetts institute of technology;mit sloan school of management~u|UC Berkeley|university of california, berkeley~u|Harvard|harvard university;harvard business school;harvard medical school;harvard college;harvard law school~u|UPenn|university of pennsylvania;the wharton school of the university of pennsylvania~u|Columbia|columbia university;columbia university in the city of new york;columbia business school~u|Cornell|cornell university~u|Cambridge|university of cambridge~u|Oxford|university of oxford~u|Yale|yale university~u|Carnegie Mellon|carnegie mellon university~u|Princeton|princeton university~u|Michigan|university of michigan~u|Tel Aviv University|tel aviv university~u|UCLA|university of california, los angeles~u|Duke|duke university~u|Georgia Tech|georgia institute of technology~u|Northwestern|northwestern university~u|Waterloo|university of waterloo~u|USC|university of southern california~u|NYU|new york university~u|Washington|university of washington~u|Illinois|university of illinois urbana-champaign;university of illinois at urbana-champaign~u|Toronto|university of toronto~u|Imperial College London|imperial college london~u|Brown|brown university~u|UT Austin|the university of texas at austin;university of texas at austin~u|Johns Hopkins|johns hopkins university;the johns hopkins university~u|UC San Diego|university of california, san diego;university of california san diego~u|Dartmouth|dartmouth college~u|Caltech|california institute of technology~u|Hebrew University|the hebrew university of jerusalem~u|McGill|mcgill university~u|Chicago|university of chicago;the university of chicago~u|BYU|brigham young university~u|ETH Zurich|eth zurich~u|Virginia|university of virginia~u|IIT Delhi|indian institute of technology delhi~u|Purdue|purdue university~u|TU Munich|technical university of munich~u|UCL|university college london~u|Georgetown|georgetown university~u|Wisconsin|university of wisconsin-madison;university of wisconsin–madison~u|WashU|washington university in st. louis~u|IIT Bombay|indian institute of technology bombay~u|Boston University|boston university~u|IIT Madras|indian institute of technology madras~u|BITS Pilani|birla institute of technology and science, pilani~u|IIT Kharagpur|indian institute of technology kharagpur~u|Colorado Boulder|university of colorado boulder~u|École Polytechnique|ecole polytechnique~u|Northeastern|northeastern university~u|Ben-Gurion|ben-gurion university of the negev~u|INSEAD|insead~u|Reichman|reichman university~u|Penn State|the pennsylvania state university;pennsylvania state university~u|Vanderbilt|vanderbilt university~u|UC Santa Barbara|university of california, santa barbara~u|Florida|university of florida~u|IIT Kanpur|indian institute of technology kanpur~u|UCSF|university of california, san francisco~u|Tsinghua|tsinghua university~u|Minnesota|university of minnesota~u|Tufts|tufts university~u|Technion|technion - israel institute of technology;technion – israel institute of technology~u|UC Davis|university of california, davis~u|Maryland|university of maryland;university of maryland, college park~u|São Paulo|university of sao paulo~u|Ohio State|the ohio state university~u|HEC Paris|hec paris~u|UC Irvine|university of california, irvine~u|LSE|the london school of economics and political science;london school of economics and political science~u|Notre Dame|university of notre dame~u|London Business School|london business school~u|Queen's|queen's university~u|Rice|rice university~u|UBC|university of british columbia;the university of british columbia~u|Bar-Ilan|bar-ilan university~u|Peking|peking university~u|Boston College|boston college~u|King's College London|king's college london~u|Emory|emory university~u|Babson|babson college~u|Arizona State|arizona state university~u|George Washington|the george washington university~u|Tokyo|the university of tokyo~u|Seoul National|seoul national university~u|RPI|rensselaer polytechnic institute~u|KTH|kth royal institute of technology~u|Texas A&M|texas a&m university~u|UNC Chapel Hill|university of north carolina at chapel hill~u|NUS|national university of singapore~u|EPFL|ecole polytechnique federale de lausanne~u|TU Delft|delft university of technology~u|Edinburgh|the university of edinburgh;university of edinburgh~u|KU Leuven|ku leuven~u|Melbourne|university of melbourne;the university of melbourne~u|Sydney|the university of sydney~u|Copenhagen Business School|copenhagen business school~u|Weizmann|weizmann institute of science~u|UNSW|university of new south wales~u|Amsterdam|university of amsterdam~u|Manchester|the university of manchester~u|Bristol|university of bristol~u|Warwick|university of warwick~u|Tec de Monterrey|tecnologico de monterrey~u|Los Andes|universidad de los andes~u|KAIST|korea advanced institute of science and technology~u|Shanghai Jiao Tong|shanghai jiao tong university~u|USTC|university of science and technology of china~u|NC State|north carolina state university~u|Pittsburgh|university of pittsburgh~u|Rochester|university of rochester~u|Case Western|case western reserve university~u|Rutgers|rutgers university~u|Virginia Tech|virginia polytechnic institute and state university~u|Michigan State|michigan state university~u|Arizona|university of arizona~u|UMass Amherst|university of massachusetts amherst~u|Santa Clara|santa clara university~c|Google|google;google x;google brain;youtube~c|Microsoft|microsoft;microsoft research~c|McKinsey|mckinsey & company;mckinsey~c|Goldman Sachs|goldman sachs~c|Amazon|amazon;amazon web services;aws~c|Apple|apple~c|Uber|uber~c|Meta|meta;facebook;instagram~c|IBM|ibm~c|Bain|bain & company~c|BCG|boston consulting group~c|Intel|intel~c|Oracle|oracle~c|Accenture|accenture~c|Morgan Stanley|morgan stanley~c|SpaceX|spacex~c|Tesla|tesla~c|Cisco|cisco;cisco systems~c|Deloitte|deloitte~c|Salesforce|salesforce~c|Yahoo|yahoo~c|LinkedIn|linkedin~c|Palantir|palantir technologies;palantir~c|Stripe|stripe~c|DeepMind|google deepmind;deepmind~c|Twitter|twitter~c|Nvidia|nvidia~c|OpenAI|openai~c|Coinbase|coinbase~c|Pfizer|pfizer~c|Dropbox|dropbox~c|PayPal|paypal~c|Genentech|genentech~c|JPMorgan|j.p. morgan;jp morgan;jpmorgan;jpmorgan chase~c|PwC|pwc~c|Airbnb|airbnb~c|Deutsche Bank|deutsche bank~c|KPMG|kpmg~c|Palo Alto Networks|palo alto networks~c|Capital One|capital one~c|VMware|vmware~c|Credit Suisse|credit suisse~c|Revolut|revolut~c|Square|square~c|eBay|ebay~c|Qualcomm|qualcomm~c|Lockheed Martin|lockheed martin~c|Lyft|lyft~c|UBS|ubs~c|Amgen|amgen~c|Merrill Lynch|merrill lynch~c|Zynga|zynga~c|Bridgewater|bridgewater associates~c|Groupon|groupon~c|Intuit|intuit~c|Juniper Networks|juniper networks~c|Citi|citi;citigroup;citibank~c|Lehman Brothers|lehman brothers~c|Pinterest|pinterest~c|Siemens|siemens~c|Oliver Wyman|oliver wyman~c|Johnson & Johnson|johnson & johnson~c|SAP|sap~c|Sun Microsystems|sun microsystems~c|EY|ey;ernst & young~c|Barclays|barclays;barclays investment bank~c|Boeing|boeing~c|Brex|brex~c|Citadel|citadel~c|Merck|merck~c|Procter & Gamble|procter & gamble~c|Rocket Internet|rocket internet~c|Scale AI|scale ai~c|Cruise|cruise~c|Yelp|yelp~c|Adobe|adobe~c|HSBC|hsbc~c|Instacart|instacart~c|Netflix|netflix~c|Samsung|samsung;samsung electronics~c|Spotify|spotify~c|Blue Origin|blue origin~c|HubSpot|hubspot~c|Flipkart|flipkart~c|Nubank|nubank~c|Rappi|rappi~c|Shopify|shopify~c|Databricks|databricks~c|Atlassian|atlassian~c|Roche|roche~c|Novartis|novartis~c|Sanofi|sanofi~c|AstraZeneca|astrazeneca~c|GSK|glaxosmithkline;gsk~c|Biogen|biogen~c|Illumina|illumina~c|Eli Lilly|eli lilly and company~c|Medtronic|medtronic~c|American Express|american express~c|BlackRock|blackrock~c|Bloomberg|bloomberg~c|Visa|visa~c|Bank of America|bank of america~c|Blackstone|blackstone~c|Affirm|affirm~c|Plaid|plaid~c|Robinhood|robinhood~c|DoorDash|doordash~c|Opendoor|opendoor~c|WeWork|wework~c|Oscar Health|oscar health~c|Splunk|splunk~c|Red Hat|red hat~c|Nutanix|nutanix~c|McAfee|mcafee~c|Symantec|symantec~c|Akamai|akamai technologies~c|Motorola|motorola~c|Nokia|nokia~c|Electronic Arts|electronic arts~c|Walmart|walmart~c|Anduril|anduril~c|Baidu|baidu~c|Infosys|infosys~c|Dell|dell~c|General Electric|general electric~c|Texas Instruments|texas instruments~c|Box|box$seed$, '~') x),
  o as (insert into public.v2_founder_orgs (kind, name) select case k when 'u' then 'uni' else 'co' end, name from src on conflict do nothing returning 1)
  insert into public.v2_founder_org_aliases (kind, value_norm, name)
  select case k when 'u' then 'uni' else 'co' end, a, name from src, regexp_split_to_table(al, ';') a on conflict do nothing;

  execute $f$
  create or replace function public.v2_founders_build() returns jsonb language sql stable security definer set search_path = public as $q$
  with fs as (select distinct founder_id, startup_id from v2_founder_facts where startup_id is not null),
  fc as (select distinct on (founder_id) founder_id, value_norm cc from v2_founder_facts where fact = 'current_country' order by founder_id, fact_id desc),
  city as (select distinct on (founder_id) founder_id, value_norm city from v2_founder_facts where fact = 'current_city' order by founder_id, fact_id desc),
  -- a US founder's state comes from the city name: the state most firms in a city of that name are in
  st as (select city, hq_state from (select lower(btrim(hq_city)) city, hq_state, row_number() over (partition by lower(btrim(hq_city)) order by count(*) desc, hq_state) rk
           from v2_firms where hq_country = 'US' and hq_state is not null and hq_city is not null group by 1, 2) x where rk = 1),
  uo as (select name, (row_number() over (order by name) - 1)::int i from v2_founder_orgs where kind = 'uni'),
  co as (select name, (row_number() over (order by name) - 1)::int i from v2_founder_orgs where kind = 'co'),
  fu as (select distinct f.founder_id, uo.i from v2_founder_facts f join v2_founder_org_aliases a on a.kind = 'uni' and a.value_norm = f.value_norm join uo on uo.name = a.name where f.fact = 'university'),
  fj as (select distinct f.founder_id, co.i from v2_founder_facts f join v2_founder_org_aliases a on a.kind = 'co' and a.value_norm = f.value_norm join co on co.name = a.name where f.fact = 'past_job'),
  sec as (select distinct on (startup_id) startup_id, sector_id from v2_startup_sectors where is_current and not archived order by startup_id, row_id),
  nm as (select distinct on (startup_id) startup_id, startup_name from v2_startups where is_current order by startup_id, row_id desc),
  pl as (select fs.startup_id,
           coalesce(array_agg(distinct fc.cc) filter (where fc.cc ~ '^[a-z]{2}$'), '{}') ||
           coalesce(array_agg(distinct 'US-' || case when city.city = 'lexington' then 'MA' else st.hq_state end) filter (where fc.cc = 'us' and (city.city = 'lexington' or st.hq_state is not null)), '{}') places
         from fs left join fc using (founder_id) left join city using (founder_id) left join st on st.city = city.city group by 1),
  su as (select fs.startup_id, array_agg(distinct fu.i) us from fs join fu using (founder_id) group by 1),
  sj as (select fs.startup_id, array_agg(distinct fj.i) cs from fs join fj using (founder_id) group by 1),
  dl as (select d.startup_id, d.deal_id, d.firm_id, d.deal_date, d.round, d.round_amount, d.amount_currency, d.event_id
         from v2_deals d where d.is_current and d.shown and d.deal_date is not null and d.startup_id in (select startup_id from fs)),
  -- one round = one event; a deal row that is not filed under an event counts as a round only when no other round of that startup sits within 60 days of it
  ev as (select startup_id, coalesce(event_id::text, 'd' || deal_id) k, bool_or(event_id is not null) linked, min(deal_date) dt, max(round_amount) amt,
           (array_agg(amount_currency order by round_amount desc nulls last))[1] cur, max(nullif(nullif(btrim(round), ''), 'Other')) rnd from dl group by 1, 2),
  ev2 as (select e.* from ev e where e.linked or not exists (select 1 from ev o where o.startup_id = e.startup_id and o.k <> e.k and abs(o.dt - e.dt) <= 60
           and (e.amt is null or o.amt = e.amt) and (o.linked or o.k < e.k))),
  -- other currencies at rough fixed rates, so one total can be shown in dollars
  fx(cur, rate) as (values ('USD', 1), ('EUR', 1.08), ('GBP', 1.27), ('CHF', 1.13), ('CAD', 0.73), ('AUD', 0.65), ('NZD', 0.6), ('SGD', 0.75), ('BRL', 0.18), ('INR', 0.012), ('JPY', 0.0066),
           ('KRW', 0.00073), ('CNY', 0.14), ('TWD', 0.031), ('SEK', 0.095), ('NOK', 0.093), ('DKK', 0.145), ('PLN', 0.25), ('CZK', 0.043), ('BGN', 0.55), ('SAR', 0.27), ('ZAR', 0.055)),
  rs as (select e.startup_id, jsonb_agg(jsonb_build_array(to_char(e.dt, 'YYYYMMDD')::int, case when e.amt > 0 and fx.rate is not null then round((e.amt * fx.rate / 1e6)::numeric, 1) end, coalesce(e.rnd, '')) order by e.dt) r
         from ev2 e left join fx on fx.cur = e.cur group by 1),
  fi as (select firm_id, (row_number() over (order by firm_id) - 1)::int i from (select distinct firm_id from dl where firm_id is not null) x),
  sf as (select dl.startup_id, jsonb_agg(distinct fi.i) f from dl join fi using (firm_id) group by 1),
  fnm as (select fi.i, coalesce(nullif(btrim(f.display_name), ''), f.short_name, '?') nm, (select s.slug from firm_summary s where s.firm_id = fi.firm_id and s.listed limit 1) slug
          from fi join (select distinct on (firm_id) firm_id, display_name, short_name from v2_firms order by firm_id) f using (firm_id)),
  rec as (select distinct on (lower(btrim(coalesce(nm.startup_name, ''))), pl.places) pl.startup_id,
            jsonb_build_array(coalesce(nm.startup_name, '?'), coalesce(sec.sector_id, 18), to_jsonb(pl.places), coalesce(to_jsonb(su.us), '[]'::jsonb), rs.r, coalesce(sf.f, '[]'::jsonb), coalesce(to_jsonb(sj.cs), '[]'::jsonb)) j
          from pl join rs using (startup_id) left join nm using (startup_id) left join sec using (startup_id) left join su using (startup_id) left join sj using (startup_id) left join sf using (startup_id)
          where cardinality(pl.places) > 0 or su.us is not null or sj.cs is not null
          order by lower(btrim(coalesce(nm.startup_name, ''))), pl.places, pl.startup_id)
  select jsonb_build_object('asof', now(),
    'sectors', (select jsonb_object_agg(sector_id, name) from v2_sector),
    'unis', coalesce((select jsonb_agg(name order by i) from uo), '[]'::jsonb),
    'cos', coalesce((select jsonb_agg(name order by i) from co), '[]'::jsonb),
    'firms', coalesce((select jsonb_agg(jsonb_build_array(nm, slug) order by i) from fnm), '[]'::jsonb),
    'startups', coalesce((select jsonb_agg(j) from rec), '[]'::jsonb))
  $q$
  $f$;

  execute $f$
  create or replace function public.v2_founders_data() returns jsonb language plpgsql volatile security definer set search_path = public as $q$
  declare d jsonb; t timestamptz;
  begin
    select data, made_at into d, t from v2_founders_cache where id = 1;
    if d is null or t < now() - interval '30 minutes' then
      -- one visitor refreshes it; anyone arriving meanwhile gets the previous answer at once
      if d is null or pg_try_advisory_xact_lock(74120311) then
        d := v2_founders_build();
        insert into v2_founders_cache (id, data, made_at) values (1, d, now()) on conflict (id) do update set data = excluded.data, made_at = excluded.made_at;
      end if;
    end if;
    return d;
  end
  $q$
  $f$;
  revoke all on function public.v2_founders_build() from public, anon, authenticated;
  revoke all on function public.v2_founders_data() from public;
  grant execute on function public.v2_founders_data() to anon, authenticated;
end $wrapci$;
