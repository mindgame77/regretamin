-- Repeats cleanup 2026-11-23, part 4: videos / interviews. Same firm + same video (YouTube video id, otherwise the
-- normalized link) = one video. Keeps the most complete copy (team member tagged, title, views, date, link not dead),
-- fills a missing title / channel / views / date on it, archives the rest (never deletes).
-- Backup: repeats_20261123. Undo: /home/box/regretamin-repeats-20261123/undo/undo_interviews.sql

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: repeats_interviews_cleanup skipped';
    return;
  end if;
  execute $ci_body$
CREATE SCHEMA IF NOT EXISTS repeats_20261123;
CREATE OR REPLACE FUNCTION public.v2_video_key(u text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $f$
  SELECT coalesce('yt:' || substring(u from '(?:[?&]v=|youtu\.be/|/shorts/|/embed/|/live/)([A-Za-z0-9_-]{11})'), public.v2_norm_url(u)) $f$;
CREATE TABLE IF NOT EXISTS repeats_20261123.interviews_map (drop_id bigint PRIMARY KEY, keep_id bigint NOT NULL, firm_id bigint NOT NULL);
INSERT INTO repeats_20261123.interviews_map (drop_id, keep_id, firm_id)
WITH b AS (
  SELECT v.*, public.v2_video_key(v.interview_url) vk,
    ((v.person_id IS NOT NULL)::int * 8 + (nullif(btrim(v.title),'') IS NOT NULL)::int * 4 + (v.view_count IS NOT NULL)::int * 2 + (v.interview_date IS NOT NULL)::int) score
  FROM public.v2_interviews v
  WHERE v.is_current AND NOT v.archived AND NOT coalesce(v.nothing_found,false) AND public.v2_video_key(v.interview_url) IS NOT NULL),
grp AS (SELECT firm_id, vk FROM b GROUP BY 1,2 HAVING count(*) > 1),
ranked AS (
  SELECT b.*, first_value(b.row_id) OVER (PARTITION BY b.firm_id, b.vk ORDER BY coalesce(b.link_dead,false) ASC, b.score DESC, b.source_level ASC NULLS LAST, b.row_id ASC) keep_id
  FROM b JOIN grp USING (firm_id, vk))
SELECT row_id AS drop_id, keep_id, firm_id FROM ranked WHERE row_id <> keep_id
ON CONFLICT (drop_id) DO NOTHING;
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_interviews AS SELECT * FROM public.v2_interviews WHERE false;
INSERT INTO repeats_20261123.v2_interviews SELECT v.* FROM public.v2_interviews v
  WHERE v.row_id IN (SELECT drop_id FROM repeats_20261123.interviews_map UNION SELECT keep_id FROM repeats_20261123.interviews_map)
    AND NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_interviews b WHERE b.row_id = v.row_id);
CREATE TABLE IF NOT EXISTS repeats_20261123.v2_checker_queue AS SELECT * FROM public.v2_checker_queue WHERE false;
INSERT INTO repeats_20261123.v2_checker_queue SELECT q.* FROM public.v2_checker_queue q
  JOIN repeats_20261123.interviews_map m ON q.table_name = 'v2_interviews' AND q.row_id = m.drop_id
  WHERE NOT EXISTS (SELECT 1 FROM repeats_20261123.v2_checker_queue b WHERE b.queue_id = q.queue_id);
-- fill blanks on the kept row only
UPDATE public.v2_interviews k SET
  title = coalesce(nullif(btrim(k.title),''), d.title), channel = coalesce(nullif(btrim(k.channel),''), d.channel),
  view_count = coalesce(k.view_count, d.view_count), interview_date = coalesce(k.interview_date, d.interview_date)
FROM (SELECT m.keep_id,
        (array_agg(v.title ORDER BY v.row_id) FILTER (WHERE nullif(btrim(v.title),'') IS NOT NULL))[1] title,
        (array_agg(v.channel ORDER BY v.row_id) FILTER (WHERE nullif(btrim(v.channel),'') IS NOT NULL))[1] channel,
        max(v.view_count) view_count,
        (array_agg(v.interview_date ORDER BY v.row_id) FILTER (WHERE v.interview_date IS NOT NULL))[1] interview_date
      FROM repeats_20261123.interviews_map m JOIN public.v2_interviews v ON v.row_id = m.drop_id GROUP BY m.keep_id) d
WHERE k.row_id = d.keep_id
  AND (nullif(btrim(k.title),'') IS NULL AND d.title IS NOT NULL OR nullif(btrim(k.channel),'') IS NULL AND d.channel IS NOT NULL
    OR k.view_count IS NULL AND d.view_count IS NOT NULL OR k.interview_date IS NULL AND d.interview_date IS NOT NULL);
UPDATE public.v2_interviews d SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: repeat of video ' || m.keep_id
FROM repeats_20261123.interviews_map m WHERE d.row_id = m.drop_id AND NOT d.archived;
UPDATE public.v2_checker_queue q SET archived = true, archive_reason = 'duplicate cleanup 2026-11-23: row archived as repeat'
FROM repeats_20261123.interviews_map m WHERE q.table_name = 'v2_interviews' AND q.row_id = m.drop_id AND q.status = 'open' AND NOT q.archived;
INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, new_value, result)
SELECT 'repeats-cleanup-20261123', m.firm_id, '', 'v2_interviews', m.drop_id,
  jsonb_build_object('note','repeat archived (backup schema repeats_20261123)','kept_row',m.keep_id), 'Accepted'
FROM repeats_20261123.interviews_map m;
$ci_body$;
end
$ci_wrap$;
