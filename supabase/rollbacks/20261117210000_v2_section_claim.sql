-- Undo 20261117210000_v2_section_claim.
-- Drops the section holds, the claim and done functions, the order index, and the nothing-found content rules.
-- Restores the previous v2_research_submit check. Does not touch v2_research_claim, v2_research_done, or v2_research_assignments.
-- Does not rewrite bot keys. Nothing-found rows that omit a required content column must be removed before the columns can be required again.
-- Firm rows and real legal, review, and video rows stay.
do $mig$
declare
  v_def text;
  v_old text;
  v_new text;
  v_next text;
  v_reviews int;
  v_videos int;
  v_legal int;
begin
  if to_regclass('public.v2_reviews') is not null then
    execute 'select count(*) from public.v2_reviews where quote is null or review_source_name is null' into v_reviews;
    if v_reviews > 0 then
      raise exception 'v2_reviews has % nothing-found rows with no quote or source name. Remove those rows, then run this rollback again.', v_reviews;
    end if;
  end if;
  if to_regclass('public.v2_interviews') is not null then
    execute 'select count(*) from public.v2_interviews where interview_url is null' into v_videos;
    if v_videos > 0 then
      raise exception 'v2_interviews has % nothing-found rows with no interview_url. Remove those rows, then run this rollback again.', v_videos;
    end if;
  end if;
  if to_regclass('public.v2_legal_items') is not null then
    execute 'select count(*) from public.v2_legal_items where item_group is null' into v_legal;
    if v_legal > 0 then
      raise exception 'v2_legal_items has % nothing-found rows with no item_group. Remove those rows, then run this rollback again.', v_legal;
    end if;
  end if;

  if to_regprocedure('public.v2_research_submit(uuid,jsonb,boolean)') is not null then
    select pg_get_functiondef('public.v2_research_submit(uuid,jsonb,boolean)'::regprocedure) into v_def;
    v_old := $old$    -- Nothing-found for legal, reviews, and interviews. Content fields are not required.
    -- The checks above still require an opened source_url, a source_level, a source_date, and a source_type.
    -- Legal nothing-found uses source_level 1, the only level that table allows.
    IF reason IS NULL
       AND tbl IN ('v2_legal_items', 'v2_reviews', 'v2_interviews')
       AND (
         fact->'nothing_found' = 'true'::jsonb
         OR lower(btrim(coalesce(fact->>'nothing_found', ''))) IN ('true', 't', '1')
       ) THEN
      IF coalesce(it->>'note', fact->>'note', '') !~* 'search' THEN
        reason := 'nothing_found needs the searches in note';
      ELSIF tbl = 'v2_legal_items' AND fact->>'source_level' IS DISTINCT FROM '1' THEN
        reason := 'legal nothing_found needs source_level 1';
      ELSE
        fact := (fact - 'nothing_found' - 'note') || jsonb_build_object('nothing_found', true);
      END IF;
    END IF;
    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;$old$;
    v_new := $new$    IF reason IS NULL AND tbl = 'v2_sec_fact_pills' AND lower(btrim(coalesce(fact->>'fact_label',''))) IN ('staff','investment staff') THEN
      reason := 'Staff and Investment staff are not accepted';
    END IF;$new$;
    if position('nothing_found needs the searches in note' in v_def) = 0 then
      raise notice 'v2_research_submit nothing_found patch already absent';
    elsif position(v_old in v_def) = 0 then
      raise exception 'v2_research_submit: nothing_found undo anchor missing';
    else
      v_next := replace(v_def, v_old, v_new);
      if v_next = v_def or position('nothing_found needs the searches in note' in v_next) > 0 then
        raise exception 'v2_research_submit: nothing_found undo did not apply';
      end if;
      execute v_next;
    end if;
  end if;

  if to_regclass('public.v2_reviews') is not null then
    execute 'alter table public.v2_reviews drop constraint if exists v2_reviews_found_content_ck';
    execute 'alter table public.v2_reviews alter column quote set not null';
    execute 'alter table public.v2_reviews alter column review_source_name set not null';
  end if;
  if to_regclass('public.v2_interviews') is not null then
    execute 'alter table public.v2_interviews drop constraint if exists v2_interviews_found_content_ck';
    execute 'alter table public.v2_interviews alter column interview_url set not null';
  end if;
  if to_regclass('public.v2_legal_items') is not null then
    execute 'alter table public.v2_legal_items drop constraint if exists v2_legal_items_found_content_ck';
    execute 'alter table public.v2_legal_items alter column item_group set not null';
  end if;

  execute 'drop function if exists public.v2_section_claim(uuid, text)';
  execute 'drop function if exists public.v2_section_done(uuid, text, bigint)';
  execute 'drop index if exists public.firm_summary_listed_deals_idx';
  execute 'drop index if exists public.v2_section_holds_bot_open_idx';
  execute 'drop index if exists public.v2_legal_items_firm_current_idx';
  execute 'drop index if exists public.v2_reviews_firm_current_idx';
  execute 'drop index if exists public.v2_interviews_firm_current_idx';
  execute 'drop table if exists public.v2_section_holds';
end
$mig$;
