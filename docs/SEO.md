# Firm page SEO (v2_firm_seo)

What it does
- Each firm gets a stored `<title>`, meta description, an indexable flag and a short fact list in `public.v2_firm_seo`.
- Title: `[Firm]: [Top sector] VC in [City] | Regretamin`. No sector: `[Firm]: VC in [City] | Regretamin`. No city: `[Firm]: [Top sector] VC | Regretamin`. Neither: `[Firm]: Venture Capital Firm | Regretamin`. Over 60 characters: the brand goes first, then the city, then the name alone. Top sector = the firm's first saved sector (`v2_firm_industries.position`). No numbers, dates or court cases.
- Description: `[Firm] is a [stage] VC firm in [City], founded [year]. [N] investments, latest [Mon YYYY]. Checked [Mon D, YYYY] against SEC, court and sanctions records.` Missing parts are left out; at most 160 characters (latest month goes first, then founded year, then the checked sentence).
- Indexable: live, research done (`firm_summary.researched`) and at least 3 of: city, sector, stage, founded year, investments, a team member. Not indexable: `noindex, follow` and not in the sitemap.
- Firm pages (`launch/edge/firm.mjs`, mirrored in `launch/build.py`): title/description from `firm_meta_seo`, JSON-LD WebPage + Organization + BreadcrumbList, the facts the page already shows in the first HTML (replaced by js/company.js on load, so the page looks the same), `<h1>` is the firm name only.
- Sitemap: `firm_seo_sitemap`, indexable firms only, 1,000 per file, `lastmod` = checked date. The checked date is `firm_summary.added` (the date the firm's data was added), since 20261118140000.
- `/investors/`: `launch/functions/investors/index.js` adds 100 plain firm links per page (`?page=N`) to the first HTML; js/firms.js redraws the list on load.

Why bot writes are not affected
- No trigger anywhere. Bot tables are only read with plain SELECTs (no row locks). Only `v2_firm_seo` is written.
- pg_cron `v2-firm-seo-refresh` every 10 minutes: `statement_timeout 30s`, `lock_timeout 1s`, one run at a time (advisory lock), 300 firms per run (new firms and changed check dates first, then the oldest-checked), rows being edited by hand are skipped (`SKIP LOCKED`). A full pass over all firms takes about 3 hours. A batch of 300 takes ~0.2 s on prod-sized data.

Hand edits
- `update v2_firm_seo set seo_title = '...', seo_description = '...', manual_edit = true where slug = '...';` The job keeps the text and still refreshes facts and the indexable flag. `manual_edit = false` hands it back to the template.

Go live (only when Alex says so)
1. Back up (`supabase db dump`). Apply `supabase/migrations/20261118120000_v2_firm_seo.sql` (creates the table, functions and the cron job; no backfill, takes well under a second).
2. Backfill in small batches, one statement each, a pause between: run `select public.v2_firm_seo_refresh(300);` 17 times (about 0.2 s each). Or just wait ~3 hours for the cron job.
3. Check: `select count(*) filter (where seo_indexable), count(*) from v2_firm_seo;` and open a few `/vc/<slug>/` pages.
4. Merge the site PR (Cloudflare deploy). Until the migration is applied, the site falls back to `firm_meta` / `firm_sitemap` and today's titles.
5. Submit `https://regretamin.com/sitemap.xml` in Google Search Console and Bing Webmaster Tools.

Rollback
- Site: revert the PR (or keep it: with the SQL objects gone it falls back to today's titles and sitemap).
- Database: `supabase/rollbacks/20261118120000_v2_firm_seo.sql` (unschedules the job, drops only the new table and functions).
