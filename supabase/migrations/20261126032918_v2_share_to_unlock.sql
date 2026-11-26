-- Share to unlock (founder, 25 Nov): a visitor posts their personal link on X, we see X open that link, they sign in,
-- and the locked content opens for their account. First locked content: the Pathfinders lists (first 3 firms are free).
--   v2_share_codes        one personal code per browser (anon id), later tied to the account that signs in
--   v2_share_start(anon)  gives this browser (or this account) its code, creating one the first time
--   v2_share_hit(code, x) called by the website when /p/<code> is opened; x = it was X opening it (its preview robot,
--                         or a visitor arriving from X). The first such visit marks the code as seen.
--   v2_share_state(anon)  seen or not, unlocked or not; signed in with a seen code that has no owner yet: takes it
--   v2_map_pathfinders    same answer as before, but only 3 firms per list until the asking account has unlocked
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_counted_places') is null or to_regclass('public.v2_top_firms') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $t$
create table if not exists public.v2_share_codes (
  code text primary key,
  anon_id uuid unique,
  user_id uuid unique,
  created_at timestamptz not null default now(),
  hits integer not null default 0,
  seen_at timestamptz,
  unlocked_at timestamptz
)
  $t$;
  execute 'alter table public.v2_share_codes enable row level security';
  execute 'comment on table public.v2_share_codes is ''Share to unlock: one personal code per browser, tied to an account at sign-in. Read and written only through v2_share_start, v2_share_hit, v2_share_state.''';
  execute $fn$
create or replace function public.v2_share_state(p_anon uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $body$
declare r public.v2_share_codes; uid uuid := auth.uid();
begin
  if uid is not null then select * into r from v2_share_codes where user_id = uid; end if;
  if r.code is null and p_anon is not null then
    select * into r from v2_share_codes where anon_id = p_anon;
    if r.code is not null and uid is not null and r.user_id is null and r.seen_at is not null then
      update v2_share_codes set user_id = uid, unlocked_at = now() where code = r.code and user_id is null;
      r.user_id := uid;
    end if;
  end if;
  return jsonb_build_object('code', r.code, 'seen', r.seen_at is not null,
    'unlocked', r.seen_at is not null and r.user_id is not null and uid is not null and r.user_id = uid);
end $body$
  $fn$;
  execute $fn$
create or replace function public.v2_share_start(p_anon uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $body$
declare c text; uid uuid := auth.uid(); n int := 0;
begin
  if p_anon is null then return jsonb_build_object('code', null, 'seen', false, 'unlocked', false); end if;
  if uid is not null then select code into c from v2_share_codes where user_id = uid; end if;
  if c is null then select code into c from v2_share_codes where anon_id = p_anon; end if;
  while c is null and n < 8 loop
    n := n + 1;
    c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    begin
      insert into v2_share_codes (code, anon_id) values (c, p_anon);
    exception when unique_violation then
      c := null;
      select code into c from v2_share_codes where anon_id = p_anon;
    end;
  end loop;
  return v2_share_state(p_anon);
end $body$
  $fn$;
  execute $fn$
create or replace function public.v2_share_hit(p_code text, p_from_x boolean default false)
returns void language sql security definer set search_path to 'public' as $body$
  update v2_share_codes
     set hits = hits + 1, seen_at = case when coalesce(p_from_x, false) and seen_at is null then now() else seen_at end
   where code = upper(left(coalesce(p_code, ''), 12))
$body$
  $fn$;
  execute 'revoke all on function public.v2_share_state(uuid) from public';
  execute 'revoke all on function public.v2_share_start(uuid) from public';
  execute 'revoke all on function public.v2_share_hit(text, boolean) from public';
  execute 'grant execute on function public.v2_share_state(uuid) to anon, authenticated';
  execute 'grant execute on function public.v2_share_start(uuid) to anon, authenticated';
  execute 'grant execute on function public.v2_share_hit(text, boolean) to anon, authenticated';
  execute $fn$
create or replace function public.v2_map_pathfinders(p_from date default '2021-01-01'::date, p_to date default null, p_stages text[] default null, p_sectors text[] default null, p_level text default null, p_place text default null, p_max_deals integer default 50)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
me as materialized (  -- has the asking account unlocked (posted its link, seen by us, signed in)? If not: 3 firms per list
  select exists (select 1 from v2_share_codes s where s.user_id = auth.uid() and s.seen_at is not null) as ok
),
top as materialized (
  select t.firm_id from v2_top_firms t
  where t.list_year = (select max(list_year) from v2_top_firms) and t.world_rank is not null
),
small as materialized (  -- not on the Top 100 list, and at most p_max_deals deals since 2021 (no limit when null)
  select d.firm_id from v2_deals d
  where d.is_current and d.shown and d.deal_date >= date '2021-01-01' and d.deal_date <= current_date
    and not exists (select 1 from top where top.firm_id = d.firm_id)
  group by 1 having p_max_deals is null or count(*) <= p_max_deals
),
early as materialized (  -- a firm's first dated deal in each startup
  select d.firm_id, d.startup_id, min(d.deal_date) as d
  from v2_deals d join small using (firm_id)
  where d.is_current and d.shown and d.deal_date is not null and d.deal_date_precision <> 'year' and d.deal_date <= current_date
  group by 1, 2
),
later as materialized (  -- a Top 100 firm's first dated deal in a startup, when it falls in the period, stage and sector asked for
  select x.firm_id, x.startup_id, x.d
  from (select distinct on (d.firm_id, d.startup_id) d.firm_id, d.startup_id, d.deal_date as d, d.round::text as round
        from v2_deals d join top using (firm_id)
        where d.is_current and d.shown and d.deal_date is not null and d.deal_date_precision <> 'year' and d.deal_date <= current_date
        order by d.firm_id, d.startup_id, d.deal_date) x
  left join stg on stg.round = x.round
  where x.d >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01') and x.d <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
fol as materialized (
  select a.firm_id as early, a.startup_id, b.firm_id as later
  from early a join later b on b.startup_id = a.startup_id and b.d > a.d
),
per as materialized (select f.early as firm_id, count(distinct f.startup_id) as n from fol f group by 1),
tops as materialized (select f.early as firm_id, f.later, count(distinct f.startup_id) as c from fol f group by 1, 2),
pl as materialized (  -- where a firm sits, as each zoom of the map names it
  select 'world'::text as l, p.region as p, p.firm_id from v2_map_counted_places p where p.region is not null
  union all
  select p.level, p.area, p.firm_id from v2_map_counted_places p where p.level in ('us', 'eu') and p.area is not null
),
ranked as materialized (
  select pl.l, pl.p, per.firm_id, per.n, fs.slug, fs.display_name as name,
         row_number() over (partition by pl.l order by per.n desc, fs.display_name) as k,
         row_number() over (partition by pl.l, pl.p order by per.n desc, fs.display_name) as kp
  from per join pl using (firm_id) join firm_summary fs on fs.firm_id = per.firm_id
),
shown as (
  select r.l, r.p, r.k, r.kp, jsonb_build_array(r.slug, r.name, r.n,
      coalesce((select jsonb_agg(jsonb_build_array(z.nm, z.c) order by z.c desc, z.nm)
                from (select n2.display_name as nm, t.c from tops t join firm_summary n2 on n2.firm_id = t.later
                      where t.firm_id = r.firm_id order by t.c desc, n2.display_name limit 3) z), '[]'::jsonb), r.p) as j
  from ranked r cross join me
  where (p_place is null and r.k <= case when me.ok then 30 else 3 end)
     or (p_place is not null and r.l = p_level and r.p = p_place and r.kp <= case when me.ok then 30 else 3 end)
)
select case when p_place is null then jsonb_build_object(
    'locked', not (select ok from me),
    'places', coalesce((select jsonb_agg(jsonb_build_object('l', x.l, 'p', x.p, 'f', x.f, 'd', x.d))
                        from (select l, p, count(*) as f, sum(n) as d from ranked group by 1, 2) x), '[]'::jsonb),
    'totals', coalesce((select jsonb_object_agg(x.l, jsonb_build_object('firms', x.f, 'follows', x.d))
                        from (select l, count(*) as f, sum(n) as d from ranked group by 1) x), '{}'::jsonb),
    'lists', coalesce((select jsonb_object_agg(x.l, x.j) from (select l, jsonb_agg(j order by k) as j from shown group by 1) x), '{}'::jsonb))
  else jsonb_build_object(
    'locked', not (select ok from me),
    'firms', (select count(*) from ranked r where r.l = p_level and r.p = p_place),
    'list', coalesce((select jsonb_agg(j order by kp) from shown), '[]'::jsonb)) end
$body$
  $fn$;
end $wrapci$;