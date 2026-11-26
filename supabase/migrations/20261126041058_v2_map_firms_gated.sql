-- Share to unlock, second part (founder, 25 Nov): "hide money flow, the firm list ... after 5, and fresh funds in trends
-- after 3". New read-only function; v2_map_firms itself is not changed.
-- The firms behind a place of the map, exactly as v2_map_firms answers (with or without the "which firms" choice), but
-- until the asking account has unlocked (v2_share_codes) only the first 5 firms are sent, 3 for Fresh funds. 'count'
-- stays the full number, and 'locked' says whether anything was held back for this visitor.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_share_codes') is null or to_regprocedure('public.v2_map_firms(text, text, date, date, text[], text[], integer)') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_map_firms_gated(p_level text, p_place text, p_from date default '2021-01-01'::date, p_to date default null, p_stages text[] default null, p_sectors text[] default null, p_firms text default null)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with me as (
  select exists (select 1 from v2_share_codes s where s.user_id = auth.uid() and s.seen_at is not null) as ok
),
d as (
  select case when p_firms is null then v2_map_firms(p_level, p_place, p_from, p_to, p_stages, p_sectors)
              else v2_map_firms(p_firms, p_level, p_place, p_from, p_to, p_stages, p_sectors) end as j
)
select case
  when d.j is null then null
  when me.ok or jsonb_typeof(d.j->'firms') <> 'array' then d.j || jsonb_build_object('locked', false)
  else jsonb_set(d.j, '{firms}', coalesce((
         select jsonb_agg(a.e order by a.i) from jsonb_array_elements(d.j->'firms') with ordinality a(e, i)
         where a.i <= case when p_firms = 'fresh' then 3 else 5 end), '[]'::jsonb))
       || jsonb_build_object('locked', true) end
from d cross join me
$body$
  $fn$;
  execute 'revoke all on function public.v2_map_firms_gated(text, text, date, date, text[], text[], text) from public';
  execute 'grant execute on function public.v2_map_firms_gated(text, text, date, date, text[], text[], text) to anon, authenticated';
end $wrapci$;