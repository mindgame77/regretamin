-- Map "Hot right now": two more choices in the firms list.
--   'fresh' = firms that raised a fund in the last 12 months (fund news or a recorded fund close).
--   'first' = "New investors": the firm's first deal EVER falls in the period, whatever sector is picked
--             (founder, 23 Nov: one meaning, not "first deal in this sector").
-- Additive: 'top', 'focused' and 'new' answer exactly as before, so the live site is unchanged until the
-- page starts sending the new words. 'new' is no longer sent by the new page and can be removed later.
do $wrapci$
declare s text; n text; f text; sig text;
begin
  if to_regclass('public.v2_funds') is null or to_regclass('public.firm_fund_announcements') is null
     or to_regprocedure('public.v2_map_hot(text,integer,text[],text[])') is null then
    raise notice 'map functions or fund tables not present, skipping';
    return;
  end if;

  execute $fn$
    create or replace function public.v2_fresh_fund_firms()
    returns setof bigint language sql stable security definer set search_path to 'public' as $body$
      select firm_id from firm_fund_announcements
      where firm_id is not null and coalesce(is_current, true) and not coalesce(archived, false)
        and announced_on > current_date - 365 and announced_on <= current_date
      union
      select firm_id from v2_funds
      where firm_id is not null and coalesce(is_current, true) and not coalesce(archived, false)
        and closed_on > current_date - 365 and closed_on <= current_date
    $body$
  $fn$;
  execute 'revoke all on function public.v2_fresh_fund_firms() from public, anon, authenticated';
  execute $c$comment on function public.v2_fresh_fund_firms() is 'Firms that raised a fund in the last 12 months. Read only by the map functions (firms choice "Fresh funds").'$c$;

  foreach sig in array array[
    'public.v2_map_firm_ids(text,text,text,date,date,text[],text[])',
    'public.v2_map_firms(text,text,text,date,date,text[],text[],integer)',
    'public.v2_map_hot(text,integer,text[],text[])',
    'public.v2_map_hot_detail(text,text,text,integer,text[],text[])'] loop
    if to_regprocedure(sig) is null then raise exception '% not found', sig; end if;
    s := pg_get_functiondef(sig::regprocedure);
    if position('''fresh''' in s) > 0 then continue; end if;  -- already done
    n := replace(s, $a$p_firms in ('top', 'focused', 'new')$a$, $b$p_firms in ('top', 'focused', 'new', 'first', 'fresh')$b$);
    if n = s then raise exception '%: list of choices not found', sig; end if;

    if sig like '%v2_map_firm_ids%' or sig like '%v2_map_firms%' then
      f := n;
      n := replace(n, $a$    and (cfg.mode <> 'new' or ($a$,
                      $b$    and (cfg.mode <> 'fresh' or p.firm_id in (select v2_fresh_fund_firms()))
    and (cfg.mode not in ('new', 'first') or ($b$);
      if n = f then raise exception '%: new-firms rule not found', sig; end if;
      f := n;
      n := replace(n, $a$x.deal_date is not null and (p_sectors is null or exists ($a$,
                      $b$x.deal_date is not null and (p_sectors is null or cfg.mode = 'first' or exists ($b$);
      if n = f then raise exception '%: first-deal sector rule not found', sig; end if;
    else
      f := n;
      n := replace(n, $a$else 'all' end mode),$a$,
                      $b$else 'all' end mode),
fresh as materialized (select f.firm_id from v2_fresh_fund_firms() f(firm_id) where (select mode from cfg) = 'fresh'),$b$);
      if n = f then raise exception '%: cfg not found', sig; end if;
      f := n;
      n := replace(n, $a$where (select mode from cfg) = 'new' and$a$, $b$where (select mode from cfg) in ('new', 'first') and$b$);
      if n = f then raise exception '%: first-deal list not found', sig; end if;
      f := n;
      n := regexp_replace(n, $a$(x\.deal_date is not null\s+and \(p_sectors is null) or exists \($a$, $b$\1 or (select mode from cfg) = 'first' or exists ($b$);
      if n = f then raise exception '%: first-deal sector rule not found', sig; end if;
      f := n;
      if sig like '%v2_map_hot_detail%' then
        n := replace(n, $a$and (cfg.mode <> 'new' or fst.fdate is not null)$a$,
                        $b$and (cfg.mode not in ('new', 'first') or fst.fdate is not null)
    and (cfg.mode <> 'fresh' or d.firm_id in (select firm_id from fresh))$b$);
      else
        n := replace(n, $a$and (cfg.mode <> 'new' or exists (select 1 from fst$a$,
                        $b$and (cfg.mode <> 'fresh' or d.firm_id in (select firm_id from fresh))
    and (cfg.mode not in ('new', 'first') or exists (select 1 from fst$b$);
      end if;
      if n = f then raise exception '%: deal filter not found', sig; end if;
      n := replace(n, $a$cfg.mode <> 'new' or $a$, $b$cfg.mode not in ('new', 'first') or $b$);
    end if;
    if position('<> ''new''' in n) > 0 then raise exception '%: an old "new" rule is left', sig; end if;
    execute n;
  end loop;
end $wrapci$;
