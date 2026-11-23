-- Repeats cleanup 2026-11-23, part 3: funds. Same firm + same fund name (letters/digits, any case) = one fund, unless the
-- copies carry two different SEC file numbers (borderline, left alone). Keeps the copy the page uses most (close date,
-- amount, SEC number), fills a missing SEC number / amount on it, archives the rest (never deletes).
-- Fund asset rows of an archived copy move to the kept fund; an asset row that exactly repeats one already on the kept
-- fund (same date and amount) is archived. Backup: repeats_20261123. Undo: /home/box/regretamin-repeats-20261123/undo/undo_funds.sql

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_funds_cleanup skipped';
    return;
  end if;
  execute $ci_body$
CREATE SCHEMA IF NOT EXISTS repeats_20261123;
CREATE OR REPLACE FUNCTION public.v2_repeat_norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$ SELECT nullif(lower(regexp_replace(coalesce(t,''), '[^[:alnum:]]+', '', 'g')), '') $f$;
CREATE TABLE IF NOT EXISTS repeats_20261123.funds_map (drop_id bigint PRIMARY KEY, keep_id bigint NOT NULL, firm_id bigint NOT NULL);
INSERT INTO repeats_20261123.funds_map (drop_id, keep_id, firm_id)
WITH b AS (
  SELECT f.*, v2_repeat_norm(f.fund_name) nn,
    ((f.closed_on IS NOT NULL)::int * 8 + (f.amount_raised IS NOT NULL)::int * 4 + (f.sec_file_number IS NOT NULL)::int * 2 + (f.fund_status IS NOT NULL)::int) score
  FROM public.v2_funds f
  WHERE f.is_current AND NOT f.archived AND NOT coalesce(f.nothing_found,false) AND v2_repeat_norm(f.fund_name) IS NOT NULL),
grp AS (SELECT firm_id, nn FROM b GROUP BY 1,2 HAVING count(*) > 1),
bad AS (  -- two different SEC file numbers under one name: borderline, left alone
  SELECT firm_id, nn FROM b GROUP BY 1,2 HAVING count(DISTINCT sec_file_number) > 1),
ranked AS (
  SELECT b.*, first_value(b.fund_id) OVER (PARTITION BY b.firm_id, b.nn ORDER BY b.score DESC, b.source_level ASC NULLS LAST, b.fund_id ASC) keep_id
  FROM b JOIN grp USING (firm_id, nn) WHERE NOT EXISTS (SELECT 1 FROM bad WHERE bad.firm_id = b.firm_id AND bad.nn = b.nn))
SELECT fund_id AS drop_id, keep_id, firm_id FROM ranked WHERE fund_id <> keep_id
ON CONFLICT (drop_id) DO NOTHING;
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_funds AS SELECT * FROM public.v2_funds WHERE false;
INSERT INTO repeats_20261123.v2_funds SELECT f.* FROM public.v2_funds f
  WHERE f.fund_id IN (SELECT drop_id FROM repeats_20261123.funds_map UNION SELECT keep_id FROM repeats_20261123.funds_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_funds b WHERE b.fund_id = f.fund_id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_fund_assets AS SELECT * FROM public.v2_fund_assets WHERE false;
INSERT INTO repeats_20261123.v2_fund_assets SELECT a.* FROM public.v2_fund_assets a
  WHERE a.fund_id IN (SELECT drop_id FROM repeats_20261123.funds_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_fund_assets b WHERE b.row_id = a.row_id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_checker_queue AS SELECT * FROM public.v2_checker_queue WHERE false;
INSERT INTO repeats_20261123.v2_checker_queue SELECT q.* FROM public.v2_checker_queue q
  JOIN repeats_20261123.funds_map m ON q.table_name = 'v2_funds' AND q.row_id = m.drop_id
  WHERE NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_checker_queue b WHERE b.queue_id = q.queue_id);

-- 1. archive the extra copies (first, so the kept row can take over their SEC number under v2_funds_fileno_uq)
UPDATE public.v2_funds d SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: repeat of fund ' || m.keep_id
FROM repeats_20261123.funds_map m WHERE d.fund_id = m.drop_id AND NOT d.archived;
-- 2. fill blanks on the kept row only
UPDATE public.v2_funds k SET sec_file_number = d.sec_file_number
FROM (SELECT DISTINCT ON (m.keep_id) m.keep_id, f.sec_file_number FROM repeats_20261123.funds_map m JOIN public.v2_funds f ON f.fund_id = m.drop_id
      WHERE f.sec_file_number IS NOT NULL ORDER BY m.keep_id, f.fund_id) d
WHERE k.fund_id = d.keep_id AND k.sec_file_number IS NULL
  AND NOT EXISTS (SELECT 1 FROM public.v2_funds o WHERE o.firm_id = k.firm_id AND o.sec_file_number = d.sec_file_number AND NOT o.archived);
UPDATE public.v2_funds k SET amount_raised = d.amount_raised, amount_currency = d.amount_currency, amount_source_type = d.amount_source_type
FROM (SELECT DISTINCT ON (m.keep_id) m.keep_id, f.amount_raised, f.amount_currency, f.amount_source_type FROM repeats_20261123.funds_map m JOIN public.v2_funds f ON f.fund_id = m.drop_id
      WHERE f.amount_raised IS NOT NULL ORDER BY m.keep_id, f.fund_id) d
WHERE k.fund_id = d.keep_id AND k.amount_raised IS NULL;
-- 3. fund assets: an exact repeat already on the kept fund is archived, the rest move to the kept fund
UPDATE public.v2_fund_assets a SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: repeat of fund asset ' || k.row_id
FROM repeats_20261123.funds_map m, public.v2_fund_assets k
WHERE a.fund_id = m.drop_id AND NOT a.archived AND k.fund_id = m.keep_id AND NOT k.archived
  AND k.as_of_date IS NOT DISTINCT FROM a.as_of_date AND k.gross_assets IS NOT DISTINCT FROM a.gross_assets;
UPDATE public.v2_fund_assets a SET fund_id = m.keep_id
FROM repeats_20261123.funds_map m WHERE a.fund_id = m.drop_id AND NOT a.archived;
UPDATE public.v2_checker_queue q SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: row archived as repeat'
FROM repeats_20261123.funds_map m WHERE q.table_name = 'v2_funds' AND q.row_id = m.drop_id AND q.status = 'open' AND NOT q.archived;
INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, new_value, result)
SELECT 'repeats-cleanup-20261123', m.firm_id, '', 'v2_funds', m.drop_id,
  jsonb_build_object('note','repeat archived (backup schema repeats_20261123)','kept_row',m.keep_id), 'Accepted'
FROM repeats_20261123.funds_map m;
$ci_body$;
end
$ci_wrap$;
