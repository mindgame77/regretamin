-- Founders "See the investors", correction to founders_see_the_investors (25 Nov): with one of the three Founders words
-- and a period, the list came back empty. The function's own "the map sent a place and a period" switch (v_deal) is
-- neither yes nor no when a period arrives without a map place, and that hid every firm. The Founders filter reads the
-- period itself, so the switch is set to "no" for it. Only calls with 'fplace', 'funi' or 'fco' are affected.
do $wrapci$
declare
  v_def text;
  a3 text := $a$  v_deal := (v_place is not null or v_plevel in ('us', 'eu')) and p_deal_from is not null;$a$;
begin
  if to_regclass('public.v2_founders_cache') is null or to_regprocedure('public.firm_directory_page_v5(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text,text,text,text[],text[],date,date,text[],text[],text)') is null then
    raise notice 'founders cache or the investors list function not present, skipping';
    return;
  end if;
  select pg_get_functiondef('public.firm_directory_page_v5(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text,text,text,text[],text[],date,date,text[],text[],text)'::regprocedure) into v_def;
  if position('v_fkind' in v_def) = 0 or position('if v_fkind is not null then v_deal := false' in v_def) > 0 then
    raise notice 'nothing to correct';
    return;
  end if;
  if (length(v_def) - length(replace(v_def, a3, ''))) / length(a3) <> 1 then
    raise notice 'the investors list function is not as expected, left unchanged';
    return;
  end if;
  v_def := replace(v_def, a3, a3 || E'\n  if v_fkind is not null then v_deal := false; end if;  -- the Founders filter reads the period itself');
  execute v_def;
end $wrapci$;
