-- Signed-in users keep only select, insert, update and delete on ready_reports (they also held truncate, references and trigger by default).
do $wrapci$
begin
  if to_regclass('public.ready_reports') is null then
    raise notice 'ready_reports not present, skipping';
    return;
  end if;
  execute 'revoke truncate, references, trigger on public.ready_reports from authenticated, anon';
end
$wrapci$;
