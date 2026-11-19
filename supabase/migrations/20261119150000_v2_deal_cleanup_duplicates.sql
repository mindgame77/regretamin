-- v2 deals: one-time cleanup of old duplicate deals (one deal number per round).
-- Built on Alex's OK (2026-11-19, t7570u). PR only. This migration only ADDS the tools; it changes no rows.
-- Step 1 (dry run, changes nothing):   select public.v2_deal_cleanup_duplicates(false, 10);
-- Step 2 (only on Alex's OK):          select public.v2_deal_cleanup_duplicates(true);
-- Undo a run:                          select public.v2_deal_cleanup_undo(<run_id>);   -- or null for all runs
-- What a run does, per live duplicate group (same firm family + startup + stage, current deals):
--   keeps the oldest deal number, fills only its empty fields from the copies (extension, date or a more
--   precise date, amount, firm amount, lead), records each copy's source in v2_deal_fill_sources, and archives
--   the copies with archive_reason 'Duplicate of deal N'. Deals more than about a year apart, with two different
--   round extensions, or (Bridge/Debt/Grant/Other) two different amounts stay separate rounds.
--   Groups with a removed deal are skipped. Every change is logged in v2_deal_cleanup_log with the full rows
--   before, so the undo puts them back exactly.
-- Rollback: supabase/rollbacks/20261119150000_v2_deal_cleanup_duplicates.sql
-- The v2 schema is not created by repo migrations. On a database without it (CI) this is a no-op.

do $mig$
begin
  if to_regclass('public.v2_deals') is null
     or to_regclass('public.v2_deal_fill_sources') is null
     or to_regprocedure('public.v2_deal_dates_conflict(date, text, date, text)') is null then
    raise notice 'v2 tables missing, skipped';
    return;
  end if;

  execute $ddl$
create table if not exists public.v2_deal_cleanup_log (
  log_id bigint generated always as identity primary key,
  run_id bigint not null,
  kept_deal_id bigint not null references public.v2_deals(deal_id),
  copy_deal_id bigint not null references public.v2_deals(deal_id),
  kept_before jsonb not null,
  copy_before jsonb not null,
  filled jsonb not null default '{}',
  fill_source_added boolean not null default false,
  created_at timestamptz not null default now(),
  undone_at timestamptz
)
$ddl$;

  execute $ddl$
alter table public.v2_deal_cleanup_log enable row level security
$ddl$;

  execute $ddl$
revoke all on public.v2_deal_cleanup_log from public, anon, authenticated
$ddl$;

  execute $ddl$
create sequence if not exists public.v2_deal_cleanup_run_seq
$ddl$;

  execute $ddl$
-- Groups the live duplicate deals and (only when p_apply) merges each copy into the oldest deal number.
-- A group: same firm family (merged_into_firm_id followed) + startup + stage, live (not archived, current).
-- Inside a group, deals are taken oldest deal_id first; a deal joins the first kept deal it matches
-- (no clear date conflict, round_extension not two different values, Bridge/Debt/Grant/Other not two different amounts),
-- otherwise it is kept as its own round. Groups with a removed deal are skipped.
-- The kept deal gets empty fields only (extension, date or a more precise date, amount, firm amount, lead);
-- each copy's source is recorded in v2_deal_fill_sources; the copy is archived 'Duplicate of deal N'.
-- Returns counts and a sample. p_apply = false (default) changes nothing.
create or replace function public.v2_deal_cleanup_duplicates(p_apply boolean default false, p_sample int default 10)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public
 set statement_timeout = '600s'
as $fn$
declare
  run bigint := CASE WHEN p_apply THEN nextval('public.v2_deal_cleanup_run_seq') END;
  g record; d public.v2_deals; k public.v2_deals; kept public.v2_deals[]; i int; hit int;
  fill jsonb; kfill jsonb; fields text[];
  n_groups int := 0; n_skipped int := 0; n_copies int := 0; n_kept int := 0; n_filled_kept int := 0; n_split int := 0;
  sample jsonb := '[]'; gsample jsonb; prec_rank jsonb := '{"year":1,"year+month":2,"full date":3}';
  kept_fill jsonb := '{}';  -- deal_id -> accumulated fill
  kept_row jsonb := '{}';   -- deal_id -> working row
  pairs jsonb;              -- list of {kept, copy, fill}
  cols text; c jsonb;
begin
  drop table if exists _c; drop table if exists _g;
  create temp table _c on commit drop as
    select x.deal_id, x.startup_id, x.round, public.v2_firm_root(x.firm_id) as root
      from public.v2_deals x
     where not x.archived and x.is_current and x.round is not null;
  create temp table _g on commit drop as
    select root, startup_id, round, array_agg(deal_id order by deal_id) ids
      from _c group by 1,2,3 having count(*) > 1;

  for g in select * from _g order by root, startup_id, round loop
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
        if not (nullif(lower(btrim(k.round_extension)),'') is not null and nullif(lower(btrim(d.round_extension)),'') is not null
                and lower(btrim(k.round_extension)) <> lower(btrim(d.round_extension)))
           and not public.v2_deal_dates_conflict(k.deal_date, k.deal_date_precision, d.deal_date, d.deal_date_precision)
           and not (k.round in ('Bridge','Debt','Grant','Other') and k.round_amount is not null and d.round_amount is not null
                    and k.round_amount <> d.round_amount) then
          hit := j; exit;
        end if;
      end loop;
      if hit is null then
        kept := kept || d;
        continue;
      end if;
      -- fill the kept deal's empty fields from this copy (working copy of the kept row)
      k := kept[hit]; fill := '{}';
      if k.round_extension is null and nullif(btrim(d.round_extension),'') is not null then
        fill := fill || jsonb_build_object('round_extension', d.round_extension); k.round_extension := d.round_extension; end if;
      if d.deal_date is not null and (k.deal_date is null
           or ((prec_rank->>d.deal_date_precision)::int > (prec_rank->>k.deal_date_precision)::int
               and ((k.deal_date_precision = 'year' and extract(year from k.deal_date) = extract(year from d.deal_date))
                 or (k.deal_date_precision = 'year+month' and date_trunc('month', k.deal_date) = date_trunc('month', d.deal_date))))) then
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
      if k.lead is null and d.lead = 'yes' then
        fill := fill || jsonb_build_object('lead', 'yes'); k.lead := 'yes'; end if;
      kept[hit] := k;
      pairs := pairs || jsonb_build_object('kept', k.deal_id, 'copy', d.deal_id, 'fill', fill,
                                           'copy_row', to_jsonb(d));
    end loop;
    if jsonb_array_length(pairs) = 0 then continue; end if;   -- every deal in the group is its own round
    n_groups := n_groups + 1;
    n_copies := n_copies + jsonb_array_length(pairs);
    n_kept := n_kept + (select count(distinct x->>'kept') from jsonb_array_elements(pairs) x);
    if cardinality(kept) > 1 then n_split := n_split + 1; end if;
    n_filled_kept := n_filled_kept + (select count(distinct x->>'kept') from jsonb_array_elements(pairs) x where x->'fill' <> '{}');
    if jsonb_array_length(sample) < p_sample then
      sample := sample || jsonb_build_object('firm_id', g.root, 'startup_id', g.startup_id, 'round', g.round,
        'deals', (select jsonb_agg(jsonb_build_object('deal_id', x.deal_id, 'firm_id', x.firm_id, 'date', x.deal_date,
                    'amount', x.round_amount, 'lead', x.lead) order by x.deal_id) from public.v2_deals x where x.deal_id = any(g.ids)),
        'keep_and_archive', (select jsonb_agg(jsonb_build_object('keep', x->'kept', 'archive', x->'copy', 'fill', x->'fill')) from jsonb_array_elements(pairs) x));
    end if;
    if p_apply then
      for c in select * from jsonb_array_elements(pairs) loop
        -- kept before (fresh) and the fill for this copy
        insert into public.v2_deal_cleanup_log (run_id, kept_deal_id, copy_deal_id, kept_before, copy_before, filled)
          select run, (c->>'kept')::bigint, (c->>'copy')::bigint, to_jsonb(kd), c->'copy_row', c->'fill'
            from public.v2_deals kd where kd.deal_id = (c->>'kept')::bigint;
        if c->'fill' <> '{}' then
          select string_agg(format('%I', key), ',') into cols from jsonb_object_keys(c->'fill') key;
          execute format('update public.v2_deals t set (%s) = (select %s from jsonb_populate_record(null::public.v2_deals, $1)) where t.deal_id = $2',
                         cols, cols) using c->'fill', (c->>'kept')::bigint;
          update public.v2_deals set shown = (deal_date is not null or round_amount is not null) where deal_id = (c->>'kept')::bigint;
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
      end loop;
    end if;
  end loop;

  return jsonb_build_object('applied', p_apply, 'run_id', run,
    'groups_with_copies', n_groups, 'copies_to_archive', n_copies, 'kept_deals', n_kept,
    'kept_deals_getting_fills', n_filled_kept, 'groups_split_into_separate_rounds', n_split,
    'groups_skipped_removed_deal', n_skipped, 'sample', sample);
end
$fn$
$ddl$;

  execute $ddl$
-- Undo one cleanup run (or all with null): put kept deals and copies back exactly as they were.
create or replace function public.v2_deal_cleanup_undo(p_run_id bigint default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path = public
 set statement_timeout = '600s'
as $fn$
declare l record; cols text; r jsonb; n int := 0;
begin
  for l in select * from public.v2_deal_cleanup_log
            where undone_at is null and (p_run_id is null or run_id = p_run_id)
            order by log_id desc loop
    r := l.copy_before - array['deal_id','row_id','source_url_norm','archived_url_norm','created_at'];
    select string_agg(format('%I', key), ',') into cols from jsonb_object_keys(r) key;
    execute format('update public.v2_deals t set (%s) = (select %s from jsonb_populate_record(null::public.v2_deals, $1)) where t.deal_id = $2', cols, cols)
      using r, l.copy_deal_id;
    r := l.kept_before - array['deal_id','row_id','source_url_norm','archived_url_norm','created_at'];
    select string_agg(format('%I', key), ',') into cols from jsonb_object_keys(r) key;
    execute format('update public.v2_deals t set (%s) = (select %s from jsonb_populate_record(null::public.v2_deals, $1)) where t.deal_id = $2', cols, cols)
      using r, l.kept_deal_id;
    if l.fill_source_added then
      delete from public.v2_deal_fill_sources where deal_id = l.kept_deal_id and submission_id = (l.copy_before->>'submission_id')::bigint;
    end if;
    update public.v2_deal_cleanup_log set undone_at = now() where log_id = l.log_id;
    n := n + 1;
  end loop;
  return jsonb_build_object('undone_pairs', n);
end
$fn$
$ddl$;

  execute $ddl$
revoke execute on function public.v2_deal_cleanup_duplicates(boolean, int) from public, anon, authenticated
$ddl$;

  execute $ddl$
revoke execute on function public.v2_deal_cleanup_undo(bigint) from public, anon, authenticated
$ddl$;

end
$mig$;
