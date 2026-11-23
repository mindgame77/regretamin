-- Repeats cleanup 2026-11-23: save-time check for funds. A new bot item (submission_id set) naming a fund this firm
-- already has (live or waiting) is refused as a duplicate when it adds nothing new: no SEC number or the same one,
-- no amount or the same amount, no close date or the same date. An item that brings new SEC data still goes through.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_funds_guard skipped';
    return;
  end if;
  execute $ci_body$
CREATE OR REPLACE FUNCTION public.v2_funds_repeat_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $f$
DECLARE v_id bigint; v_n text := v2_repeat_norm(NEW.fund_name);
BEGIN
  IF NEW.submission_id IS NULL OR NEW.firm_id IS NULL OR v_n IS NULL OR coalesce(NEW.archived,false) OR coalesce(NEW.nothing_found,false) THEN
    RETURN NEW;
  END IF;
  SELECT r.fund_id INTO v_id FROM public.v2_funds r
   WHERE r.firm_id = NEW.firm_id AND NOT r.archived AND NOT coalesce(r.nothing_found,false) AND v2_repeat_norm(r.fund_name) = v_n
     AND (NEW.sec_file_number IS NULL OR r.sec_file_number = NEW.sec_file_number)
     AND (NEW.amount_raised IS NULL OR r.amount_raised = NEW.amount_raised)
     AND (NEW.closed_on IS NULL OR r.closed_on = NEW.closed_on)
   ORDER BY r.fund_id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'unique_violation', CONSTRAINT = 'v2_funds_repeat_guard',
      MESSAGE = format('repeat of fund %s on this firm', v_id);
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS v2_funds_repeat_guard ON public.v2_funds;
CREATE TRIGGER v2_funds_repeat_guard BEFORE INSERT ON public.v2_funds FOR EACH ROW EXECUTE FUNCTION public.v2_funds_repeat_guard();
$ci_body$;
end
$ci_wrap$;
