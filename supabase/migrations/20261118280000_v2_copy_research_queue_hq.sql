-- Copy blank v2 HQ and SEC CRD fields from research_queue. Never overwrites
-- a value that is already set. New list-builder firms get the same copy from
-- v2_research_add_firm when a matching queue row exists.
-- Rollback: supabase/rollbacks/20261118280000_v2_copy_research_queue_hq.sql
-- That rollback clears only the fields this migration marked.

do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.research_queue') is null then
    raise notice 'v2_firms or research_queue missing, skipped';
    return;
  end if;

  execute $fn$
CREATE OR REPLACE FUNCTION public.research_queue_country_iso(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $iso$
  SELECT CASE
    WHEN nullif(btrim(p), '') IS NULL THEN NULL
    -- List-builder tags, not countries.
    WHEN upper(btrim(p)) IN ('US-SMALL', 'US-CUR') THEN NULL
    WHEN upper(btrim(p)) IN ('US', 'CA', 'MX', 'GL', 'PM', 'AD', 'AL', 'AT', 'AX', 'BA', 'BE', 'BG', 'BV', 'BY', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FO', 'FR', 'GB', 'GG', 'GI', 'GR', 'HR', 'HU', 'IE', 'IM', 'IS', 'IT', 'JE', 'LI', 'LT', 'LU', 'LV', 'MC', 'MD', 'ME', 'MK', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'RS', 'RU', 'SE', 'SI', 'SJ', 'SK', 'SM', 'UA', 'VA', 'XK', 'AG', 'AI', 'AR', 'AW', 'BB', 'BL', 'BM', 'BO', 'BQ', 'BR', 'BS', 'BZ', 'CL', 'CO', 'CR', 'CU', 'CW', 'DM', 'DO', 'EC', 'FK', 'GD', 'GF', 'GP', 'GS', 'GT', 'GY', 'HN', 'HT', 'JM', 'KN', 'KY', 'LC', 'MF', 'MQ', 'MS', 'NI', 'PA', 'PE', 'PR', 'PY', 'SR', 'SV', 'SX', 'TC', 'TT', 'UY', 'VC', 'VE', 'VG', 'VI', 'AF', 'AM', 'AZ', 'BD', 'BN', 'BT', 'CN', 'GE', 'HK', 'ID', 'IN', 'IO', 'JP', 'KG', 'KH', 'KP', 'KR', 'KZ', 'LA', 'LK', 'MM', 'MN', 'MO', 'MV', 'MY', 'NP', 'PH', 'PK', 'SG', 'TH', 'TJ', 'TL', 'TM', 'TW', 'UZ', 'VN', 'AE', 'BH', 'IL', 'IQ', 'IR', 'JO', 'KW', 'LB', 'OM', 'PS', 'QA', 'SA', 'SY', 'TR', 'YE', 'AO', 'BF', 'BI', 'BJ', 'BW', 'CD', 'CF', 'CG', 'CI', 'CM', 'CV', 'DJ', 'DZ', 'EG', 'EH', 'ER', 'ET', 'GA', 'GH', 'GM', 'GN', 'GQ', 'GW', 'KE', 'KM', 'LR', 'LS', 'LY', 'MA', 'MG', 'ML', 'MR', 'MU', 'MW', 'MZ', 'NA', 'NE', 'NG', 'RE', 'RW', 'SC', 'SD', 'SH', 'SL', 'SN', 'SO', 'SS', 'ST', 'SZ', 'TD', 'TF', 'TG', 'TN', 'TZ', 'UG', 'YT', 'ZA', 'ZM', 'ZW', 'AS', 'AU', 'CC', 'CK', 'CX', 'FJ', 'FM', 'GU', 'HM', 'KI', 'MH', 'MP', 'NC', 'NF', 'NR', 'NU', 'NZ', 'PF', 'PG', 'PN', 'PW', 'SB', 'TK', 'TO', 'TV', 'UM', 'VU', 'WF', 'WS') THEN upper(btrim(p))
    ELSE (
      SELECT m.iso FROM (VALUES
      ('united states', 'US'),
      ('usa', 'US'),
      ('us', 'US'),
      ('u.s.', 'US'),
      ('u.s.a.', 'US'),
      ('united states of america', 'US'),
      ('united kingdom', 'GB'),
      ('great britain', 'GB'),
      ('uk', 'GB'),
      ('u.k.', 'GB'),
      ('gb', 'GB'),
      ('korea, south', 'KR'),
      ('south korea', 'KR'),
      ('republic of korea', 'KR'),
      ('hong kong sar', 'HK'),
      ('hong kong', 'HK'),
      ('hong kong sar china', 'HK'),
      ('taiwan', 'TW'),
      ('taiwan,  republic of china', 'TW'),
      ('taiwan, republic of china', 'TW'),
      ('people''s republic of china', 'CN'),
      ('china', 'CN'),
      ('prc', 'CN'),
      ('czech republic', 'CZ'),
      ('czechia', 'CZ'),
      ('united arab emirates', 'AE'),
      ('uae', 'AE'),
      ('cayman islands', 'KY'),
      ('india', 'IN'),
      ('russia', 'RU'),
      ('russian federation', 'RU'),
      ('vietnam', 'VN'),
      ('viet nam', 'VN'),
      ('turkey', 'TR'),
      ('turkiye', 'TR'),
      ('türkiye', 'TR'),
      ('cote d''ivoire', 'CI'),
      ('côte d''ivoire', 'CI'),
      ('ivory coast', 'CI'),
      ('bahamas, the', 'BS'),
      ('the bahamas', 'BS'),
      ('bahamas', 'BS'),
      ('the gambia', 'GM'),
      ('gambia, the', 'GM'),
      ('gambia', 'GM'),
      ('dr congo', 'CD'),
      ('democratic republic of the congo', 'CD'),
      ('congo, democratic republic of the', 'CD'),
      ('congo', 'CG'),
      ('republic of the congo', 'CG'),
      ('kingdom of denmark', 'DK'),
      ('denmark', 'DK'),
      ('south africa', 'ZA'),
      ('new zealand', 'NZ'),
      ('saudi arabia', 'SA'),
      ('british virgin islands', 'VG'),
      ('isle of man', 'IM'),
      ('north macedonia', 'MK'),
      ('macedonia', 'MK'),
      ('dominican republic', 'DO'),
      ('el salvador', 'SV'),
      ('costa rica', 'CR'),
      ('puerto rico', 'PR'),
      ('sri lanka', 'LK'),
      ('bosnia and herzegovina', 'BA'),
      ('trinidad and tobago', 'TT'),
      ('antigua and barbuda', 'AG'),
      ('saint kitts and nevis', 'KN'),
      ('papua new guinea', 'PG'),
      ('united states virgin islands', 'VI'),
      ('afghanistan', 'AF'),
      ('albania', 'AL'),
      ('algeria', 'DZ'),
      ('andorra', 'AD'),
      ('angola', 'AO'),
      ('argentina', 'AR'),
      ('armenia', 'AM'),
      ('australia', 'AU'),
      ('austria', 'AT'),
      ('azerbaijan', 'AZ'),
      ('bahrain', 'BH'),
      ('bangladesh', 'BD'),
      ('barbados', 'BB'),
      ('belarus', 'BY'),
      ('belgium', 'BE'),
      ('belize', 'BZ'),
      ('benin', 'BJ'),
      ('bermuda', 'BM'),
      ('bhutan', 'BT'),
      ('bolivia', 'BO'),
      ('botswana', 'BW'),
      ('brazil', 'BR'),
      ('brunei', 'BN'),
      ('bulgaria', 'BG'),
      ('burkina faso', 'BF'),
      ('burundi', 'BI'),
      ('cambodia', 'KH'),
      ('cameroon', 'CM'),
      ('canada', 'CA'),
      ('cape verde', 'CV'),
      ('cabo verde', 'CV'),
      ('chad', 'TD'),
      ('chile', 'CL'),
      ('colombia', 'CO'),
      ('comoros', 'KM'),
      ('croatia', 'HR'),
      ('cuba', 'CU'),
      ('cyprus', 'CY'),
      ('ecuador', 'EC'),
      ('egypt', 'EG'),
      ('equatorial guinea', 'GQ'),
      ('eritrea', 'ER'),
      ('estonia', 'EE'),
      ('eswatini', 'SZ'),
      ('swaziland', 'SZ'),
      ('ethiopia', 'ET'),
      ('fiji', 'FJ'),
      ('finland', 'FI'),
      ('france', 'FR'),
      ('gabon', 'GA'),
      ('georgia', 'GE'),
      ('germany', 'DE'),
      ('ghana', 'GH'),
      ('gibraltar', 'GI'),
      ('greece', 'GR'),
      ('greenland', 'GL'),
      ('grenada', 'GD'),
      ('guatemala', 'GT'),
      ('guernsey', 'GG'),
      ('guinea', 'GN'),
      ('guinea-bissau', 'GW'),
      ('guyana', 'GY'),
      ('haiti', 'HT'),
      ('honduras', 'HN'),
      ('hungary', 'HU'),
      ('iceland', 'IS'),
      ('indonesia', 'ID'),
      ('iran', 'IR'),
      ('iraq', 'IQ'),
      ('ireland', 'IE'),
      ('israel', 'IL'),
      ('italy', 'IT'),
      ('jamaica', 'JM'),
      ('japan', 'JP'),
      ('jersey', 'JE'),
      ('jordan', 'JO'),
      ('kazakhstan', 'KZ'),
      ('kenya', 'KE'),
      ('kuwait', 'KW'),
      ('kyrgyzstan', 'KG'),
      ('laos', 'LA'),
      ('latvia', 'LV'),
      ('lebanon', 'LB'),
      ('lesotho', 'LS'),
      ('liberia', 'LR'),
      ('libya', 'LY'),
      ('liechtenstein', 'LI'),
      ('lithuania', 'LT'),
      ('luxembourg', 'LU'),
      ('madagascar', 'MG'),
      ('malawi', 'MW'),
      ('malaysia', 'MY'),
      ('maldives', 'MV'),
      ('mali', 'ML'),
      ('malta', 'MT'),
      ('mauritania', 'MR'),
      ('mauritius', 'MU'),
      ('mexico', 'MX'),
      ('moldova', 'MD'),
      ('monaco', 'MC'),
      ('mongolia', 'MN'),
      ('montenegro', 'ME'),
      ('morocco', 'MA'),
      ('mozambique', 'MZ'),
      ('myanmar', 'MM'),
      ('namibia', 'NA'),
      ('nepal', 'NP'),
      ('netherlands', 'NL'),
      ('nicaragua', 'NI'),
      ('niger', 'NE'),
      ('nigeria', 'NG'),
      ('norway', 'NO'),
      ('oman', 'OM'),
      ('pakistan', 'PK'),
      ('panama', 'PA'),
      ('paraguay', 'PY'),
      ('peru', 'PE'),
      ('philippines', 'PH'),
      ('poland', 'PL'),
      ('portugal', 'PT'),
      ('qatar', 'QA'),
      ('romania', 'RO'),
      ('rwanda', 'RW'),
      ('senegal', 'SN'),
      ('serbia', 'RS'),
      ('sierra leone', 'SL'),
      ('singapore', 'SG'),
      ('slovakia', 'SK'),
      ('slovenia', 'SI'),
      ('somalia', 'SO'),
      ('spain', 'ES'),
      ('sudan', 'SD'),
      ('sweden', 'SE'),
      ('switzerland', 'CH'),
      ('syria', 'SY'),
      ('tanzania', 'TZ'),
      ('thailand', 'TH'),
      ('togo', 'TG'),
      ('tunisia', 'TN'),
      ('turkmenistan', 'TM'),
      ('uganda', 'UG'),
      ('ukraine', 'UA'),
      ('uruguay', 'UY'),
      ('uzbekistan', 'UZ'),
      ('venezuela', 'VE'),
      ('yemen', 'YE'),
      ('zambia', 'ZM'),
      ('zimbabwe', 'ZW'),
      ('south sudan', 'SS'),
      ('palestine', 'PS'),
      ('palestinian territory', 'PS'),
      ('macau', 'MO'),
      ('macao', 'MO')
      ) m(raw, iso)
      WHERE m.raw = lower(btrim(p))
      LIMIT 1
    )
  END
$iso$;
$fn$;

  execute $fn$
CREATE OR REPLACE FUNCTION public.research_queue_us_state(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $st$
  SELECT CASE
    WHEN nullif(btrim(p), '') IS NULL THEN NULL
    WHEN upper(btrim(p)) IN ('AK', 'AL', 'AR', 'AZ', 'CA', 'CO', 'CT', 'DC', 'DE', 'FL', 'GA', 'HI', 'IA', 'ID', 'IL', 'IN', 'KS', 'KY', 'LA', 'MA', 'MD', 'ME', 'MI', 'MN', 'MO', 'MS', 'MT', 'NC', 'ND', 'NE', 'NH', 'NJ', 'NM', 'NV', 'NY', 'OH', 'OK', 'OR', 'PA', 'PR', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VA', 'VT', 'WA', 'WI', 'WV', 'WY') THEN upper(btrim(p))
    ELSE (
      SELECT m.a FROM (VALUES
      ('alabama', 'AL'),
      ('alaska', 'AK'),
      ('arizona', 'AZ'),
      ('arkansas', 'AR'),
      ('california', 'CA'),
      ('colorado', 'CO'),
      ('connecticut', 'CT'),
      ('delaware', 'DE'),
      ('district of columbia', 'DC'),
      ('florida', 'FL'),
      ('georgia', 'GA'),
      ('hawaii', 'HI'),
      ('idaho', 'ID'),
      ('illinois', 'IL'),
      ('indiana', 'IN'),
      ('iowa', 'IA'),
      ('kansas', 'KS'),
      ('kentucky', 'KY'),
      ('louisiana', 'LA'),
      ('maine', 'ME'),
      ('maryland', 'MD'),
      ('massachusetts', 'MA'),
      ('michigan', 'MI'),
      ('minnesota', 'MN'),
      ('mississippi', 'MS'),
      ('missouri', 'MO'),
      ('montana', 'MT'),
      ('nebraska', 'NE'),
      ('nevada', 'NV'),
      ('new hampshire', 'NH'),
      ('new jersey', 'NJ'),
      ('new mexico', 'NM'),
      ('new york', 'NY'),
      ('north carolina', 'NC'),
      ('north dakota', 'ND'),
      ('ohio', 'OH'),
      ('oklahoma', 'OK'),
      ('oregon', 'OR'),
      ('pennsylvania', 'PA'),
      ('rhode island', 'RI'),
      ('south carolina', 'SC'),
      ('south dakota', 'SD'),
      ('tennessee', 'TN'),
      ('texas', 'TX'),
      ('utah', 'UT'),
      ('vermont', 'VT'),
      ('virginia', 'VA'),
      ('washington', 'WA'),
      ('west virginia', 'WV'),
      ('wisconsin', 'WI'),
      ('wyoming', 'WY'),
      ('puerto rico', 'PR')
      ) m(n, a)
      WHERE m.n = lower(btrim(p))
      LIMIT 1
    )
  END
$st$;
$fn$;

  execute $fn$
CREATE OR REPLACE FUNCTION public.research_queue_city_clean(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $c$
  SELECT CASE
    WHEN nullif(btrim(p), '') IS NULL THEN NULL
    WHEN btrim(p) = upper(btrim(p)) AND char_length(btrim(p)) > 3
      THEN initcap(lower(btrim(p)))
    ELSE btrim(p)
  END
$c$;
$fn$;

  execute $fn$
CREATE OR REPLACE FUNCTION public.v2_apply_research_queue_fields(
  p_firm_id bigint,
  p_registry_id text,
  p_bot_key_id bigint DEFAULT NULL,
  p_source_owner text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'bots'
AS $apply$
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

  -- Any HQ field requires city, country, and source. A US row also needs a 2-letter state.
  IF (v_f.hq_country IS NULL OR v_f.hq_city IS NULL)
     AND v_new_country IS NOT NULL
     AND v_new_city IS NOT NULL
     AND (v_new_country IS DISTINCT FROM 'US' OR v_new_state ~ '^[A-Z]{2}$') THEN
    v_fill_country := (v_f.hq_country IS NULL);
    v_fill_city := (v_f.hq_city IS NULL);
  END IF;
  IF v_f.hq_state IS NULL AND v_state IS NOT NULL THEN
    IF (coalesce(v_f.hq_country, CASE WHEN v_fill_country THEN v_iso END) IS NOT NULL
        AND coalesce(nullif(btrim(v_f.hq_city), ''), CASE WHEN v_fill_city THEN v_city END) IS NOT NULL
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
$apply$;
$fn$;

  execute 'revoke all on function public.research_queue_country_iso(text) from public, anon, authenticated';
  execute 'revoke all on function public.research_queue_us_state(text) from public, anon, authenticated';
  execute 'revoke all on function public.research_queue_city_clean(text) from public, anon, authenticated';
  execute 'revoke all on function public.v2_apply_research_queue_fields(bigint, text, bigint, text) from public, anon, authenticated';
  execute 'grant execute on function public.research_queue_country_iso(text) to service_role';
  execute 'grant execute on function public.research_queue_us_state(text) to service_role';
  execute 'grant execute on function public.research_queue_city_clean(text) to service_role';
  execute 'grant execute on function public.v2_apply_research_queue_fields(bigint, text, bigint, text) to service_role';

  -- Log table for an exact rollback of the one-time copy only.
  execute $tbl$
CREATE TABLE IF NOT EXISTS public.v2_research_queue_copy (
  firm_id bigint PRIMARY KEY REFERENCES public.v2_firms(firm_id),
  filled_country boolean NOT NULL DEFAULT false,
  filled_city boolean NOT NULL DEFAULT false,
  filled_state boolean NOT NULL DEFAULT false,
  filled_crd boolean NOT NULL DEFAULT false,
  registry_row_id bigint,
  submission_id bigint,
  copied_at timestamptz NOT NULL DEFAULT now()
)
$tbl$;
  execute 'alter table public.v2_research_queue_copy enable row level security';
  execute 'revoke all on public.v2_research_queue_copy from public, anon, authenticated';
  execute 'grant all on public.v2_research_queue_copy to service_role';
end
$mig$;

-- One-time copy of blank fields. Skips unclear countries, conflicts, and
-- rows that would violate the HQ check (city+country required; US needs state).
do $copy$
declare
  v_bot bigint;
  v_batch bigint;
  v_sub bigint;
  v_today date := (now() at time zone 'America/Los_Angeles')::date;
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.research_queue') is null
     or to_regclass('public.v2_research_queue_copy') is null then
    raise notice 'v2 copy skipped';
    return;
  end if;

  if exists (select 1 from public.v2_research_queue_copy) then
    raise notice 'research_queue copy already applied, skipped';
    return;
  end if;

  create temporary table _firms_link (slug text, registry_id text) on commit drop;
  if to_regclass('public.firms') is not null then
    execute 'insert into _firms_link select slug, registry_id from public.firms where deleted_at is null';
  end if;

  insert into public.v2_bot_keys (bot_name, key_hash, frozen, freeze_reason, freeze_date)
  values ('research_queue_copy', null, true, 'one-time research_queue field copy', now())
  on conflict (bot_name) do update
    set freeze_reason = excluded.freeze_reason
  returning bot_key_id into v_bot;

  v_batch := nextval('public.v2_batch_seq');
  insert into public.v2_research_submissions (
    batch_id, firm_id, bot_key_id, target_box, payload, status
  ) values (
    v_batch, null, v_bot, 'F1',
    jsonb_build_object('source', 'research_queue_copy'),
    'Accepted'
  ) returning submission_id into v_sub;

  create temporary table _qcopy_plan on commit drop as
  with q as (
    select
      registry_id,
      name,
      website,
      public.v2_norm_url(website) as website_norm,
      public._slugify(registry_id) as registry_slug,
      nullif(btrim(country), '') as country_raw,
      public.research_queue_country_iso(country) as country_iso,
      public.research_queue_city_clean(hq_city) as city,
      nullif(btrim(state), '') as state_raw,
      case when nullif(btrim(sec_crd), '') ~ '^[0-9]+$' then btrim(sec_crd) end as crd
    from public.research_queue
  ),
  v2 as (
    select firm_id, slug, display_name, website_url, website_url_norm,
           hq_city, hq_state, hq_country, hq_source
      from public.v2_firms
     where merged_into_firm_id is null
  ),
  matches as (
    select firm_id, registry_id, pri from (
      select v.firm_id, q.registry_id, 1 as pri
        from v2 v
        join _firms_link p on p.slug = v.slug
        join q on q.registry_id = p.registry_id
      union
      select v.firm_id, q.registry_id, 1
        from v2 v
        join q on q.registry_id = v.slug or q.registry_slug = v.slug
      union
      select v.firm_id, q.registry_id, 2
        from v2 v
        join q on q.website_norm is not null and v.website_url_norm is not null
             and q.website_norm = v.website_url_norm
      union
      select v.firm_id, q.registry_id, 3
        from v2 v
        join q on lower(btrim(q.name)) = lower(btrim(v.display_name))
             and nullif(btrim(q.name), '') is not null
    ) x
  ),
  best as (
    select firm_id, min(pri) as pri from matches group by firm_id
  ),
  chosen as (
    select distinct m.firm_id, m.registry_id, m.pri
      from matches m
      join best b on b.firm_id = m.firm_id and b.pri = m.pri
  ),
  joined as (
    select c.firm_id, c.pri, q.*
      from chosen c
      join q on q.registry_id = c.registry_id
  ),
  agg as (
    select
      j.firm_id,
      count(distinct j.country_iso) filter (where j.country_iso is not null) as n_iso,
      count(*) filter (where j.country_raw is not null and j.country_iso is null) as n_unclear,
      max(j.country_iso) as country_iso,
      count(distinct lower(j.city)) filter (where j.city is not null) as n_city,
      (array_agg(j.city order by j.city) filter (where j.city is not null))[1] as city,
      count(distinct j.crd) filter (where j.crd is not null) as n_crd,
      max(j.crd) as crd,
      array_agg(j.state_raw order by j.state_raw) filter (where j.state_raw is not null) as states_raw,
      (array_agg(j.website order by j.website) filter (where j.website is not null))[1] as website
    from joined j
    group by j.firm_id
  ),
  planned as (
    select
      a.firm_id,
      v.hq_country as old_country,
      v.hq_city as old_city,
      v.hq_state as old_state,
      v.hq_source as old_source,
      v.website_url,
      case when a.n_iso = 1 and a.n_unclear = 0 then a.country_iso end as agreed_iso,
      case when a.n_city = 1 then a.city end as agreed_city,
      case when a.n_crd = 1 then a.crd end as agreed_crd,
      a.n_iso, a.n_unclear, a.n_city, a.n_crd, a.states_raw, a.website
    from agg a
    join v2 v on v.firm_id = a.firm_id
  ),
  with_state as (
    select p.*,
      case
        when coalesce(p.old_country, p.agreed_iso) is distinct from 'US' then
          case when p.states_raw is not null
                and (select count(distinct lower(btrim(x))) from unnest(p.states_raw) x) = 1
               then public.research_queue_city_clean(p.states_raw[1])
               -- keep non-US state text as cleaned trim; city_clean also initcaps ALL CAPS
               else null end
        else
          case when (
            select count(distinct public.research_queue_us_state(x))
              from unnest(p.states_raw) x
             where public.research_queue_us_state(x) is not null
          ) = 1
          and not exists (
            select 1 from unnest(p.states_raw) x
            where nullif(btrim(x), '') is not null
              and public.research_queue_us_state(x) is null
          )
          then (
            select max(public.research_queue_us_state(x))
              from unnest(p.states_raw) x
          )
          else null end
      end as agreed_state
    from planned p
  )
  select
    s.firm_id,
    s.old_country, s.old_city, s.old_state, s.old_source,
    s.agreed_iso, s.agreed_city, s.agreed_state, s.agreed_crd,
    s.website_url, s.website,
    (s.old_country is null and s.agreed_iso is not null and s.agreed_city is not null
      and (s.agreed_iso is distinct from 'US' or s.agreed_state ~ '^[A-Z]{2}$')) as fill_country,
    (s.old_city is null and s.agreed_iso is not null and s.agreed_city is not null
      and (s.agreed_iso is distinct from 'US' or s.agreed_state ~ '^[A-Z]{2}$')
      and s.old_country is null) as fill_city,
    (s.old_state is null and s.agreed_state is not null
      and coalesce(s.old_country, s.agreed_iso) is not null
      and coalesce(nullif(btrim(s.old_city), ''), s.agreed_city) is not null
      and (coalesce(s.old_country, s.agreed_iso) is distinct from 'US' or s.agreed_state ~ '^[A-Z]{2}$')
      and (s.old_country is not null or (
        s.agreed_iso is not null and s.agreed_city is not null
        and (s.agreed_iso is distinct from 'US' or s.agreed_state ~ '^[A-Z]{2}$')
      ))) as fill_state,
    (s.agreed_crd is not null
      and not exists (
        select 1 from public.v2_firm_registry_ids r
         where r.firm_id = s.firm_id and r.registry_type = 'SEC CRD' and r.is_current
      )
      and not exists (
        select 1 from public.v2_firm_registry_ids r
         where r.registry_type = 'SEC CRD' and not r.archived and r.registry_value = s.agreed_crd
      )) as fill_crd
  from with_state s;

  update public.v2_firms f
     set hq_country = case when p.fill_country then p.agreed_iso else f.hq_country end,
         hq_city    = case when p.fill_city then p.agreed_city else f.hq_city end,
         hq_state   = case when p.fill_state then p.agreed_state else f.hq_state end,
         hq_source  = case
                        when f.hq_source is null and (p.fill_country or p.fill_city) then
                          jsonb_build_object(
                            'url',
                            case
                              when p.agreed_crd is not null
                                then 'https://adviserinfo.sec.gov/firm/summary/' || p.agreed_crd
                              when p.website_url is not null
                               and p.website_url ~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$'
                               and not public.v2_url_banned(p.website_url)
                                then p.website_url
                              when p.website is not null
                               and p.website ~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$'
                               and not public.v2_url_banned(p.website)
                                then p.website
                              else 'https://regretamin.com/sources/research-queue'
                            end,
                            'level', case when p.agreed_crd is not null then 1 else 4 end,
                            'date', to_char(v_today, 'YYYY-MM-DD')
                          )
                        else f.hq_source
                      end
    from _qcopy_plan p
   where f.firm_id = p.firm_id
     and (p.fill_country or p.fill_city or p.fill_state);

  insert into public.v2_firm_registry_ids (
    source_url, source_level, source_date, source_date_precision, source_date_is_found_date,
    source_type, source_owner, is_current, archived, submission_id, firm_id,
    registry_type, registry_value, registry_country, nothing_found
  )
  select
    'https://adviserinfo.sec.gov/firm/summary/' || p.agreed_crd,
    1, v_today, 'full date', true,
    'Regulator', 'research_queue', true, false, v_sub, p.firm_id,
    'SEC CRD', p.agreed_crd, 'US', false
  from _qcopy_plan p
  where p.fill_crd;

  insert into public.v2_research_queue_copy (
    firm_id, filled_country, filled_city, filled_state, filled_crd, registry_row_id, submission_id
  )
  select
    p.firm_id, p.fill_country, p.fill_city, p.fill_state, p.fill_crd,
    case when p.fill_crd then r.row_id end,
    case when p.fill_crd then v_sub end
  from _qcopy_plan p
  left join public.v2_firm_registry_ids r
    on r.firm_id = p.firm_id and r.registry_type = 'SEC CRD' and r.is_current
   and r.source_owner = 'research_queue' and p.fill_crd
  where p.fill_country or p.fill_city or p.fill_state or p.fill_crd
  on conflict (firm_id) do nothing;

  if to_regclass('public.firm_summary') is not null then
    perform public.refresh_firm_summary(array(
      select firm_id from public.v2_research_queue_copy
       where filled_country or filled_city or filled_state
    ));
  end if;
end
$copy$;

-- v2_research_add_firm: after creating or finding a firm, copy blank HQ and
-- SEC CRD fields from the research_queue row with this registry_id.
do $add$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped add_firm replace';
    return;
  end if;

  execute $fn$
CREATE OR REPLACE FUNCTION public.v2_research_add_firm(p_key_id uuid, p_firm jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  nm text;
  web text;
  reg text;
  slg text;
  fid bigint;
  created boolean := false;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  IF jsonb_typeof(p_firm) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm must be an object with name, website, registry_id');
  END IF;
  nm := btrim(coalesce(p_firm->>'name', ''));
  web := btrim(coalesce(p_firm->>'website', ''));
  reg := btrim(coalesce(p_firm->>'registry_id', ''));
  IF nm = '' OR web = '' OR reg = '' THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'firm needs name, website, and registry_id');
  END IF;
  IF length(nm) > 200 OR length(reg) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'name and registry_id must be 200 characters or less');
  END IF;
  IF web !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(:[0-9]+)?(/[^\s]*)?$' OR public.v2_url_never_website(web) THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'website is not a valid firm site');
  END IF;

  -- Existing firm on v2_firms only: registry value, the slug itself, the same website, then the name slug.
  SELECT r.firm_id INTO fid
    FROM public.v2_firm_registry_ids r
    JOIN public.v2_firms f ON f.firm_id = r.firm_id
   WHERE NOT r.archived AND NOT coalesce(f.archived, false) AND r.registry_value = reg
   ORDER BY r.is_current DESC, r.firm_id
   LIMIT 1;

  IF fid IS NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false) AND slug IN (reg, public._slugify(reg))
     ORDER BY firm_id
     LIMIT 1;
  END IF;

  IF fid IS NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false)
       AND website_url_norm IS NOT NULL
       AND website_url_norm = public.v2_norm_url(web)
     LIMIT 1;
  END IF;

  IF fid IS NULL AND public._slugify(nm) IS NOT NULL THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE NOT coalesce(archived, false) AND slug = public._slugify(nm)
     LIMIT 1;
  END IF;

  IF fid IS NULL THEN
    slg := coalesce(public._slugify(nm), public._slugify(reg));
    IF slg IS NULL OR length(slg) > 200 THEN
      RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'could not make a slug from name or registry_id');
    END IF;

    SELECT firm_id INTO fid FROM public.v2_firms WHERE slug = slg;
  END IF;

  IF fid IS NULL THEN
    BEGIN
      INSERT INTO public.v2_firms (slug, display_name, website_url, firm_status)
      VALUES (slg, nm, web, 'Active')
      RETURNING firm_id INTO fid;
      created := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT firm_id INTO fid FROM public.v2_firms
       WHERE slug = slg
          OR (website_url_norm = public.v2_norm_url(web) AND NOT coalesce(archived, false))
       ORDER BY firm_id
       LIMIT 1;
      IF fid IS NULL THEN
        RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', left(SQLERRM, 300));
      END IF;
    END;
  END IF;

  BEGIN
    PERFORM public.v2_apply_research_queue_fields(fid, reg, bk.bot_key_id, bot);
  EXCEPTION WHEN others THEN
    RAISE WARNING 'add_firm queue copy %: %', fid, SQLERRM;
  END;

  RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', created,
    'slug', (SELECT slug FROM public.v2_firms WHERE firm_id = fid));
END
$function$;
$fn$;

  execute 'revoke all on function public.v2_research_add_firm(uuid, jsonb) from public, anon, authenticated';
  execute 'grant execute on function public.v2_research_add_firm(uuid, jsonb) to service_role';
end
$add$;
