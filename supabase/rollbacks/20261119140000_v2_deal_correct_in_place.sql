-- Rollback for 20261119140000_v2_deal_correct_in_place.sql
-- Restores bots.v2_apply_deal_change, bots.v2_undo_deal_change and public.v2_research_submit exactly as they
-- were live on 2026-11-19 before this migration (backed up from the live database).
-- Note: corrections applied in place while this migration was live keep their in-place receipts; the restored
-- undo function does not know 'in_place' receipts, so revert those (if needed) before rolling back.

do $rb$
begin
  if to_regprocedure('bots.v2_apply_deal_change(bigint)') is null then
    raise notice 'v2 tables missing, skipped';
    return;
  end if;
  execute $ddl$
CREATE OR REPLACE FUNCTION bots.v2_apply_deal_change(p_qid bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE q public.v2_checker_queue; oldrow jsonb; newrow jsonb; patch jsonb; cols text; receipt jsonb;
BEGIN
 SELECT * INTO q FROM public.v2_checker_queue WHERE queue_id=p_qid FOR UPDATE;
 IF NOT FOUND OR q.table_name <> 'v2_deals' OR q.kind <> 'changed-key-fact' OR q.archived OR q.status NOT IN ('open','passed') THEN RAISE EXCEPTION 'deal change queue unavailable'; END IF;
 IF q.new_value ? '_deal_receipt' THEN RETURN q.new_value->'_deal_receipt'; END IF;
 SELECT to_jsonb(d) INTO oldrow FROM public.v2_deals d WHERE deal_id=q.row_id AND firm_id=q.firm_id FOR UPDATE;
 IF oldrow IS NULL OR oldrow IS DISTINCT FROM q.old_value THEN RAISE EXCEPTION 'deal changed since submission; check current deal and resend'; END IF;
 IF NOT (oldrow->>'is_current')::boolean OR (oldrow->>'archived')::boolean THEN RAISE EXCEPTION 'deal is no longer current'; END IF;
 IF q.new_value->>'_deal_action'='remove' THEN
  UPDATE public.v2_deals SET shown=false WHERE deal_id=q.row_id RETURNING to_jsonb(v2_deals) INTO newrow;
  receipt := jsonb_build_object('action','remove','before',oldrow,'after',newrow,'deal_id',q.row_id,'active',true);
 ELSIF q.new_value->>'_deal_action'='correct' THEN
  patch := (oldrow - ARRAY['deal_id','row_id','source_url_norm','archived_url_norm','created_at']) || (q.new_value-'_deal_action') || jsonb_build_object('submission_id',q.submission_id,'is_current',true,'shown',true);
  patch := patch || jsonb_build_object('shown',nullif(patch->>'deal_date','') IS NOT NULL OR nullif(patch->>'round_amount','') IS NOT NULL);
  SELECT string_agg(format('%I',key),',') INTO cols FROM jsonb_object_keys(patch) key;
  EXECUTE format('INSERT INTO public.v2_deals AS d (%s) SELECT %s FROM jsonb_populate_record(NULL::public.v2_deals,$1) RETURNING to_jsonb(d)',cols,cols) INTO newrow USING patch;
  UPDATE public.v2_deals SET is_current=false,shown=false,archived=true,archive_reason=left('Replaced by deal '||(newrow->>'deal_id'),300) WHERE deal_id=q.row_id;
  receipt := jsonb_build_object('action','correct','before',oldrow,'after',(SELECT to_jsonb(d) FROM public.v2_deals d WHERE deal_id=q.row_id),'new',newrow,'deal_id',(newrow->>'deal_id')::bigint,'active',true);
 ELSE RAISE EXCEPTION 'unknown deal change action'; END IF;
 UPDATE public.v2_checker_queue SET new_value=new_value||jsonb_build_object('_deal_receipt',receipt) WHERE queue_id=p_qid;
 INSERT INTO public.v2_change_log(actor,firm_id,box,table_name,row_id,submission_id,old_value,new_value,result)
 VALUES('v2_deal_change',q.firm_id,'F12','v2_deals',(receipt->>'deal_id')::bigint,q.submission_id,oldrow,receipt,'Accepted');
 RETURN receipt;
END $function$
$ddl$;

  execute $ddl$
CREATE OR REPLACE FUNCTION bots.v2_undo_deal_change(p_qid bigint)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE q public.v2_checker_queue; r jsonb; cur jsonb; fresh jsonb;
BEGIN
 SELECT * INTO q FROM public.v2_checker_queue WHERE queue_id=p_qid FOR UPDATE;
 r:=q.new_value->'_deal_receipt';
 IF r IS NULL OR NOT coalesce((r->>'active')::boolean,false) THEN RETURN 'already'; END IF;
 SELECT to_jsonb(d) INTO cur FROM public.v2_deals d WHERE deal_id=q.row_id FOR UPDATE;
 IF cur IS DISTINCT FROM r->'after' THEN RETURN 'conflict'; END IF;
 IF r->>'action'='correct' THEN
  SELECT to_jsonb(d) INTO fresh FROM public.v2_deals d WHERE deal_id=(r->>'deal_id')::bigint FOR UPDATE;
  IF fresh IS DISTINCT FROM r->'new' THEN RETURN 'conflict'; END IF;
  UPDATE public.v2_deals SET is_current=false,shown=false,archived=true,archive_reason='Correction reverted' WHERE deal_id=(r->>'deal_id')::bigint;
 END IF;
 UPDATE public.v2_deals SET is_current=(r#>>'{before,is_current}')::boolean,shown=(r#>>'{before,shown}')::boolean,archived=(r#>>'{before,archived}')::boolean,archive_reason=r#>>'{before,archive_reason}' WHERE deal_id=q.row_id;
 UPDATE public.v2_checker_queue SET new_value=jsonb_set(new_value,'{_deal_receipt,active}','false') WHERE queue_id=p_qid;
 RETURN 'reverted';
END $function$
$ddl$;

  execute $ddl$
CREATE OR REPLACE FUNCTION public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys; bk public.v2_bot_keys; bot text; batch bigint;
  it jsonb; idx int := -1; firmkey text; firms text[] := '{}'; refused jsonb := '[]'; results jsonb := '[]';
  tbl text; box text; fact jsonb; p jsonb; k text; v jsonb; reason text; sid bigint; fid bigint; res jsonb;
  sec_id smallint; o_site text; empty_fill boolean; ft_id smallint;
  v_sector_word text; v_sub_count int;
  pkcol text; newid bigint; cols text; refs jsonb := '{}'; q_kind text; o jsonb; n jsonb; upd jsonb; diff boolean;
  rej_today int; firms_hour int; paused jsonb := '{}'; v_prej int; frz text; acc int := 0; rejn int := 0; held int := 0; v_skipped int := 0;
  src_tables text[] := ARRAY['v2_funds','v2_fund_assets','v2_startups','v2_startup_sectors','v2_deals','v2_people',
    'v2_person_firm_roles','v2_board_seats','v2_interviews','v2_legal_items','v2_sec_registration','v2_sec_fact_pills','v2_social_accounts',
    'v2_reviews','v2_firm_aum','v2_firm_contacts','v2_firm_registry_ids',
    'v2_investor_principles','v2_firm_stages','v2_firm_industries','v2_firm_types_firms','firm_fund_announcements','v2_firm_check_sizes','v2_firm_former_names'];
  firm_fields jsonb := '{"legal_name":"legal_name_source","founded_year":"founded_year_source","thesis_text":"thesis_source","hq_street":"hq_source","hq_suite":"hq_source","hq_city":"hq_source","hq_state":"hq_source","hq_postal":"hq_source","hq_country":"hq_source","website_url":null,"short_name":null}';
  blocked text[] := ARRAY['row_id','submission_id','archived','archive_reason','created_at','is_current','source_url_norm','archived_url_norm','link_dead','website_source','original_text'];
  src_keys text[] := ARRAY['source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url','nothing_found'];
  v_st_web text; v_st_raw text; v_st_host text; v_st_id bigint; v_st_name text; v_st_note text; v_st_match boolean := false; v_cname text; v_industry text;
  -- v2_deal_no_dup
  v_dup_id bigint; v_dup_note text; v_t public.v2_deals; v_fill jsonb; v_empty_ids bigint[];
  v_new_round text; v_new_date date; v_new_prec text; v_new_amt numeric; v_new_fa numeric; v_ccy text;
  v_site_reason text := 'website_url required: find this startup''s website or skip the startup and its deal';
  -- Hosted-platform domains are not a startup's own website. One list. The host or any subdomain of it is rejected.
  v_platform_hosts text[] := ARRAY['linktr.ee','medium.com','github.com','notion.site','wixsite.com','carrd.co','substack.com','linkedin.com','facebook.com','x.com','twitter.com','instagram.com'];
  -- dup_safe_submit: plain words for each "no duplicates" rule; a duplicate rejects only its own item
  dup_words jsonb := '{"v2_sa_current_uq":"this firm already has a current social account for this platform",
    "v2_aum_current_uq":"this firm already has a current AUM",
    "v2_fc_current_uq":"this firm already has a current contact",
    "v2_fri_current_uq":"this firm already has a current registry id of this type",
    "v2_fri_type_value_uq":"this registry id is already on file",
    "v2_sfp_current_uq":"this firm already has a current SEC fact with this label",
    "v2_secreg_current_uq":"this firm already has a current SEC registration",
    "v2_news_url_uq":"this firm already has this news link",
    "v2_firm_stages_firm_stage_uq":"this firm already has this stage",
    "v2_firm_check_sizes_firm_program_amount_uq":"this firm already has this check size",
    "v2_firm_industries_firm_text_uq":"this firm already has this industry",
    "v2_funds_fileno_uq":"this firm already has a fund with this SEC file number",
    "v2_startups_domain_uq":"a startup with this website domain already exists",
    "v2_firms_website_norm_uq":"another firm already has this website",
    "v2_firms_slug_key":"another firm already has this slug",
    "v2_investor_principles_firm_id_display_order_key":"this firm already has a principle in this display order",
    "firm_fund_announcements_firm_id_url_name_key":"this firm already has this fund announcement"}';
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','this key is not linked to a bot'); END IF;
  bot := ik.bot_id;
  SELECT * INTO bk FROM public.v2_bot_keys WHERE bot_name = bot;
  IF NOT FOUND OR bk.key_hash IS DISTINCT FROM ik.key_hash THEN
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  END IF;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok',false,'error',format('Key frozen: %s, %s', coalesce(bk.freeze_reason,'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')));
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN RETURN jsonb_build_object('ok',false,'error','items must be a non-empty array'); END IF;
  IF jsonb_array_length(p_items) > 500 THEN RETURN jsonb_build_object('ok',false,'error','max 500 items per batch'); END IF;
  batch := nextval('public.v2_batch_seq');

  BEGIN  -- whole batch; rolled back at the end when p_dry_run
  FOR it IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    BEGIN  -- per-item block
    idx := idx + 1; reason := NULL; sid := NULL; newid := NULL; q_kind := NULL; res := NULL;
    v_st_match := false; v_st_id := NULL; v_st_name := NULL; v_st_raw := NULL; v_st_host := NULL; v_cname := NULL;
    v_dup_id := NULL; v_dup_note := NULL; v_empty_ids := NULL; v_fill := NULL;
    IF jsonb_typeof(it) <> 'object' THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: item must be an object'); CONTINUE; END IF;
    firmkey := coalesce(it->>'firm_id', it->>'firm_ref');
    IF firmkey IS NULL THEN
      results := results || jsonb_build_object('index',idx,'status','Rejected: firm_id (existing firm) or firm_ref (new firm) required'); CONTINUE; END IF;
    IF NOT firmkey = ANY(firms) THEN
      IF cardinality(firms) >= 10 THEN
        refused := refused || jsonb_build_object('index',idx,'firm',firmkey,'status','Refused: batch over 10 firms; firms 11+ are refused, send them in the next batch (I1.5)'); CONTINUE; END IF;
      firms := firms || firmkey;
    END IF;
    -- gentle freeze: 100+ rejections today for one firm pauses only that firm for this bot
    IF NOT paused ? firmkey THEN
      SELECT count(*) INTO v_prej FROM public.v2_research_submissions
        WHERE bot_key_id = bk.bot_key_id AND status LIKE 'Rejected:%'
          AND status IS DISTINCT FROM ('Rejected: ' || v_site_reason)
          AND received_at >= date_trunc('day', now() AT TIME ZONE 'America/Los_Angeles') AT TIME ZONE 'America/Los_Angeles'
          AND coalesce(firm_id::text, payload->>'firm_ref') = firmkey;
      paused := paused || jsonb_build_object(firmkey, v_prej >= 100);
    END IF;
    IF (paused->>firmkey)::boolean THEN
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'status','Rejected: firm paused for today, too many rejections (100+ for this firm today); send other firms');
      CONTINUE;
    END IF;
    tbl := it->>'table'; box := it->>'box'; fact := coalesce(it->'fact','{}');
    fid := CASE WHEN (it->>'firm_id') ~ '^\d+$' THEN (it->>'firm_id')::bigint END;
    IF it->>'firm_id' IS NOT NULL AND fid IS NULL THEN reason := 'firm_id must be a number';
    ELSIF box IS NULL OR box !~ '^[A-Z]{1,3}[0-9]{1,3}[a-z]?$' THEN reason := 'box required (e.g. F12)';
    ELSIF tbl IS NULL OR NOT (tbl = ANY(src_tables) OR tbl = 'v2_firms') THEN reason := format('unknown table "%s" (P9)', coalesce(tbl,''));
    ELSIF jsonb_typeof(fact) <> 'object' THEN reason := 'fact must be an object';
    ELSIF fid IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.v2_firms WHERE firm_id = fid) THEN reason := format('firm_id %s not found', fid);
    END IF;
    -- source checks (R2, P1, P2, S1-S4)
    IF reason IS NULL THEN
      fact := fact || jsonb_build_object('source_owner', coalesce(fact->>'source_owner', bot));
      IF coalesce(fact->>'source_url','') = '' THEN reason := 'no source link (source_url)';
      ELSIF (fact->>'source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'source_url is a search/chat page; cite the page itself';
      ELSIF (fact->>'source_url') !~* '^(https?://)?(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'source_url is not a valid link';
      ELSIF coalesce(fact->>'source_level','') !~ '^[1-4]$' THEN reason := 'no source level (source_level must be 1, 2, 3 or 4)';
      ELSIF coalesce(fact->>'source_date','') !~ '^\d{4}-\d{2}-\d{2}$' THEN reason := 'no source date (source_date YYYY-MM-DD)';
      ELSIF coalesce(fact->>'source_type','') = '' THEN reason := 'no source type (source_type)';
      END IF;
      IF reason IS NULL THEN
        BEGIN IF (fact->>'source_date')::date > current_date THEN reason := 'source_date is in the future'; END IF;
        EXCEPTION WHEN others THEN reason := 'source_date is not a real date'; END;
      END IF;
    END IF;
    -- Nothing-found for legal, reviews, and interviews. Content fields are not required.
    -- The checks above still require an opened source_url, a source_level, a source_date, and a source_type.
    -- Legal nothing-found uses source_level 1, the only level that table allows.
    IF reason IS NULL
       AND tbl IN ('v2_legal_items', 'v2_reviews', 'v2_interviews', 'v2_person_firm_roles')
       AND (
         fact->'nothing_found' = 'true'::jsonb
         OR lower(btrim(coalesce(fact->>'nothing_found', ''))) IN ('true', 't', '1')
       ) THEN
      IF coalesce(it->>'note', fact->>'note', '') !~* 'search' THEN
        reason := 'nothing_found needs the searches in note';
      ELSIF tbl = 'v2_legal_items' AND fact->>'source_level' IS DISTINCT FROM '1' THEN
        reason := 'legal nothing_found needs source_level 1';
      ELSIF tbl = 'v2_person_firm_roles' AND (fact ? 'person_id' OR fact ? 'person_ref') THEN
        reason := 'founders nothing_found has no person: leave out person_id';
      ELSIF tbl = 'v2_person_firm_roles' THEN
        -- Founders nothing-found: a role row with no person, marked is_founder and nothing_found.
        fact := (fact - 'nothing_found' - 'note' - 'title' - 'kind') || jsonb_build_object('nothing_found', true, 'is_founder', true);
      ELSE
        fact := (fact - 'nothing_found' - 'note') || jsonb_build_object('nothing_found', true);
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;
    -- G5.2 (Alex 2026-11-04 12:40 PM PT): a review's reviewer_role / reviewer_company needs a valid reviewer_role_source_url
    IF reason IS NULL AND tbl = 'v2_reviews' AND (coalesce(btrim(fact->>'reviewer_role'),'') <> '' OR coalesce(btrim(fact->>'reviewer_company'),'') <> '') THEN
      IF coalesce(btrim(fact->>'reviewer_role_source_url'),'') = '' THEN reason := 'reviewer_role/reviewer_company sent without reviewer_role_source_url (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_role_source_url is a search/chat page; cite the page itself (G5.2)';
      ELSIF (fact->>'reviewer_role_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_role_source_url is not a valid link (G5.2)';
      END IF;
    END IF;
    -- G5.2.1 (Alex 2026-11-04 12:54 PM PT): a review_author that replaces the name on an existing review of the same quote/source
    -- (e.g. a username -> a real name) needs reviewer_name_source_url; any reviewer_name_source_url given must be a valid link
    IF reason IS NULL AND tbl = 'v2_reviews' THEN
      IF coalesce(btrim(fact->>'reviewer_name_source_url'),'') <> '' THEN
        IF (fact->>'reviewer_name_source_url') ~* '(google\.[a-z.]+/search|bing\.com/search|duckduckgo\.com/\?|grok\.com|x\.com/i/grok|chatgpt\.com|perplexity\.ai/search)' THEN reason := 'reviewer_name_source_url is a search/chat page; cite the page itself (G5.2.1)';
        ELSIF (fact->>'reviewer_name_source_url') !~* '^https?://(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$' THEN reason := 'reviewer_name_source_url is not a valid link (G5.2.1)';
        END IF;
      ELSIF coalesce(btrim(fact->>'review_author'),'') <> '' AND EXISTS (
        SELECT 1 FROM public.v2_reviews r WHERE r.firm_id = fid AND NOT r.archived
          AND coalesce(btrim(r.review_author),'') <> '' AND lower(btrim(r.review_author)) <> lower(btrim(fact->>'review_author'))
          AND (lower(rtrim(btrim(r.source_url),'/')) = lower(rtrim(btrim(fact->>'source_url'),'/')) OR btrim(r.quote) = btrim(fact->>'quote'))) THEN
        reason := 'review_author replaces the name on an existing review; send reviewer_name_source_url (the page that states the name) (G5.2.1)';
      END IF;
    END IF;
    -- Startup sectors: prefer a 45-name sub-industry (trimmed, case-insensitive).
    -- 1:1 old parent names (Bio -> Biotech, Security -> Cybersecurity, and any
    -- parent with only one sub) auto-convert. Ambiguous old parents and a bare
    -- sector_id are accepted with the parent in sector_id and industry_name left
    -- null. Only names that match nothing are rejected.
    IF reason IS NULL AND tbl = 'v2_startup_sectors' THEN
      v_industry := NULL;
      sec_id := NULL;
      v_sub_count := NULL;
      v_sector_word := nullif(btrim(coalesce(fact->>'sector', fact->>'industry_name', '')),'');
      IF v_sector_word IS NOT NULL THEN
        SELECT l.name, l.parent_sector_id INTO v_industry, sec_id
          FROM public.v2_industry_list l
         WHERE lower(l.name) = lower(v_sector_word);
        IF v_industry IS NULL THEN
          SELECT s.sector_id,
                 (SELECT count(*) FROM public.v2_industry_list i WHERE i.parent_sector_id = s.sector_id),
                 (SELECT i.name FROM public.v2_industry_list i WHERE i.parent_sector_id = s.sector_id ORDER BY i.sort, i.name LIMIT 1)
            INTO sec_id, v_sub_count, v_industry
            FROM public.v2_sector s
           WHERE lower(s.name) = lower(v_sector_word);
          IF sec_id IS NOT NULL AND v_sub_count IS DISTINCT FROM 1 THEN
            v_industry := NULL;
          END IF;
        END IF;
        IF sec_id IS NULL THEN
          reason := format('unknown sector "%s"; sector must be one of: %s',
            v_sector_word,
            (SELECT string_agg(name, ', ' ORDER BY sort) FROM public.v2_industry_list));
        ELSIF fact ? 'sector' AND fact ? 'industry_name'
          AND lower(btrim(fact->>'sector')) IS DISTINCT FROM lower(btrim(fact->>'industry_name')) THEN
          reason := 'sector and industry_name disagree';
        ELSIF fact ? 'sector_id' AND (fact->>'sector_id') IS DISTINCT FROM sec_id::text THEN
          reason := 'sector and sector_id disagree';
        ELSIF v_industry IS NOT NULL THEN
          fact := (fact - 'sector') || jsonb_build_object('sector_id', sec_id, 'industry_name', v_industry);
        ELSE
          fact := (fact - 'sector' - 'industry_name') || jsonb_build_object('sector_id', sec_id);
        END IF;
      ELSIF coalesce(fact->>'sector_id','') = '' THEN
        reason := 'sector is required and must be one of: ' ||
          (SELECT string_agg(name, ', ' ORDER BY sort) FROM public.v2_industry_list);
      ELSIF coalesce(fact->>'sector_id','') !~ '^\d+$' THEN
        reason := 'sector_id must be a number';
      ELSE
        SELECT s.sector_id INTO sec_id
          FROM public.v2_sector s
         WHERE s.sector_id = (fact->>'sector_id')::smallint;
        IF sec_id IS NULL THEN
          reason := format('unknown sector_id %s; sector must be one of: %s',
            fact->>'sector_id',
            (SELECT string_agg(name, ', ' ORDER BY sort) FROM public.v2_industry_list));
        ELSE
          fact := (fact - 'industry_name') || jsonb_build_object('sector_id', sec_id);
        END IF;
      END IF;
    END IF;

    IF reason IS NULL AND tbl = 'v2_firm_types_firms' AND fact ? 'firm_type' THEN
      SELECT t.firm_type_id INTO ft_id FROM public.v2_firm_type t WHERE lower(t.name) = lower(btrim(fact->>'firm_type')) ORDER BY t.firm_type_id LIMIT 1;
      IF ft_id IS NULL THEN reason := format('unknown firm type "%s"', fact->>'firm_type');
      ELSIF fact ? 'firm_type_id' AND (fact->>'firm_type_id') IS DISTINCT FROM ft_id::text THEN reason := 'firm_type and firm_type_id disagree';
      ELSE fact := (fact - 'firm_type') || jsonb_build_object('firm_type_id', ft_id); END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_investor_principles' THEN
      IF char_length(btrim(coalesce(fact->>'quote',''))) = 0 THEN reason := 'quote required (exact excerpt, 150 characters or less)';
      ELSIF char_length(btrim(fact->>'quote')) > 150 THEN reason := 'quote is over 150 characters (exact excerpt, 150 characters or less)';
      ELSIF NOT (fact ? 'display_order') AND fid IS NOT NULL THEN
        fact := fact || jsonb_build_object('display_order', coalesce((SELECT max(pr.display_order) FROM public.v2_investor_principles pr WHERE pr.firm_id = fid), 0) + 1);
      END IF;
      IF reason IS NULL AND nullif(btrim(fact->>'published_at'),'') IS NULL THEN
        fact := fact - 'published_at';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_stages' AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('read_on', fact->>'source_date');
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_industries' AND NOT (fact ? 'date_read') AND coalesce(fact->>'source_date','') <> '' THEN
      fact := fact || jsonb_build_object('date_read', fact->>'source_date');
    END IF;
    -- Firm industries must be one of the 45-name list. For the first day, known old
    -- values are auto-converted via v2_industry_alias (expires_at). After that they are rejected.
    IF reason IS NULL AND tbl = 'v2_firm_industries' THEN
      IF nullif(btrim(coalesce(fact->>'industry_text','')),'') IS NULL THEN
        reason := 'industry_text is required';
      ELSE
        v_industry := NULL;
        SELECT l.name INTO v_industry
          FROM public.v2_industry_list l
         WHERE lower(l.name) = lower(btrim(fact->>'industry_text'));
        IF v_industry IS NULL THEN
          SELECT a.new_name INTO v_industry
            FROM public.v2_industry_alias a
           WHERE a.old_value_lower = lower(btrim(fact->>'industry_text'))
             AND a.expires_at > now();
        END IF;
        IF v_industry IS NULL THEN
          reason := 'industry_text must be one of: ' ||
            (SELECT string_agg(name, ', ' ORDER BY sort) FROM public.v2_industry_list);
        ELSE
          fact := fact || jsonb_build_object('industry_text', v_industry);
        END IF;
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_firm_check_sizes' THEN
      -- Deals-style currency: accept amount_currency as an alias for currency.
      IF fact ? 'amount_currency' AND NOT (fact ? 'currency') THEN
        fact := fact || jsonb_build_object('currency', fact->>'amount_currency');
      END IF;
      fact := fact - 'amount_currency';
      IF fact ? 'currency' THEN
        fact := fact || jsonb_build_object('currency', upper(btrim(coalesce(fact->>'currency',''))));
        IF btrim(coalesce(fact->>'currency','')) = '' THEN
          fact := fact - 'currency';
        ELSIF fact->>'currency' !~ '^[A-Z]{3}$' THEN
          reason := 'check size currency must be a 3-letter code';
        END IF;
      END IF;
      IF reason IS NULL AND NOT (fact ? 'read_on') AND coalesce(fact->>'source_date','') <> '' THEN
        fact := fact || jsonb_build_object('read_on', fact->>'source_date');
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'amount_text','')),'') IS NULL THEN
        reason := 'check size amount_text is required (source excerpt, not shown)';
      END IF;
      IF reason IS NULL AND fact ? 'min_usd' AND fact->'min_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'min_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size min_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND fact ? 'max_usd' AND fact->'max_usd' <> 'null'::jsonb AND btrim(coalesce(fact->>'max_usd','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size max_usd must be a positive whole number of US dollars';
      END IF;
      IF reason IS NULL AND fact ? 'min_amount' AND fact->'min_amount' <> 'null'::jsonb AND btrim(coalesce(fact->>'min_amount','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size min_amount must be a positive whole number';
      END IF;
      IF reason IS NULL AND fact ? 'max_amount' AND fact->'max_amount' <> 'null'::jsonb AND btrim(coalesce(fact->>'max_amount','')) !~ '^[1-9][0-9]*$' THEN
        reason := 'check size max_amount must be a positive whole number';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_amount','')),'') IS NOT NULL AND nullif(btrim(coalesce(fact->>'max_amount','')),'') IS NOT NULL AND (btrim(fact->>'min_amount'))::numeric > (btrim(fact->>'max_amount'))::numeric THEN
        reason := 'check size min_amount is greater than max_amount';
      END IF;
      IF reason IS NULL AND (nullif(btrim(coalesce(fact->>'min_amount','')),'') IS NOT NULL OR nullif(btrim(coalesce(fact->>'max_amount','')),'') IS NOT NULL) AND nullif(btrim(coalesce(fact->>'currency','')),'') IS NULL THEN
        reason := 'check size currency is required with min_amount or max_amount';
      END IF;
      -- Fill min_usd/max_usd from original-currency amounts so existing USD columns stay populated.
      -- Provided min_usd/max_usd are left as sent (not rounded). Converted USD is rounded to 2 significant digits.
      -- USD rate is 1; other currencies use v2_fx_rates. Original min_amount/max_amount stay exact.
      IF reason IS NULL AND fact ? 'currency' THEN
        IF fact->>'currency' = 'USD' THEN
          IF nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'min_amount','')),'') IS NOT NULL THEN
            fact := fact || jsonb_build_object('min_usd', (btrim(fact->>'min_amount'))::bigint);
          END IF;
          IF nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_amount','')),'') IS NOT NULL THEN
            fact := fact || jsonb_build_object('max_usd', (btrim(fact->>'max_amount'))::bigint);
          END IF;
        ELSIF NOT EXISTS (SELECT 1 FROM public.v2_fx_rates r WHERE r.currency = fact->>'currency') THEN
          reason := 'no USD rate for currency '||(fact->>'currency')||' (update v2_fx_rates)';
        ELSE
          IF nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'min_amount','')),'') IS NOT NULL THEN
            fact := fact || jsonb_build_object('min_usd', (
              SELECT greatest(1, public.v2_usd_sig2((btrim(fact->>'min_amount'))::numeric * r.usd_rate))::bigint
              FROM public.v2_fx_rates r WHERE r.currency = fact->>'currency'));
          END IF;
          IF nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_amount','')),'') IS NOT NULL THEN
            fact := fact || jsonb_build_object('max_usd', (
              SELECT greatest(1, public.v2_usd_sig2((btrim(fact->>'max_amount'))::numeric * r.usd_rate))::bigint
              FROM public.v2_fx_rates r WHERE r.currency = fact->>'currency'));
          END IF;
        END IF;
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NULL THEN
        reason := 'check size needs min_usd or max_usd, or min_amount or max_amount with currency';
      END IF;
      IF reason IS NULL AND nullif(btrim(coalesce(fact->>'min_usd','')),'') IS NOT NULL AND nullif(btrim(coalesce(fact->>'max_usd','')),'') IS NOT NULL AND (btrim(fact->>'min_usd'))::numeric > (btrim(fact->>'max_usd'))::numeric THEN
        reason := 'check size min_usd is greater than max_usd';
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'firm_fund_announcements' THEN
      IF NOT (fact ? 'url') AND coalesce(fact->>'source_url','') <> '' THEN fact := fact || jsonb_build_object('url', fact->>'source_url'); END IF;
      IF NOT (fact ? 'retrieved_on') AND coalesce(fact->>'source_date','') <> '' THEN fact := fact || jsonb_build_object('retrieved_on', fact->>'source_date'); END IF;
    END IF;
    IF reason IS NULL THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key WHERE key = ANY(blocked) OR key LIKE '%\_norm';
      IF k IS NOT NULL THEN reason := 'field not allowed (set by the database): '||k; END IF;
    END IF;
    -- Deal changes use a strict field allowlist; action/reason are control fields, not table columns.
    IF reason IS NULL AND tbl='v2_deals' AND fact ? 'deal_id' THEN
      IF fid IS NULL THEN reason := 'deal change requires existing firm_id';
      ELSIF coalesce(fact->>'deal_id','') !~ '^[0-9]{1,18}$' THEN reason := 'deal_id must be a number';
      ELSIF coalesce(fact->>'action','correct') NOT IN ('correct','remove') THEN reason := 'deal action must be correct or remove';
      ELSIF fact->>'source_level'='4' THEN reason := 'deal change needs source_level 1-3';
      ELSE
        SELECT to_jsonb(d) INTO o FROM public.v2_deals d WHERE deal_id=(fact->>'deal_id')::bigint AND firm_id=fid FOR UPDATE;
        IF o IS NULL THEN reason := 'deal_id not found for this firm';
        ELSIF NOT (o->>'is_current')::boolean OR (o->>'archived')::boolean THEN reason := 'deal_id is not current; use the latest deal_id';
        ELSE
          SELECT string_agg(key,', ') INTO k FROM jsonb_object_keys(fact) key
           WHERE NOT (key=ANY(src_keys) OR key IN ('deal_id','action','reason','round','round_extension','deal_date','deal_date_precision','round_amount','firm_amount','amount_currency','amount_approximate','lead'));
          IF k IS NOT NULL THEN reason := 'deal change field not allowed: '||k;
          ELSIF coalesce(fact->>'action','correct')='remove' AND nullif(btrim(fact->>'reason'),'') IS NULL THEN reason := 'removal reason required';
          ELSIF coalesce(fact->>'action','correct')='remove' AND EXISTS(SELECT 1 FROM jsonb_object_keys(fact) key WHERE key IN ('round','round_extension','deal_date','deal_date_precision','round_amount','firm_amount','amount_currency','amount_approximate','lead')) THEN reason := 'remove sends no corrected fields';
          ELSIF coalesce(fact->>'action','correct')='correct' AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(fact) key WHERE key IN ('round','round_extension','deal_date','deal_date_precision','round_amount','firm_amount','amount_currency','amount_approximate','lead')) THEN reason := 'send at least one corrected deal field';
          END IF;
        END IF;
      END IF;
    END IF;
    IF reason IS NULL AND tbl <> 'v2_firms' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(fact) key
        WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name=key) AND NOT (tbl='v2_deals' AND fact ? 'deal_id' AND key IN ('action','reason'));
      IF k IS NOT NULL THEN reason := 'unknown field: '||k; END IF;
    END IF;
    -- resolve @refs from earlier items of this batch
    p := '{}';
    IF reason IS NULL THEN
      FOR k, v IN SELECT * FROM jsonb_each(fact) LOOP
        IF jsonb_typeof(v) = 'string' AND left(v#>>'{}',1) = '@' THEN
          IF refs ? substr(v#>>'{}',2) THEN p := p || jsonb_build_object(k, refs->substr(v#>>'{}',2));
          ELSE reason := format('ref %s not found in this batch (the item that makes it was rejected, held, or comes later)', v#>>'{}'); EXIT; END IF;
        ELSE p := p || jsonb_build_object(k, v); END IF;
      END LOOP;
      IF tbl <> 'v2_firms' AND p ? 'firm_id' = false AND EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema='public' AND c.table_name=tbl AND c.column_name='firm_id') THEN
        p := p || jsonb_build_object('firm_id', fid); END IF;
    END IF;

    INSERT INTO public.v2_research_submissions (batch_id, firm_id, bot_key_id, target_box, payload)
      VALUES (batch, fid, bk.bot_key_id, coalesce(box,'?'), jsonb_build_object('target_table',tbl,'fact',coalesce(it->'fact','{}'::jsonb),'firm_ref',it->>'firm_ref','ref',it->>'ref','origin',it->>'note','source_owner',coalesce(fact->>'source_owner',bot),'item_index',idx))
      RETURNING submission_id INTO sid;

    IF reason IS NULL AND tbl = 'v2_firms' THEN
      IF fid IS NULL THEN  -- only the publish step creates a firm (F1.3.1)
        reason := NULL; q_kind := 'new-firm';
        INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, new_value) VALUES (sid, NULL, 'new-firm', tbl, p);
        UPDATE public.v2_research_submissions SET status = 'Held: new firm waits for the Checker (F1.3.1)' WHERE submission_id = sid;
        INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result) VALUES (bot, NULL, box, tbl, sid, p, 'Blocked: held, new firm waits for the Checker');
        held := held + 1;
        results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: new firm waits for the Checker (F1.3.1)','checker_queued','new-firm');
        CONTINUE;
      END IF;
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR firm_fields ? key);
      IF k IS NOT NULL THEN reason := 'unknown firm field: '||k||' (allowed: '||(SELECT string_agg(x,', ') FROM jsonb_object_keys(firm_fields) x)||')'; END IF;
      IF reason IS NULL AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE firm_fields ? key) THEN reason := 'no firm field to set'; END IF;
      IF reason IS NULL THEN
        SELECT to_jsonb(f) INTO o FROM public.v2_firms f WHERE firm_id = fid;
        upd := '{}'; diff := false; empty_fill := false;
        FOR k, v IN SELECT * FROM jsonb_each(p) WHERE firm_fields ? key LOOP
          upd := upd || jsonb_build_object(k, v);
          IF firm_fields->>k IS NOT NULL THEN upd := upd || jsonb_build_object(firm_fields->>k, jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date')); END IF;
          IF o->k IS NOT NULL AND o->k <> 'null'::jsonb AND nullif(btrim(o->>k),'') IS NOT NULL AND (o->>k) IS DISTINCT FROM (v#>>'{}') THEN diff := true;
          ELSIF nullif(btrim(v#>>'{}'),'') IS NOT NULL AND (o->k IS NULL OR o->k = 'null'::jsonb OR nullif(btrim(o->>k),'') IS NULL) THEN empty_fill := true; END IF;
        END LOOP;
        IF diff THEN  -- changed key fact: never overwrite directly (P15)
         BEGIN  -- dup_safe_submit: this item's work is one subtransaction
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: changed key fact waits for the Checker (P15)' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result) VALUES (bot, fid, box, tbl, fid, sid, o, upd, 'Blocked: held, changed key fact waits for the Checker');
          PERFORM public.v2_auto_publish_apply_submission(sid);
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: changed key fact waits for the Checker (P15)','checker_queued','changed-key-fact');
          CONTINUE;
         EXCEPTION WHEN unique_violation THEN
          GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
          reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
         END;
        END IF;
        IF reason IS NULL AND empty_fill THEN
         BEGIN  -- dup_safe_submit
          INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
            VALUES (sid, fid, 'changed-key-fact', tbl, fid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd);
          UPDATE public.v2_research_submissions SET status = 'Held: empty firm field waits for the Checker' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd, 'Blocked: held, empty firm field waits for the Checker');
          PERFORM public.v2_auto_publish_apply_submission(sid);
          held := held + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty firm field waits for the Checker','checker_queued','changed-key-fact');
          CONTINUE;
         EXCEPTION WHEN unique_violation THEN
          GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
          reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
         END;
        END IF;
        IF reason IS NULL THEN
        BEGIN
          EXECUTE format('UPDATE public.v2_firms t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_firms, $1)), last_checked_date = current_date WHERE firm_id = $2 RETURNING to_jsonb(t)',
            (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x), (SELECT string_agg(format('%I',x),',') FROM jsonb_object_keys(upd) x)) INTO n USING upd, fid;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, fid, sid, (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), (SELECT jsonb_object_agg(x, n->x) FROM jsonb_object_keys(upd) x), 'Accepted');
          acc := acc + 1;
          results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',fid);
          CONTINUE;
        EXCEPTION
          WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
            reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
          WHEN others THEN reason := left(SQLERRM, 300); END;
        END IF;
      END IF;
    END IF;

    -- 015: sector row for a startup: max 2 per startup (11. startup_sectors), startup must exist
    IF reason IS NULL AND tbl = 'v2_startup_sectors' THEN
      IF (p->>'startup_id') !~ '^\d+$' OR NOT EXISTS (SELECT 1 FROM public.v2_startups WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) THEN
        reason := format('startup_id %s not found', coalesce(p->>'startup_id',''));
      ELSIF EXISTS (SELECT 1 FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND sector_id = (p->>'sector_id')::smallint) THEN
        -- Already stored: a quiet skip, not a rejection. Nothing is written and it does not count toward the gentle freeze.
        UPDATE public.v2_research_submissions SET status = 'Skipped: sector already set' WHERE submission_id = sid;
        v_skipped := v_skipped + 1;
        results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Skipped: sector already set');
        CONTINUE;
      ELSIF (SELECT count(*) FROM public.v2_startup_sectors WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived) >= 2 THEN
        reason := 'startup already has 2 sectors (max 2)';
      END IF;
    END IF;
    -- 015: website fill for an EXISTING startup (fact has startup_id): fills an empty website_url only; never a new startup, never overwrites
    IF reason IS NULL AND tbl = 'v2_startups' AND p ? 'startup_id' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('startup_id','website_url'));
      IF k IS NOT NULL THEN reason := 'existing startup: only website_url can be filled (not allowed: '||k||')';
      ELSIF coalesce(p->>'website_url','') = '' THEN reason := 'existing startup: website_url required';
      ELSIF (p->>'startup_id') !~ '^\d+$' THEN reason := 'startup_id must be a number';
      ELSE
        SELECT to_jsonb(s) INTO o FROM public.v2_startups s WHERE startup_id = (p->>'startup_id')::bigint AND NOT archived;
        IF o IS NULL THEN reason := format('startup_id %s not found', p->>'startup_id');
        ELSE
          o_site := nullif(o->>'website_url','');
          IF o_site IS NOT NULL THEN
            IF lower(regexp_replace(regexp_replace(o_site,'^(https?://)?(www\.)?',''),'/+$','')) = lower(regexp_replace(regexp_replace(p->>'website_url','^(https?://)?(www\.)?',''),'/+$','')) THEN
              UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
              INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
                VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',o_site), jsonb_build_object('website_url',p->>'website_url'), 'Accepted');
              acc := acc + 1;
              results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'startup_id')::bigint,'note','website already set to the same site; nothing changed');
              CONTINUE;
            END IF;
            reason := 'startup already has a different website_url; never overwritten (P15)';
          ELSIF (p->>'source_level') = '4' THEN reason := 'website fill needs source_level 1-3';
          ELSE
           BEGIN  -- dup_safe_submit
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
              VALUES (sid, fid, 'changed-key-fact', tbl, (o->>'startup_id')::bigint,
                jsonb_build_object('website_url', NULL),
                jsonb_build_object('website_url', p->>'website_url',
                  'website_source', jsonb_build_object('url',p->>'source_url','level',(p->>'source_level')::int,'date',p->>'source_date','type',p->>'source_type','owner',p->>'source_owner','submission_id',sid)));
            UPDATE public.v2_research_submissions SET status = 'Held: empty startup website waits for the Checker' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, (o->>'startup_id')::bigint, sid, jsonb_build_object('website_url',NULL), jsonb_build_object('website_url',p->>'website_url'), 'Blocked: held, empty startup website waits for the Checker');
            PERFORM public.v2_auto_publish_apply_submission(sid);
            held := held + 1;
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', (o->>'startup_id')::bigint); END IF;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty startup website waits for the Checker','table',tbl,'row_id',(o->>'startup_id')::bigint,'checker_queued','changed-key-fact');
            CONTINUE;
           EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
            reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
           END;
          END IF;
        END IF;
      END IF;
    END IF;

    -- Fill linkedin_url (and x_url if sent) on an EXISTING person (fact has person_id):
    -- fills a blank URL only; never a new person, never overwrites.
    IF reason IS NULL AND tbl = 'v2_people' AND p ? 'person_id' THEN
      SELECT string_agg(key, ', ') INTO k FROM jsonb_object_keys(p) key
        WHERE NOT (key = ANY(src_keys) OR key IN ('person_id','linkedin_url','x_url'));
      IF k IS NOT NULL THEN reason := 'existing person: only linkedin_url or x_url can be filled (not allowed: '||k||')';
      ELSIF coalesce(nullif(btrim(p->>'linkedin_url'),''), nullif(btrim(p->>'x_url'),'')) IS NULL THEN
        reason := 'existing person: linkedin_url or x_url required';
      ELSIF (p->>'person_id') !~ '^\d+$' THEN reason := 'person_id must be a number';
      ELSIF NOT EXISTS (
        SELECT 1 FROM public.v2_person_firm_roles r
         WHERE r.person_id = (p->>'person_id')::bigint AND r.firm_id = fid AND NOT r.archived
      ) THEN reason := format('person_id %s is not on this firm', p->>'person_id');
      ELSE
        SELECT to_jsonb(pe) INTO o FROM public.v2_people pe WHERE person_id = (p->>'person_id')::bigint AND NOT archived;
        IF o IS NULL THEN reason := format('person_id %s not found', p->>'person_id');
        ELSE
          upd := '{}'::jsonb;
          IF nullif(btrim(p->>'linkedin_url'),'') IS NOT NULL THEN
            IF nullif(btrim(o->>'linkedin_url'),'') IS NOT NULL THEN
              IF public.v2_norm_url(p->>'linkedin_url') IS DISTINCT FROM public.v2_norm_url(o->>'linkedin_url') THEN
                reason := 'person already has a different linkedin_url; never overwritten';
              END IF;
            ELSE
              upd := upd || jsonb_build_object('linkedin_url', p->>'linkedin_url');
            END IF;
          END IF;
          IF reason IS NULL AND nullif(btrim(p->>'x_url'),'') IS NOT NULL THEN
            IF nullif(btrim(o->>'x_url'),'') IS NOT NULL THEN
              IF public.v2_norm_url(p->>'x_url') IS DISTINCT FROM public.v2_norm_url(o->>'x_url') THEN
                reason := 'person already has a different x_url; never overwritten';
              END IF;
            ELSE
              upd := upd || jsonb_build_object('x_url', p->>'x_url');
            END IF;
          END IF;
          IF reason IS NULL AND upd = '{}'::jsonb THEN
            UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, (o->>'person_id')::bigint, sid,
                jsonb_strip_nulls(jsonb_build_object('linkedin_url',o->>'linkedin_url','x_url',o->>'x_url')),
                jsonb_strip_nulls(jsonb_build_object('linkedin_url',p->>'linkedin_url','x_url',p->>'x_url')),
                'Accepted');
            acc := acc + 1;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',(o->>'person_id')::bigint,'note','url already set to the same value; nothing changed');
            CONTINUE;
          ELSIF reason IS NULL AND (p->>'source_level') = '4' THEN
            reason := 'person url fill needs source_level 1-3';
          ELSIF reason IS NULL THEN
           BEGIN  -- dup_safe_submit
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, old_value, new_value)
              VALUES (sid, fid, 'changed-key-fact', tbl, (o->>'person_id')::bigint,
                (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x),
                upd);
            UPDATE public.v2_research_submissions SET status = 'Held: empty person url waits for the Checker' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, (o->>'person_id')::bigint, sid,
                (SELECT jsonb_object_agg(x, o->x) FROM jsonb_object_keys(upd) x), upd,
                'Blocked: held, empty person url waits for the Checker');
            PERFORM public.v2_auto_publish_apply_submission(sid);
            held := held + 1;
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', (o->>'person_id')::bigint); END IF;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Held: empty person url waits for the Checker','table',tbl,'row_id',(o->>'person_id')::bigint,'checker_queued','changed-key-fact');
            CONTINUE;
           EXCEPTION WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
            reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
           END;
          END IF;
        END IF;
      END IF;
    END IF;

    -- New startup (no startup_id): the website is the only identity. A matching name does not matter.
    -- v2_startups.domain is generated as lower(split_part(regexp_replace(regexp_replace(website_url, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1)).
    -- The lookup uses that expression. A port, query, fragment, or trailing dot left on that host is stripped for the comparison only.
    IF reason IS NULL AND tbl = 'v2_startups' AND NOT (p ? 'startup_id') THEN
      v_st_web := btrim(coalesce(p->>'website_url', ''));
      IF v_st_web IS DISTINCT FROM coalesce(p->>'website_url', '') THEN
        p := p || jsonb_build_object('website_url', v_st_web);
      END IF;
      v_st_raw := lower(split_part(regexp_replace(regexp_replace(v_st_web, '^https?://', '', 'i'), '^www\.', '', 'i'), '/', 1));
      v_st_host := regexp_replace(regexp_replace(split_part(split_part(v_st_raw, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '');
      IF v_st_host = '' OR EXISTS (
        SELECT 1 FROM unnest(v_platform_hosts) AS h(host)
        WHERE v_st_host = h.host OR right(v_st_host, length(h.host) + 1) = '.' || h.host
      ) THEN
        reason := v_site_reason;
      ELSE
        SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
        FROM public.v2_startups s
        WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
        ORDER BY s.startup_id
        LIMIT 1;
        IF v_st_id IS NULL THEN
          SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
          FROM public.v2_startups s
          WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> ''
            AND regexp_replace(regexp_replace(split_part(split_part(s.domain, '?', 1), '#', 1), ':[0-9]+$', ''), '\.+$', '') = v_st_host
          ORDER BY s.startup_id
          LIMIT 1;
        END IF;
        IF v_st_id IS NOT NULL THEN v_st_match := true; END IF;
      END IF;
    END IF;

    IF reason IS NULL AND tbl = 'v2_deals' AND btrim(coalesce(p->>'deal_date','')) ~ '^\d{4}$' THEN
      -- bare year stored as January 1 with the existing precision. The page shows the year only.
      p := p || jsonb_build_object('deal_date', btrim(p->>'deal_date') || '-01-01', 'deal_date_precision', 'year');
    END IF;
    -- v2_deal_no_dup (Alex OK 2026-11-19): a new deal never makes a second live row for the same round.
    --   a) same firm (merge chain followed) + startup + stage (names normalized), dates within about a year or one missing
    --      -> merged into the existing deal, empty fields only.
    --   b) else, when the firm + startup has no deal with a known stage and has empty deals (no stage, no amount)
    --      -> the new deal fills the oldest empty one; any other empty ones are flagged for review.
    --   Nothing new to fill -> Skipped, naming the existing deal_id.
    IF reason IS NULL AND tbl = 'v2_deals' AND p ? 'round' THEN
      p := p || jsonb_build_object('round', public.v2_deal_round_norm(p->>'round'));
    END IF;
    IF reason IS NULL AND tbl = 'v2_deals' AND NOT (p ? 'deal_id') AND fid IS NOT NULL
       AND coalesce(p->>'startup_id', '') ~ '^[0-9]{1,18}$' THEN
      PERFORM pg_advisory_xact_lock(hashtextextended('v2_deal_dup:' || public.v2_firm_root(fid) || ':' || (p->>'startup_id'), 0));
      v_new_round := p->>'round';
      v_new_prec := nullif(p->>'deal_date_precision', '');
      v_new_date := CASE WHEN coalesce(p->>'deal_date', '') ~ '^\d{4}-\d{2}-\d{2}$' THEN (p->>'deal_date')::date END;
      v_new_amt := CASE WHEN coalesce(p->>'round_amount', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p->>'round_amount')::numeric END;
      v_new_fa := CASE WHEN coalesce(p->>'firm_amount', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p->>'firm_amount')::numeric END;
      v_ccy := nullif(upper(btrim(coalesce(p->>'amount_currency', ''))), '');
      IF v_new_round IS NOT NULL THEN
        v_dup_id := public.v2_deal_same_round(fid, (p->>'startup_id')::bigint, v_new_round, p->>'round_extension',
                                              v_new_date, v_new_prec, v_new_amt);
        IF v_dup_id IS NOT NULL THEN v_dup_note := format('same %s round already saved as deal %s', v_new_round, v_dup_id); END IF;
      END IF;
      IF v_dup_id IS NULL AND NOT EXISTS (
           SELECT 1 FROM public.v2_deals d
            WHERE d.firm_id = ANY(ARRAY(SELECT public.v2_firm_family(fid))) AND d.startup_id = (p->>'startup_id')::bigint
              AND NOT d.archived AND d.round IS NOT NULL) THEN
        SELECT array_agg(d.deal_id ORDER BY d.is_current DESC, d.deal_id) INTO v_empty_ids
          FROM public.v2_deals d
         WHERE d.firm_id = ANY(ARRAY(SELECT public.v2_firm_family(fid))) AND d.startup_id = (p->>'startup_id')::bigint
           AND NOT d.archived AND d.round IS NULL AND d.round_amount IS NULL AND d.firm_amount IS NULL
           AND NOT public.v2_deal_dates_conflict(d.deal_date, d.deal_date_precision, v_new_date, v_new_prec);
        IF cardinality(v_empty_ids) > 0 THEN
          v_dup_id := v_empty_ids[1];
          v_dup_note := format('filled empty deal %s (no stage, no amount)', v_dup_id);
        END IF;
      END IF;
      IF v_dup_id IS NOT NULL THEN
        SELECT * INTO v_t FROM public.v2_deals WHERE deal_id = v_dup_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM public.v2_checker_queue q
                    WHERE q.row_id = v_t.deal_id AND q.table_name = 'v2_deals' AND q.new_value->>'_deal_action' = 'remove'
                      AND q.new_value#>>'{_deal_receipt,active}' = 'true') THEN
          reason := format('duplicate: this deal is already saved as deal_id %s and was removed; do not save it again', v_dup_id);
        ELSIF NOT v_t.is_current THEN
          reason := format('duplicate: this deal is already saved as deal_id %s and waits for the Checker; do not send it again', v_dup_id);
        ELSIF v_t.firm_id <> fid THEN
          reason := format('duplicate: this deal is already saved as deal_id %s under firm_id %s (the firm this one was merged into)', v_dup_id, v_t.firm_id);
        ELSE
          -- fill empty fields only; never overwrite a value the deal already has
          v_fill := '{}';
          IF v_t.round IS NULL AND v_new_round IS NOT NULL THEN
            v_fill := v_fill || jsonb_build_object('round', v_new_round);
          END IF;
          IF v_t.round_extension IS NULL AND nullif(btrim(coalesce(p->>'round_extension', '')), '') IS NOT NULL
             AND (v_t.round IS NULL OR v_t.round = v_new_round) THEN
            v_fill := v_fill || jsonb_build_object('round_extension', p->>'round_extension');
          END IF;
          IF v_new_date IS NOT NULL AND v_new_prec IS NOT NULL AND (
               v_t.deal_date IS NULL
               OR (v_t.deal_date_precision = 'year' AND v_new_prec IN ('year+month', 'full date')
                   AND extract(year FROM v_t.deal_date) = extract(year FROM v_new_date))
               OR (v_t.deal_date_precision = 'year+month' AND v_new_prec = 'full date'
                   AND date_trunc('month', v_t.deal_date) = date_trunc('month', v_new_date))) THEN
            v_fill := v_fill || jsonb_build_object('deal_date', v_new_date, 'deal_date_precision', v_new_prec);
          END IF;
          IF v_t.round_amount IS NULL AND v_new_amt IS NOT NULL AND v_ccy IS NOT NULL
             AND (v_t.amount_currency IS NULL OR v_t.amount_currency = v_ccy)
             AND (v_t.firm_amount IS NULL OR v_t.firm_amount <= v_new_amt) THEN
            v_fill := v_fill || jsonb_build_object('round_amount', v_new_amt, 'amount_currency', v_ccy);
            IF p ? 'amount_approximate' THEN v_fill := v_fill || jsonb_build_object('amount_approximate', p->'amount_approximate'); END IF;
          END IF;
          IF v_t.firm_amount IS NULL AND v_new_fa IS NOT NULL AND v_ccy IS NOT NULL
             AND coalesce(v_t.amount_currency, v_ccy) = v_ccy
             AND v_new_fa <= coalesce(v_t.round_amount, (v_fill->>'round_amount')::numeric, v_new_fa) THEN
            v_fill := v_fill || jsonb_build_object('firm_amount', v_new_fa, 'amount_currency', v_ccy);
          END IF;
          IF v_t.lead IS NULL AND p->>'lead' = 'yes' THEN
            v_fill := v_fill || jsonb_build_object('lead', 'yes');
          END IF;
          IF v_fill <> '{}' AND (p->>'source_level') = '4' THEN
            v_fill := '{}';  -- a level 4 source cannot change a live deal
            v_dup_note := v_dup_note || '; level 4 source, nothing filled';
          END IF;
          -- Existing source values stay unchanged. Fill a wholly absent source only.
          -- Every newly filled field is attributed to this submission separately (v2_deal_fill_sources).
          IF v_fill <> '{}' AND nullif(btrim(v_t.source_url), '') IS NULL THEN
            v_fill := v_fill || (SELECT coalesce(jsonb_object_agg(key, value), '{}') FROM jsonb_each(p) WHERE key = ANY(src_keys) AND key <> 'nothing_found');
          END IF;
          IF cardinality(v_empty_ids) > 1 THEN
            INSERT INTO public.v2_deal_review_flags (deal_id, related_deal_id, reason, submission_id)
              SELECT x, v_dup_id, 'leftover empty deal', sid FROM unnest(v_empty_ids[2:]) AS x
              ON CONFLICT DO NOTHING;
            v_dup_note := v_dup_note || format('; %s other empty deal(s) flagged for review', cardinality(v_empty_ids) - 1);
          END IF;
          IF v_fill = '{}' THEN
            UPDATE public.v2_research_submissions SET status = format('Skipped: already saved as deal %s; nothing new to fill', v_dup_id) WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, v_dup_id, sid, to_jsonb(v_t), p, format('Blocked: duplicate of deal %s, nothing new to fill', v_dup_id));
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', v_dup_id); END IF;
            v_skipped := v_skipped + 1;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status',format('Skipped: already saved as deal %s; nothing new to fill', v_dup_id),
              'table',tbl,'existing_deal_id',v_dup_id,'note',v_dup_note);
            CONTINUE;
          END IF;
          -- One deal number: fill the existing deal in place and keep its deal_id.
          BEGIN
            SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(v_fill) key;
            EXECUTE format('UPDATE public.v2_deals d SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.v2_deals, $1)) WHERE d.deal_id = $2',
                           cols, cols) USING v_fill, v_dup_id;
            UPDATE public.v2_deals SET shown = (deal_date IS NOT NULL OR round_amount IS NOT NULL)
             WHERE deal_id = v_dup_id AND is_current AND NOT archived
             RETURNING to_jsonb(v2_deals) INTO res;
            INSERT INTO public.v2_deal_fill_sources (deal_id, submission_id, fields, source)
              VALUES (v_dup_id, sid,
                      to_jsonb(ARRAY(SELECT key FROM jsonb_object_keys(v_fill) key WHERE NOT key = ANY(src_keys) ORDER BY key)),
                      (SELECT coalesce(jsonb_object_agg(key, value), '{}') FROM jsonb_each(fact) WHERE key = ANY(src_keys)));
            UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
            INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
              VALUES (bot, fid, box, tbl, v_dup_id, sid,
                      (SELECT coalesce(jsonb_object_agg(key, to_jsonb(v_t)->key), '{}') FROM jsonb_object_keys(v_fill) key),
                      v_fill, 'Accepted');
            IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', v_dup_id); END IF;
            acc := acc + 1;
            results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,
              'deal_id',v_dup_id,'filled_deal_id',v_dup_id,
              'filled_fields',to_jsonb(ARRAY(SELECT key FROM jsonb_object_keys(v_fill) key WHERE NOT key = ANY(src_keys) ORDER BY key)),
              'live',coalesce((res->>'shown')::boolean,false),'note',v_dup_note);
            CONTINUE;
          EXCEPTION WHEN others THEN reason := left(SQLERRM, 300);
          END;
        END IF;
      END IF;
    END IF;
    IF reason IS NULL AND tbl='v2_deals' AND p ? 'deal_id' THEN
      BEGIN
        -- Validate the merged record against all existing table constraints in a subtransaction.
        -- This test insert is always rolled back; only the publish step writes the new version.
        n := (o - ARRAY['deal_id','row_id','source_url_norm','archived_url_norm','created_at']) || (p-ARRAY['deal_id','action','reason']) || jsonb_build_object('submission_id',sid);
        IF coalesce(p->>'action','correct')='correct' THEN
          BEGIN
            SELECT string_agg(format('%I',key),',') INTO cols FROM jsonb_object_keys(n) key;
            EXECUTE format('INSERT INTO public.v2_deals (%s) SELECT %s FROM jsonb_populate_record(NULL::public.v2_deals,$1)',cols,cols) USING n;
            RAISE EXCEPTION USING ERRCODE='ZX001',MESSAGE='validation rollback';
          EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
          END;
        END IF;
        INSERT INTO public.v2_checker_queue(submission_id,firm_id,kind,table_name,row_id,old_value,new_value)
        VALUES(sid,fid,'changed-key-fact',tbl,(p->>'deal_id')::bigint,o,
          (p-ARRAY['deal_id','action','reason'])||jsonb_build_object('_deal_action',coalesce(p->>'action','correct')));
        UPDATE public.v2_research_submissions SET status='Accepted' WHERE submission_id=sid;
        PERFORM public.v2_auto_publish_apply_submission(sid);
        SELECT new_value->'_deal_receipt' INTO res FROM public.v2_checker_queue WHERE submission_id=sid;
        acc:=acc+1;
        results:=results||jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'deal_id',coalesce((res->>'deal_id')::bigint,(p->>'deal_id')::bigint),'replaces_deal_id',CASE WHEN coalesce(p->>'action','correct')='correct' THEN (p->>'deal_id')::bigint END,'checker_queued','changed-key-fact','live',coalesce((res->>'active')::boolean,false));
        CONTINUE;
      EXCEPTION WHEN others THEN reason:=left(SQLERRM,300);
      END;
    END IF;
    -- one current contact per firm (v2_fc_current_uq): reject a second contact instead of failing the whole call
    IF reason IS NULL AND tbl = 'v2_firm_contacts' AND fid IS NOT NULL AND EXISTS (SELECT 1 FROM public.v2_firm_contacts WHERE firm_id = fid AND is_current) THEN
      reason := 'firm already has a current contact; send email, phone and other contact fields together in one contact item';
    END IF;
    IF reason IS NULL AND NOT v_st_match THEN
      IF (p->>'source_level') = '4' THEN p := p || '{"archived":true,"archive_reason":"L4 kept archived (R2)"}'; END IF;
      p := p || jsonb_build_object('submission_id', sid);
      SELECT string_agg(format('%I', key), ',') INTO cols FROM jsonb_object_keys(p) key;
      BEGIN  -- dup_safe_submit: insert + hide + auto-publish of this item are one subtransaction; a duplicate undoes only this item
        BEGIN
          EXECUTE format('INSERT INTO public.%I AS t (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING to_jsonb(t)', tbl, cols, cols, tbl) INTO res USING p;
        EXCEPTION
          WHEN unique_violation THEN
            GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME;
            IF tbl = 'v2_startups' AND NOT (p ? 'startup_id') AND (v_cname = 'v2_startups_domain_uq' OR position('v2_startups_domain_uq' in SQLERRM) > 0) THEN
              SELECT s.startup_id, s.startup_name INTO v_st_id, v_st_name
              FROM public.v2_startups s
              WHERE NOT s.archived AND s.domain IS NOT NULL AND s.domain <> '' AND s.domain = v_st_raw
              ORDER BY s.startup_id
              LIMIT 1;
              IF v_st_id IS NULL THEN
                reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
              ELSE
                v_st_match := true;
              END IF;
            ELSE
              v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
              reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
            END IF;
          WHEN others THEN reason := left(SQLERRM, 300);
        END;
        IF reason IS NULL AND NOT v_st_match THEN
          pkcol := CASE tbl WHEN 'v2_funds' THEN 'fund_id' WHEN 'v2_startups' THEN 'startup_id' WHEN 'v2_people' THEN 'person_id'
                            WHEN 'v2_deals' THEN 'deal_id' WHEN 'v2_legal_items' THEN 'legal_item_id' WHEN 'v2_investor_principles' THEN 'id' WHEN 'v2_firm_stages' THEN 'id' WHEN 'v2_firm_industries' THEN 'id' WHEN 'firm_fund_announcements' THEN 'id' WHEN 'v2_firm_check_sizes' THEN 'id' ELSE 'row_id' END;
          newid := (res->>pkcol)::bigint;
          -- 011: new rows stay hidden until the Checker passes them (v2_publish_queue_item sets is_current/shown)
          IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=tbl AND column_name='is_current') THEN
            EXECUTE format('UPDATE public.%I SET is_current = false WHERE submission_id = $1', tbl) USING sid;
          END IF;
          IF tbl = 'v2_deals' THEN UPDATE public.v2_deals SET shown = false WHERE submission_id = sid; END IF;
          UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
          INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
            VALUES (bot, fid, box, tbl, newid, sid, NULL, res, 'Accepted');
          -- name-only rows go to the Checker (glossary 30, C4.2)
          IF NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p) key WHERE NOT (key = ANY(src_keys) OR key IN ('firm_id','submission_id','archived','archive_reason') OR key LIKE '%\_name')) THEN
            q_kind := 'name-only';
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'name-only', tbl, newid, res);
          ELSE  -- 011: every accepted item goes live only after the Checker passes it (Checker-first, R4.1; covers 010 LP rows too)
            q_kind := 'accepted-item';
            INSERT INTO public.v2_checker_queue (submission_id, firm_id, kind, table_name, row_id, new_value) VALUES (sid, fid, 'accepted-item', tbl, newid, res);
          END IF;
          -- Auto-publish, when on for this firm, shows the row now. The queue stays open. Off is a no-op.
          PERFORM public.v2_auto_publish_apply_submission(sid);
          IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', newid); END IF;
          acc := acc + 1;
          results := results || jsonb_strip_nulls(jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',newid,'checker_queued',q_kind,
            'note',CASE WHEN (p->>'source_level')='4' THEN 'L4: kept archived (R2)' END));
          CONTINUE;
        END IF;
      EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_cname = CONSTRAINT_NAME; v_cname := coalesce(nullif(v_cname,''), substring(SQLERRM from 'constraint "([^"]+)"'));
        reason := format('duplicate: %s (constraint %s); send a correction instead of a new item', coalesce(dup_words->>v_cname, 'this item already exists'), coalesce(nullif(v_cname,''), 'unknown'));
      END;
    END IF;

    IF v_st_match THEN
      v_st_note := format('matched existing startup %s by website (submitted "%s", existing "%s")', v_st_id, coalesce(nullif(btrim(p->>'startup_name'), ''), '(none)'), coalesce(nullif(btrim(v_st_name), ''), '(none)'));
      UPDATE public.v2_research_submissions SET status = 'Accepted' WHERE submission_id = sid;
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
        VALUES (bot, fid, box, tbl, v_st_id, sid,
          jsonb_build_object('startup_id', v_st_id, 'startup_name', v_st_name),
          jsonb_build_object('startup_name', p->>'startup_name', 'website_url', p->>'website_url'),
          'Accepted');
      IF it->>'ref' IS NOT NULL THEN refs := refs || jsonb_build_object(it->>'ref', v_st_id); END IF;
      acc := acc + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Accepted','table',tbl,'row_id',v_st_id,'matched_startup_id',v_st_id,'note',v_st_note);
      CONTINUE;
    END IF;

    IF reason IS NOT NULL THEN
      UPDATE public.v2_research_submissions SET status = 'Rejected: '||reason WHERE submission_id = sid;
      INSERT INTO public.v2_rejected_rows (payload, target_table, error_message, source_owner, submission_id, status)
        VALUES (coalesce(it->'fact','{}'::jsonb) || jsonb_build_object('_item', it - 'fact'), coalesce(tbl,'?'), reason, left(coalesce(fact->>'source_owner',bot),200), sid, 'new');
      INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, submission_id, new_value, result)
        VALUES (bot, fid, coalesce(box,'?'), coalesce(tbl,'?'), sid, it, 'Rejected: '||reason);
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'submission_id',sid,'status','Rejected: '||reason);
      CONTINUE;
    END IF;
    EXCEPTION WHEN others THEN  -- per-item safety net: undo only this item, report the real reason
      reason := left(SQLERRM, 300);
      INSERT INTO public.v2_rejected_rows (payload, target_table, error_message, source_owner, status)
        VALUES (coalesce(it->'fact','{}'::jsonb) || jsonb_build_object('_item', it - 'fact'), coalesce(tbl,'?'), reason, bot, 'new');
      rejn := rejn + 1;
      results := results || jsonb_build_object('index',idx,'status','Rejected: '||reason);
    END;
  END LOOP;

  -- freeze rules (I2.7)
  SELECT count(DISTINCT coalesce(firm_id::text, payload->>'firm_ref')) INTO firms_hour FROM public.v2_research_submissions
    WHERE bot_key_id = bk.bot_key_id AND received_at > now() - interval '1 hour';
  frz := CASE WHEN firms_hour > 200 THEN format('%s firms in the last hour', firms_hour) END;
  IF frz IS NOT NULL AND NOT p_dry_run THEN
    UPDATE public.v2_bot_keys SET frozen = true, freeze_date = now(), freeze_reason = frz,
      freeze_count_7d = CASE WHEN freeze_date > now() - interval '7 days' THEN coalesce(freeze_count_7d,0) + 1 ELSE 1 END
      WHERE bot_key_id = bk.bot_key_id;
    INSERT INTO public.v2_change_log (actor, box, table_name, row_id, new_value, result)
      VALUES ('v2_research_submit', 'I2', 'v2_bot_keys', bk.bot_key_id, jsonb_build_object('bot',bot,'frozen',true,'reason',frz), 'Blocked: Key frozen: '||frz);
  END IF;

  IF p_dry_run THEN RAISE EXCEPTION 'v2_dry_run_rollback'; END IF;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'v2_dry_run_rollback' THEN RAISE; END IF;
  END;

  RETURN jsonb_strip_nulls(jsonb_build_object('ok', true, 'bot_id', bot, 'dry_run', p_dry_run, 'batch_id', CASE WHEN NOT p_dry_run THEN batch END,
    'accepted', acc, 'rejected', rejn, 'held', held, 'skipped', CASE WHEN v_skipped > 0 THEN v_skipped END, 'refused', jsonb_array_length(refused), 'firms', cardinality(firms),
    'results', results, 'refused_items', CASE WHEN jsonb_array_length(refused) > 0 THEN refused END,
    'key_frozen', CASE WHEN frz IS NOT NULL AND NOT p_dry_run THEN format('Key frozen: %s, %s', frz, to_char(now() AT TIME ZONE 'America/Los_Angeles','YYYY-MM-DD HH24:MI "PT"')) END,
    'would_freeze', CASE WHEN frz IS NOT NULL AND p_dry_run THEN frz END));
END $function$
$ddl$;

end
$rb$;
