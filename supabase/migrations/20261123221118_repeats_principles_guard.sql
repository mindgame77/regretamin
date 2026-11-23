-- Repeats cleanup 2026-11-23: save-time check for investment principles. A new bot item (submission_id set) whose quote
-- matches a live or waiting principle on the same firm, credited to the same source (same name, the firm / "Firm",
-- or one name contains the other), is refused as a duplicate. The same words from a different named person still go in.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_principles_guard skipped';
    return;
  end if;
  execute $ci_body$
CREATE OR REPLACE FUNCTION public.v2_principles_repeat_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $f$
DECLARE v_id bigint; v_q text := v2_repeat_norm(NEW.quote);
        v_a text := coalesce(v2_repeat_norm(NEW.investor_name),''); v_t text := coalesce(v2_repeat_norm(NEW.investor_title),'');
BEGIN
  IF NEW.submission_id IS NULL OR NEW.firm_id IS NULL OR v_q IS NULL OR coalesce(NEW.archived,false) THEN
    RETURN NEW;
  END IF;
  SELECT r.id INTO v_id FROM public.v2_investor_principles r
   WHERE r.firm_id = NEW.firm_id AND NOT r.archived AND v2_repeat_norm(r.quote) = v_q
     AND (   coalesce(v2_repeat_norm(r.investor_name),'') = v_a
          OR v_a IN ('','firm') OR coalesce(v2_repeat_norm(r.investor_name),'') IN ('','firm')
          OR v_t = 'firm' OR coalesce(v2_repeat_norm(r.investor_title),'') = 'firm'
          OR (v_a <> '' AND coalesce(v2_repeat_norm(r.investor_name),'') <> ''
              AND (position(v_a in v2_repeat_norm(r.investor_name)) > 0 OR position(v2_repeat_norm(r.investor_name) in v_a) > 0)))
   ORDER BY r.id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'unique_violation', CONSTRAINT = 'v2_investor_principles_repeat_guard',
      MESSAGE = format('repeat of principle %s on this firm', v_id);
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS v2_ip_repeat_guard ON public.v2_investor_principles;
CREATE TRIGGER v2_ip_repeat_guard BEFORE INSERT ON public.v2_investor_principles FOR EACH ROW EXECUTE FUNCTION public.v2_principles_repeat_guard();
$ci_body$;
end
$ci_wrap$;
