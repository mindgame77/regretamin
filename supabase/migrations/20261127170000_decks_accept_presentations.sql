-- Raise report: the private "decks" place also takes PowerPoint and Keynote files (founder, 27 Nov 2026). They are turned into a PDF by the
-- converter before the model reads them (launch/functions/api/_ready/convert.js). The only change: more file types allowed on the one bucket.
-- Size limit (20 MB), privacy and the owner-only rules are unchanged.
-- Undo: update storage.buckets set allowed_mime_types = array['application/pdf'] where id = 'decks';
do $wrap$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage not present, skipping';
    return;
  end if;
  update storage.buckets
     set allowed_mime_types = array[
       'application/pdf',
       'application/vnd.openxmlformats-officedocument.presentationml.presentation',
       'application/vnd.ms-powerpoint',
       'application/x-iwork-keynote-sffkey']
   where id = 'decks';
end $wrap$;
