-- Undo 20261118040000_v2_bot_notes.
-- Deploy the previous research-ingest-v2 first (claim replies then have no notes and the notes actions are gone),
-- then run this. It removes the two note functions and the bots.bot_notes table with every note in it.
-- No other table, function or key is touched.
drop function if exists public.v2_bot_notes_ack(uuid, uuid[], text);
drop function if exists public.v2_bot_notes_unread(uuid);
drop table if exists bots.bot_notes;
