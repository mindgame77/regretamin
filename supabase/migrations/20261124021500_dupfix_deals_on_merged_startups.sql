do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_events') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 5: move shown deals that sit on merged (archived) startups to the merge target; archive any that become repeats.
create table dupfix_20261123.s5_deals_state as
  select d.deal_id, d.startup_id, d.shown, d.is_current, d.archived, d.archive_reason, d.event_id,
         (regexp_match(s.archive_reason, 'Duplicate of startup (\d+)'))[1]::bigint as target_id
  from public.v2_deals d join public.v2_startups s using (startup_id)
  where d.shown and s.archived and s.archive_reason ~ '^Duplicate of startup \d+';
delete from dupfix_20261123.s5_deals_state x using public.v2_startups t where t.startup_id = x.target_id and t.archived;
update public.v2_deals d set startup_id = x.target_id from dupfix_20261123.s5_deals_state x where d.deal_id = x.deal_id;
with dup as (
  select x.deal_id, min(y.deal_id) keep_id from dupfix_20261123.s5_deals_state x
  join public.v2_deals d on d.deal_id = x.deal_id
  join public.v2_deals y on y.deal_id <> d.deal_id and y.firm_id = d.firm_id and y.startup_id = d.startup_id and y.is_current and not y.archived
   and public.v2_deal_round_norm(y.round) = public.v2_deal_round_norm(d.round) and abs(y.deal_date - d.deal_date) <= 366
   and y.deal_id not in (select deal_id from dupfix_20261123.s5_deals_state)
  group by x.deal_id)
update public.v2_deals d set archived = true, is_current = false, shown = false, archive_reason = 'Duplicate of deal ' || dup.keep_id
from dup where d.deal_id = dup.deal_id;
$sql$;
end $mig$;
