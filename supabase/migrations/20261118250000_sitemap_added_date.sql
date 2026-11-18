-- Sitemap lastmod and stale SEO "Checked <date>" text use firm_summary.added,
-- the firm's one check date (the date its data was added).
-- firm_meta and v2_firm_seo_compute already use added (PRs 414 and 413).
-- firm_seo_sitemap still read the cached v2_firm_seo.last_checked_date column.
-- This points the sitemap at added directly, and recomputes SEO only for firms
-- whose cached check date does not already match added (2 live firms today).
-- Nothing else on the page changes. Not applied by this change.
-- Rollback: supabase/rollbacks/20261118250000_sitemap_added_date.sql
-- The v2 schema is not created by repo migrations. On a database without those tables (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_firm_seo') is null
     or to_regclass('public.v2_firm_live') is null
     or to_regclass('public.v2_firms') is null
     or to_regclass('public.firm_summary') is null
     or to_regprocedure('public.v2_firm_seo_compute(bigint[])') is null then
    raise notice 'v2 seo tables missing, skipped';
    return;
  end if;

  execute $sql$
create or replace function public.firm_seo_sitemap(p_page integer default 1, p_size integer default 1000)
 returns table(slug text, lastmod date, total bigint)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with pub as (
    select l.slug::text as slug, coalesce(fs.added::date, s.last_checked_date) as lastmod
      from v2_firm_seo s
      join v2_firm_live l on l.firm_id = s.firm_id
      join v2_firms f on f.firm_id = s.firm_id
      left join firm_summary fs on fs.firm_id = s.firm_id
     where s.seo_indexable and not coalesce(f.archived, false) and f.merged_into_firm_id is null
  )
  select p.slug, p.lastmod, (select count(*) from pub)
    from pub p
   order by p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 1000), 1), 1000)
   limit least(greatest(coalesce(p_size, 1000), 1), 1000)
$function$
$sql$;

  -- Recompute cached "Checked <date>" / facts.last_checked only where they still
  -- disagree with added. Same upsert as v2_firm_seo_refresh, including manual_edit.
  execute $sql$
  insert into v2_firm_seo as s (firm_id, slug, seo_title, seo_description, seo_indexable, facts, last_checked_date, seo_updated_at, checked_at)
  select c.firm_id, c.slug, c.seo_title, c.seo_description, c.seo_indexable, c.facts, c.last_checked_date, now(), now()
    from v2_firm_seo_compute(array(
      select s.firm_id
        from v2_firm_seo s
        join firm_summary fs on fs.firm_id = s.firm_id
       where s.last_checked_date is distinct from fs.added::date
    )) c
  on conflict (firm_id) do update set
    slug = excluded.slug,
    seo_title = case when s.manual_edit then s.seo_title else excluded.seo_title end,
    seo_description = case when s.manual_edit then s.seo_description else excluded.seo_description end,
    seo_indexable = excluded.seo_indexable, facts = excluded.facts, last_checked_date = excluded.last_checked_date,
    seo_updated_at = case when (s.slug, s.seo_indexable, s.facts, s.last_checked_date) is distinct from (excluded.slug, excluded.seo_indexable, excluded.facts, excluded.last_checked_date)
                            or (not s.manual_edit and (s.seo_title, s.seo_description) is distinct from (excluded.seo_title, excluded.seo_description))
                          then now() else s.seo_updated_at end,
    checked_at = now()
$sql$;
end
$mig$;
