-- Bots read the register: each deal in the deals action gets also_in_round (up to 10 other firms/noted names in that round), only when there are any.
CREATE OR REPLACE FUNCTION public.v2_research_firm_deals(p_key uuid, p_firm_id bigint, p_only_gaps boolean DEFAULT false, p_limit integer DEFAULT 500, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'bots'
AS $function$
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
        select jsonb_agg(to_jsonb(p) || coalesce((
                 select jsonb_build_object('also_in_round', jsonb_agg(coalesce(f2.display_name::text, ef.noted_name)))
                   from (select e.firm_id, e.noted_name from public.v2_event_firms e
                          where e.event_id = (select x.event_id from public.v2_deals x where x.deal_id = p.deal_id)
                            and e.firm_id is distinct from p_firm_id
                          order by e.firm_id nulls last limit 10) ef
                   left join public.v2_firms f2 on f2.firm_id = ef.firm_id
                 having count(*) > 0), '{}'::jsonb)
                 order by p.startup_name, p.deal_id)
          from (select * from d order by d.startup_name, d.deal_id limit n offset o) p
      ), '[]'::jsonb))
  );
end
$function$
;
