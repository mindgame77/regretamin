-- Step 1 (2026-11-23, Alex OK 1:24 PM PT): clean up duplicate deals with NO round (blank stage),
-- which the 11-19 cleanup (v2_deal_cleanup_duplicates, round is not null only) never looked at.
-- Same mechanism and log: v2_deal_cleanup_log (new run id from v2_deal_cleanup_run_seq), fills empty fields
-- on the kept deal (recorded in v2_deal_fill_sources), copy archived 'Duplicate of deal N'.
-- Undo: select public.v2_deal_cleanup_undo(<run_id>);
-- Group: same firm family + startup, live (is_current, not archived), round IS NULL.
-- Kept: shown first, then oldest deal number. A deal is a copy of a kept deal only when:
--   same year (if either date is year-only) or dates within 31 days (both precise), or both dates missing;
--   round amounts the same (both missing or equal); firm amounts equal or one missing; round extensions not two different values;
--   same currency when both have one.
-- The kept deal's shown flag is never touched (shown logic unchanged); a copy gets archived/is_current=false/shown=false
-- exactly like the 11-19 cleanup.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: deal_blank_round_duplicates_cleanup skipped';
    return;
  end if;
  execute $ci_body$
create or replace function public.v2_deal_cleanup_blank_round(p_apply boolean default false, p_sample int default 10, p_startups bigint[] default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public
 set statement_timeout = '600s'
as $fn$
declare
  run bigint := CASE WHEN p_apply THEN nextval('public.v2_deal_cleanup_run_seq') END;
  g record; d public.v2_deals; k public.v2_deals; kept public.v2_deals[]; hit int;
  fill jsonb; n_groups int := 0; n_skipped int := 0; n_copies int := 0; n_kept int := 0; n_filled int := 0;
  sample jsonb := '[]'; prec_rank jsonb := '{"year":1,"year+month":2,"full date":3}';
  pairs jsonb; cols text; c jsonb; same_date boolean;
begin
  drop table if exists _bc; drop table if exists _bg;
  create temp table _bc on commit drop as
    select x.deal_id, x.startup_id, public.v2_firm_root(x.firm_id) as root, coalesce(x.shown,false) sh
      from public.v2_deals x
     where not x.archived and x.is_current and x.round is null and x.startup_id is not null
       and (p_startups is null or x.startup_id = any(p_startups));
  create temp table _bg on commit drop as
    select root, startup_id, array_agg(deal_id order by sh desc, deal_id) ids
      from _bc group by 1,2 having count(*) > 1;

  for g in select * from _bg order by root, startup_id loop
    if exists (select 1 from public.v2_checker_queue q
                where q.row_id = any(g.ids) and q.table_name = 'v2_deals' and q.new_value->>'_deal_action' = 'remove'
                  and q.new_value#>>'{_deal_receipt,active}' = 'true') then
      n_skipped := n_skipped + 1; continue;
    end if;
    kept := '{}'; pairs := '[]';
    for i in 1 .. cardinality(g.ids) loop
      select * into d from public.v2_deals where deal_id = g.ids[i];
      hit := null;
      for j in 1 .. coalesce(cardinality(kept), 0) loop
        k := kept[j];
        same_date := case
          when k.deal_date is null and d.deal_date is null then true
          when k.deal_date is null or d.deal_date is null then false
          when coalesce(k.deal_date_precision,'full date') = 'year' or coalesce(d.deal_date_precision,'full date') = 'year'
            then extract(year from k.deal_date) = extract(year from d.deal_date)
          when coalesce(k.deal_date_precision,'full date') = 'year+month' or coalesce(d.deal_date_precision,'full date') = 'year+month'
            then date_trunc('month', k.deal_date) = date_trunc('month', d.deal_date)
          else abs(k.deal_date - d.deal_date) <= 31 end;
        if same_date
           and k.round_amount is not distinct from d.round_amount
           and (k.firm_amount is null or d.firm_amount is null or k.firm_amount = d.firm_amount)
           and (k.amount_currency is null or d.amount_currency is null or k.amount_currency = d.amount_currency)
           and not (nullif(lower(btrim(k.round_extension)),'') is not null and nullif(lower(btrim(d.round_extension)),'') is not null
                    and lower(btrim(k.round_extension)) <> lower(btrim(d.round_extension))) then
          hit := j; exit;
        end if;
      end loop;
      if hit is null then kept := kept || d; continue; end if;
      k := kept[hit]; fill := '{}';
      if k.round_extension is null and nullif(btrim(d.round_extension),'') is not null then
        fill := fill || jsonb_build_object('round_extension', d.round_extension); k.round_extension := d.round_extension; end if;
      if d.deal_date is not null and k.deal_date is not null
         and (prec_rank->>coalesce(d.deal_date_precision,'full date'))::int > (prec_rank->>coalesce(k.deal_date_precision,'full date'))::int then
        fill := fill || jsonb_build_object('deal_date', d.deal_date, 'deal_date_precision', d.deal_date_precision);
        k.deal_date := d.deal_date; k.deal_date_precision := d.deal_date_precision; end if;
      if k.round_amount is null and d.round_amount is not null and d.amount_currency is not null
         and (k.amount_currency is null or k.amount_currency = d.amount_currency)
         and (k.firm_amount is null or k.firm_amount <= d.round_amount) then
        fill := fill || jsonb_build_object('round_amount', d.round_amount, 'amount_currency', d.amount_currency, 'amount_approximate', d.amount_approximate);
        k.round_amount := d.round_amount; k.amount_currency := d.amount_currency; k.amount_approximate := d.amount_approximate; end if;
      if k.firm_amount is null and d.firm_amount is not null and d.amount_currency is not null
         and coalesce(k.amount_currency, d.amount_currency) = d.amount_currency
         and d.firm_amount <= coalesce(k.round_amount, d.firm_amount) then
        fill := fill || jsonb_build_object('firm_amount', d.firm_amount, 'amount_currency', d.amount_currency);
        k.firm_amount := d.firm_amount; k.amount_currency := d.amount_currency; end if;
      if k.lead is null and d.lead = 'yes' then fill := fill || jsonb_build_object('lead', 'yes'); k.lead := 'yes'; end if;
      kept[hit] := k;
      pairs := pairs || jsonb_build_object('kept', k.deal_id, 'copy', d.deal_id, 'fill', fill, 'copy_row', to_jsonb(d));
    end loop;
    if jsonb_array_length(pairs) = 0 then continue; end if;
    n_groups := n_groups + 1;
    n_copies := n_copies + jsonb_array_length(pairs);
    n_kept := n_kept + (select count(distinct x->>'kept') from jsonb_array_elements(pairs) x);
    n_filled := n_filled + (select count(distinct x->>'kept') from jsonb_array_elements(pairs) x where x->'fill' <> '{}');
    if jsonb_array_length(sample) < p_sample then
      sample := sample || jsonb_build_object('firm_id', g.root, 'startup_id', g.startup_id,
        'keep_and_archive', (select jsonb_agg(jsonb_build_object('keep', x->'kept', 'archive', x->'copy', 'fill', x->'fill')) from jsonb_array_elements(pairs) x));
    end if;
    if p_apply then
      for c in select * from jsonb_array_elements(pairs) loop
        insert into public.v2_deal_cleanup_log (run_id, kept_deal_id, copy_deal_id, kept_before, copy_before, filled)
          select run, (c->>'kept')::bigint, (c->>'copy')::bigint, to_jsonb(kd), c->'copy_row', c->'fill'
            from public.v2_deals kd where kd.deal_id = (c->>'kept')::bigint;
        if c->'fill' <> '{}' then
          select string_agg(format('%I', key), ',') into cols from jsonb_object_keys(c->'fill') key;
          execute format('update public.v2_deals t set (%s) = (select %s from jsonb_populate_record(null::public.v2_deals, $1)) where t.deal_id = $2',
                         cols, cols) using c->'fill', (c->>'kept')::bigint;
          insert into public.v2_deal_fill_sources (deal_id, submission_id, fields, source)
            values ((c->>'kept')::bigint, (c#>>'{copy_row,submission_id}')::bigint,
                    to_jsonb(array(select key from jsonb_object_keys(c->'fill') key order by key)),
                    (select coalesce(jsonb_object_agg(key, value), '{}') from jsonb_each(c->'copy_row')
                      where key in ('source_url','source_level','source_date','source_date_precision','source_date_is_found_date','source_type','source_owner','archived_url')))
            on conflict do nothing;
          if found then
            update public.v2_deal_cleanup_log set fill_source_added = true where run_id = run and copy_deal_id = (c->>'copy')::bigint;
          end if;
        end if;
        update public.v2_deals set archived = true, is_current = false, shown = false,
               archive_reason = 'Duplicate of deal ' || (c->>'kept')
         where deal_id = (c->>'copy')::bigint;
        insert into public.v2_change_log (actor, firm_id, box, table_name, row_id, old_value, new_value, result)
          values ('deal-dupes-cleanup-20261123', (c#>>'{copy_row,firm_id}')::bigint, '', 'v2_deals', (c->>'copy')::bigint,
                  c->'copy_row', jsonb_build_object('note', 'Duplicate of deal ' || (c->>'kept'), 'run_id', run, 'filled_on_kept', c->'fill'), 'Accepted');
      end loop;
    end if;
  end loop;
  return jsonb_build_object('applied', p_apply, 'run_id', run, 'groups_with_copies', n_groups, 'copies_to_archive', n_copies,
    'kept_deals', n_kept, 'kept_deals_getting_fills', n_filled, 'groups_skipped_removed_deal', n_skipped, 'sample', sample);
end
$fn$;
revoke execute on function public.v2_deal_cleanup_blank_round(boolean, int, bigint[]) from public, anon, authenticated;
-- Step 1 apply: backup, then run the blank-round deal cleanup.
create schema if not exists deal_dupes_20261123;
create table deal_dupes_20261123.v2_deals_step1 as
  select x.* from public.v2_deals x
   where not x.archived and x.is_current and x.round is null and x.startup_id is not null
     and (public.v2_firm_root(x.firm_id), x.startup_id) in (
       select public.v2_firm_root(firm_id), startup_id from public.v2_deals
        where not archived and is_current and round is null and startup_id is not null group by 1,2 having count(*) > 1);
create table deal_dupes_20261123.step1_result as select public.v2_deal_cleanup_blank_round(true, 20) as result, now() as ran_at;
$ci_body$;
end
$ci_wrap$;
