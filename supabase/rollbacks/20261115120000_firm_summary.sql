-- Undo the firm_summary speed-up. Point firms.js back to firm_directory_page first.
select cron.unschedule('firm-summary-refresh') where exists (select 1 from cron.job where jobname = 'firm-summary-refresh');
do $$
declare t text;
begin
  foreach t in array array['v2_deals','v2_firms','v2_firm_live','v2_firm_industries','v2_firm_stages',
                           'v2_legal_items','v2_auto_published','v2_startups','v2_startup_sectors'] loop
    execute format('drop trigger if exists firm_summary_ins on public.%I', t);
    execute format('drop trigger if exists firm_summary_upd on public.%I', t);
    execute format('drop trigger if exists firm_summary_del on public.%I', t);
  end loop;
end $$;
drop trigger if exists firm_summary_sector on public.v2_sector;
drop function if exists public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[]);
drop function if exists public.firm_summary_by_firm_trg();
drop function if exists public.firm_summary_by_startup_trg();
drop function if exists public.firm_summary_all_trg();
drop function if exists public.refresh_firm_summary_all();
drop function if exists public.refresh_firm_summary(bigint[]);
drop function if exists public.firm_summary_region(text);
drop table if exists public.firm_summary;
-- Optional: the two v2_deals indexes are harmless and also speed up the old function; drop only if wanted:
-- drop index if exists public.v2_deals_startup_id_idx;
-- drop index if exists public.v2_deals_firm_startup_idx;
