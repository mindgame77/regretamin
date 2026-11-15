-- Firm page: return hidden bare deals (no date, no amount, D1.8 / v2_deals_check7)
-- as activity.portfolio_only. A bare row is omitted when that firm already has a dated deal in the same startup.
-- The shown flag is not changed. activity.deals,
-- counts.deals, deals_12m and latest_deal stay dated-only.
-- The v2 schema is not created by repo migrations. On a database without
-- _v2_deals / v2_firm_page (CI) this is a no-op.
-- Rollback: supabase/rollbacks/20261116010000_v2_portfolio_only_deals.sql
do $mig$
declare
  d text;
  n text;
begin
  if to_regprocedure('public._v2_deals(bigint)') is null
     or to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_startups') is null then
    raise exception 'v2_firm_page exists but v2_deals or v2_startups is missing';
  end if;

  execute $fn$
create or replace function public._v2_portfolio_only(fid bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(x order by x->>'company'),'[]') from (
    select jsonb_build_object(
      'company', s.startup_name,
      'round', d.round,
      'date', d.deal_date::text,
      'date_precision', coalesce(d.deal_date_precision, 'day'),
      'url', d.source_url,
      'amount', d.round_amount,
      'currency', d.amount_currency,
      'lead', coalesce(d.lead = 'yes', false),
      'sector', sec.name,
      'industry_name', sec.industry_name,
      'domain', s.domain,
      'website_url', s.website_url,
      'st_status', s.st_status,
      'portfolio_only', true) x
    from v2_deals d
    join v2_startups s on s.startup_id = d.startup_id and s.is_current and not s.archived
    left join lateral (
      select sc.name, nullif(btrim(ss.industry_name), '') as industry_name
      from v2_startup_sectors ss
      join v2_sector sc on sc.sector_id = ss.sector_id
      where ss.startup_id = s.startup_id and ss.is_current and not ss.archived
      limit 1
    ) sec on true
    where d.firm_id = fid and d.is_current and not d.archived and not d.nothing_found
      and d.deal_date is null and d.round_amount is null
      and not coalesce(d.shown, true)
      and not exists (
        select 1 from v2_deals x
        where x.firm_id = d.firm_id and x.startup_id = d.startup_id
          and x.is_current and not x.archived and not x.nothing_found
          and coalesce(x.shown, true) and x.deal_date is not null)
  ) q
$$
$fn$;
  execute 'revoke all on function public._v2_portfolio_only(bigint) from public, anon, authenticated';
  execute 'grant execute on function public._v2_portfolio_only(bigint) to service_role';

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
  if position($a$portfolio_only := _v2_portfolio_only(fid)$a$ in d) > 0
     and position($a$'portfolio_only',portfolio_only$a$ in d) > 0 then
    raise notice 'v2_firm_page portfolio_only already patched';
    return;
  end if;

  if position($a$deals jsonb;$a$ in d) = 0 then
    raise exception 'v2_firm_page: deals declare anchor missing';
  end if;
  n := replace(d, $a$deals jsonb;$a$, $a$deals jsonb; portfolio_only jsonb;$a$);

  if position($a$deals := _v2_deals(fid);$a$ in n) = 0 then
    raise exception 'v2_firm_page: deals assign anchor missing';
  end if;
  n := replace(n,
    $a$deals := _v2_deals(fid);$a$,
    $a$deals := _v2_deals(fid);
  portfolio_only := _v2_portfolio_only(fid);$a$);

  if position($a$'deals',deals,'reviews',revs$a$ in n) = 0 then
    raise exception 'v2_firm_page: activity deals anchor missing';
  end if;
  n := replace(n,
    $a$'deals',deals,'reviews',revs$a$,
    $a$'deals',deals,'portfolio_only',coalesce(portfolio_only,'[]'::jsonb),'reviews',revs$a$);

  if n = d
     or position($a$portfolio_only := _v2_portfolio_only(fid)$a$ in n) = 0
     or position($a$'portfolio_only',coalesce(portfolio_only,'[]'::jsonb)$a$ in n) = 0
     or position($a$'deals',deals,'reviews',revs$a$ in n) > 0 then
    raise exception 'v2_firm_page: portfolio_only patch did not apply';
  end if;
  execute n;
end
$mig$;
