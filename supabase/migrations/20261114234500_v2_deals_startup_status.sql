-- Deal lists: each startup name keeps every existing field and gains st_status from v2_startups.
-- The page colors Shut down and Acquired from that value. Other values and null stay uncolored.
-- No other field changes. No rows are written. Old clients ignore the extra key.
-- The v2 schema is not created by repo migrations. On a database without _v2_deals (CI) this is a no-op.
-- Not applied to the live database. Apply after review.
-- Rollback: supabase/rollbacks/20261114234500_v2_deals_startup_status.sql
do $mig$
declare
  d text;
  n text;
begin
  if to_regprocedure('public._v2_deals(bigint)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  if to_regclass('public.v2_startups') is null
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_startups' and column_name = 'st_status'
     ) then
    raise exception '_v2_deals exists but v2_startups.st_status is missing';
  end if;

  select pg_get_functiondef('public._v2_deals(bigint)'::regprocedure) into d;
  if position($a$'st_status', s.st_status$a$ in d) > 0 then
    raise notice '_v2_deals st_status already present';
    return;
  end if;
  if position($a$'website_url', s.website_url) x$a$ in d) = 0 then
    raise exception '_v2_deals: website_url anchor missing';
  end if;
  n := replace(d,
    $a$'website_url', s.website_url) x$a$,
    $a$'website_url', s.website_url, 'st_status', s.st_status) x$a$);
  if n = d
     or position($a$'st_status', s.st_status$a$ in n) = 0
     or position($a$'company', s.startup_name$a$ in n) = 0
     or position($a$'industry_name', sec.industry_name$a$ in n) = 0
     or position($a$'website_url', s.website_url) x$a$ in n) > 0 then
    raise exception '_v2_deals: st_status patch did not apply';
  end if;
  execute n;
end
$mig$;
