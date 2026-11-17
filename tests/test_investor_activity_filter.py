"""Activity status filter for the investors list. The migration is not applied here."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261117120000_investor_activity_filter.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261117120000_investor_activity_filter.sql").read_text(encoding="utf-8")
JS = (ROOT / "launch/js/firms.js").read_text(encoding="utf-8")
SIG = "public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])"


def test_migration_reuses_the_existing_activity_rank_and_keeps_the_timeout():
    assert "set statement_timeout to '5s'" in MIG
    assert "statement_timeout to '8s'" not in MIG
    assert "statement_timeout to '10s'" not in MIG
    assert "statement_timeout to '3s'" not in MIG
    assert "scored as materialized" in MIG
    assert "when scored.deals_this_year >= 3 then 3 when scored.deals_this_year >= 1 then 2 when scored.deals > 0 then 1 else 0 end" in MIG
    assert "extract(month from current_date) < 6" in MIG
    assert "btrim(coalesce(t, '')) ~ '^[0-3]$'" in MIG
    assert "s.firm_status = any(" not in MIG
    assert "p_legal text[]" in MIG
    assert "p_info text[]" in MIG
    assert "drop table" not in MIG.lower()
    assert "drop function" not in MIG.lower()
    assert f"grant execute on function {SIG} to anon, authenticated, service_role" in MIG


def test_rollback_restores_the_firm_status_filter():
    assert "s.firm_status = any(v_status)" in UNDO
    assert "set statement_timeout to '5s'" in UNDO
    assert "drop table" not in UNDO.lower()
    assert "drop function" not in UNDO.lower()
    assert "create or replace function public.firm_directory(" not in UNDO


def test_menu_drops_removed_groups_and_reads_activity_ranks():
    assert "title: 'Legal records'" not in JS
    assert "title: 'Recorded information'" not in JS
    assert "Deals in last 12 months" not in JS
    assert "p_legal: []" in JS
    assert "p_info: []" in JS
    assert "activityValue(f)" in JS
    assert "rule.rank(f && f.deals_this_year, f && f.deals)" in JS
    assert "INLINE_OPTIONS = 5" in JS
    assert "g.options.length > shown.length" in JS
