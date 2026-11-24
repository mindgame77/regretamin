do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_events') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 6: join split register event 1291 into 1290 (Wormsensing Series A $9.5M, 2026-10-27, same press release).
-- 1291 is left in place with no deals or sources (v2_events has no archive flag; nothing is deleted).
create table dupfix_20261123.s6_deals as select deal_id, event_id from public.v2_deals where event_id = 1291;
create table dupfix_20261123.s6_sources as select source_id, event_id from public.v2_event_sources where event_id = 1291;
create table dupfix_20261123.s6_firms as select event_id, firm_id, noted_name, lead from public.v2_event_firms where event_id = 1291;
update public.v2_deals set event_id = 1290 where event_id = 1291;
update public.v2_event_sources set event_id = 1290 where event_id = 1291;
insert into public.v2_event_firms (event_id, firm_id, noted_name, lead)
  select 1290, f.firm_id, f.noted_name, f.lead from dupfix_20261123.s6_firms f
  where not exists (select 1 from public.v2_event_firms k where k.event_id = 1290 and k.firm_id is not distinct from f.firm_id and k.noted_name is not distinct from f.noted_name);
$sql$;
end $mig$;
