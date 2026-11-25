
BEGIN;

create or replace function roundlist.done_check(p_round_id bigint, p_source_url text, p_note text, p_report jsonb)
returns jsonb
language plpgsql
stable
set search_path = roundlist, public, pg_catalog
as $f$
declare
  v_round roundlist.rounds;
  v_src text := nullif(btrim(coalesce(p_source_url, '')), '');
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_report jsonb := coalesce(p_report, '{}'::jsonb);
  v_investors jsonb;
  v_item jsonb;
  v_startup_id bigint;
  v_startup_ids bigint[];
  v_event_id bigint;
  v_event_ids bigint[];
  v_event_amount numeric;
  v_amount numeric;
  v_amount_missing boolean;
  v_no_lead boolean;
  v_lead_ok boolean := false;
  v_pending jsonb := '[]'::jsonb;
  v_firm_id bigint;
  v_firm_ids bigint[];
  v_name text;
  v_site text;
  v_domain text;
  v_matched_id bigint;
  v_matched_name text;
  v_i int;
begin
  if jsonb_typeof(v_report) is distinct from 'object' then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: report must be an object with amount or amount_not_in_source, and investors');
  end if;
  if v_src is null or v_src !~* '^https?://' or length(v_src) > 2000 then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: source_url is required (the http(s) link to the announcement)');
  end if;

  select * into v_round from roundlist.rounds x where x.round_id = p_round_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'round not found');
  end if;

  v_amount_missing := (v_report->>'amount_not_in_source') in ('true', 't');
  if v_report ? 'amount' and jsonb_typeof(v_report->'amount') <> 'null'
     and nullif(btrim(coalesce(v_report->>'amount', '')), '') is not null then
    if v_amount_missing then
      return jsonb_build_object('ok', false, 'error',
        'finish_round done refused: give the amount, or set amount_not_in_source to true, not both');
    end if;
    begin
      v_amount := (v_report->>'amount')::numeric;
    exception when others then
      return jsonb_build_object('ok', false, 'error',
        'finish_round done refused: amount must be a number in the currency of the announcement, with no letters');
    end;
  elsif not v_amount_missing then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: say the amount, or set amount_not_in_source to true if the source does not give one');
  end if;

  v_no_lead := (v_report->>'no_lead_named') in ('true', 't');
  if v_no_lead and (v_note is null or v_note !~* 'no lead named in the source') then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: when no lead is named, the note must say "no lead named in the source"');
  end if;

  if jsonb_typeof(v_report->'investors') is distinct from 'array' then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: list every named investor in investors (firm_id when the firm is already in our list, or name and website when it is not)');
  end if;
  v_investors := v_report->'investors';
  if jsonb_array_length(v_investors) < 1 then
    return jsonb_build_object('ok', false, 'error',
      'finish_round done refused: list every named investor from the source (at least one)');
  end if;

  -- Resolve each named investor. Firms are never created.
  for v_i in 0 .. jsonb_array_length(v_investors) - 1 loop
    v_item := v_investors->v_i;
    if jsonb_typeof(v_item) is distinct from 'object' then
      return jsonb_build_object('ok', false, 'error',
        'finish_round done refused: each investors item must be an object with firm_id, or with name and website');
    end if;
    v_firm_id := null;
    v_matched_id := null;
    v_matched_name := null;
    v_firm_ids := null;
    if v_item ? 'firm_id' and nullif(btrim(coalesce(v_item->>'firm_id', '')), '') is not null then
      begin
        v_firm_id := (v_item->>'firm_id')::bigint;
      exception when others then
        return jsonb_build_object('ok', false, 'error',
          'finish_round done refused: firm_id must be a whole number');
      end;
    end if;
    v_name := nullif(btrim(coalesce(v_item->>'name', '')), '');
    v_site := nullif(btrim(coalesce(v_item->>'website', v_item->>'website_url', '')), '');
    if v_firm_id is not null and (v_name is not null or v_site is not null) then
      return jsonb_build_object('ok', false, 'error',
        'finish_round done refused: use firm_id when the firm is already in our list, or name and website when it is not, not both');
    end if;
    if v_firm_id is not null then
      select f.firm_id, f.display_name into v_matched_id, v_matched_name
        from public.v2_firms f
       where f.firm_id = v_firm_id and not coalesce(f.archived, false);
      if v_matched_id is null then
        return jsonb_build_object('ok', false, 'error',
          format('finish_round done refused: firm_id %s is not a firm in our list. If it is new, give name and website instead', v_firm_id));
      end if;
    elsif v_name is not null and v_site is not null then
      v_domain := roundlist.norm_site(v_site);
      if v_domain is null or length(v_name) > 300 or length(v_site) > 500 then
        return jsonb_build_object('ok', false, 'error',
          format('finish_round done refused: "%s" needs a real website like https://example.com', v_name));
      end if;
      -- If this firm is already in our list, the bot must link the deal, not list it as new.
      select f.firm_id, f.display_name into v_matched_id, v_matched_name
        from public.v2_firms f
       where not coalesce(f.archived, false)
         and (roundlist.norm_site(f.website_url) = v_domain
              or roundlist.norm_site(f.website_url_norm) = v_domain)
       order by f.firm_id
       limit 1;
      if v_matched_id is null then
        select array_agg(distinct f.firm_id), min(f.display_name)
          into v_firm_ids, v_matched_name
          from public.v2_firms f
         where not coalesce(f.archived, false)
           and (lower(btrim(f.display_name)) = lower(v_name)
                or lower(btrim(coalesce(f.legal_name, ''))) = lower(v_name)
                or lower(btrim(coalesce(f.short_name, ''))) = lower(v_name));
        if v_firm_ids is not null and cardinality(v_firm_ids) = 1 then
          v_matched_id := v_firm_ids[1];
        elsif v_firm_ids is not null and cardinality(v_firm_ids) > 1 then
          return jsonb_build_object('ok', false, 'error',
            format('finish_round done refused: "%s" matches more than one firm already in our list (%s). Use the firm_id and save the deal',
                   v_name, array_to_string(v_firm_ids, ', ')));
        end if;
      end if;
      if v_matched_id is not null then
        return jsonb_build_object('ok', false, 'error',
          format('finish_round done refused: %s is already in our list (firm_id %s, %s). Save the deal with that firm_id; do not list it as not in our list',
                 v_name, v_matched_id, v_matched_name));
      end if;
      v_pending := v_pending || jsonb_build_array(jsonb_build_object(
        'name', v_name, 'website', v_site, 'website_domain', v_domain,
        'lead', (v_item->>'lead') in ('true', 't', 'yes')));
    else
      return jsonb_build_object('ok', false, 'error',
        'finish_round done refused: each named investor needs firm_id (already in our list) or name and website (not in our list)');
    end if;
  end loop;

  -- Matching startup: website domain first, name only when the list row has no website.
  if roundlist.norm_site(v_round.startup_website) is not null then
    select array_agg(s.startup_id order by s.startup_id) into v_startup_ids
      from public.v2_startups s
     where s.is_current and not s.archived
       and (s.domain = roundlist.norm_site(v_round.startup_website)
            or roundlist.norm_site(s.website_url) = roundlist.norm_site(v_round.startup_website)
            or roundlist.norm_site(s.website_url_norm) = roundlist.norm_site(v_round.startup_website));
  else
    select array_agg(s.startup_id order by s.startup_id) into v_startup_ids
      from public.v2_startups s
     where s.is_current and not s.archived
       and roundlist.norm_text(s.startup_name) = roundlist.norm_text(v_round.startup_name);
  end if;
  if v_startup_ids is null or cardinality(v_startup_ids) = 0 then
    return jsonb_build_object('ok', false, 'pending', v_pending, 'error',
      'finish_round done refused: no matching startup for this website or name. Save the startup and the deals first');
  end if;
  if cardinality(v_startup_ids) > 1 then
    return jsonb_build_object('ok', false, 'pending', v_pending, 'error',
      format('finish_round done refused: several startups match this website or name (%s). This needs a person to look at it',
             array_to_string(v_startup_ids, ', ')));
  end if;
  v_startup_id := v_startup_ids[1];

  -- Matching event: same startup, same round (letters/digits only), exact date, full date.
  select array_agg(e.event_id order by e.event_id) into v_event_ids
    from public.v2_events e
   where e.kind = 'round'
     and e.startup_id = v_startup_id
     and e.event_date = v_round.round_date
     and e.event_date_precision = 'full date'
     and roundlist.norm_text(e.round) = roundlist.norm_text(v_round.round);
  if v_event_ids is null or cardinality(v_event_ids) = 0 then
    return jsonb_build_object('ok', false, 'pending', v_pending, 'startup_id', v_startup_id, 'error',
      format('finish_round done refused: no matching event for this startup and round with exact date %s. Save the deals from the announcement first; each deal needs this exact date',
             v_round.round_date));
  end if;
  -- If several events still match, pick the one with the most current shown deals.
  select x.event_id, x.amount into v_event_id, v_event_amount
    from (
      select e.event_id, e.amount
        from public.v2_events e
        join unnest(v_event_ids) i(event_id) on i.event_id = e.event_id
        left join public.v2_deals d
          on d.event_id = e.event_id and d.is_current and not d.archived and d.shown
         and not coalesce(d.nothing_found, false)
       group by e.event_id, e.amount
       order by count(d.deal_id) desc, e.event_id
       limit 1
    ) x;

  if not exists (
       select 1
         from public.v2_event_sources es
        where es.event_id = v_event_id
          and es.source_url ~* '^https?://'
     ) and not exists (
       select 1
         from public.v2_deals d
        where d.event_id = v_event_id
          and d.is_current and not d.archived and d.shown
          and not coalesce(d.nothing_found, false)
          and d.source_url ~* '^https?://'
     ) then
    return jsonb_build_object('ok', false, 'pending', v_pending, 'event_id', v_event_id, 'error',
      'finish_round done refused: the matching event has no source URL. Save the deals with the announcement link first');
  end if;

  if v_amount is not null then
    if v_event_amount is null then
      return jsonb_build_object('ok', false, 'pending', v_pending, 'event_id', v_event_id, 'error',
        'finish_round done refused: the source gives an amount, but the matching event has none. Save the deals with that amount first');
    end if;
    if v_event_amount <> v_amount then
      return jsonb_build_object('ok', false, 'pending', v_pending, 'event_id', v_event_id, 'error',
        format('finish_round done refused: the amount you gave (%s) does not match the event amount (%s)',
               v_amount, v_event_amount));
    end if;
  end if;

  -- Lead: a current shown deal marked lead, or an explicit "no lead named" note,
  -- or a not-in-list investor marked lead (the lead is named but not yet in our list).
  if exists (
       select 1 from public.v2_deals d
        where d.event_id = v_event_id
          and d.is_current and not d.archived and d.shown
          and not coalesce(d.nothing_found, false)
          and d.lead = 'yes'
     ) then
    v_lead_ok := true;
  elsif v_no_lead then
    v_lead_ok := true;
  elsif exists (
       select 1 from jsonb_array_elements(v_pending) p
        where (p->>'lead') in ('true', 't', 'yes')
     ) then
    v_lead_ok := true;
  end if;
  if not v_lead_ok then
    return jsonb_build_object('ok', false, 'pending', v_pending, 'event_id', v_event_id, 'error',
      'finish_round done refused: mark the lead deal, or if the source names no lead write "no lead named in the source" in the note and set no_lead_named to true, or mark lead true on the not-in-list investor who led');
  end if;

  -- Every investor given as firm_id must already have a current, unarchived, shown deal on this event.
  for v_i in 0 .. jsonb_array_length(v_investors) - 1 loop
    v_item := v_investors->v_i;
    if v_item ? 'firm_id' and nullif(btrim(coalesce(v_item->>'firm_id', '')), '') is not null then
      v_firm_id := (v_item->>'firm_id')::bigint;
      if not exists (
           select 1 from public.v2_deals d
            where d.event_id = v_event_id
              and d.firm_id = v_firm_id
              and d.is_current and not d.archived and d.shown
              and not coalesce(d.nothing_found, false)
         ) then
        select f.display_name into v_matched_name from public.v2_firms f where f.firm_id = v_firm_id;
        return jsonb_build_object('ok', false, 'pending', v_pending, 'event_id', v_event_id, 'error',
          format('finish_round done refused: no current deal links %s (firm_id %s) to this round. Save that deal first',
                 coalesce(v_matched_name, 'that firm'), v_firm_id));
      end if;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'startup_id', v_startup_id, 'event_id', v_event_id, 'pending', v_pending);
end
$f$;

-- A. Round 100 as it was: the bot listed DST Global as not in our list, and only
--    Accel / Menlo / Fifth Wall as saved firms (the deals it added that night).
--    DST Global was already in the system. This must be refused.
CREATE TEMP TABLE dry_roundlist_done AS
SELECT 'as_was'::text AS case_name, ok, error
  FROM jsonb_to_record(roundlist.done_check(
    100,
    'https://www.prnewswire.com/news-releases/higgsfield-raises-400-million-series-b-financing-at-5-4-billion-valuation-with-annualized-revenue-reaching-700-million-302852430.html',
    'DST Global led and is not in the system. Accel, Menlo Ventures, and Fifth Wall were saved.',
    '{
      "amount": 400000000,
      "investors": [
        {"firm_id": 8},
        {"firm_id": 188},
        {"firm_id": 323},
        {"name": "DST Global", "website": "https://dst-global.com", "lead": true}
      ]
    }'::jsonb
  )) AS x(ok boolean, error text);

-- B. Correct finish on today's data: every current shown deal is listed by firm_id,
--    amount $400M, DST is the lead (already marked on the deal).
INSERT INTO dry_roundlist_done
SELECT 'correct'::text, ok, error
  FROM jsonb_to_record(roundlist.done_check(
    100,
    'https://www.prnewswire.com/news-releases/higgsfield-raises-400-million-series-b-financing-at-5-4-billion-valuation-with-annualized-revenue-reaching-700-million-302852430.html',
    'Saved DST Global as lead and the other named investors that are already in our list.',
    (
      SELECT jsonb_build_object(
        'amount', 400000000,
        'investors', jsonb_agg(jsonb_build_object('firm_id', d.firm_id) ORDER BY d.firm_id)
      )
      FROM public.v2_deals d
      WHERE d.event_id = 1314
        AND d.is_current AND NOT d.archived AND d.shown
        AND NOT coalesce(d.nothing_found, false)
    )
  )) AS x(ok boolean, error text);

SELECT case_name, ok, error FROM dry_roundlist_done ORDER BY case_name;

ROLLBACK;
