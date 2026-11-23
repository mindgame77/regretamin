-- v2_map_who_filter_focus_rules (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_who_filter_focus_rules skipped';
    return;
  end if;
  execute $designmig$
-- Focused funds: at least 10 deals in three years; with a sector chosen more than 33% of them in it,
-- with none chosen more than 50% in any one sector. New entrants now also works with no sector chosen.
do $do$
declare
  fn regprocedure; s text; o text;
  spec constant text := 'exists (select 1 from v2_deals y join v2_startup_sectors ss on ss.startup_id = y.startup_id and ss.is_current join v2_sector sc using (sector_id) where y.firm_id = x.firm_id and y.is_current and y.deal_date > current_date - interval ''3 years'' and y.deal_date <= current_date and sc.name <> ''Other'' group by sc.name having count(*) > 0.5 * (select count(*) from v2_deals z where z.firm_id = x.firm_id and z.is_current and z.deal_date > current_date - interval ''3 years'' and z.deal_date <= current_date))';
begin
  foreach fn in array array['public.v2_map_hot(text,int,text[],text[])'::regprocedure, 'public.v2_map_firms(text,text,text,date,date,text[],text[],int)'::regprocedure] loop
    s := pg_get_functiondef(fn);
    o := s; s := replace(s, 'case when p_firms = ''top'' then ''top'' when p_firms in (''focused'', ''new'') and p_sectors is not null then p_firms else ''all'' end mode', 'case when p_firms in (''top'', ''focused'', ''new'') then p_firms else ''all'' end mode');
    if s = o then raise exception 'mode not found in %', fn; end if;
    o := s; s := replace(s, 'having count(*) >= 5 and count(*) filter (where exists (', 'having count(*) >= 10 and case when p_sectors is null then ' || spec || ' else count(*) filter (where exists (');
    if s = o then raise exception 'having not found in %', fn; end if;
    o := s; s := replace(s, 'sc.name = any(p_sectors))) > 0.25 * count(*)', 'sc.name = any(p_sectors))) > 0.33 * count(*) end');
    if s = o then raise exception 'share not found in %', fn; end if;
    o := s; s := replace(s, 'x.deal_date is not null and exists (', 'x.deal_date is not null and (p_sectors is null or exists (');
    if s = o then raise exception 'first-deal not found in %', fn; end if;
    o := s;
    s := replace(s, 'sc.name = any(p_sectors))) >= coalesce(p_from', 'sc.name = any(p_sectors)))) >= coalesce(p_from');
    s := regexp_replace(s, 'any\(p_sectors\)\)(\s+group by x\.firm_id\),)', 'any(p_sectors)))\1');
    if s = o then raise exception 'first-deal close not found in %', fn; end if;
    execute s;
  end loop;
end
$do$;
$designmig$;
end
$wrapci$;
