-- Undo renewing a deal_gaps hold when a submit is accepted.
do $undo$
begin
  if to_regclass('public.v2_research_submissions') is not null then
    execute 'drop trigger if exists v2_renew_deal_gap_holds on public.v2_research_submissions';
  end if;
  drop function if exists public.v2_renew_deal_gap_holds();
end
$undo$;
