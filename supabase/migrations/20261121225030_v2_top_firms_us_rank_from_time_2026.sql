-- v2_top_firms_us_rank_from_time_2026 (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_top_firms_us_rank_from_time_2026 skipped';
    return;
  end if;
  execute $designmig$
-- Match TIME's list to our listed firms: by website first, then by name where exactly one US firm has that name.
update public.v2_top_firms_external t set firm_id = f.firm_id
from (select firm_id, lower(regexp_replace(regexp_replace(coalesce(website_url,''),'^https?://(www\.)?',''),'/.*$','')) dom from firm_summary where listed) f
where t.list_year = 2026 and t.source = 'TIME' and f.dom = t.domain;

with nm as (
  select s.firm_id, regexp_replace(btrim(regexp_replace(regexp_replace(regexp_replace(lower(s.display_name),'\(.*\)','','g'),'[^a-z0-9 ]','','g'),'\m(ventures?|capital|partners?|vc|management|group|fund|advisors|investments?|investors|venture|the)\M','','g')),' +',' ','g') k
  from firm_summary s join v2_map_firm_places p using (firm_id) where s.listed and p.region like 'US %'),
one as (select k, min(firm_id) firm_id from nm where k <> '' group by k having count(*) = 1)
update public.v2_top_firms_external t set firm_id = one.firm_id
from one
where t.list_year = 2026 and t.source = 'TIME' and t.firm_id is null
  and one.k = regexp_replace(btrim(regexp_replace(regexp_replace(regexp_replace(lower(t.firm_name),'\(.*\)','','g'),'[^a-z0-9 ]','','g'),'\m(ventures?|capital|partners?|vc|management|group|fund|advisors|investments?|investors|venture|the)\M','','g')),' +',' ','g');

-- The US rank now comes from TIME: the first 100 firms on TIME's list that we have listed and place in the US.
update public.v2_top_firms set us_rank = null where list_year = 2026 and us_rank is not null;

insert into public.v2_top_firms (list_year, firm_id, region, led, deals, us_rank, added_by, note)
select 2026, x.firm_id, x.region,
       coalesce((select count(distinct d.startup_id || '|' || coalesce(d.round::text,'')) from v2_deals d where d.firm_id = x.firm_id and d.is_current and d.lead::text = 'yes' and d.deal_date >= date '2026-11-21' - interval '3 years' and d.deal_date <= date '2026-11-21'), 0),
       coalesce((select count(*) from v2_deals d where d.firm_id = x.firm_id and d.is_current and d.deal_date >= date '2026-11-21' - interval '3 years' and d.deal_date <= date '2026-11-21'), 0),
       x.rn, 'TIME 2026', 'On the list only through TIME''s US ranking'
from (select t.firm_id, p.region, row_number() over (order by t.rank) rn
      from public.v2_top_firms_external t join v2_map_firm_places p using (firm_id)
      where t.list_year = 2026 and t.source = 'TIME' and p.region like 'US %') x
where x.rn <= 100
on conflict (list_year, firm_id) do update set us_rank = excluded.us_rank;
$designmig$;
end
$wrapci$;
