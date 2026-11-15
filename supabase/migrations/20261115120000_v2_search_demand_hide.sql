-- Hide demand firms from the paged investors list.
-- Runs after firm_directory_page exists. Does not replace the rest of that function.
-- A hidden firm also has no v2_firm_live row until research is done, so the other
-- page, sitemap, and suggest reads already omit it.
-- CI has no v2 schema: this is a no-op there.
-- Undo: supabase/rollbacks/20261115120000_v2_search_demand_hide.sql
do $mig$
declare
  d text;
  needle text := 'not coalesce(f.archived, false) and f.merged_into_firm_id is null';
  extra text := needle || ' and not coalesce(f.demand_hidden, false)';
  sig text := 'public.firm_directory_page(int,int,text,boolean,text[],text[],text[],text[],text[],text[],text[])';
begin
  if to_regclass('public.v2_firms') is null
     or not exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'v2_firms' and column_name = 'demand_hidden'
     )
     or to_regprocedure(sig) is null then
    raise notice 'firm_directory_page hide patch skipped';
    return;
  end if;
  select pg_get_functiondef(sig::regprocedure) into d;
  if position('demand_hidden' in d) > 0 then
    return;
  end if;
  if position(needle in d) = 0 then
    raise notice 'firm_directory_page hide patch: live filter text not found, left unchanged';
    return;
  end if;
  execute replace(d, needle, extra);
end
$mig$;
