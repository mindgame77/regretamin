-- Teardown of supabase/migrations/20261121060000_v2_startup_location_fill.sql, in one command:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261121060000_v2_startup_location_fill.sql
-- Fastest off switch (no rollback needed): update public.v2_work_setting set value = 'off', updated_at = now() where name = 'location_fill';
-- This file removes the three location entry points, the location columns on founderlist.startups (the founder
-- columns and founder functions stay as they are) and the two settings. Countries and cities already filled stay
-- on the startups, and public.v2_startup_location_sources stays as their source record. To also take the filled
-- values back off, run supabase/rollbacks/20261121060001_v2_startup_location_values_undo.sql FIRST.
-- After this, fill_startup_location / claim_next_location_startups / finish_location_startup answer "server error"
-- until the door is redeployed without them.
do $undo$
begin
  drop function if exists public.v2_startup_location_fill(uuid, bigint, text, text, jsonb, boolean, text, boolean);
  drop function if exists public.founderlist_claim_next_location_startups(uuid, integer);
  drop function if exists public.founderlist_finish_location_startup(uuid, bigint, text, text);
  drop function if exists public.founderlist_location_bot_ok(text);
  drop function if exists public.v2_location_fill_on();
  drop function if exists founderlist.loc_release_expired();
  drop function if exists founderlist.loc_row_json(founderlist.startups);
  if to_regclass('founderlist.startups') is not null then
    drop index if exists founderlist.founderlist_loc_pick_idx;
    drop index if exists founderlist.founderlist_loc_taken_idx;
    alter table founderlist.startups drop constraint if exists founderlist_loc_status_chk;
    alter table founderlist.startups drop column if exists loc_status, drop column if exists loc_taken_by,
      drop column if exists loc_taken_at, drop column if exists loc_finished_at, drop column if exists loc_notes;
  end if;
  if to_regclass('public.v2_work_setting') is not null then
    delete from public.v2_work_setting where name in ('location_fill', 'location_list_bots');
  end if;
end
$undo$;
