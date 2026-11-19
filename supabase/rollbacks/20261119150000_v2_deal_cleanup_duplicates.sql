-- Rollback for 20261119150000_v2_deal_cleanup_duplicates.sql
-- First undoes every cleanup run that is not undone yet (rows go back exactly as logged), then drops the tools.

do $rb$
begin
  if to_regprocedure('public.v2_deal_cleanup_undo(bigint)') is null then
    raise notice 'cleanup tools missing, skipped';
    return;
  end if;
  perform public.v2_deal_cleanup_undo(null);
  execute 'drop function if exists public.v2_deal_cleanup_duplicates(boolean, int)';
  execute 'drop function if exists public.v2_deal_cleanup_undo(bigint)';
  execute 'drop table if exists public.v2_deal_cleanup_log';
  execute 'drop sequence if exists public.v2_deal_cleanup_run_seq';
end
$rb$;
