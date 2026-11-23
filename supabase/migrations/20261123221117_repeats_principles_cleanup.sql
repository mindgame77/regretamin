-- Repeats cleanup 2026-11-23, part 5: investment principles. Same firm + same quote (letters/digits, any case) credited
-- to the same source (same name, the firm itself / "Firm", or one name contains the other) = one principle.
-- Keeps a copy with a real name (earliest first), fills a missing summary / date on it, archives the rest (never deletes).
-- The same words credited to two different named people are left alone (borderline).
-- Backup: repeats_20261123. Undo: /home/box/regretamin-repeats-20261123/undo/undo_principles.sql

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_principles_cleanup skipped';
    return;
  end if;
  execute $ci_body$
CREATE SCHEMA IF NOT EXISTS repeats_20261123;
CREATE OR REPLACE FUNCTION public.v2_repeat_norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$ SELECT nullif(lower(regexp_replace(coalesce(t,''), '[^[:alnum:]]+', '', 'g')), '') $f$;
CREATE TABLE IF NOT EXISTS repeats_20261123.principles_map (drop_id bigint PRIMARY KEY, keep_id bigint NOT NULL, firm_id bigint NOT NULL);
INSERT INTO repeats_20261123.principles_map (drop_id, keep_id, firm_id)
WITH b AS (
  SELECT p.*, v2_repeat_norm(p.quote) nq, coalesce(v2_repeat_norm(p.investor_name),'') na, coalesce(v2_repeat_norm(p.investor_title),'') nt,
    ((coalesce(v2_repeat_norm(p.investor_name),'firm') <> 'firm')::int * 8 + (p.published_at IS NOT NULL)::int * 2 + (nullif(btrim(p.summary),'') IS NOT NULL)::int) score
  FROM public.v2_investor_principles p
  WHERE p.is_current AND NOT p.archived AND v2_repeat_norm(p.quote) IS NOT NULL),
grp AS (SELECT firm_id, nq FROM b GROUP BY 1,2 HAVING count(*) > 1),
bad AS (  -- same words credited to two different named people: borderline, left alone
  SELECT DISTINCT x.firm_id, x.nq FROM b x JOIN b y ON y.firm_id = x.firm_id AND y.nq = x.nq AND y.id <> x.id
  WHERE NOT (x.na = y.na OR x.na IN ('','firm') OR y.na IN ('','firm') OR x.nt = 'firm' OR y.nt = 'firm'
             OR (x.na <> '' AND y.na <> '' AND (position(x.na in y.na) > 0 OR position(y.na in x.na) > 0)))),
ranked AS (
  SELECT b.*, first_value(b.id) OVER (PARTITION BY b.firm_id, b.nq ORDER BY b.score DESC, b.id ASC) keep_id
  FROM b JOIN grp USING (firm_id, nq) WHERE NOT EXISTS (SELECT 1 FROM bad WHERE bad.firm_id = b.firm_id AND bad.nq = b.nq))
SELECT id AS drop_id, keep_id, firm_id FROM ranked WHERE id <> keep_id
ON CONFLICT (drop_id) DO NOTHING;
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_investor_principles AS SELECT * FROM public.v2_investor_principles WHERE false;
INSERT INTO repeats_20261123.v2_investor_principles SELECT p.* FROM public.v2_investor_principles p
  WHERE p.id IN (SELECT drop_id FROM repeats_20261123.principles_map UNION SELECT keep_id FROM repeats_20261123.principles_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_investor_principles b WHERE b.id = p.id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_checker_queue AS SELECT * FROM public.v2_checker_queue WHERE false;
INSERT INTO repeats_20261123.v2_checker_queue SELECT q.* FROM public.v2_checker_queue q
  JOIN repeats_20261123.principles_map m ON q.table_name = 'v2_investor_principles' AND q.row_id = m.drop_id
  WHERE NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_checker_queue b WHERE b.queue_id = q.queue_id);
-- fill blanks on the kept row only
UPDATE public.v2_investor_principles k SET
  summary = coalesce(nullif(btrim(k.summary),''), d.summary), published_at = coalesce(k.published_at, d.published_at)
FROM (SELECT m.keep_id,
        (array_agg(p.summary ORDER BY p.id) FILTER (WHERE nullif(btrim(p.summary),'') IS NOT NULL))[1] summary,
        (array_agg(p.published_at ORDER BY p.id) FILTER (WHERE p.published_at IS NOT NULL))[1] published_at
      FROM repeats_20261123.principles_map m JOIN public.v2_investor_principles p ON p.id = m.drop_id GROUP BY m.keep_id) d
WHERE k.id = d.keep_id
  AND (nullif(btrim(k.summary),'') IS NULL AND d.summary IS NOT NULL OR k.published_at IS NULL AND d.published_at IS NOT NULL);
UPDATE public.v2_investor_principles d SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: repeat of principle ' || m.keep_id
FROM repeats_20261123.principles_map m WHERE d.id = m.drop_id AND NOT d.archived;
UPDATE public.v2_checker_queue q SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: row archived as repeat'
FROM repeats_20261123.principles_map m WHERE q.table_name = 'v2_investor_principles' AND q.row_id = m.drop_id AND q.status = 'open' AND NOT q.archived;
INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, new_value, result)
SELECT 'repeats-cleanup-20261123', m.firm_id, '', 'v2_investor_principles', m.drop_id,
  jsonb_build_object('note','repeat archived (backup schema repeats_20261123)','kept_row',m.keep_id), 'Accepted'
FROM repeats_20261123.principles_map m;
$ci_body$;
end
$ci_wrap$;
