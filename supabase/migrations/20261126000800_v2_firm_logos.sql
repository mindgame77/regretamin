-- 25 Nov 2026 (founder: logos should be on record "with other information about company"; "the most efficient thing").
-- The website holds the logo pictures (assets/logos/f-<slug>.png) and publishes which firms have one in
-- https://regretamin.com/assets/logos/firms.json. This table is the database's copy of that list, and
-- v2_firm_logos_sync() refreshes it from that file, so nobody has to type firm names: run
--   select v2_firm_logos_sync();
-- after new logos are published. New table and function; nothing existing changes.
do $wrapci$
begin
  if to_regclass('public.firm_summary') is null then
    raise notice 'firm_summary is not here, nothing to do'; return;
  end if;

  create table if not exists public.v2_firm_logos (
    firm_id bigint primary key,
    slug text not null,
    file text not null,
    added_at timestamptz not null default now(),
    seen_at timestamptz not null default now());
  alter table public.v2_firm_logos enable row level security;
  comment on table public.v2_firm_logos is
    'Which firms have a logo on the website and where the picture is (path on regretamin.com). A copy of assets/logos/firms.json, refreshed by v2_firm_logos_sync().';

  execute $m1$
create or replace function public.v2_firm_logos_sync()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare r record; arr jsonb; n_site int; n_rows int; n_gone int;
begin
  select status, content into r from extensions.http_get('https://regretamin.com/assets/logos/firms.json');
  if r.status is distinct from 200 then return jsonb_build_object('ok', false, 'why', 'the file answered ' || coalesce(r.status::text, 'nothing')); end if;
  arr := r.content::jsonb;
  if jsonb_typeof(arr) <> 'array' or jsonb_array_length(arr) < 100 then return jsonb_build_object('ok', false, 'why', 'the file does not look like the list of firms'); end if;
  n_site := jsonb_array_length(arr);
  insert into v2_firm_logos (firm_id, slug, file)
  select distinct on (s.firm_id) s.firm_id, s.slug, 'assets/logos/f-' || s.slug || '.png'
  from jsonb_array_elements_text(arr) x(slug) join firm_summary s on s.slug = x.slug and s.listed
  order by s.firm_id
  on conflict (firm_id) do update set slug = excluded.slug, file = excluded.file, seen_at = now();
  -- a logo taken off the website leaves the record too
  delete from v2_firm_logos l where not exists (select 1 from jsonb_array_elements_text(arr) x(slug) where x.slug = l.slug);
  get diagnostics n_gone = row_count;
  select count(*) into n_rows from v2_firm_logos;
  return jsonb_build_object('ok', true, 'on_the_website', n_site, 'on_record', n_rows, 'removed', n_gone);
end
$function$
  $m1$;
  revoke all on function public.v2_firm_logos_sync() from public, anon, authenticated;
end $wrapci$;