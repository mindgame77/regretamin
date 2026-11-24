do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_events') is null or to_regclass('merge_20261121.groups') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 3: merge 4 confirmed duplicate startups with the existing merge method (merge_20261121.do_batch, batch 8, run 202611231).
create table dupfix_20261123.s3_deals_state as select deal_id, startup_id, shown, archived, event_id from public.v2_deals where startup_id in (423,19487,159894,145402,156899,105978,155820,47606);
insert into merge_20261121.groups (group_no, kept_id, batch, state) values
  (1679, 19487, 8, 'pending'),   -- Nubank: nu.com is Nubank's site
  (1680, 145402, 8, 'pending'),  -- each::labs: eachlabs.com redirects to eachlabs.ai
  (1681, 105978, 8, 'pending'),  -- Drillinginfo: drillinginfo.com redirects to enverus.com
  (1682, 47606, 8, 'pending');   -- Stuut: the copy's website is a broken urldefense.com link
insert into merge_20261121.members (group_no, startup_id) values
  (1679, 19487), (1679, 423), (1680, 145402), (1680, 159894), (1681, 105978), (1681, 156899), (1682, 47606), (1682, 155820);
select merge_20261121.do_batch(8, 202611231);
$sql$;
end $mig$;
