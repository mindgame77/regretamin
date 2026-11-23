-- Repeats cleanup 2026-11-23: save-time check for videos / interviews. A new bot item (submission_id set) for a video
-- this firm already has (live or waiting, same YouTube id or same normalized link) is refused as a duplicate.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_interviews_guard skipped';
    return;
  end if;
  execute $ci_body$
CREATE OR REPLACE FUNCTION public.v2_interviews_repeat_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'public', 'pg_temp' AS $f$
DECLARE v_id bigint; v_k text := v2_video_key(NEW.interview_url);
BEGIN
  IF NEW.submission_id IS NULL OR NEW.firm_id IS NULL OR v_k IS NULL OR coalesce(NEW.archived,false) OR coalesce(NEW.nothing_found,false) THEN
    RETURN NEW;
  END IF;
  SELECT r.row_id INTO v_id FROM public.v2_interviews r
   WHERE r.firm_id = NEW.firm_id AND NOT r.archived AND NOT coalesce(r.nothing_found,false) AND v2_video_key(r.interview_url) = v_k
   ORDER BY r.row_id LIMIT 1;
  IF v_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'unique_violation', CONSTRAINT = 'v2_interviews_repeat_guard',
      MESSAGE = format('repeat of video %s on this firm', v_id);
  END IF;
  RETURN NEW;
END $f$;
DROP TRIGGER IF EXISTS v2_iv_repeat_guard ON public.v2_interviews;
CREATE TRIGGER v2_iv_repeat_guard BEFORE INSERT ON public.v2_interviews FOR EACH ROW EXECUTE FUNCTION public.v2_interviews_repeat_guard();
$ci_body$;
end
$ci_wrap$;
