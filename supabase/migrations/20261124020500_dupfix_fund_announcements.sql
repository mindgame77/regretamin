do $mig$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_events') is null then
    raise notice 'tables not present; skipped'; return;
  end if;
  execute $sql$
-- Step 2: archive fund announcements that copy an SEC fund (same firm + name), then same-name announcement repeats (keep the better sourced).
create table dupfix_20261123.s2_ffa_state as select id, is_current, archived, archive_reason, event_id from public.firm_fund_announcements;
create table dupfix_20261123.s2_map as
select a.id, 'SEC fund ' || min(f.fund_id) as reason
  from public.firm_fund_announcements a
  join public.v2_funds f on f.firm_id = a.firm_id and f.is_current and not f.archived and lower(btrim(f.fund_name)) = lower(btrim(a.name))
 where a.is_current and not a.archived group by a.id;
insert into dupfix_20261123.s2_map
select id, 'announcement ' || kept from (
  select id, first_value(id) over w kept, row_number() over w rn
    from public.firm_fund_announcements a
   where is_current and not archived and id not in (select id from dupfix_20261123.s2_map)
  window w as (partition by firm_id, lower(btrim(name)) order by (source_url is not null) desc, coalesce(source_level, 9), (amount_usd is not null) desc, id)) z
 where rn > 1;
update public.firm_fund_announcements a set archived = true, is_current = false, archive_reason = 'Duplicate of ' || m.reason
  from dupfix_20261123.s2_map m where a.id = m.id;
$sql$;
end $mig$;
