-- Step 3 (2026-11-23, Alex OK 1:24 PM PT): merge startups saved twice under the same name with a different website ending.
-- Same machinery as the 2026-11-21 merge (schema merge_20261121), copied to schema merge_20261123, run 202611231.
-- Only 104 groups with evidence they are one company (site redirects to the other, same full site title,
-- a deal source citing the other site, same investor firm, or a shared founder). Every other same-name pair is left alone.
-- Kept: finished founder-list row first, then most founder facts + live deals, then lowest id.
-- Copies: archived 'Duplicate of startup N (merge 2026-11-23)' so their website routes to N (v2_startup_dup_route).
-- Groups whose copy is held by a bot (founder or location) are deferred, not touched.
-- Undo: select public.v2_deal_cleanup_undo(<blank-round run id in merge_20261123.after_result>); select merge_20261123.undo(202611231);

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: startup_domain_ending_merge skipped';
    return;
  end if;
  execute $ci_body$
create schema if not exists merge_20261123;
revoke all on schema merge_20261123 from public;
do $$ begin if exists (select 1 from pg_roles where rolname='anon') then execute 'revoke all on schema merge_20261123 from anon, authenticated'; end if; end $$;
create table merge_20261123.members (group_no int not null, startup_id bigint primary key);
create table merge_20261123.groups (group_no int primary key, kept_id bigint, batch int, state text not null default 'pending', reason text, done_at timestamptz);
create table merge_20261123.bk (bk_id bigserial primary key, run_id bigint not null, batch int not null, tbl text not null, pk bigint not null, row_before jsonb not null, saved_at timestamptz not null default now(), undone_at timestamptz, unique (run_id, tbl, pk));
create table merge_20261123.deal_dups (run_id bigint, batch int, deal_id bigint primary key, kept_deal_id bigint);
create table merge_20261123.batch_log (run_id bigint, batch int, at timestamptz default now(), result jsonb);
insert into merge_20261123.members (group_no, startup_id) values (1,12031),(1,141381),(2,50617),(2,106217),(3,65690),(3,76117),(4,734),(4,30883),(5,3244),(5,41137),(6,38610),(6,46160),(7,17068),(7,115307),(8,141567),(8,143368),(9,57731),(9,130170),(10,7800),(10,49432),(11,30529),(11,89290),(12,7716),(12,101517),(13,27147),(13,74724),(14,15467),(14,45040),(15,41115),(15,47655),(16,14604),(16,39355),(17,6549),(17,9751),(18,6946),(18,11405),(19,88318),(19,94843),(20,113420),(20,115160),(21,16658),(21,48539),(22,21065),(22,90929),(23,37421),(23,39895),(24,8010),(24,21246),(25,17085),(25,120342),(26,113741),(26,115092),(27,1632),(27,8015),(28,25235),(28,111529),(28,130877),(29,56730),(29,108195),(30,2433),(30,76312),(31,24131),(31,121965),(32,44557),(32,94163),(33,78037),(33,91159),(34,100275),(34,101289),(35,117063),(35,155392),(36,9049),(36,155977),(37,2768),(37,120801),(38,28248),(38,63610),(39,12187),(39,108985),(40,14633),(40,110293),(41,116455),(41,117537),(42,70236),(42,83473),(43,50347),(43,95394),(44,109218),(44,115227),(45,20153),(45,108624),(46,17117),(46,116206),(47,49740),(47,74136),(48,28774),(48,40483),(49,85057),(49,144871),(50,4110),(50,36536),(51,82298),(51,144877),(52,41225),(52,49549),(53,109158),(53,154752),(54,1634),(54,93559),(55,25084),(55,145193),(56,105436),(56,108015),(57,99919),(57,100159),(58,90978),(58,104090),(59,98723),(59,131452),(60,49414),(60,76122),(61,92454),(61,125321),(62,3205),(62,123781),(63,2332),(63,45881),(64,102148),(64,128077),(65,102456),(65,134231),(66,1358),(66,102751),(67,69306),(67,159548),(68,49394),(68,159078),(69,48667),(69,74702),(70,108753),(70,139359),(71,98939),(71,99127),(72,86814),(72,149639),(73,62203),(73,97285),(74,46412),(74,90253),(75,65346),(75,108506),(76,113881),(76,117204),(77,92279),(77,133804),(78,34626),(78,61259),(79,14479),(79,86304),(80,49864),(80,156907),(81,88892),(81,144851),(82,70036),(82,87918),(83,91255),(83,105912),(84,151478),(84,155570),(85,50338),(85,87930),(86,1610),(86,11008),(87,112020),(87,131948),(88,7761),(88,30489),(89,113840),(89,138024),(90,31702),(90,157251),(91,65708),(91,66672),(92,102481),(92,102767),(93,15506),(93,159627),(94,43683),(94,51765),(95,113068),(95,121126),(96,9345),(96,69126),(97,131975),(97,139966),(98,21492),(98,142918),(99,30409),(99,31649),(100,12122),(100,53362),(101,8223),(101,56614),(102,5192),(102,11086),(103,26735),(103,42982),(104,41330),(104,89084);
with s as (
  select m.group_no, m.startup_id, (f.status = 'done') is_done,
    (select count(*) from public.v2_founder_facts x where x.startup_id = m.startup_id)
    + (select count(*) from public.v2_deals d where d.startup_id = m.startup_id and not d.archived) n
  from merge_20261123.members m left join founderlist.startups f using (startup_id))
insert into merge_20261123.groups (group_no, kept_id, batch)
select distinct on (group_no) group_no, startup_id, 1 from s order by group_no, is_done desc nulls last, n desc, startup_id;

CREATE OR REPLACE FUNCTION merge_20261123.do_batch(p_batch integer, p_run bigint DEFAULT 202611231)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '115s'
AS $function$
declare
  v_ids bigint[]; v_copies bigint[]; v_moved bigint[]; v_dup bigint[] := '{}'; v_keep_moved bigint[] := '{}';
  d record; v_other bigint; n_deals int; n_dup int; n_facts int; n_facts_left int; n_sec int; n_sec_left int;
  n_board int; n_fb int; n_fill int; n_arch int; n_fl int; n_def int; v_res jsonb; v_tag text := '(merge 2026-11-23)';
begin
  -- lock members' list rows so bots can't claim them mid-merge
  perform 1 from founderlist.startups f join merge_20261123.members m using (startup_id)
    join merge_20261123.groups g using (group_no) where g.batch = p_batch and g.state = 'pending' for update of f;
  -- defer groups that a bot is working on, or that are no longer clean
  update merge_20261123.groups g set state = 'deferred', reason = x.reason
  from (
    select g2.group_no, string_agg(distinct r, '; ') reason
    from merge_20261123.groups g2 join merge_20261123.members m using (group_no)
    left join public.v2_startups s using (startup_id) left join founderlist.startups f using (startup_id)
    cross join lateral (values
      (case when s.startup_id is null then 'startup missing ' || m.startup_id end),
      (case when s.archived then 'already archived ' || m.startup_id end),
      (case when m.startup_id <> g2.kept_id and f.status = 'taken' then 'copy held by ' || f.taken_by end),
      (case when m.startup_id <> g2.kept_id and f.loc_status = 'taken' then 'copy location held by ' || f.loc_taken_by end)) v(r)
    where g2.batch = p_batch and g2.state = 'pending' and r is not null
    group by g2.group_no) x
  where g.group_no = x.group_no;
  get diagnostics n_def = row_count;

  create temp table mm on commit drop as
    select g.group_no, g.kept_id, m.startup_id copy_id
    from merge_20261123.groups g join merge_20261123.members m using (group_no)
    where g.batch = p_batch and g.state = 'pending' and m.startup_id <> g.kept_id;
  select array_agg(distinct x) into v_ids from (select kept_id x from mm union select copy_id from mm) t;
  select array_agg(copy_id) into v_copies from mm;
  if v_ids is null then
    return jsonb_build_object('batch', p_batch, 'groups', 0, 'deferred', n_def);
  end if;

  -- full backup of every row we may touch
  insert into merge_20261123.bk (run_id, batch, tbl, pk, row_before)
    select p_run, p_batch, 'v2_startups', t.startup_id, to_jsonb(t) from public.v2_startups t where t.startup_id = any(v_ids)
    union all select p_run, p_batch, 'v2_deals', t.deal_id, to_jsonb(t) from public.v2_deals t where t.startup_id = any(v_ids)
    union all select p_run, p_batch, 'v2_founder_facts', t.fact_id, to_jsonb(t) from public.v2_founder_facts t where t.startup_id = any(v_ids)
    union all select p_run, p_batch, 'v2_startup_sectors', t.row_id, to_jsonb(t) from public.v2_startup_sectors t where t.startup_id = any(v_ids)
    union all select p_run, p_batch, 'v2_board_seats', t.row_id, to_jsonb(t) from public.v2_board_seats t where t.startup_id = any(v_ids)
    union all select p_run, p_batch, 'v2_founder_feedback', t.feedback_id, to_jsonb(t) from public.v2_founder_feedback t where t.domain_matched_startup_id = any(v_ids)
    union all select p_run, p_batch, 'founderlist.startups', t.list_id, to_jsonb(t) from founderlist.startups t where t.startup_id = any(v_ids)
  on conflict do nothing;

  -- deals: move all to kept, then archive the moved ones that repeat a deal kept already has
  with u as (update public.v2_deals t set startup_id = mm.kept_id from mm where t.startup_id = mm.copy_id returning t.deal_id)
  select coalesce(array_agg(deal_id), '{}') into v_moved from u;
  n_deals := cardinality(v_moved);
  for d in select * from public.v2_deals t where t.deal_id = any(v_moved) and not t.archived and t.round is not null
           order by t.is_current desc, t.deal_id loop
    select d2.deal_id into v_other from public.v2_deals d2
     where d2.firm_id = any(array(select public.v2_firm_family(d.firm_id)))
       and d2.startup_id = d.startup_id and not d2.archived and d2.deal_id <> d.deal_id
       and d2.round = public.v2_deal_round_norm(d.round)
       and (d2.deal_id <> all(v_moved) or d2.deal_id = any(v_keep_moved))
       and not (nullif(lower(btrim(d2.round_extension)), '') is not null and nullif(lower(btrim(d.round_extension)), '') is not null
                and lower(btrim(d2.round_extension)) <> lower(btrim(d.round_extension)))
       and not public.v2_deal_dates_conflict(d2.deal_date, d2.deal_date_precision, d.deal_date, d.deal_date_precision)
       and not (d2.round in ('Bridge','Debt','Grant','Other') and d2.round_amount is not null and d.round_amount is not null
                and d2.round_amount <> d.round_amount)
     order by (d2.deal_id <> all(v_moved)) desc, d2.is_current desc, d2.deal_id limit 1;
    if v_other is not null then
      insert into merge_20261123.deal_dups values (p_run, p_batch, d.deal_id, v_other);
      v_dup := v_dup || d.deal_id;
    else
      v_keep_moved := v_keep_moved || d.deal_id;
    end if;
  end loop;
  update public.v2_deals t set archived = true, archive_reason = 'Duplicate of deal ' || x.kept_deal_id || ' ' || v_tag
    from merge_20261123.deal_dups x where x.deal_id = t.deal_id and x.batch = p_batch and x.run_id = p_run and not t.archived;
  get diagnostics n_dup = row_count;

  -- founder facts: move unless kept already has the identical fact (those stay on the archived copy; nothing deleted)
  with c as (
    select f.fact_id, mm.kept_id,
      row_number() over (partition by mm.kept_id, f.founder_id, f.fact, f.value_norm order by f.fact_id) rn
    from public.v2_founder_facts f join mm on f.startup_id = mm.copy_id
    where not exists (select 1 from public.v2_founder_facts k where k.startup_id = mm.kept_id and k.founder_id = f.founder_id
                        and k.fact = f.fact and k.value_norm is not distinct from f.value_norm))
  update public.v2_founder_facts t set startup_id = c.kept_id from c where c.fact_id = t.fact_id and c.rn = 1;
  get diagnostics n_facts = row_count;
  select count(*) into n_facts_left from public.v2_founder_facts where startup_id = any(v_copies);

  -- sectors: fill kept up to the 2-sector max, no repeats; the rest stay on the archived copy
  with k as (select mm.kept_id, count(s.*) filter (where not s.archived) n from mm left join public.v2_startup_sectors s on s.startup_id = mm.kept_id group by mm.kept_id),
  c as (
    select s.row_id, mm.kept_id, k.n,
      row_number() over (partition by mm.kept_id order by s.source_level nulls last, s.row_id) rn,
      row_number() over (partition by mm.kept_id, s.sector_id order by s.row_id) rs
    from public.v2_startup_sectors s join mm on s.startup_id = mm.copy_id join k on k.kept_id = mm.kept_id
    where not s.archived
      and not exists (select 1 from public.v2_startup_sectors x where x.startup_id = mm.kept_id and x.sector_id = s.sector_id))
  update public.v2_startup_sectors t set startup_id = c.kept_id from c
   where c.row_id = t.row_id and c.rs = 1 and c.rn <= 2 - c.n;
  get diagnostics n_sec = row_count;
  select count(*) into n_sec_left from public.v2_startup_sectors where startup_id = any(v_copies) and not archived;

  update public.v2_board_seats t set startup_id = mm.kept_id from mm where t.startup_id = mm.copy_id;
  get diagnostics n_board = row_count;
  update public.v2_founder_feedback t set domain_matched_startup_id = mm.kept_id from mm where t.domain_matched_startup_id = mm.copy_id;
  get diagnostics n_fb = row_count;

  -- archive copies the same way as the 2026-11-20 merge
  update public.v2_startups t set archived = true, archive_reason = 'Duplicate of startup ' || mm.kept_id || ' ' || v_tag
    from mm where t.startup_id = mm.copy_id;
  get diagnostics n_arch = row_count;

  -- fill empty kept fields only
  with c as (
    select mm.kept_id,
      (array_agg(s.website_url order by s.startup_id) filter (where s.website_url is not null))[1] website_url,
      (array_agg(s.st_country order by s.startup_id) filter (where s.st_country is not null))[1] st_country,
      (array_agg(s.st_city order by s.startup_id) filter (where s.st_city is not null))[1] st_city,
      (array_agg(s.st_founded_year order by s.startup_id) filter (where s.st_founded_year is not null))[1] st_founded_year
    from mm join public.v2_startups s on s.startup_id = mm.copy_id group by mm.kept_id)
  update public.v2_startups t set
      website_url = coalesce(t.website_url, c.website_url),
      st_country = coalesce(t.st_country, c.st_country),
      st_city = case when t.st_city is null and (t.st_country is null or t.st_country = c.st_country) then c.st_city else t.st_city end,
      st_founded_year = coalesce(t.st_founded_year, c.st_founded_year)
    from c where c.kept_id = t.startup_id
     and ((t.website_url is null and c.website_url is not null) or (t.st_country is null and c.st_country is not null)
          or (t.st_city is null and c.st_city is not null and (t.st_country is null or t.st_country = c.st_country))
          or (t.st_founded_year is null and c.st_founded_year is not null));
  get diagnostics n_fill = row_count;

  -- founder list: open copies become rejected so no bot claims them; done copies stay done with a note
  update founderlist.startups t set
      status = case when t.status = 'open' then 'rejected' else t.status end,
      notes = left(concat_ws(' | ', t.notes, 'Duplicate of startup ' || mm.kept_id || ' ' || v_tag), 4000),
      loc_status = case when t.loc_status = 'open' then 'rejected' else t.loc_status end,
      loc_notes = case when t.loc_status = 'open' then left(concat_ws(' | ', t.loc_notes, 'Duplicate of startup ' || mm.kept_id || ' ' || v_tag), 4000) else t.loc_notes end
    from mm where t.startup_id = mm.copy_id;
  get diagnostics n_fl = row_count;
  -- kept list row: fill an empty website from the copy
  update founderlist.startups t set startup_website = s.website_url
    from mm join public.v2_startups s on s.startup_id = mm.kept_id
   where t.startup_id = mm.kept_id and t.startup_website is null and s.website_url is not null;

  update merge_20261123.groups g set state = 'done', done_at = now()
   where g.batch = p_batch and g.state = 'pending';

  v_res := jsonb_build_object('batch', p_batch, 'groups', (select count(distinct group_no) from mm), 'copies', (select count(*) from mm),
    'deferred', n_def, 'deals_moved', n_deals, 'deals_combined', n_dup, 'facts_moved', n_facts, 'facts_identical_left_on_copy', n_facts_left,
    'sectors_moved', n_sec, 'sectors_left_on_copy', n_sec_left, 'board_seats_moved', n_board, 'feedback_moved', n_fb,
    'kept_filled', n_fill, 'copies_archived', n_arch, 'list_rows_marked', n_fl);
  insert into merge_20261123.batch_log (run_id, batch, result) values (p_run, p_batch, v_res);
  return v_res;
end $function$;

CREATE OR REPLACE FUNCTION merge_20261123.undo(p_run bigint DEFAULT 202611231, p_batch integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
 SET statement_timeout TO '600s'
AS $function$
-- restores only the columns the merge changed, so later bot work on these rows is kept
declare r record; v_tbl text; v_key text; cols text; n int := 0; v_kept boolean;
begin
  for r in select * from merge_20261123.bk where run_id = p_run and undone_at is null and (p_batch is null or batch = p_batch)
           order by case when tbl = 'v2_founder_facts' then 1 when tbl = 'v2_startup_sectors' then 2 when tbl <> 'v2_startups' then 3
                         when exists (select 1 from merge_20261123.groups g where g.kept_id = pk) then 4 else 5 end, bk_id desc loop
    v_tbl := case r.tbl when 'founderlist.startups' then 'founderlist.startups' else 'public.' || r.tbl end;
    v_key := case r.tbl when 'v2_startups' then 'startup_id' when 'v2_deals' then 'deal_id' when 'v2_founder_facts' then 'fact_id'
                        when 'v2_founder_feedback' then 'feedback_id' when 'founderlist.startups' then 'list_id' else 'row_id' end;
    v_kept := exists (select 1 from merge_20261123.groups g where g.kept_id = coalesce((r.row_before->>'startup_id')::bigint, -1));
    cols := case r.tbl
      when 'v2_deals' then 'startup_id,archived,archive_reason'
      when 'v2_founder_facts' then 'startup_id'
      when 'v2_startup_sectors' then 'startup_id'
      when 'v2_board_seats' then 'startup_id'
      when 'v2_founder_feedback' then 'domain_matched_startup_id'
      when 'v2_startups' then case when v_kept then 'website_url,st_country,st_city,st_founded_year,archived' else 'archived,archive_reason' end
      when 'founderlist.startups' then case when v_kept then 'startup_website,list_id' else 'status,notes,loc_status,loc_notes' end end;
    execute format('update %s t set (%s) = (select %s from jsonb_populate_record(null::%s, $1)) where t.%I = $2',
                   v_tbl, cols, cols, v_tbl, v_key) using r.row_before, r.pk;
    update merge_20261123.bk set undone_at = now() where bk_id = r.bk_id;
    n := n + 1;
  end loop;
  update merge_20261123.groups g set state = 'undone' where g.state = 'done' and (p_batch is null or g.batch = p_batch);
  return jsonb_build_object('rows_restored', n);
end $function$;
revoke all on all functions in schema merge_20261123 from public;

create table merge_20261123.run_result as select merge_20261123.do_batch(1) as result, now() as ran_at;
insert into public.v2_change_log (actor, firm_id, box, table_name, row_id, old_value, new_value, result)
select 'startup-merge-20261123', null, '', 'v2_startups', m.startup_id, jsonb_build_object('startup_id', m.startup_id),
       jsonb_build_object('note', 'Duplicate of startup ' || g.kept_id || ' (merge 2026-11-23)'), 'Accepted'
  from merge_20261123.members m join merge_20261123.groups g using (group_no)
 where g.state = 'done' and m.startup_id <> g.kept_id;
create table merge_20261123.after_result as
  select public.v2_deal_cleanup_blank_round(true, 0, (select array_agg(kept_id) from merge_20261123.groups where state = 'done')) as result, now() as ran_at;
$ci_body$;
end
$ci_wrap$;
