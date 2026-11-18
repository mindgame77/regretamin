-- Undo universal firm claims (actions next_firm and firm_done).
-- Drops the functions and the v2_work_claims table (claim history only; no firm, deal or submission data).
do $undo$
begin
  drop function if exists public.v2_firm_done(uuid, text, bigint);
  drop function if exists public.v2_next_firm(uuid, text);
  drop function if exists public.v2_work_job_fn(text);
  drop function if exists public.v2_work_bot(uuid);
  drop function if exists public.v2_job_firms_deal_gaps(bigint);
  drop table if exists public.v2_work_claims;
end
$undo$;
