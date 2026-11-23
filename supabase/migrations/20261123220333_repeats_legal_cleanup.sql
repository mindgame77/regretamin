-- Repeats cleanup 2026-11-23, part 1: legal cases (Alex: "Fix all of that one by one", legal first).
-- Archives exact repeats of the same case on the same firm (never deletes). Backup: schema repeats_20261123.
-- Undo: /home/box/regretamin-repeats-20261123/undo/undo_legal.sql

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_legal_cleanup skipped';
    return;
  end if;
  execute $ci_body$
CREATE SCHEMA IF NOT EXISTS repeats_20261123;

-- shared text normalizer for repeat matching: lower case, letters and digits only
CREATE OR REPLACE FUNCTION public.v2_repeat_norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$ SELECT nullif(lower(regexp_replace(coalesce(t,''), '[^[:alnum:]]+', '', 'g')), '') $f$;

-- certain repeats (same docket / same regulator decision / identical text); checked by hand
CREATE TABLE IF NOT EXISTS repeats_20261123.legal_map (drop_id bigint PRIMARY KEY, keep_id bigint NOT NULL, firm_id bigint NOT NULL, why text);
INSERT INTO repeats_20261123.legal_map (drop_id, keep_id, firm_id, why) VALUES
  (1160, 1080, 186,  'same Ninth Circuit docket 25-5701 (courtlistener 71302164)'),
  (218,  214,  704,  'identical row: SEC File No. 3-19843'),
  (1495, 1482, 3418, 'same Handelsgericht Wien Konkurs 2 S 121/24t'),
  (5919, 4298, 2154, 'same FCMC 7 Sep 2021 decision against AS Baltic Technology Ventures')
ON CONFLICT (drop_id) DO NOTHING;
-- only rows that still exist, still match their firm and are still live
DELETE FROM repeats_20261123.legal_map m WHERE NOT EXISTS (
  SELECT 1 FROM public.v2_legal_items d JOIN public.v2_legal_items k ON k.legal_item_id = m.keep_id
  WHERE d.legal_item_id = m.drop_id AND d.firm_id = m.firm_id AND k.firm_id = m.firm_id AND NOT d.archived AND NOT k.archived);

CREATE TABLE IF NOT EXISTS repeats_20261123.v2_legal_items AS SELECT * FROM public.v2_legal_items WHERE false;
INSERT INTO repeats_20261123.v2_legal_items SELECT li.* FROM public.v2_legal_items li
  WHERE li.legal_item_id IN (SELECT drop_id FROM repeats_20261123.legal_map UNION SELECT keep_id FROM repeats_20261123.legal_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_legal_items b WHERE b.legal_item_id = li.legal_item_id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_checker_queue AS SELECT * FROM public.v2_checker_queue WHERE false;
INSERT INTO repeats_20261123.v2_checker_queue SELECT q.* FROM public.v2_checker_queue q
  JOIN repeats_20261123.legal_map m ON q.table_name = 'v2_legal_items' AND q.row_id = m.drop_id
  WHERE NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_checker_queue b WHERE b.queue_id = q.queue_id);

-- fill blanks on the kept row only (never overwrite)
UPDATE public.v2_legal_items k SET
  other_party = coalesce(k.other_party, d.other_party),
  regulator_name = coalesce(k.regulator_name, d.regulator_name),
  filed_year = coalesce(k.filed_year, d.filed_year),
  closed_year = coalesce(k.closed_year, d.closed_year),
  settlement_terms = coalesce(k.settlement_terms, d.settlement_terms)
FROM repeats_20261123.legal_map m JOIN public.v2_legal_items d ON d.legal_item_id = m.drop_id
WHERE k.legal_item_id = m.keep_id
  AND (k.other_party IS NULL AND d.other_party IS NOT NULL OR k.regulator_name IS NULL AND d.regulator_name IS NOT NULL
    OR k.filed_year IS NULL AND d.filed_year IS NOT NULL OR k.closed_year IS NULL AND d.closed_year IS NOT NULL
    OR k.settlement_terms IS NULL AND d.settlement_terms IS NOT NULL);

UPDATE public.v2_legal_items d SET archived = true,
  archive_reason = 'duplicate cleanup 2026-11-23: repeat of legal item ' || m.keep_id
FROM repeats_20261123.legal_map m WHERE d.legal_item_id = m.drop_id AND NOT d.archived;

UPDATE public.v2_checker_queue q SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: row archived as repeat'
FROM repeats_20261123.legal_map m WHERE q.table_name = 'v2_legal_items' AND q.row_id = m.drop_id AND q.status = 'open' AND NOT q.archived;

INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, new_value, result)
SELECT 'repeats-cleanup-20261123', m.firm_id, '', 'v2_legal_items', m.drop_id,
  jsonb_build_object('note','repeat archived (backup schema repeats_20261123)','kept_row',m.keep_id,'why',m.why), 'Accepted'
FROM repeats_20261123.legal_map m;
$ci_body$;
end
$ci_wrap$;
