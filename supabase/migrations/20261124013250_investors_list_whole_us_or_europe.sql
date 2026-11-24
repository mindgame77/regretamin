-- The map's "See the investors" on the US or Europe view with no circle open: the list shows that whole view,
-- the same firms the map counted. Two existing functions learn "the whole US / Europe" (a level with no area).
-- Every call that worked before gives the same answer: a place was always sent until now.
do $wrapci$
declare s text; n text;
begin
  if to_regprocedure('public.v2_map_firm_ids(text,text,text,date,date,text[],text[])') is null then
    raise notice 'v2_map_firm_ids not present, skipping';
    return;
  end if;

  s := pg_get_functiondef('public.v2_map_firm_ids(text,text,text,date,date,text[],text[])'::regprocedure);
  n := replace(s, $a$(p_level in ('us', 'eu') and p.level = p_level and p.area = p_place))$a$,
                  $b$(p_level in ('us', 'eu') and p.level = p_level and (p_place is null or p.area = p_place)))$b$);
  if n = s then
    if position('p_place is null or p.area = p_place' in s) = 0 then raise exception 'v2_map_firm_ids: place rule not found'; end if;
  else
    execute n;
  end if;

  select pg_get_functiondef(p.oid) into s from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'firm_directory_page_v5';
  n := replace(s, $a$v_deal := v_place is not null and p_deal_from is not null;$a$,
                  $b$v_deal := (v_place is not null or v_plevel in ('us', 'eu')) and p_deal_from is not null;$b$);
  n := replace(n, $a$v_narrow := v_place is not null or v_country$a$, $b$v_narrow := v_place is not null or v_deal or v_country$b$);
  if n = s then
    if position('v_plevel in (''us'', ''eu'')) and p_deal_from' in s) = 0 then raise exception 'firm_directory_page_v5: deal rule not found'; end if;
  else
    execute n;
  end if;
end $wrapci$;
