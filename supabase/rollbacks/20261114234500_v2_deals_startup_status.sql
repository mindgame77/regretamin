-- Undo 20261114234500_v2_deals_startup_status: remove st_status from deal rows.
-- Every other deal field stays. No rows are written.
do $mig$
declare
  d text;
  n text;
begin
  if to_regprocedure('public._v2_deals(bigint)') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;
  select pg_get_functiondef('public._v2_deals(bigint)'::regprocedure) into d;
  if position($a$'st_status', s.st_status$a$ in d) = 0 then
    raise notice '_v2_deals st_status already absent';
    return;
  end if;
  n := replace(d,
    $a$'website_url', s.website_url, 'st_status', s.st_status) x$a$,
    $a$'website_url', s.website_url) x$a$);
  if n = d or position($a$'st_status'$a$ in n) > 0 then
    raise exception '_v2_deals: st_status undo did not apply';
  end if;
  execute n;
end
$mig$;
