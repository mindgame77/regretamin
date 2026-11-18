-- Undo 20261118120000_v2_firm_seo.sql. Drops only the new objects; firm_meta, firm_sitemap and every bot table are untouched.
-- Deploy the previous site build first (or keep this one: the edge falls back to firm_meta / firm_sitemap when these are gone).
do $undo$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') and exists (select 1 from cron.job where jobname = 'v2-firm-seo-refresh') then
    perform cron.unschedule('v2-firm-seo-refresh');
  end if;
end
$undo$;
drop function if exists public.firm_seo_directory(integer, integer);
drop function if exists public.firm_seo_sitemap(integer, integer);
drop function if exists public.firm_meta_seo(text);
drop function if exists public.v2_firm_seo_refresh(int);
drop function if exists public.v2_firm_seo_compute(bigint[]);
drop function if exists public.v2_seo_stage_label(int);
drop function if exists public.v2_seo_stage_rank(text);
drop table if exists public.v2_firm_seo;
