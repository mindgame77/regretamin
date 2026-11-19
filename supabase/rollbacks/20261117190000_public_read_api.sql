-- Rollback for 20261117190000_public_read_api.sql.
-- Drops the public API functions and the api schema. v2 tables, firm_summary,
-- existing functions, and bots.bot_key_pickup are not changed.
-- A key that was sealed and not yet delivered is deleted with the schema.
-- A key a caller already saved still works only until this rollback; after it, the hash is gone.

drop function if exists public.api_firm_deals(text, text, integer);
drop function if exists public.api_firm(text);
drop function if exists public.api_open_firm(text);
drop function if exists public.api_firms_updated(text, integer);
drop function if exists public.api_firms(text, text, text, text, integer);
drop function if exists public.api_activity_text(text);
drop function if exists public.api_visible_firms(bigint);
drop function if exists public.api_cursor_unpack(text, text);
drop function if exists public.api_cursor_pack(text, text, text);
drop function if exists public.api_log(uuid, text, integer, integer);
drop function if exists public.api_authorize(text);
drop function if exists public.pending_api_key_pickups();
drop function if exists public.clear_api_key_pickup(uuid);
drop function if exists public.approve_api_key_pickup(uuid);
drop function if exists public.api_key_apply(uuid, text);
drop function if exists public.create_api_key(text, text, integer);
drop function if exists public.api_set_key_active(uuid, boolean);
drop function if exists public.api_set_enabled(boolean);
drop function if exists public.api_is_enabled();
drop function if exists public.api_activity_label(integer, date[]);

drop schema if exists api cascade;
