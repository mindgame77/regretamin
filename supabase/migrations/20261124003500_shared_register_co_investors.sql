-- co_investors on a saved round: listed firms join the round's event; unknown names are stored as noted text only (never a new firm).
create or replace function public.v2_event_add_co_investors(p_key_id uuid, p_submission_id bigint, p_names jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare bk public.v2_bot_keys; e bigint; own bigint; x jsonb; t text; fid bigint; n int;
        matched jsonb := '[]'; noted jsonb := '[]';
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot'); end if;
  if not exists (select 1 from public.v2_research_submissions s where s.submission_id = p_submission_id and s.bot_key_id = bk.bot_key_id) then
    return jsonb_build_object('ok', false, 'error', 'submission not found for this bot');
  end if;
  select d.event_id, d.firm_id into e, own from public.v2_deals d
   where d.submission_id = p_submission_id and d.is_current and not d.archived and d.event_id is not null order by d.deal_id desc limit 1;
  if e is null then return jsonb_build_object('ok', false, 'error', 'round not saved yet, so co_investors were not added'); end if;
  for x in select * from jsonb_array_elements(coalesce(p_names, '[]')) limit 20 loop
    fid := null; t := btrim(x #>> '{}');
    if t is null or t = '' then continue; end if;
    if t ~ '^\d{1,12}$' then
      select coalesce(f.merged_into_firm_id, f.firm_id) into fid from public.v2_firms f where f.firm_id = t::bigint;
    else
      select count(distinct coalesce(f.merged_into_firm_id, f.firm_id)), min(coalesce(f.merged_into_firm_id, f.firm_id)) into n, fid
        from public.v2_firms f
       where not coalesce(f.archived, false)
         and lower(t) in (lower(btrim(f.display_name::text)), lower(btrim(f.short_name::text)), lower(btrim(f.legal_name::text)));
      if n <> 1 then fid := null; end if;
    end if;
    if fid is not null then
      if fid is distinct from own then
        insert into public.v2_event_firms (event_id, firm_id) values (e, fid) on conflict (event_id, firm_id) where firm_id is not null do nothing;
      end if;
      matched := matched || to_jsonb(fid);
    else
      insert into public.v2_event_firms (event_id, noted_name) values (e, left(t, 200)) on conflict (event_id, lower(btrim(noted_name))) where firm_id is null do nothing;
      noted := noted || to_jsonb(left(t, 200));
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'event_id', e, 'matched_firm_ids', matched, 'noted_only', noted);
end $$;
revoke all on function public.v2_event_add_co_investors(uuid, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.v2_event_add_co_investors(uuid, bigint, jsonb) to service_role;
