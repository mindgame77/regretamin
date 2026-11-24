do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_events') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 1: archive repeated deals (same firm + startup + round within a year, same add-on), keep the best row.
create schema if not exists dupfix_20261123;
create table dupfix_20261123.s1_deals_state as select deal_id, shown, is_current, archived from public.v2_deals;
create table dupfix_20261123.s1_map as
with d as (
  select deal_id, firm_id, startup_id, round, coalesce(lower(btrim(round_extension)),'') ext, deal_date, round_amount, created_at,
         (source_url is not null)::int + (round_amount is not null)::int + (deal_date_precision = 'full date')::int score
    from public.v2_deals where is_current and not archived and not coalesce(nothing_found,false) and shown and round is not null),
g as (
  select firm_id, startup_id, round from d group by 1,2,3
  having count(*) > 1 and max(deal_date) - min(deal_date) <= 366 and count(distinct ext) = 1
     and not (round in ('Other','Bridge','Debt','Grant') and count(distinct round_amount) > 1)),
r as (
  select d.*, row_number() over (partition by d.firm_id, d.startup_id, d.round order by d.score desc, d.created_at, d.deal_id) rn
    from d join g using (firm_id, startup_id, round))
select a.deal_id as archived_deal_id, k.deal_id as kept_deal_id
  from r a join r k on k.firm_id = a.firm_id and k.startup_id = a.startup_id and k.round = a.round and k.rn = 1
 where a.rn > 1;
update public.v2_deals d set archived = true, is_current = false, shown = false, archive_reason = 'Duplicate of deal ' || m.kept_deal_id
  from dupfix_20261123.s1_map m where d.deal_id = m.archived_deal_id;
$sql$;
end $mig$;
