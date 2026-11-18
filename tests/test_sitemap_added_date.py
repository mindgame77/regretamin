"""Sitemap lastmod and stale SEO check dates use firm_summary.added."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261118250000_sitemap_added_date.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()


def test_sitemap_reads_added():
    assert "coalesce(fs.added::date, s.last_checked_date) as lastmod" in MIG
    assert "left join firm_summary fs on fs.firm_id = s.firm_id" in MIG
    assert "s.last_checked_date as lastmod" not in MIG


def test_only_stale_seo_rows_are_recomputed():
    assert "from v2_firm_seo_compute(array(" in MIG
    assert "where s.last_checked_date is distinct from fs.added::date" in MIG
    assert "create trigger" not in MIG.lower()
    assert "update public." not in MIG.lower()


def test_rollback_restores_cached_lastmod():
    assert "s.last_checked_date as lastmod" in UNDO
    assert "fs.added::date" not in UNDO
