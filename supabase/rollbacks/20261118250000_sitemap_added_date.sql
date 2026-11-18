-- Rollback for 20261118250000_sitemap_added_date.sql: firm_seo_sitemap lastmod back to the cached last_checked_date.
-- Recomputed SEO rows keep the added date (the correct check date); this does not put the stale dates back.
do $rb$
begin
  if to_regclass('public.v2_firm_seo') is null
     or to_regclass('public.v2_firm_live') is null
     or to_regclass('public.v2_firms') is null then
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
    select l.slug::text as slug, s.last_checked_date as lastmod
      from v2_firm_seo s
      join v2_firm_live l on l.firm_id = s.firm_id
      join v2_firms f on f.firm_id = s.firm_id
     where s.seo_indexable and not coalesce(f.archived, false) and f.merged_into_firm_id is null
  )
  select p.slug, p.lastmod, (select count(*) from pub)
    from pub p
   order by p.slug
  offset greatest(coalesce(p_page, 1) - 1, 0) * least(greatest(coalesce(p_size, 1000), 1), 1000)
   limit least(greatest(coalesce(p_size, 1000), 1), 1000)
$function$
$sql$;
end
$rb$;
