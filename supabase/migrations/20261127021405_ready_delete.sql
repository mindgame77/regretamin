-- Delete button for decks on My score (founder, 26 Nov 2026). A signed-in person may delete only their own report row and their own deck file.
do $wrapci$
begin
  if to_regclass('public.ready_reports') is null then
    raise notice 'ready_reports not present, skipping';
    return;
  end if;

  execute 'drop policy if exists ready_reports_owner_delete on public.ready_reports';
  execute 'create policy ready_reports_owner_delete on public.ready_reports for delete to authenticated using (user_id = auth.uid())';
  execute 'grant delete on public.ready_reports to authenticated';

  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists decks_owner_delete on storage.objects';
    execute $q$create policy decks_owner_delete on storage.objects for delete to authenticated
             using (bucket_id = 'decks' and (storage.foldername(name))[1] = auth.uid()::text)$q$;
  end if;
end
$wrapci$;
