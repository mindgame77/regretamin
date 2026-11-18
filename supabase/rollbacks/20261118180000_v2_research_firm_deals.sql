-- Undo v2 research-bot deal lookup (action deals). Drops the read-only function only.
-- No table or data is changed.
do $undo$
begin
  drop function if exists public.v2_research_firm_deals(uuid, bigint, boolean, int, int);
end
$undo$;
