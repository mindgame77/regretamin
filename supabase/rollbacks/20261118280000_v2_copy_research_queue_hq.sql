-- Undo the research_queue HQ / SEC CRD copy.
-- Clears only fields this migration marked in v2_research_queue_copy.
-- Restores v2_research_add_firm to the previous body (20261108165320).
-- Firm rows stay; blank fields go back to blank.

do $undo$
declare
  v_ids bigint[];
  v_bot bigint;
begin
  if to_regclass('public.v2_research_queue_copy') is not null then
    select array_agg(firm_id) into v_ids
      from public.v2_research_queue_copy
     where filled_country or filled_city or filled_state;

    -- HQ: clear only the blanks this copy filled. Leave any pre-existing source alone.
    if to_regclass('public.v2_firms') is not null then
      update public.v2_firms f
         set hq_country = case when c.filled_country then null else f.hq_country end,
             hq_city    = case when c.filled_city then null else f.hq_city end,
             hq_state   = case when c.filled_state then null else f.hq_state end,
             hq_source  = case when c.filled_country or c.filled_city then null else f.hq_source end
        from public.v2_research_queue_copy c
       where f.firm_id = c.firm_id
         and (c.filled_country or c.filled_city or c.filled_state);
    end if;

    if to_regclass('public.v2_firm_registry_ids') is not null then
      delete from public.v2_firm_registry_ids r
       using public.v2_research_queue_copy c
       where c.filled_crd
         and (
           (c.registry_row_id is not null and r.row_id = c.registry_row_id)
           or (c.registry_row_id is null and r.firm_id = c.firm_id
               and r.registry_type = 'SEC CRD' and r.source_owner = 'research_queue'
               and r.submission_id is not distinct from c.submission_id)
         );
    end if;

    if to_regclass('public.v2_research_submissions') is not null then
      delete from public.v2_research_submissions s
       using public.v2_research_queue_copy c
       where c.filled_crd and c.submission_id is not null
         and s.submission_id = c.submission_id
         and not exists (
           select 1 from public.v2_firm_registry_ids r where r.submission_id = s.submission_id
         );
      -- The shared copy submission (firm_id is null) if it has no remaining rows.
      select bot_key_id into v_bot from public.v2_bot_keys where bot_name = 'research_queue_copy';
      if v_bot is not null then
        delete from public.v2_research_submissions s
         where s.bot_key_id = v_bot
           and not exists (
             select 1 from public.v2_firm_registry_ids r where r.submission_id = s.submission_id
           );
        begin
          delete from public.v2_bot_keys where bot_key_id = v_bot;
        exception when others then
          raise notice 'research_queue_copy bot key left in place: %', SQLERRM;
        end;
      end if;
    end if;

    if to_regclass('public.firm_summary') is not null and v_ids is not null then
      perform public.refresh_firm_summary(v_ids);
    end if;

    drop table if exists public.v2_research_queue_copy;
  end if;
end
$undo$;

do $fn$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_bot_keys') is null
     or to_regclass('bots.ingest_keys') is null then
    raise notice 'v2 schema missing, skipped add_firm restore';
  else
    execute $body$
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

  IF fid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false,
      'slug', (SELECT slug FROM public.v2_firms WHERE firm_id = fid));
  END IF;

  slg := coalesce(public._slugify(nm), public._slugify(reg));
  IF slg IS NULL OR length(slg) > 200 THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', 'could not make a slug from name or registry_id');
  END IF;

  SELECT firm_id INTO fid FROM public.v2_firms WHERE slug = slg;
  IF fid IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false, 'slug', slg);
  END IF;

  BEGIN
    INSERT INTO public.v2_firms (slug, display_name, website_url, firm_status)
    VALUES (slg, nm, web, 'Active')
    RETURNING firm_id INTO fid;
  EXCEPTION WHEN unique_violation THEN
    SELECT firm_id INTO fid FROM public.v2_firms
     WHERE slug = slg
        OR (website_url_norm = public.v2_norm_url(web) AND NOT coalesce(archived, false))
     ORDER BY firm_id
     LIMIT 1;
    IF fid IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', left(SQLERRM, 300));
    END IF;
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', false,
      'slug', (SELECT slug FROM public.v2_firms WHERE firm_id = fid));
  END;

  RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'firm_id', fid, 'created', true, 'slug', slg);
END
$function$;
$body$;
    execute 'revoke all on function public.v2_research_add_firm(uuid, jsonb) from public, anon, authenticated';
    execute 'grant execute on function public.v2_research_add_firm(uuid, jsonb) to service_role';
  end if;

  drop function if exists public.v2_apply_research_queue_fields(bigint, text, bigint, text);
  drop function if exists public.research_queue_country_iso(text);
  drop function if exists public.research_queue_us_state(text);
  drop function if exists public.research_queue_city_clean(text);
end
$fn$;
