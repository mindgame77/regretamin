"""Not active covers finished research and undated deals. The migration is not applied here."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261117222549_investor_activity_not_checked.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261117222549_investor_activity_not_checked.sql").read_text(encoding="utf-8")
SIG = "public.firm_directory_page_v2(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[])"


def _directory(sql):
    start = sql.index("create or replace function public.firm_directory_page_v2")
    end = sql.index("$function$;", start)
    return sql[start:end]


def test_migration_stores_researched_and_uses_it_only_for_not_active():
    directory = _directory(MIG)
    assert "add column if not exists researched boolean not null default false" in MIG
    assert "a.done_at is not null" in MIG
    assert "firm_summary_set_researched" in MIG
    assert "firm_summary_researched_assignment" in MIG
    assert "v2_deals" not in MIG
    assert "refresh_firm_summary" not in MIG
    assert "set statement_timeout to '5s'" in directory
    assert directory.count("or scored.investments > 0 or scored.researched then 1") == 2
    assert "when deals > 0 or investments > 0 or researched then 1" in directory
    assert "when coalesce(s.investments, 0) > 0 or s.researched then 1 else 0 end" in directory
    assert "'researched', o.researched" in directory
    assert "when coalesce(s.deals, 0) > 0 then s.deals" in MIG
    assert "when coalesce(s.investments, 0) > 0 or s.researched then 1" in MIG
    assert f"grant execute on function {SIG} to anon, authenticated, service_role" in MIG
    assert "drop table" not in MIG.lower()


def test_rollback_restores_the_dated_only_not_active_check():
    directory = _directory(UNDO)
    assert "when scored.deals > 0 then 1 else 0 end" in directory
    assert "researched" not in directory
    assert "drop function if exists public.firm_summary_set_researched()" in UNDO
    assert "drop function if exists public.firm_summary_researched_from_assignment()" in UNDO
    assert "drop column if exists researched" in UNDO
    assert "api_activity_label(s.deals, s.dated_dates)" in UNDO
    assert "drop table" not in UNDO.lower()
    assert "create or replace function public.firm_directory(" not in UNDO
