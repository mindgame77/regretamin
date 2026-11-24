do $mig$
begin
  if to_regclass('public.v2_deals') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
create schema if not exists dupfix_20261123;
-- Step 9: of the remaining same firm+startup+round pairs (more than a year apart or otherwise not caught in step 1), archive only the 8 that are clearly one round:
-- same press article and amount (Omnea, PlayerZero, Tacta), the same announcement from two sources (Parasail, Thinkpilot), or a portfolio-page year with no date conflict (Great Wave x3).
create table dupfix_20261123.s9_map (archived_deal_id bigint primary key, kept_deal_id bigint not null, prev_shown boolean, prev_is_current boolean, prev_archive_reason text);
insert into dupfix_20261123.s9_map (archived_deal_id, kept_deal_id)
values (5633, 45422), (30286, 12131), (45207, 37869), (29238, 49006), (60388, 367973), (325930, 332777), (325938, 332787), (325976, 332797);
update dupfix_20261123.s9_map m set prev_shown = d.shown, prev_is_current = d.is_current, prev_archive_reason = d.archive_reason
from public.v2_deals d where d.deal_id = m.archived_deal_id;
update public.v2_deals d set archived = true, is_current = false, shown = false, archive_reason = 'Duplicate of deal ' || m.kept_deal_id
from dupfix_20261123.s9_map m
where d.deal_id = m.archived_deal_id and not d.archived
  and exists (select 1 from public.v2_deals k where k.deal_id = m.kept_deal_id and k.is_current and not k.archived and k.firm_id = d.firm_id and k.startup_id = d.startup_id);
$sql$;
end $mig$;
