-- Undo for docs/map_functions.sql. Removes only what that file added; no data is touched.
drop function if exists public.v2_map_updates(int);
drop function if exists public.v2_map_firms(text, text, date, date, text[], text[], int);
drop function if exists public.v2_map_summary(date, date, text[], text[]);
drop view if exists public.v2_map_firm_places;
