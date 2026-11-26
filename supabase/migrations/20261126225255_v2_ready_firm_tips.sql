-- "Am I ready to pitch?", the full research: tips about the firms to pitch (founder, 26 Nov 2026: "extra insights about some
-- investors ... if we have a button to pitch, it's even better"). New and read-only; nothing existing changes.
-- For each firm asked for: its apply link, its largest audience (platform, followers), its stated cheque size, and how many of
-- its deals of the last year it led (the numbers the signals already use).
do $wrapci$
begin
  if to_regclass('public.firm_summary') is null or to_regclass('public.v2_firm_contacts') is null or to_regclass('public.v2_social_accounts') is null or to_regclass('public.v2_firm_check_sizes') is null or to_regclass('public.v2_firm_signals') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_ready_firm_tips(p_slugs text[])
returns jsonb
language sql
stable security definer
set search_path to 'public'
as $body$
select coalesce(jsonb_agg(jsonb_build_object(
  'slug', fs.slug,
  'apply', (select c.apply_link from v2_firm_contacts c
            where c.firm_id = fs.firm_id and coalesce(c.is_current, true) and not coalesce(c.archived, false) and c.apply_link ~* '^https?://'
            order by c.created_at desc limit 1),
  'audience', (select jsonb_build_object('platform', s.platform, 'followers', s.follower_count, 'url', s.account_url)
            from v2_social_accounts s
            where s.firm_id = fs.firm_id and coalesce(s.is_current, true) and not coalesce(s.archived, false) and not coalesce(s.nothing_found, false)
              and s.follower_count is not null and s.account_url ~* '^https?://'
            order by s.follower_count desc limit 1),
  'cheque', (select c.amount_text from v2_firm_check_sizes c
            where c.firm_id = fs.firm_id and coalesce(c.is_current, true) and not coalesce(c.archived, false) and btrim(coalesce(c.amount_text, '')) <> ''
            order by c.max_usd nulls last, c.min_usd nulls last limit 1),
  'deals', g.deals_now, 'led', g.led_now)), '[]'::jsonb)
from firm_summary fs left join v2_firm_signals g on g.firm_id = fs.firm_id
where fs.listed and fs.slug = any(p_slugs[1:12])
$body$
$fn$;
  execute 'revoke all on function public.v2_ready_firm_tips(text[]) from public, anon';
  execute 'grant execute on function public.v2_ready_firm_tips(text[]) to authenticated, service_role';
  execute 'comment on function public.v2_ready_firm_tips(text[]) is ''Am I ready to pitch, full research: per firm its apply link, largest audience, stated cheque size and how many of its deals of the last year it led. Read-only.''';
end
$wrapci$;
