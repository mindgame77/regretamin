do $mig$
begin
  if to_regclass('public.v2_social_accounts') is null or to_regclass('public.v2_firms') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 7: archive real social rows (not "nothing found" markers) whose account link is just the firm's own website.
-- Rows 9236, 9237, 9238, 9280, 9292, 9351 (firms 3302, 3396, 3910). Firms with no other non-YouTube social then show 'socials' missing to the jobs.
update public.v2_social_accounts s set archived = true, is_current = false, archive_reason = 'Bad link: firm website, not an account (dupfix 2026-11-23)'
from public.v2_firms f
where f.firm_id = s.firm_id and s.is_current and not s.archived and not s.nothing_found and s.account_url_norm = f.website_url_norm;
$sql$;
end $mig$;
