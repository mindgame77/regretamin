-- Undo 20261116010000_v2_portfolio_only_deals: drop activity.portfolio_only
-- from v2_firm_page and remove _v2_portfolio_only. shown flags and deal rows
-- are not changed.
do $mig$
declare
  d text;
  n text;
begin
  if to_regprocedure('public.v2_firm_page(text)') is not null then
    select pg_get_functiondef('public.v2_firm_page(text)'::regprocedure) into d;
    if position($a$portfolio_only$a$ in d) > 0 then
      n := d;
      n := replace(n,
        $a$'deals',deals,'portfolio_only',coalesce(portfolio_only,'[]'::jsonb),'reviews',revs$a$,
        $a$'deals',deals,'reviews',revs$a$);
      n := replace(n,
        $a$deals := _v2_deals(fid);
  portfolio_only := _v2_portfolio_only(fid);$a$,
        $a$deals := _v2_deals(fid);$a$);
      n := replace(n, $a$deals jsonb; portfolio_only jsonb;$a$, $a$deals jsonb;$a$);
      if n = d or position($a$portfolio_only$a$ in n) > 0 then
        raise exception 'v2_firm_page: portfolio_only undo did not apply';
      end if;
      execute n;
    else
      raise notice 'v2_firm_page portfolio_only already absent';
    end if;
  end if;
  if to_regprocedure('public._v2_portfolio_only(bigint)') is not null then
    execute 'drop function public._v2_portfolio_only(bigint)';
  end if;
end
$mig$;
