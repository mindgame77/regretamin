-- Undo 20261114220000_v2_check_size_original_currency.
-- firm.check_size again formats only min_usd and max_usd as US dollars.
-- Rows in v2_firm_check_sizes stay. Nothing is deleted.
do $mig$
declare
  v_def text;
  v_next text;
  v_old text;
  v_new text;
begin
  if to_regprocedure('public.v2_firm_page(text)') is null then
    raise notice 'v2 schema missing, skipped page';
    return;
  end if;
  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into v_def;
  v_old := $old$'check_size',(select case when c.currency is not null and c.currency <> 'USD' then case when c.min_amount is not null and c.max_amount is not null and c.min_amount = c.max_amount and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) then public._money_display(c.min_amount,c.currency) when c.min_amount is not null and c.max_amount is not null and c.min_amount < c.max_amount and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) and c.max_amount = trunc(c.max_amount) then public._money_display(c.min_amount,c.currency) || '–' || public._money_display(c.max_amount,c.currency) when c.min_amount is null and c.max_amount is not null and c.max_amount > 0 and c.max_amount = trunc(c.max_amount) then 'Up to ' || public._money_display(c.max_amount,c.currency) when c.max_amount is null and c.min_amount is not null and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) then public._money_display(c.min_amount,c.currency) || '+' else null end else case when c.min_usd is not null and c.max_usd is not null and c.min_usd = c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') when c.min_usd is not null and c.max_usd is not null and c.min_usd < c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) and c.max_usd = trunc(c.max_usd) then public._money_display(c.min_usd,'USD') || '–' || public._money_display(c.max_usd,'USD') when c.min_usd is null and c.max_usd is not null and c.max_usd > 0 and c.max_usd = trunc(c.max_usd) then 'Up to ' || public._money_display(c.max_usd,'USD') when c.max_usd is null and c.min_usd is not null and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') || '+' else null end end from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived order by c.read_on desc nulls last, c.id desc limit 1),$old$;
  v_new := $new$'check_size',(select case when c.min_usd is not null and c.max_usd is not null and c.min_usd = c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') when c.min_usd is not null and c.max_usd is not null and c.min_usd < c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) and c.max_usd = trunc(c.max_usd) then public._money_display(c.min_usd,'USD') || '–' || public._money_display(c.max_usd,'USD') when c.min_usd is null and c.max_usd is not null and c.max_usd > 0 and c.max_usd = trunc(c.max_usd) then 'Up to ' || public._money_display(c.max_usd,'USD') when c.max_usd is null and c.min_usd is not null and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') || '+' else null end from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived order by c.read_on desc nulls last, c.id desc limit 1),$new$;
  if position(v_old in v_def) = 0 then
    raise notice 'v2_firm_page check size currency already absent';
  else
    v_next := replace(v_def, v_old, v_new);
    if v_next = v_def
       or position($a$c.currency is not null and c.currency <> 'USD'$a$ in v_next) > 0
       or position($a$'check_size',(select case when c.min_usd$a$ in v_next) = 0 then
      raise exception 'v2_firm_page: check size currency undo did not apply';
    end if;
    execute v_next;
  end if;
end
$mig$;
