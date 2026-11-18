-- Rollback for 20261118160000_firm_meta_added.sql: firm_meta.updated_at back to greatest(live_since, last_checked_date).
do $rb$
begin
  if to_regclass('public.v2_firm_live') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing, skipped';
    return;
  end if;
  execute $sql$
create or replace function public.firm_meta(p_slug text)
 returns table(slug text, name text, short_name text, hq text, firm_type text, legal_name text, primary_domain text, founded_year integer, updated_at timestamp with time zone, indexable boolean)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select f.slug::text, f.display_name::text, f.short_name::text, nullif(concat_ws(', ', f.hq_city, coalesce(f.hq_state, f.hq_country)),''),
    (select t.name::text from v2_firm_types_firms tf join v2_firm_type t on t.firm_type_id=tf.firm_type_id where tf.firm_id=f.firm_id limit 1),
    f.legal_name::text, regexp_replace(regexp_replace(coalesce(f.website_url,''),'^https?://(www\.)?',''),'/.*$',''), f.founded_year::int,
    greatest(l.live_since, f.last_checked_date::timestamptz), true
  from v2_firm_live l join v2_firms f on f.firm_id=l.firm_id where l.slug=lower(btrim(coalesce(p_slug,''))) and not coalesce(f.archived,false) limit 1 $function$
$sql$;
end
$rb$;
