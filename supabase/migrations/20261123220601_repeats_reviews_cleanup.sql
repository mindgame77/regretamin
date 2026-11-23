-- Repeats cleanup 2026-11-23, part 2: reviews. Same firm + same quote (letters/digits, any case) + same person credited
-- (same name, or one name contains the other) = one review. Keeps the most complete copy, archives the rest (never deletes).
-- Groups where the same quote is credited to different people are left alone (borderline).
-- Backup: schema repeats_20261123. Undo: /home/box/regretamin-repeats-20261123/undo/undo_reviews.sql

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_reviews_cleanup skipped';
    return;
  end if;
  execute $ci_body$
CREATE SCHEMA IF NOT EXISTS repeats_20261123;
CREATE OR REPLACE FUNCTION public.v2_repeat_norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$ SELECT nullif(lower(regexp_replace(coalesce(t,''), '[^[:alnum:]]+', '', 'g')), '') $f$;
CREATE TABLE IF NOT EXISTS repeats_20261123.reviews_map (drop_id bigint PRIMARY KEY, keep_id bigint NOT NULL, firm_id bigint NOT NULL);
INSERT INTO repeats_20261123.reviews_map (drop_id, keep_id, firm_id)
WITH b AS (
  SELECT r.*, v2_repeat_norm(r.quote) nq, coalesce(v2_repeat_norm(r.review_author),'') na,
    ((r.review_author IS NOT NULL)::int + (r.review_year IS NOT NULL)::int + (r.reviewer_role IS NOT NULL)::int + (r.reviewer_company IS NOT NULL)::int
     + (r.summary IS NOT NULL)::int + (r.source_date IS NOT NULL)::int + (r.reviewer_role_source_url IS NOT NULL)::int + (r.archived_url IS NOT NULL)::int) score
  FROM public.v2_reviews r
  WHERE r.is_current AND NOT r.archived AND NOT coalesce(r.nothing_found,false) AND v2_repeat_norm(r.quote) IS NOT NULL),
grp AS (SELECT firm_id, nq FROM b GROUP BY 1,2 HAVING count(*) > 1),
bad AS (  -- groups where two rows credit different people: borderline, left alone
  SELECT DISTINCT x.firm_id, x.nq FROM b x JOIN b y ON y.firm_id = x.firm_id AND y.nq = x.nq AND y.row_id <> x.row_id
  WHERE NOT (x.na = y.na OR (x.na <> '' AND y.na <> '' AND (position(x.na in y.na) > 0 OR position(y.na in x.na) > 0)))),
ranked AS (
  SELECT b.*, first_value(b.row_id) OVER (PARTITION BY b.firm_id, b.nq ORDER BY b.score DESC, b.source_level ASC NULLS LAST, b.row_id ASC) keep_id
  FROM b JOIN grp USING (firm_id, nq) WHERE NOT EXISTS (SELECT 1 FROM bad WHERE bad.firm_id = b.firm_id AND bad.nq = b.nq))
SELECT row_id AS drop_id, keep_id, firm_id FROM ranked WHERE row_id <> keep_id
ON CONFLICT (drop_id) DO NOTHING;
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_reviews AS SELECT * FROM public.v2_reviews WHERE false;
INSERT INTO repeats_20261123.v2_reviews SELECT r.* FROM public.v2_reviews r
  WHERE r.row_id IN (SELECT drop_id FROM repeats_20261123.reviews_map UNION SELECT keep_id FROM repeats_20261123.reviews_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_reviews b WHERE b.row_id = r.row_id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_checker_queue AS SELECT * FROM public.v2_checker_queue WHERE false;
INSERT INTO repeats_20261123.v2_checker_queue SELECT q.* FROM public.v2_checker_queue q
  JOIN repeats_20261123.reviews_map m ON q.table_name = 'v2_reviews' AND q.row_id = m.drop_id
  WHERE NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_checker_queue b WHERE b.queue_id = q.queue_id);
-- fill blanks on the kept row only: year, and role together with its source link
UPDATE public.v2_reviews k SET review_year = d.review_year
FROM (SELECT DISTINCT ON (m.keep_id) m.keep_id, r.review_year FROM repeats_20261123.reviews_map m JOIN public.v2_reviews r ON r.row_id = m.drop_id
      WHERE r.review_year IS NOT NULL ORDER BY m.keep_id, r.row_id) d
WHERE k.row_id = d.keep_id AND k.review_year IS NULL;
UPDATE public.v2_reviews k SET reviewer_role = d.reviewer_role, reviewer_role_source_url = d.reviewer_role_source_url
FROM (SELECT DISTINCT ON (m.keep_id) m.keep_id, r.reviewer_role, r.reviewer_role_source_url FROM repeats_20261123.reviews_map m JOIN public.v2_reviews r ON r.row_id = m.drop_id
      WHERE r.reviewer_role IS NOT NULL AND r.reviewer_role_source_url IS NOT NULL ORDER BY m.keep_id, r.row_id) d
WHERE k.row_id = d.keep_id AND k.reviewer_role IS NULL AND k.reviewer_role_source_url IS NULL;
UPDATE public.v2_reviews d SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: repeat of review ' || m.keep_id
FROM repeats_20261123.reviews_map m WHERE d.row_id = m.drop_id AND NOT d.archived;
UPDATE public.v2_checker_queue q SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: row archived as repeat'
FROM repeats_20261123.reviews_map m WHERE q.table_name = 'v2_reviews' AND q.row_id = m.drop_id AND q.status = 'open' AND NOT q.archived;
INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, new_value, result)
SELECT 'repeats-cleanup-20261123', m.firm_id, '', 'v2_reviews', m.drop_id,
  jsonb_build_object('note','repeat archived (backup schema repeats_20261123)','kept_row',m.keep_id), 'Accepted'
FROM repeats_20261123.reviews_map m;
$ci_body$;
end
$ci_wrap$;
