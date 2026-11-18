-- Read-only deal lookup for research bots on the v2 door (action deals).
-- Any active ingest key may read one firm's current deals with their deal_id, so a bot
-- can file F12 corrections (round, date, amount) on deals other bots filed.
-- Returns the firm, the total count, and one page of deals (limit 1-500, default 500; offset).
-- p_only_gaps = true returns only deals with no deal_date and no round.
-- Rows: v2_deals is_current, not archived, not nothing_found (same as the firm page).
-- It does not write, publish, or change any row.
-- Rollback: supabase/rollbacks/20261118180000_v2_research_firm_deals.sql
-- The v2 schema is not created by repo migrations. On a database without v2
-- (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_startups') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped';
    return;
  end if;

  execute $ddl$
create or replace function public.v2_research_firm_deals(
  p_key uuid, p_firm_id bigint, p_only_gaps boolean default false, p_limit int default 500, p_offset int default 0)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path = public, bots
 as $function$
declare
  n int := least(greatest(coalesce(p_limit, 500), 1), 500);
  o int := greatest(coalesce(p_offset, 0), 0);
  g boolean := coalesce(p_only_gaps, false);
  v_name text;
begin
  if not exists (select 1 from bots.ingest_keys k where k.id = p_key and k.active) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  select f.display_name::text into v_name from public.v2_firms f where f.firm_id = p_firm_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'firm not found');
  end if;

  return (
    with d as (
      select d.deal_id, d.startup_id,
             s.startup_name::text as startup_name, s.website_url as startup_website,
             s.st_city::text as startup_city, s.st_country::text as startup_country,
             d.round, d.round_extension::text as round_extension,
             d.deal_date, d.deal_date_precision,
             d.round_amount, d.firm_amount, d.amount_currency::text as amount_currency, d.amount_approximate,
             d.lead
        from public.v2_deals d
        left join public.v2_startups s
          on s.startup_id = d.startup_id and s.is_current and not s.archived
       where d.firm_id = p_firm_id
         and d.is_current and not d.archived and not coalesce(d.nothing_found, false)
         and (not g or (d.deal_date is null and nullif(btrim(d.round), '') is null))
    )
    select jsonb_build_object(
      'ok', true,
      'firm_id', p_firm_id,
      'firm', v_name,
      'only_gaps', g,
      'total', (select count(*) from d),
      'limit', n,
      'offset', o,
      'deals', coalesce((
        select jsonb_agg(to_jsonb(p) order by p.startup_name, p.deal_id)
          from (select * from d order by d.startup_name, d.deal_id limit n offset o) p
      ), '[]'::jsonb))
  );
end
$function$;
$ddl$;

  -- Server only: the door calls it with the service role.
  execute 'revoke all on function public.v2_research_firm_deals(uuid, bigint, boolean, int, int) from public, anon, authenticated';
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.v2_research_firm_deals(uuid, bigint, boolean, int, int) to service_role';
  end if;
end
$mig$;
