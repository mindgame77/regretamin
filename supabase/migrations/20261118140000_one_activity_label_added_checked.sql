-- One activity label, decided by the database, and firm_summary.added as the one "checked" date.
--
-- 1. public.api_activity_label(deals, dated_dates, investments, researched) is the rule (Alex):
--    Active = 3+ dated deals in the year window, Low activity = 1-2, Not active = none in the window but
--    researched or any deal / undated portfolio row on record, Not checked yet = none of those.
--    firm_directory_page_v2 rows get 'activity' and v2_firm_page activity gets 'label', both from that
--    function over firm_summary. The /investors/ list and the firm page only display it.
--    Computed on read from the stored firm_summary row: no trigger, nothing on the bot write path.
-- 2. The SEO job reads firm_summary.added (the date the firm's data was added) instead of
--    v2_firms.last_checked_date, for "Checked <date>", facts.last_checked, sitemap lastmod and change detection.
--
-- Each existing function gets one small text insertion into its live definition (skipped if already done).
-- Not applied by this change. Rollback: supabase/rollbacks/20261118140000_one_activity_label_added_checked.sql

do $mig$
declare
  v_def text;
begin
  if to_regclass('public.firm_summary') is null then
    raise notice 'firm_summary missing, skipped';
    return;
  end if;

  execute $fn$
create or replace function public.api_activity_label(p_deals integer, p_dates date[], p_investments integer, p_researched boolean)
returns text
language sql
stable
set search_path to 'pg_temp'
as $body$
  select case
    when n >= 3 then 'Active'
    when n >= 1 then 'Low activity'
    when coalesce(p_deals, 0) > 0 or coalesce(p_investments, 0) > 0 or coalesce(p_researched, false) then 'Not active'
    else 'Not checked yet'
  end
  from (
    select count(*)::integer as n
      from unnest(coalesce(p_dates, '{}'::date[])) as d(day)
     where extract(year from d.day) between extract(year from current_date)::integer
             - case when extract(month from current_date) < 6 then 1 else 0 end
         and extract(year from current_date)::integer
  ) c
$body$;
$fn$;

  -- /investors/ rows
  if to_regprocedure('public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])') is not null then
    v_def := pg_get_functiondef('public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])'::regprocedure);
    if strpos(v_def, 'api_activity_label(o.deals') = 0 then
      if strpos(v_def, $a$'deals_this_year', o.deals_this_year,$a$) = 0 then
        raise exception 'firm_directory_page_v2: row anchor not found';
      end if;
      execute replace(v_def, $a$'deals_this_year', o.deals_this_year,$a$,
        $a$'deals_this_year', o.deals_this_year, 'activity', public.api_activity_label(o.deals, o.dated_dates, o.investments, o.researched),$a$);
    end if;
  end if;

  -- firm page payload
  if to_regprocedure('public.v2_firm_page(text)') is not null then
    v_def := pg_get_functiondef('public.v2_firm_page(text)'::regprocedure);
    if strpos(v_def, 'api_activity_label(s.deals') = 0 then
      if strpos(v_def, $a$'activity',json_build_object('lazy',false,'active',true,$a$) = 0 then
        raise exception 'v2_firm_page: activity anchor not found';
      end if;
      execute replace(v_def, $a$'activity',json_build_object('lazy',false,'active',true,$a$,
        $a$'activity',json_build_object('lazy',false,'active',true,'label',(select public.api_activity_label(s.deals, s.dated_dates, s.investments, s.researched) from firm_summary s where s.firm_id=fid),$a$);
    end if;
  end if;

  -- SEO job: checked date = firm_summary.added
  if to_regprocedure('public.v2_firm_seo_compute(bigint[])') is not null then
    v_def := pg_get_functiondef('public.v2_firm_seo_compute(bigint[])'::regprocedure);
    if strpos(v_def, 's.added::date as last_checked_date') = 0 then
      if strpos(v_def, E'f.last_checked_date,\n') = 0 then raise exception 'v2_firm_seo_compute: anchor not found'; end if;
      execute replace(v_def, E'f.last_checked_date,\n', E's.added::date as last_checked_date,\n');
    end if;
    v_def := pg_get_functiondef('public.v2_firm_seo_refresh(integer)'::regprocedure);
    if strpos(v_def, 'fs.added::date is distinct from s.last_checked_date') = 0 then
      if strpos(v_def, 'f.last_checked_date is distinct from s.last_checked_date') = 0 then raise exception 'v2_firm_seo_refresh: anchor not found'; end if;
      execute replace(v_def, 'f.last_checked_date is distinct from s.last_checked_date', 'fs.added::date is distinct from s.last_checked_date');
    end if;
  end if;
end
$mig$;
