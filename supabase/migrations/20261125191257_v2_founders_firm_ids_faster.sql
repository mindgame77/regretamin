-- v2_founders_firm_ids (added 25 Nov) gave the right firms but took 5 to 8 seconds: it looked each firm up in the stored
-- answer one at a time, and every look-up unpacked the whole answer again. This version unpacks the list of firms once.
-- Same input, same output; nothing else is touched.
do $wrapci$
begin
  if to_regclass('public.v2_founders_cache') is null or to_regclass('public.firm_summary') is null then
    raise notice 'founders cache not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_founders_firm_ids(p_kind text, p_keys text, p_from date default null, p_to date default null)
returns setof bigint language sql stable security definer set search_path to 'public' as $body$
with c as materialized (select data from v2_founders_cache where id = 1),
keys as materialized (select k from unnest(string_to_array(coalesce(p_keys, ''), '|')) k where k <> ''),
idx as materialized (  -- where the named universities or companies sit in the answer's own lists
  select (o.ord - 1)::int i
  from c, jsonb_array_elements_text(c.data -> case p_kind when 'funi' then 'unis' else 'cos' end) with ordinality o(name, ord)
  where p_kind in ('funi', 'fco') and o.name in (select k from keys)
),
fl as materialized (select (o.ord - 1)::int i, o.f ->> 1 slug from c, jsonb_array_elements(c.data -> 'firms') with ordinality o(f, ord)),
st as materialized (
  select s.v -> 5 firms
  from c, jsonb_array_elements(c.data -> 'startups') s(v)
  where exists (select 1 from jsonb_array_elements(s.v -> 4) r
                where (r ->> 0)::int between to_char(greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01'), 'YYYYMMDD')::int
                                         and to_char(coalesce(p_to, current_date), 'YYYYMMDD')::int)
    and case p_kind
      when 'fplace' then exists (select 1 from jsonb_array_elements_text(s.v -> 2) pl where pl in (select k from keys))
      when 'funi' then exists (select 1 from jsonb_array_elements_text(s.v -> 3) u where u::int in (select i from idx))
      when 'fco' then exists (select 1 from jsonb_array_elements_text(s.v -> 6) u where u::int in (select i from idx))
      else false end
),
fi as (select distinct f::int i from st, jsonb_array_elements_text(st.firms) f)
select fs.firm_id from fi join fl using (i) join firm_summary fs on fs.slug = fl.slug
$body$
  $fn$;
  execute 'revoke all on function public.v2_founders_firm_ids(text, text, date, date) from public';
end $wrapci$;
