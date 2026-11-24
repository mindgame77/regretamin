-- Investors list: one more sort word, 'known' = by the deals we know in detail (dated, shown), then by all
-- investments found. The Deals column now shows both numbers ("9 (228)") and sorts by the first
-- (founder, 24 Nov: "please do"). Additive: the word 'deals' still sorts by all investments found, as before.
do $wrapci$
declare s text; n text; sig text := 'public.firm_directory_page_v5(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text,text,text,text[],text[],date,date,text[],text[],text)';
begin
  if to_regprocedure(sig) is null then
    raise notice 'firm_directory_page_v5 not present, skipping';
    return;
  end if;
  s := pg_get_functiondef(sig::regprocedure);
  if position('''known''' in s) > 0 then return; end if;  -- already done
  n := replace(s, $a$p_sort in ('newest', 'name', 'city', 'deal', 'deals', 'activity')$a$, $b$p_sort in ('newest', 'name', 'city', 'deal', 'deals', 'known', 'activity')$b$);
  if n = s then raise exception 'list of sort words not found'; end if;
  s := n;
  n := replace(s, $a$             case when v_sort = 'deals' and v_asc then nullif(m.investments, 0) end asc nulls last,$a$,
$b$             case when v_sort = 'known' and v_asc then coalesce(m.deals, 0) end asc,
             case when v_sort = 'known' and not v_asc then coalesce(m.deals, 0) end desc,
             case when v_sort = 'known' and v_asc then nullif(m.investments, 0) end asc nulls last,
             case when v_sort = 'known' and not v_asc then nullif(m.investments, 0) end desc nulls last,
             case when v_sort = 'deals' and v_asc then nullif(m.investments, 0) end asc nulls last,$b$);
  if n = s then raise exception 'deals sort rule not found'; end if;
  execute n;
end $wrapci$;
