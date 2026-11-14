-- Average check: when currency is set and is not USD, the pill shows min_amount and max_amount
-- in that currency. public._money_display supplies the symbol ($ € £ ¥) or the code ("CHF 1M").
-- A null currency, or USD, stays the min_usd / max_usd dollar pill, unchanged.
-- min_usd and max_usd stay the dollar conversion and are not drawn beside a non-USD amount.
-- No new column. No rows are written. The ingest door is unchanged.
-- The v2 schema is not created by repo migrations. On a database without v2_firm_page (CI) this is a no-op.
-- Rollback: supabase/rollbacks/20261114220000_v2_check_size_original_currency.sql
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
  if to_regclass('public.v2_firm_check_sizes') is null
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_firm_check_sizes' and column_name = 'min_amount')
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_firm_check_sizes' and column_name = 'max_amount')
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_firm_check_sizes' and column_name = 'currency') then
    raise exception 'v2_firm_page exists but v2_firm_check_sizes min_amount, max_amount, or currency is missing';
  end if;

  select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into v_def;
  if position($a$c.currency is not null and c.currency <> 'USD'$a$ in v_def) > 0 then
    raise notice 'v2_firm_page check size currency already patched';
    return;
  end if;

  v_old := $old$'check_size',(select case when c.min_usd is not null and c.max_usd is not null and c.min_usd = c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') when c.min_usd is not null and c.max_usd is not null and c.min_usd < c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) and c.max_usd = trunc(c.max_usd) then public._money_display(c.min_usd,'USD') || '–' || public._money_display(c.max_usd,'USD') when c.min_usd is null and c.max_usd is not null and c.max_usd > 0 and c.max_usd = trunc(c.max_usd) then 'Up to ' || public._money_display(c.max_usd,'USD') when c.max_usd is null and c.min_usd is not null and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') || '+' else null end from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived order by c.read_on desc nulls last, c.id desc limit 1),$old$;
  v_new := $new$'check_size',(select case when c.currency is not null and c.currency <> 'USD' then case when c.min_amount is not null and c.max_amount is not null and c.min_amount = c.max_amount and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) then public._money_display(c.min_amount,c.currency) when c.min_amount is not null and c.max_amount is not null and c.min_amount < c.max_amount and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) and c.max_amount = trunc(c.max_amount) then public._money_display(c.min_amount,c.currency) || '–' || public._money_display(c.max_amount,c.currency) when c.min_amount is null and c.max_amount is not null and c.max_amount > 0 and c.max_amount = trunc(c.max_amount) then 'Up to ' || public._money_display(c.max_amount,c.currency) when c.max_amount is null and c.min_amount is not null and c.min_amount > 0 and c.min_amount = trunc(c.min_amount) then public._money_display(c.min_amount,c.currency) || '+' else null end else case when c.min_usd is not null and c.max_usd is not null and c.min_usd = c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') when c.min_usd is not null and c.max_usd is not null and c.min_usd < c.max_usd and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) and c.max_usd = trunc(c.max_usd) then public._money_display(c.min_usd,'USD') || '–' || public._money_display(c.max_usd,'USD') when c.min_usd is null and c.max_usd is not null and c.max_usd > 0 and c.max_usd = trunc(c.max_usd) then 'Up to ' || public._money_display(c.max_usd,'USD') when c.max_usd is null and c.min_usd is not null and c.min_usd > 0 and c.min_usd = trunc(c.min_usd) then public._money_display(c.min_usd,'USD') || '+' else null end end from v2_firm_check_sizes c where c.firm_id=fid and c.is_current and not c.archived order by c.read_on desc nulls last, c.id desc limit 1),$new$;
  if position(v_old in v_def) = 0 then
    raise exception 'v2_firm_page: check size anchor missing';
  end if;
  v_next := replace(v_def, v_old, v_new);
  if v_next = v_def
     or position($a$c.currency is not null and c.currency <> 'USD'$a$ in v_next) = 0
     or position($a$public._money_display(c.min_amount,c.currency)$a$ in v_next) = 0
     or position($a$'check_size',(select case when c.min_usd$a$ in v_next) > 0 then
    raise exception 'v2_firm_page: check size currency patch did not apply';
  end if;
  execute v_next;
end
$mig$;
