-- team duplicates cleanup, applied with apply flag on (see migration_cleanup.sql)

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: team_duplicates_cleanup skipped';
    return;
  end if;
  execute $ci_body$
DO $w$ BEGIN
  PERFORM set_config('team_dupes.apply','yes',true);
  EXECUTE $t$DO $mig$
DECLARE
  v_apply boolean := coalesce(current_setting('team_dupes.apply', true), '') = 'yes';
  v_actor text := 'team-dupes-cleanup-20261123';
  v_sample bigint[] := ARRAY[1,2,5,6,8];  -- YC, a16z, Sequoia, Lightspeed, Accel
  v_before jsonb; v_after jsonb; v_counts jsonb;
  n_people_merged int; n_keep int; n_roles_repointed int; n_iv int; n_bs int; n_li int; n_q int;
  n_roles_archived int; n_founder_flag int; n_fill int;
BEGIN
  -- 0. what the sample firms look like now (all live team rows: name | title | founder)
  SELECT jsonb_object_agg(f.display_name, coalesce(t.rows,'[]'::jsonb)) INTO v_before
  FROM public.v2_firms f
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(format('%s | %s%s', btrim(pe.person_name), coalesce(r.title,'(no title)'), CASE WHEN r.is_founder THEN ' | founder' ELSE '' END)
                     ORDER BY lower(btrim(pe.person_name)), r.row_id) rows
    FROM public.v2_person_firm_roles r JOIN public.v2_people pe ON pe.person_id = r.person_id
    WHERE r.firm_id = f.firm_id AND r.is_current AND NOT r.archived AND NOT r.nothing_found
      AND pe.is_current AND NOT pe.archived) t ON true
  WHERE f.firm_id = ANY(v_sample);

  -- 1. person merge map: same firm + same normalized name -> keep oldest person_id.
  --    Skip a cluster if two of its people carry different LinkedIn links (likely two real people).
  CREATE TEMP TABLE _td_map ON COMMIT DROP AS
  WITH r AS (
    SELECT r.firm_id, r.person_id, lower(regexp_replace(btrim(p.person_name), '\s+', ' ', 'g')) nm, p.linkedin_url_norm li
    FROM public.v2_person_firm_roles r
    JOIN public.v2_people p ON p.person_id = r.person_id AND p.is_current AND NOT p.archived
    WHERE r.is_current AND NOT r.archived),
  cl AS (
    SELECT firm_id, nm, min(person_id) keep_id, array_agg(DISTINCT person_id) ids
    FROM r GROUP BY 1,2
    HAVING count(DISTINCT person_id) > 1 AND count(DISTINCT li) <= 1)
  SELECT DISTINCT c.firm_id, c.nm, c.keep_id, x AS drop_id
  FROM cl c, unnest(c.ids) x WHERE x <> c.keep_id;

  IF EXISTS (SELECT 1 FROM _td_map GROUP BY drop_id HAVING count(DISTINCT keep_id) > 1) THEN
    RAISE EXCEPTION 'stop: a person would merge into two different people';
  END IF;
  IF EXISTS (SELECT 1 FROM _td_map m1 JOIN _td_map m2 ON m2.keep_id = m1.drop_id) THEN
    RAISE EXCEPTION 'stop: merge chain found';
  END IF;

  -- 2. backup (same transaction)
  CREATE SCHEMA IF NOT EXISTS team_dupes_20261123;
  CREATE TABLE team_dupes_20261123.merge_map AS SELECT * FROM _td_map;
  CREATE TABLE team_dupes_20261123.v2_people AS
    SELECT * FROM public.v2_people WHERE person_id IN (SELECT keep_id FROM _td_map UNION SELECT drop_id FROM _td_map);
  CREATE TABLE team_dupes_20261123.v2_interviews AS
    SELECT * FROM public.v2_interviews WHERE person_id IN (SELECT drop_id FROM _td_map);
  CREATE TABLE team_dupes_20261123.v2_board_seats AS
    SELECT * FROM public.v2_board_seats WHERE person_id IN (SELECT drop_id FROM _td_map);
  CREATE TABLE team_dupes_20261123.v2_legal_items AS
    SELECT * FROM public.v2_legal_items WHERE person_id IN (SELECT drop_id FROM _td_map);
  CREATE TABLE team_dupes_20261123.v2_checker_queue AS
    SELECT * FROM public.v2_checker_queue
    WHERE table_name = 'v2_people' AND kind = 'changed-key-fact' AND status = 'open' AND NOT archived
      AND row_id IN (SELECT drop_id FROM _td_map);

  -- 3. archive the newer duplicate people
  UPDATE public.v2_people p SET archived = true,
         archive_reason = 'Duplicate of person ' || m.keep_id
  FROM _td_map m WHERE p.person_id = m.drop_id AND NOT p.archived;
  GET DIAGNOSTICS n_people_merged = ROW_COUNT;

  -- 4. copy links/photo/followers the kept person is missing (newest duplicate that has it wins).
  --    People are one row per person_id and are updated in place (same as the LinkedIn fill in v2_auto_publish_apply_queue).
  WITH d AS (SELECT DISTINCT m.keep_id, p.* FROM _td_map m JOIN public.v2_people p ON p.person_id = m.drop_id),
  pick AS (
    SELECT keep_id,
      (array_agg(linkedin_url ORDER BY created_at DESC) FILTER (WHERE nullif(btrim(linkedin_url),'') IS NOT NULL))[1] li,
      (array_agg(x_url ORDER BY created_at DESC) FILTER (WHERE nullif(btrim(x_url),'') IS NOT NULL))[1] xu,
      (array_agg(photo_url ORDER BY created_at DESC) FILTER (WHERE nullif(btrim(photo_url),'') IS NOT NULL))[1] ph,
      (array_agg(x_followers ORDER BY created_at DESC) FILTER (WHERE x_followers IS NOT NULL))[1] xf,
      (array_agg(linkedin_followers ORDER BY created_at DESC) FILTER (WHERE linkedin_followers IS NOT NULL))[1] lf,
      (array_agg(social_read_on ORDER BY created_at DESC) FILTER (WHERE social_read_on IS NOT NULL))[1] sr
    FROM d GROUP BY keep_id)
  UPDATE public.v2_people p SET
    linkedin_url = coalesce(nullif(btrim(p.linkedin_url),''), pick.li),
    x_url = coalesce(nullif(btrim(p.x_url),''), pick.xu),
    photo_url = coalesce(nullif(btrim(p.photo_url),''), pick.ph),
    x_followers = coalesce(p.x_followers, pick.xf),
    linkedin_followers = coalesce(p.linkedin_followers, pick.lf),
    social_read_on = coalesce(p.social_read_on, pick.sr)
  FROM pick
  WHERE p.person_id = pick.keep_id
    AND (  (nullif(btrim(p.linkedin_url),'') IS NULL AND pick.li IS NOT NULL)
        OR (nullif(btrim(p.x_url),'') IS NULL AND pick.xu IS NOT NULL)
        OR (nullif(btrim(p.photo_url),'') IS NULL AND pick.ph IS NOT NULL)
        OR (p.x_followers IS NULL AND pick.xf IS NOT NULL)
        OR (p.linkedin_followers IS NULL AND pick.lf IS NOT NULL)
        OR (p.social_read_on IS NULL AND pick.sr IS NOT NULL));
  GET DIAGNOSTICS n_fill = ROW_COUNT;

  -- 5. back up every role row of the affected firm+person groups, then repoint roles and other links
  CREATE TABLE team_dupes_20261123.v2_person_firm_roles AS
    SELECT r.* FROM public.v2_person_firm_roles r
    WHERE r.person_id IN (SELECT drop_id FROM _td_map)
       OR (r.firm_id, r.person_id) IN (
            SELECT firm_id, person_id FROM public.v2_person_firm_roles
            WHERE is_current AND NOT archived AND person_id IS NOT NULL
            GROUP BY 1,2 HAVING count(*) > 1)
       OR (r.firm_id, r.person_id) IN (SELECT firm_id, keep_id FROM _td_map);

  UPDATE public.v2_person_firm_roles r SET person_id = m.keep_id
  FROM (SELECT DISTINCT drop_id, keep_id FROM _td_map) m WHERE r.person_id = m.drop_id;
  GET DIAGNOSTICS n_roles_repointed = ROW_COUNT;
  UPDATE public.v2_interviews t SET person_id = m.keep_id FROM (SELECT DISTINCT drop_id, keep_id FROM _td_map) m WHERE t.person_id = m.drop_id;
  GET DIAGNOSTICS n_iv = ROW_COUNT;
  UPDATE public.v2_board_seats t SET person_id = m.keep_id FROM (SELECT DISTINCT drop_id, keep_id FROM _td_map) m WHERE t.person_id = m.drop_id;
  GET DIAGNOSTICS n_bs = ROW_COUNT;
  UPDATE public.v2_legal_items t SET person_id = m.keep_id FROM (SELECT DISTINCT drop_id, keep_id FROM _td_map) m WHERE t.person_id = m.drop_id;
  GET DIAGNOSTICS n_li = ROW_COUNT;
  -- open LinkedIn fills waiting on a merged person now land on the kept person (still fill-blank-only)
  UPDATE public.v2_checker_queue q SET row_id = m.keep_id
  FROM (SELECT DISTINCT drop_id, keep_id FROM _td_map) m
  WHERE q.table_name = 'v2_people' AND q.kind = 'changed-key-fact' AND q.status = 'open' AND NOT q.archived AND q.row_id = m.drop_id;
  GET DIAGNOSTICS n_q = ROW_COUNT;

  -- 6. one live role row per firm + person.
  --    Keep: newest row that has a title (so a later title-less founder row does not wipe "Managing Partner");
  --    tie -> Firm website source, then highest row_id. If no row has a title, the newest row.
  --    If an archived sibling said founder, the kept row keeps the founder flag.
  CREATE TEMP TABLE _td_roles ON COMMIT DROP AS
  SELECT r.row_id, r.firm_id, r.person_id, r.is_founder,
         first_value(r.row_id) OVER w AS keep_row,
         bool_or(r.is_founder) OVER (PARTITION BY r.firm_id, r.person_id) AS any_founder
  FROM public.v2_person_firm_roles r
  WHERE r.is_current AND NOT r.archived AND r.person_id IS NOT NULL
    AND (r.firm_id, r.person_id) IN (
      SELECT firm_id, person_id FROM public.v2_person_firm_roles
      WHERE is_current AND NOT archived AND person_id IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1)
  WINDOW w AS (PARTITION BY r.firm_id, r.person_id
               ORDER BY (nullif(btrim(r.title),'') IS NOT NULL) DESC, r.created_at DESC,
                        (r.source_type = 'Firm website') DESC, r.row_id DESC);

  UPDATE public.v2_person_firm_roles r SET archived = true, archive_reason = 'Duplicate of row ' || t.keep_row
  FROM _td_roles t WHERE r.row_id = t.row_id AND t.row_id <> t.keep_row;
  GET DIAGNOSTICS n_roles_archived = ROW_COUNT;

  UPDATE public.v2_person_firm_roles r SET is_founder = true
  FROM _td_roles t WHERE r.row_id = t.row_id AND t.row_id = t.keep_row AND t.any_founder AND NOT r.is_founder;
  GET DIAGNOSTICS n_founder_flag = ROW_COUNT;

  -- 7. change log (one row per firm touched)
  INSERT INTO public.v2_change_log (actor, firm_id, box, table_name, row_id, old_value, new_value, result)
  SELECT v_actor, x.firm_id, '', 'v2_person_firm_roles', NULL,
         NULL, jsonb_build_object('note','duplicate team members merged (backup schema team_dupes_20261123)','people_merged', x.pm, 'roles_archived', x.ra),
         'Accepted'
  FROM (
    SELECT firm_id, sum(pm)::int pm, sum(ra)::int ra FROM (
      SELECT firm_id, count(*) pm, 0 ra FROM _td_map GROUP BY 1
      UNION ALL SELECT firm_id, 0, count(*) FILTER (WHERE row_id <> keep_row) FROM _td_roles GROUP BY 1) z
    GROUP BY firm_id) x;

  SELECT count(DISTINCT keep_id) INTO n_keep FROM _td_map;
  v_counts := jsonb_build_object(
    'people_merged_away', n_people_merged, 'kept_people', n_keep, 'kept_people_filled', n_fill,
    'roles_repointed', n_roles_repointed, 'interviews_repointed', n_iv, 'board_seats_repointed', n_bs,
    'legal_items_repointed', n_li, 'queue_fills_repointed', n_q,
    'role_rows_archived', n_roles_archived, 'founder_flag_carried', n_founder_flag,
    'firms_touched', (SELECT count(DISTINCT firm_id) FROM (SELECT firm_id FROM _td_map UNION SELECT firm_id FROM _td_roles) z),
    'left_dupe_name_pairs', (SELECT count(*) FROM (
        SELECT r.firm_id, lower(btrim(p.person_name)) FROM public.v2_person_firm_roles r
        JOIN public.v2_people p ON p.person_id = r.person_id AND p.is_current AND NOT p.archived
        WHERE r.is_current AND NOT r.archived GROUP BY 1,2 HAVING count(DISTINCT r.person_id) > 1) a),
    'left_dupe_role_pairs', (SELECT count(*) FROM (
        SELECT firm_id, person_id FROM public.v2_person_firm_roles
        WHERE is_current AND NOT archived AND person_id IS NOT NULL GROUP BY 1,2 HAVING count(*) > 1) b));

  SELECT jsonb_object_agg(f.display_name, coalesce(t.rows,'[]'::jsonb)) INTO v_after
  FROM public.v2_firms f
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(format('%s | %s%s', btrim(pe.person_name), coalesce(r.title,'(no title)'), CASE WHEN r.is_founder THEN ' | founder' ELSE '' END)
                     ORDER BY lower(btrim(pe.person_name)), r.row_id) rows
    FROM public.v2_person_firm_roles r JOIN public.v2_people pe ON pe.person_id = r.person_id
    WHERE r.firm_id = f.firm_id AND r.is_current AND NOT r.archived AND NOT r.nothing_found
      AND pe.is_current AND NOT pe.archived) t ON true
  WHERE f.firm_id = ANY(v_sample);

  IF NOT v_apply THEN
    RAISE EXCEPTION 'DRYRUN %', jsonb_build_object('counts', v_counts, 'before', v_before, 'after', v_after)::text;
  END IF;
  RAISE NOTICE 'APPLIED %', v_counts::text;
END
$mig$$t$;
END $w$;
$ci_body$;
end
$ci_wrap$;
