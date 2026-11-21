-- Hotfix after PR 436 go-live: the deferred check v2_founder_require_role runs at COMMIT, after
-- v2_founder_add (security definer) has returned, so it ran as service_role, which has no table
-- privileges on v2_founders / v2_founder_facts -> every add_founder through the door failed with
-- "permission denied for table v2_founders" (door answered 500). Run the check as its owner.
alter function public.v2_founder_require_role() security definer;
alter function public.v2_founder_require_role() set search_path = public, pg_catalog;
revoke all on function public.v2_founder_require_role() from public;
