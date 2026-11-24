do $mig$
begin
  if to_regclass('public.v2_firms') is null or not exists (select 1 from pg_proc where proname = 'v2_apply_research_queue_fields') then
    raise notice 'v2_firms not present; skipped'; return;
  end if;
  execute $sql$
-- HQ can be a country only; city optional (Alex, 2026-11-23 5:17 PM PT). check7 (US needs a 2-letter state) unchanged.
alter table public.v2_firms drop constraint v2_firms_check6;
alter table public.v2_firms add constraint v2_firms_check6 check (((hq_street is null) and (hq_suite is null) and (hq_city is null) and (hq_state is null) and (hq_postal is null) and (hq_country is null)) or ((hq_source is not null) and (hq_country is not null)));
CREATE OR REPLACE FUNCTION public.v2_apply_research_queue_fields(p_firm_id bigint, p_registry_id text, p_bot_key_id bigint DEFAULT NULL::bigint, p_source_owner text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
AS $function$
DECLARE
  v_q public.research_queue;
  v_f public.v2_firms;
  v_iso text;
  v_city text;
  v_state text;
  v_crd text;
  v_src jsonb;
  v_new_country text;
  v_new_city text;
  v_new_state text;
  v_fill_country boolean := false;
  v_fill_city boolean := false;
  v_fill_state boolean := false;
  v_owner text;
  v_batch bigint;
  v_sub bigint;
  v_src_url text;
  v_today date;
BEGIN
  IF p_firm_id IS NULL OR nullif(btrim(p_registry_id), '') IS NULL THEN
    RETURN;
  END IF;
  SELECT * INTO v_q FROM public.research_queue WHERE registry_id = btrim(p_registry_id);
  IF NOT FOUND THEN
    RETURN;
  END IF;
  SELECT * INTO v_f FROM public.v2_firms WHERE firm_id = p_firm_id;
  IF NOT FOUND OR v_f.merged_into_firm_id IS NOT NULL THEN
    RETURN;
  END IF;

  v_iso := public.research_queue_country_iso(v_q.country);
  v_city := public.research_queue_city_clean(v_q.hq_city);
  v_crd := CASE WHEN nullif(btrim(v_q.sec_crd), '') ~ '^[0-9]+$' THEN btrim(v_q.sec_crd) END;
  v_new_country := coalesce(v_f.hq_country, v_iso);
  IF v_new_country = 'US' THEN
    v_state := public.research_queue_us_state(v_q.state);
  ELSE
    v_state := nullif(btrim(v_q.state), '');
  END IF;
  v_new_city := coalesce(nullif(btrim(v_f.hq_city), ''), v_city);
  v_new_state := coalesce(nullif(btrim(v_f.hq_state), ''), v_state);

  -- Any HQ field requires country and source (city optional since 2026-11-23). A US row also needs a 2-letter state.
  IF (v_f.hq_country IS NULL OR v_f.hq_city IS NULL)
     AND v_new_country IS NOT NULL
     AND (v_new_country IS DISTINCT FROM 'US' OR v_new_state ~ '^[A-Z]{2}$') THEN
    v_fill_country := (v_f.hq_country IS NULL);
    v_fill_city := (v_f.hq_city IS NULL AND v_city IS NOT NULL);
  END IF;
  IF v_f.hq_state IS NULL AND v_state IS NOT NULL THEN
    IF (coalesce(v_f.hq_country, CASE WHEN v_fill_country THEN v_iso END) IS NOT NULL
        AND (coalesce(v_f.hq_country, CASE WHEN v_fill_country THEN v_iso END) IS DISTINCT FROM 'US'
             OR v_state ~ '^[A-Z]{2}$')) THEN
      v_fill_state := true;
    END IF;
  END IF;

  IF v_fill_country OR v_fill_city OR v_fill_state THEN
    v_today := (now() AT TIME ZONE 'America/Los_Angeles')::date;
    IF v_crd IS NOT NULL THEN
      v_src_url := 'https://adviserinfo.sec.gov/firm/summary/' || v_crd;
    ELSIF v_f.website_url IS NOT NULL
      AND v_f.website_url ~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$'
      AND NOT public.v2_url_banned(v_f.website_url) THEN
      v_src_url := v_f.website_url;
    ELSIF v_q.website IS NOT NULL
      AND v_q.website ~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$'
      AND NOT public.v2_url_banned(v_q.website) THEN
      v_src_url := v_q.website;
    ELSE
      v_src_url := 'https://regretamin.com/sources/research-queue';
    END IF;
    v_src := jsonb_build_object(
      'url', v_src_url,
      'level', CASE WHEN v_crd IS NOT NULL THEN 1 ELSE 4 END,
      'date', to_char(v_today, 'YYYY-MM-DD')
    );
    UPDATE public.v2_firms
       SET hq_country = CASE WHEN v_fill_country THEN v_iso ELSE hq_country END,
           hq_city    = CASE WHEN v_fill_city THEN v_city ELSE hq_city END,
           hq_state   = CASE WHEN v_fill_state THEN v_state ELSE hq_state END,
           hq_source  = CASE WHEN hq_source IS NULL AND (v_fill_country OR v_fill_city)
                             THEN v_src ELSE hq_source END
     WHERE firm_id = p_firm_id;
  END IF;

  IF v_crd IS NOT NULL
     AND p_bot_key_id IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM public.v2_firm_registry_ids r
        WHERE r.firm_id = p_firm_id AND r.registry_type = 'SEC CRD' AND r.is_current
     )
     AND NOT EXISTS (
       SELECT 1 FROM public.v2_firm_registry_ids r
        WHERE r.registry_type = 'SEC CRD' AND NOT r.archived AND r.registry_value = v_crd
     ) THEN
    v_owner := coalesce(nullif(btrim(p_source_owner), ''), 'research_queue');
    v_today := coalesce(v_today, (now() AT TIME ZONE 'America/Los_Angeles')::date);
    v_batch := nextval('public.v2_batch_seq');
    INSERT INTO public.v2_research_submissions (
      batch_id, firm_id, bot_key_id, target_box, payload, status
    ) VALUES (
      v_batch, p_firm_id, p_bot_key_id, 'F1',
      jsonb_build_object('source', 'research_queue', 'registry_type', 'SEC CRD', 'registry_value', v_crd),
      'Accepted'
    ) RETURNING submission_id INTO v_sub;
    INSERT INTO public.v2_firm_registry_ids (
      source_url, source_level, source_date, source_date_precision, source_date_is_found_date,
      source_type, source_owner, is_current, archived, submission_id, firm_id,
      registry_type, registry_value, registry_country, nothing_found
    ) VALUES (
      'https://adviserinfo.sec.gov/firm/summary/' || v_crd,
      1, v_today, 'full date', true,
      'Regulator', v_owner, true, false, v_sub, p_firm_id,
      'SEC CRD', v_crd, 'US', false
    );
  END IF;
END
$function$;

$sql$;
end
$mig$;
