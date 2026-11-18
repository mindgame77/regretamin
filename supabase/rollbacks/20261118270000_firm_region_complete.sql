-- Rollback for 20261118270000_firm_region_complete.sql: restore the previous
-- firm_summary_region map and recompute stored firm_summary.region. The
-- Australia & Oceania filter option comes back out when launch/js/firms.js
-- is reverted with the pull request.

create or replace function public.firm_summary_region(p_country text)
returns text language sql immutable as $$
  select case case when upper(btrim(p_country)) ~ '^[A-Z]{2}$' then upper(btrim(p_country)) end
    when 'US' then 'north_america' when 'CA' then 'north_america' when 'MX' then 'north_america'
    when 'GB' then 'europe' when 'CH' then 'europe' when 'IE' then 'europe' when 'DE' then 'europe'
    when 'FR' then 'europe' when 'NL' then 'europe' when 'SE' then 'europe' when 'NO' then 'europe'
    when 'DK' then 'europe' when 'FI' then 'europe' when 'IT' then 'europe' when 'ES' then 'europe'
    when 'AT' then 'europe' when 'BE' then 'europe' when 'PT' then 'europe' when 'UA' then 'europe' when 'PL' then 'europe' when 'LU' then 'europe' when 'EE' then 'europe' when 'BG' then 'europe' when 'IS' then 'europe' when 'CY' then 'europe' when 'CZ' then 'europe' when 'IM' then 'europe' when 'LV' then 'europe' when 'LT' then 'europe' when 'RO' then 'europe' when 'HU' then 'europe' when 'SK' then 'europe' when 'SI' then 'europe' when 'HR' then 'europe' when 'RS' then 'europe' when 'GR' then 'europe' when 'MT' then 'europe' when 'MC' then 'europe' when 'LI' then 'europe' when 'JE' then 'europe' when 'GG' then 'europe' when 'GI' then 'europe' when 'BA' then 'europe' when 'MK' then 'europe' when 'AL' then 'europe' when 'ME' then 'europe' when 'MD' then 'europe' when 'AD' then 'europe' when 'SM' then 'europe'
    when 'KY' then 'latam' when 'BR' then 'latam' when 'AR' then 'latam' when 'CL' then 'latam' when 'CO' then 'latam'
    when 'CN' then 'asia' when 'JP' then 'asia' when 'KR' then 'asia' when 'SG' then 'asia'
    when 'IN' then 'asia' when 'HK' then 'asia' when 'TW' then 'asia'
    when 'ZA' then 'africa' when 'NG' then 'africa' when 'KE' then 'africa' when 'EG' then 'africa'
    when 'AE' then 'middle_east' when 'IL' then 'middle_east' when 'SA' then 'middle_east' when 'QA' then 'middle_east'
    else 'unknown' end
$$;

do $mig$
begin
  if to_regclass('public.firm_summary') is null then
    raise notice 'firm_summary missing, skipped recompute';
    return;
  end if;
  update public.firm_summary s
     set region = public.firm_summary_region(s.hq_country)
   where s.region is distinct from public.firm_summary_region(s.hq_country);
end
$mig$;
