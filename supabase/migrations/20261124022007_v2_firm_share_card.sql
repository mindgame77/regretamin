-- The numbers for the firm share card (the picture a messenger shows for a shared /vc/<slug>/ link).
-- Read-only. One row from firm_summary plus the firm's signals; the same rules the pages use
-- (status = api_activity_label, "deals this year" = the Investors list's count).
do $wrapci$
begin
  if to_regclass('public.v2_firm_signals') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables not present, skipping v2_firm_share_card';
    return;
  end if;
  execute $cardfn$
create or replace function public.v2_firm_share_card(p_slug text)
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $fn$
  select jsonb_build_object(
    'name', s.display_name,
    'hq', nullif(concat_ws(', ', nullif(btrim(coalesce(s.city_label, s.hq_city)), ''),
                               coalesce(nullif(btrim(s.hq_state), ''), nullif(btrim(s.hq_country), ''))), ''),
    'status', public.api_activity_label(s.deals, s.dated_dates, s.investments, s.researched),
    'last_deal', s.latest_deal_date,
    'deals_year', (select count(*) from unnest(coalesce(s.dated_dates, '{}'::date[])) d
                    where extract(year from d) between extract(year from current_date)::int
                            - case when extract(month from current_date) < 6 then 1 else 0 end
                          and extract(year from current_date)::int),
    'deals_all', coalesce(s.deals, 0),
    'signals', coalesce((select to_jsonb(g.signals) from v2_firm_signals g where g.firm_id = s.firm_id), '[]'::jsonb),
    'sectors', coalesce((select jsonb_agg(q.x order by q.i) from (
                  select t.x, t.i from jsonb_array_elements_text(coalesce(to_jsonb(s.industries), '[]'::jsonb)) with ordinality t(x, i)
                  order by t.i limit 3) q), '[]'::jsonb))
  from firm_summary s
  where s.listed and s.slug = left(lower(btrim(coalesce(p_slug, ''))), 120)
  limit 1
$fn$;
grant execute on function public.v2_firm_share_card(text) to anon, authenticated;
$cardfn$;
end $wrapci$;
