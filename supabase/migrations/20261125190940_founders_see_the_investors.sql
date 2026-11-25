-- Founders view, "See the investors" (founder, 25 Nov: "let's add it"): the Investors list can show the firms that backed
-- the startups of the founders the map is showing (a state or country, a university, a company, or all that are shown).
-- 1) New read-only function v2_founders_firm_ids: reads the answer the Founders view itself is drawn from
--    (v2_founders_cache), so the list holds the same firms the map counted.
--      p_kind  'fplace' (keys are places as the view names them: 'us', 'gb', 'US-TX'), 'funi' or 'fco' (keys are names)
--      p_keys  the keys, separated by |
--      p_from / p_to  the stretch of time on the timeline: a startup counts when it has a round in it
-- 2) firm_directory_page_v5 gets one more filter, used only when p_place_level is one of those three words.
--    Every existing call (world, us, eu, country, nothing) answers exactly as before.
do $wrapci$
declare
  v_def text;
  a1 text := $a$  v_country text := case when p_place_level = 'country' and upper(btrim(coalesce(p_place, ''))) ~ '^[A-Z]{2}$' then upper(btrim(p_place)) end;$a$;
  a2 text := $a$and (not v_deal or s.firm_id in (select v2_map_firm_ids(p_deal_firms, v_plevel, v_place, p_deal_from, p_deal_to, v_dstages, v_dsectors)))$a$;
begin
  if to_regclass('public.v2_founders_cache') is null or to_regprocedure('public.firm_directory_page_v5(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text,text,text,text[],text[],date,date,text[],text[],text)') is null then
    raise notice 'founders cache or the investors list function not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_founders_firm_ids(p_kind text, p_keys text, p_from date default null, p_to date default null)
returns setof bigint language sql stable security definer set search_path to 'public' as $body$
with c as (select data from v2_founders_cache where id = 1),
keys as (select k from unnest(string_to_array(coalesce(p_keys, ''), '|')) k where k <> ''),
idx as (  -- where the named universities or companies sit in the answer's own lists
  select (o.ord - 1)::int i
  from c, jsonb_array_elements_text(c.data -> case p_kind when 'funi' then 'unis' else 'cos' end) with ordinality o(name, ord)
  where p_kind in ('funi', 'fco') and o.name in (select k from keys)
),
st as (
  select s.v
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
fi as (select distinct f::int i from st, jsonb_array_elements_text(st.v -> 5) f)
select fs.firm_id
from fi cross join c join firm_summary fs on fs.slug = c.data -> 'firms' -> fi.i ->> 1
$body$
  $fn$;
  execute 'revoke all on function public.v2_founders_firm_ids(text, text, date, date) from public';

  select pg_get_functiondef('public.firm_directory_page_v5(integer,integer,text,boolean,text[],text[],text[],text[],text[],text[],text[],text[],text,text,text,text[],text[],date,date,text[],text[],text)'::regprocedure) into v_def;
  if position('v_fkind' in v_def) > 0 then
    raise notice 'the investors list function already has the founders filter';
    return;
  end if;
  if (length(v_def) - length(replace(v_def, a1, ''))) / length(a1) <> 1 or (length(v_def) - length(replace(v_def, a2, ''))) / length(a2) <> 1 then
    raise notice 'the investors list function is not as expected, left unchanged';
    return;
  end if;
  v_def := replace(v_def, a1, a1 || E'\n  v_fkind text := case when p_place_level in (''fplace'', ''funi'', ''fco'') then p_place_level end;');
  v_def := replace(v_def, a2, a2 || E'\n       and (v_fkind is null or s.firm_id in (select v2_founders_firm_ids(v_fkind, p_place, p_deal_from, p_deal_to)))');
  execute v_def;
end $wrapci$;
