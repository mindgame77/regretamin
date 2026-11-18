-- When a research submit is accepted for a firm this key still holds on
-- deal_gaps, push that claim's expires_at to now() + 2 hours so the hold does
-- not lapse mid-work. Does nothing if the firm is not held by this key, is
-- already done, or is held by someone else. dry_run rolls the renewal back
-- with the rest of the batch.
-- Rollback: supabase/rollbacks/20261118240000_renew_deal_gap_holds.sql
-- Not applied to production by this change.
-- On a database without v2_work_claims or v2_research_submissions (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_work_claims') is null
     or to_regclass('public.v2_research_submissions') is null then
    raise notice 'v2_work_claims or v2_research_submissions missing, skipped';
    return;
  end if;

  execute $sql$
create or replace function public.v2_renew_deal_gap_holds()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
begin
  if new.status = 'Accepted' and new.firm_id is not null and new.bot_key_id is not null then
    update public.v2_work_claims
       set expires_at = now() + interval '2 hours'
     where job = 'deal_gaps'
       and firm_id = new.firm_id
       and bot_key_id = new.bot_key_id
       and done_at is null;
  end if;
  return new;
end
$fn$;
$sql$;

  execute 'drop trigger if exists v2_renew_deal_gap_holds on public.v2_research_submissions';
  execute $sql$
create trigger v2_renew_deal_gap_holds
after update of status on public.v2_research_submissions
for each row
when (new.status = 'Accepted')
execute function public.v2_renew_deal_gap_holds()
$sql$;

  execute 'revoke all on function public.v2_renew_deal_gap_holds() from public';
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on function public.v2_renew_deal_gap_holds() from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on function public.v2_renew_deal_gap_holds() from authenticated';
  end if;
end
$mig$;
