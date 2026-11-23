-- Repeats cleanup 2026-11-23: save-time check for legal cases.
-- A new bot item (submission_id set) that exactly repeats a live or waiting case on the same firm/person is refused
-- as a duplicate. v2_research_submit already turns unique_violation into "duplicate: ... send a correction instead".
-- Rows without submission_id (admin/merge writes), archived/L4 rows and nothing-found rows are not checked.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_legal_guard skipped';
    return;
  end if;
  execute $ci_body$
CREATE OR REPLACE FUNCTION public.v2_legal_repeat_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $f$
DECLARE v_id bigint;
BEGIN
  IF NEW.submission_id IS NULL OR NEW.firm_id IS NULL OR coalesce(NEW.archived,false) OR coalesce(NEW.nothing_found,false) THEN
    RETURN NEW;
  END IF;
  SELECT r.legal_item_id INTO v_id FROM public.v2_legal_items r
   WHERE r.firm_id = NEW.firm_id AND r.person_id IS NOT DISTINCT FROM NEW.person_id
     AND NOT r.archived AND NOT coalesce(r.nothing_found,false)
     AND (   (v2_repeat_norm(NEW.case_summary) IS NOT NULL AND v2_repeat_norm(r.case_summary) = v2_repeat_norm(NEW.case_summary))
          OR (    r.source_url_norm IS NOT DISTINCT FROM v2_norm_url(NEW.source_url)
              AND r.item_group IS NOT DISTINCT FROM NEW.item_group AND r.side IS NOT DISTINCT FROM NEW.side
              AND r.case_type IS NOT DISTINCT FROM NEW.case_type AND r.status IS NOT DISTINCT FROM NEW.status
              AND r.filed_year IS NOT DISTINCT FROM NEW.filed_year AND r.closed_year IS NOT DISTINCT FROM NEW.closed_year
              AND v2_repeat_norm(r.other_party) IS NOT DISTINCT FROM v2_repeat_norm(NEW.other_party)
              AND v2_repeat_norm(r.regulator_name) IS NOT DISTINCT FROM v2_repeat_norm(NEW.regulator_name)
              AND v2_repeat_norm(r.court) IS NOT DISTINCT FROM v2_repeat_norm(NEW.court)
              AND v2_repeat_norm(r.case_summary) IS NOT DISTINCT FROM v2_repeat_norm(NEW.case_summary)))
   ORDER BY r.legal_item_id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'unique_violation', CONSTRAINT = 'v2_legal_items_repeat_guard',
      MESSAGE = format('repeat of legal item %s on this firm', v_id);
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS v2_li_repeat_guard ON public.v2_legal_items;
CREATE TRIGGER v2_li_repeat_guard BEFORE INSERT ON public.v2_legal_items FOR EACH ROW EXECUTE FUNCTION public.v2_legal_repeat_guard();
$ci_body$;
end
$ci_wrap$;
