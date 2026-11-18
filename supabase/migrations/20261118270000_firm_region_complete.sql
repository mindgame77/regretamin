-- Complete the firm directory country-to-region map. Adds Australia & Oceania
-- and maps every ISO-2 country so "Not disclosed" is only a blank or invalid
-- code. The same map is in launch/js/firms.js. Stored firm_summary.region is
-- recomputed. v2_work_hq_na_europe, the research-bot country filter, is
-- unchanged.
-- Rollback: supabase/rollbacks/20261118270000_firm_region_complete.sql

create or replace function public.firm_summary_region(p_country text)
returns text language sql immutable as $$
  select case case when upper(btrim(p_country)) ~ '^[A-Z]{2}$' then upper(btrim(p_country)) end
    when 'US' then 'north_america' when 'CA' then 'north_america' when 'MX' then 'north_america' when 'GL' then 'north_america' when 'PM' then 'north_america'
    when 'AD' then 'europe' when 'AL' then 'europe' when 'AT' then 'europe' when 'AX' then 'europe' when 'BA' then 'europe' when 'BE' then 'europe'
    when 'BG' then 'europe' when 'BV' then 'europe' when 'BY' then 'europe' when 'CH' then 'europe' when 'CY' then 'europe' when 'CZ' then 'europe'
    when 'DE' then 'europe' when 'DK' then 'europe' when 'EE' then 'europe' when 'ES' then 'europe' when 'FI' then 'europe' when 'FO' then 'europe'
    when 'FR' then 'europe' when 'GB' then 'europe' when 'GG' then 'europe' when 'GI' then 'europe' when 'GR' then 'europe' when 'HR' then 'europe'
    when 'HU' then 'europe' when 'IE' then 'europe' when 'IM' then 'europe' when 'IS' then 'europe' when 'IT' then 'europe' when 'JE' then 'europe'
    when 'LI' then 'europe' when 'LT' then 'europe' when 'LU' then 'europe' when 'LV' then 'europe' when 'MC' then 'europe' when 'MD' then 'europe'
    when 'ME' then 'europe' when 'MK' then 'europe' when 'MT' then 'europe' when 'NL' then 'europe' when 'NO' then 'europe' when 'PL' then 'europe'
    when 'PT' then 'europe' when 'RO' then 'europe' when 'RS' then 'europe' when 'RU' then 'europe' when 'SE' then 'europe' when 'SI' then 'europe'
    when 'SJ' then 'europe' when 'SK' then 'europe' when 'SM' then 'europe' when 'UA' then 'europe' when 'VA' then 'europe' when 'XK' then 'europe'
    when 'AG' then 'latam' when 'AI' then 'latam' when 'AR' then 'latam' when 'AW' then 'latam' when 'BB' then 'latam' when 'BL' then 'latam'
    when 'BM' then 'latam' when 'BO' then 'latam' when 'BQ' then 'latam' when 'BR' then 'latam' when 'BS' then 'latam' when 'BZ' then 'latam'
    when 'CL' then 'latam' when 'CO' then 'latam' when 'CR' then 'latam' when 'CU' then 'latam' when 'CW' then 'latam' when 'DM' then 'latam'
    when 'DO' then 'latam' when 'EC' then 'latam' when 'FK' then 'latam' when 'GD' then 'latam' when 'GF' then 'latam' when 'GP' then 'latam'
    when 'GS' then 'latam' when 'GT' then 'latam' when 'GY' then 'latam' when 'HN' then 'latam' when 'HT' then 'latam' when 'JM' then 'latam'
    when 'KN' then 'latam' when 'KY' then 'latam' when 'LC' then 'latam' when 'MF' then 'latam' when 'MQ' then 'latam' when 'MS' then 'latam'
    when 'NI' then 'latam' when 'PA' then 'latam' when 'PE' then 'latam' when 'PR' then 'latam' when 'PY' then 'latam' when 'SR' then 'latam'
    when 'SV' then 'latam' when 'SX' then 'latam' when 'TC' then 'latam' when 'TT' then 'latam' when 'UY' then 'latam' when 'VC' then 'latam'
    when 'VE' then 'latam' when 'VG' then 'latam' when 'VI' then 'latam'
    when 'AF' then 'asia' when 'AM' then 'asia' when 'AZ' then 'asia' when 'BD' then 'asia' when 'BN' then 'asia' when 'BT' then 'asia'
    when 'CN' then 'asia' when 'GE' then 'asia' when 'HK' then 'asia' when 'ID' then 'asia' when 'IN' then 'asia' when 'IO' then 'asia'
    when 'JP' then 'asia' when 'KG' then 'asia' when 'KH' then 'asia' when 'KP' then 'asia' when 'KR' then 'asia' when 'KZ' then 'asia'
    when 'LA' then 'asia' when 'LK' then 'asia' when 'MM' then 'asia' when 'MN' then 'asia' when 'MO' then 'asia' when 'MV' then 'asia'
    when 'MY' then 'asia' when 'NP' then 'asia' when 'PH' then 'asia' when 'PK' then 'asia' when 'SG' then 'asia' when 'TH' then 'asia'
    when 'TJ' then 'asia' when 'TL' then 'asia' when 'TM' then 'asia' when 'TW' then 'asia' when 'UZ' then 'asia' when 'VN' then 'asia'
    when 'AE' then 'middle_east' when 'BH' then 'middle_east' when 'IL' then 'middle_east' when 'IQ' then 'middle_east' when 'IR' then 'middle_east' when 'JO' then 'middle_east'
    when 'KW' then 'middle_east' when 'LB' then 'middle_east' when 'OM' then 'middle_east' when 'PS' then 'middle_east' when 'QA' then 'middle_east' when 'SA' then 'middle_east'
    when 'SY' then 'middle_east' when 'TR' then 'middle_east' when 'YE' then 'middle_east'
    when 'AO' then 'africa' when 'BF' then 'africa' when 'BI' then 'africa' when 'BJ' then 'africa' when 'BW' then 'africa' when 'CD' then 'africa'
    when 'CF' then 'africa' when 'CG' then 'africa' when 'CI' then 'africa' when 'CM' then 'africa' when 'CV' then 'africa' when 'DJ' then 'africa'
    when 'DZ' then 'africa' when 'EG' then 'africa' when 'EH' then 'africa' when 'ER' then 'africa' when 'ET' then 'africa' when 'GA' then 'africa'
    when 'GH' then 'africa' when 'GM' then 'africa' when 'GN' then 'africa' when 'GQ' then 'africa' when 'GW' then 'africa' when 'KE' then 'africa'
    when 'KM' then 'africa' when 'LR' then 'africa' when 'LS' then 'africa' when 'LY' then 'africa' when 'MA' then 'africa' when 'MG' then 'africa'
    when 'ML' then 'africa' when 'MR' then 'africa' when 'MU' then 'africa' when 'MW' then 'africa' when 'MZ' then 'africa' when 'NA' then 'africa'
    when 'NE' then 'africa' when 'NG' then 'africa' when 'RE' then 'africa' when 'RW' then 'africa' when 'SC' then 'africa' when 'SD' then 'africa'
    when 'SH' then 'africa' when 'SL' then 'africa' when 'SN' then 'africa' when 'SO' then 'africa' when 'SS' then 'africa' when 'ST' then 'africa'
    when 'SZ' then 'africa' when 'TD' then 'africa' when 'TF' then 'africa' when 'TG' then 'africa' when 'TN' then 'africa' when 'TZ' then 'africa'
    when 'UG' then 'africa' when 'YT' then 'africa' when 'ZA' then 'africa' when 'ZM' then 'africa' when 'ZW' then 'africa'
    when 'AS' then 'oceania' when 'AU' then 'oceania' when 'CC' then 'oceania' when 'CK' then 'oceania' when 'CX' then 'oceania' when 'FJ' then 'oceania'
    when 'FM' then 'oceania' when 'GU' then 'oceania' when 'HM' then 'oceania' when 'KI' then 'oceania' when 'MH' then 'oceania' when 'MP' then 'oceania'
    when 'NC' then 'oceania' when 'NF' then 'oceania' when 'NR' then 'oceania' when 'NU' then 'oceania' when 'NZ' then 'oceania' when 'PF' then 'oceania'
    when 'PG' then 'oceania' when 'PN' then 'oceania' when 'PW' then 'oceania' when 'SB' then 'oceania' when 'TK' then 'oceania' when 'TO' then 'oceania'
    when 'TV' then 'oceania' when 'UM' then 'oceania' when 'VU' then 'oceania' when 'WF' then 'oceania' when 'WS' then 'oceania'
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
