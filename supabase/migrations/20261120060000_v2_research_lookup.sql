-- Read-only firm / startup lookup for research bots on the v2 door (action lookup).
-- Built on Alex's OK (2026-11-20, "Please do"). Preview only; apply only on "make it live".
-- Why: bots search for firms their own way and miss firms whose name is written a little
-- differently ("All Aboard Fund" vs "All Aboard"), so they write "not in system" and skip the
-- deal, or add a second copy of a startup. lookup gives every bot the same search.
-- A bot sends a firm or a startup with a name and/or a website. Matches, best first:
--   1 website       same website domain (lowercase, no scheme, www, port, path or trailing dot)
--   2 name          same name after dropping punctuation, case and filler words
--     short name / legal name (firms only): the same, on the firm's short or legal name
--   3 partial name  one name's words appear whole inside the other's (both at least 4 letters)
-- Filler words: firms drop the, ventures, venture, capital, partners, partner, fund, funds, vc,
-- vcs, management, group, investments, investment, holdings and legal suffixes; startups drop
-- only legal suffixes (inc, llc, ltd, corp, co, ...), so "Rain AI" and "Rain Labs" stay distinct.
-- Archived firms, and archived or old (not is_current) startup rows, are skipped.
-- Up to 5 matches; total says how many matched in all. An empty list means not found.
-- It does not write anything and adds no tables or indexes.
-- Rollback: supabase/rollbacks/20261120060000_v2_research_lookup.sql
-- The v2 schema is not created by repo migrations. On a database without v2 (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_startups') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  -- Website -> bare domain. Null when it does not look like a domain.
  execute $ddl$
create or replace function public.v2_lookup_domain(p text)
 returns text
 language sql
 immutable
 set search_path = pg_catalog
 as $function$
  select case when d ~ '^[a-z0-9-]+(\.[a-z0-9-]+)+$' then d end
    from (select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
                   lower(btrim(coalesce(p, ''))),
                   '^[a-z][a-z0-9+.-]*://', ''), '[/?#].*$', ''), ':[0-9]+$', ''), '\.$', ''), '^www\.', '') as d) s
$function$
$ddl$;

  -- Name -> match key: lowercase words of letters and digits, filler words dropped (per kind).
  -- When only filler is left ("Capital Partners"), the words are kept as they are.
  execute $ddl$
create or replace function public.v2_lookup_name(p text, p_kind text)
 returns text
 language sql
 immutable
 set search_path = pg_catalog
 as $function$
  select coalesce(nullif(btrim(regexp_replace(regexp_replace(w,
           case when p_kind = 'firm'
                then '\m(the|ventures|venture|capital|partners|partner|fund|funds|vc|vcs|management|group|investments|investment|holdings|inc|incorporated|llc|llp|lp|ltd|limited|corp|corporation|co|gmbh|plc)\M'
                else '\m(inc|incorporated|llc|ltd|limited|corp|corporation|co|gmbh|plc)\M' end,
           '', 'g'), ' +', ' ', 'g')), ''), w)
    from (select btrim(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]+', ' ', 'g')) as w) s
$function$
$ddl$;

  execute $ddl$
create or replace function public.v2_research_lookup(p_key uuid, p_kind text, p_name text, p_website text)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path = public, bots
 as $function$
declare
  v_kind text := lower(btrim(coalesce(p_kind, '')));
  v_name text := btrim(coalesce(p_name, ''));
  v_site text := btrim(coalesce(p_website, ''));
  v_n text;      -- name key, words joined by one space
  v_c text;      -- name key without spaces
  v_d text;      -- website domain
  v_like text[]; -- cheap pre-filter on the raw name before the regex work
  v_rows jsonb;
  v_total int;
begin
  if not exists (select 1 from bots.ingest_keys k where k.id = p_key and k.active) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if v_kind not in ('firm', 'startup') then
    return jsonb_build_object('ok', false, 'error', 'send a firm or a startup');
  end if;
  if length(v_name) > 200 or length(v_site) > 500 then
    return jsonb_build_object('ok', false, 'error', 'name is up to 200 characters and website up to 500');
  end if;
  v_n := public.v2_lookup_name(v_name, v_kind);
  v_c := replace(v_n, ' ', '');
  v_d := public.v2_lookup_domain(v_site);
  if v_site <> '' and v_d is null and v_c = '' then
    return jsonb_build_object('ok', false, 'error', 'website is not a valid domain, and no name was sent');
  end if;
  if v_c = '' and v_d is null then
    return jsonb_build_object('ok', false, 'error', 'send a name or a website');
  end if;
  -- A record can only match by name if its raw name holds one of the query words, or the whole
  -- query key once spaces and punctuation are gone ("Bpi France" for "Bpifrance").
  v_like := case when v_c = '' then '{}'::text[] else
    array(select '%' || w || '%' from unnest(string_to_array(v_n, ' ')) w where w <> '') end;

  if v_kind = 'firm' then
    with r as materialized (
      select f.firm_id as id, f.display_name::text as name, f.website_url as website,
             public.v2_lookup_domain(f.website_url) as d,
             public.v2_lookup_name(f.display_name, 'firm') as n,
             public.v2_lookup_name(f.short_name, 'firm') as sn,
             public.v2_lookup_name(f.legal_name, 'firm') as ln
        from public.v2_firms f
       where not coalesce(f.archived, false)
         and ((v_d is not null and f.website_url ilike '%' || v_d || '%')
           or (v_c <> '' and (lower(concat_ws(' ', f.display_name, f.short_name, f.legal_name)) like any (v_like)
                           or regexp_replace(lower(concat_ws(' ', f.display_name, f.short_name, f.legal_name)), '[^a-z0-9]+', '', 'g') like '%' || v_c || '%')))
    ), m as (
      select r.id, r.name, r.website, x.rank, x.reason, x.key
        from r, lateral (
          select * from (values
            (1, 'website', r.n, v_d is not null and r.d = v_d),
            (2, 'name', r.n, v_c <> '' and replace(r.n, ' ', '') = v_c),
            (3, 'short name', r.sn, v_c <> '' and replace(r.sn, ' ', '') = v_c),
            (3, 'legal name', r.ln, v_c <> '' and replace(r.ln, ' ', '') = v_c),
            (4, 'partial name', r.n, length(v_c) >= 4 and length(replace(r.n, ' ', '')) >= 4
                and (strpos(' ' || r.n || ' ', ' ' || v_n || ' ') > 0 or strpos(' ' || v_n || ' ', ' ' || r.n || ' ') > 0)),
            (4, 'partial name', r.sn, length(v_c) >= 4 and length(replace(r.sn, ' ', '')) >= 4
                and (strpos(' ' || r.sn || ' ', ' ' || v_n || ' ') > 0 or strpos(' ' || v_n || ' ', ' ' || r.sn || ' ') > 0))
          ) v(rank, reason, key, hit)
           where v.hit
           order by v.rank
           limit 1) x
    )
    select count(*)::int,
           coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'website', t.website, 'match_reason', t.reason)
                      order by t.rank, t.diff, t.id) filter (where t.pos <= 5), '[]'::jsonb)
      into v_total, v_rows
      from (select m.*, abs(length(m.key) - length(v_n)) as diff,
                   row_number() over (order by m.rank, abs(length(m.key) - length(v_n)), m.id) as pos
              from m) t;
  else
    with r as materialized (
      select s.startup_id as id, s.startup_name::text as name, s.website_url as website, s.domain as d,
             public.v2_lookup_name(s.startup_name, 'startup') as n
        from public.v2_startups s
       where s.is_current and not coalesce(s.archived, false)
         and ((v_d is not null and s.domain = v_d)
           or (v_c <> '' and (lower(s.startup_name) like any (v_like)
                           or translate(lower(s.startup_name), ' -._,&''', '') like '%' || v_c || '%')))
    ), m as (
      select r.id, r.name, r.website, r.n as key,
             case when v_d is not null and r.d = v_d then 1
                  when v_c <> '' and replace(r.n, ' ', '') = v_c then 2
                  when length(v_c) >= 4 and length(replace(r.n, ' ', '')) >= 4
                   and (strpos(' ' || r.n || ' ', ' ' || v_n || ' ') > 0 or strpos(' ' || v_n || ' ', ' ' || r.n || ' ') > 0) then 4
             end as rank
        from r
    )
    select count(*)::int,
           coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'website', t.website,
                      'match_reason', case t.rank when 1 then 'website' when 2 then 'name' else 'partial name' end)
                      order by t.rank, t.diff, t.id) filter (where t.pos <= 5), '[]'::jsonb)
      into v_total, v_rows
      from (select m.*, abs(length(m.key) - length(v_n)) as diff,
                   row_number() over (order by m.rank, abs(length(m.key) - length(v_n)), m.id) as pos
              from m where m.rank is not null) t;
  end if;

  return jsonb_build_object(
    'ok', true,
    'kind', v_kind,
    'searched', jsonb_build_object('name_key', nullif(v_n, ''), 'domain', v_d),
    'found', v_total > 0,
    'total', v_total,
    'matches', v_rows);
end
$function$;
$ddl$;

  -- Server only: the door calls it with the service role.
  execute 'revoke all on function public.v2_lookup_domain(text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_lookup_name(text, text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_research_lookup(uuid, text, text, text) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_research_lookup(uuid, text, text, text) to service_role';
  end if;
end
$mig$;
