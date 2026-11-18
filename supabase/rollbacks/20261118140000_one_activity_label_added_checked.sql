-- Rollback for 20261118140000_one_activity_label_added_checked.sql: removes each text insertion, then the 4-argument label function.
do $rb$
declare v_def text;
begin
  if to_regprocedure('public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])') is not null then
    v_def := pg_get_functiondef('public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])'::regprocedure);
    if strpos(v_def, 'api_activity_label(o.deals') > 0 then
      execute replace(v_def, $a$ 'activity', public.api_activity_label(o.deals, o.dated_dates, o.investments, o.researched),$a$, '');
    end if;
  end if;
  if to_regprocedure('public.v2_firm_page(text)') is not null then
    v_def := pg_get_functiondef('public.v2_firm_page(text)'::regprocedure);
    if strpos(v_def, 'api_activity_label(s.deals') > 0 then
      execute replace(v_def, $a$'label',(select public.api_activity_label(s.deals, s.dated_dates, s.investments, s.researched) from firm_summary s where s.firm_id=fid),$a$, '');
    end if;
  end if;
  if to_regprocedure('public.v2_firm_seo_compute(bigint[])') is not null then
    v_def := pg_get_functiondef('public.v2_firm_seo_compute(bigint[])'::regprocedure);
    execute replace(v_def, E's.added::date as last_checked_date,\n', E'f.last_checked_date,\n');
    v_def := pg_get_functiondef('public.v2_firm_seo_refresh(integer)'::regprocedure);
    execute replace(v_def, 'fs.added::date is distinct from s.last_checked_date', 'f.last_checked_date is distinct from s.last_checked_date');
  end if;
  drop function if exists public.api_activity_label(integer, date[], integer, boolean);
end
$rb$;
