"""Preview: copy blank HQ and SEC CRD from research_queue onto v2 firms."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261118280000_v2_copy_research_queue_hq.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261118280000_v2_copy_research_queue_hq.sql").read_text()
GUIDE = (ROOT / "docs/PAGE_DATA_GUIDE.md").read_text()


def _body(text):
    lines = [line for line in text.splitlines() if not line.strip().startswith("--")]
    return "\n".join(lines).lower()


def test_migration_is_preview_safe_and_skips_without_v2():
    low = _body(SQL)
    assert "to_regclass('public.v2_firms') is null" in low
    assert "to_regclass('public.research_queue') is null" in low
    assert "create or replace function public.research_queue_country_iso" in low
    assert "create or replace function public.v2_apply_research_queue_fields" in low
    assert "create or replace function public.v2_research_add_firm" in low
    assert "create table if not exists public.v2_research_queue_copy" in low
    assert "v2_apply_research_queue_fields(fid, reg, bk.bot_key_id, bot)" in low
    assert "refresh_firm_summary" in low
    # Never overwrite a value that is already set.
    assert "hq_country is null" in low
    assert "never overwrites" in SQL.lower()
    assert "us-small" in low and "us-cur" in low
    assert "source_owner" in low and "research_queue" in low
    assert "registry_type = 'sec crd'" in low or "registry_type, registry_value" in low
    assert "is_current" in low
    assert "revoke all on function public.v2_apply_research_queue_fields" in low
    assert "grant execute on function public.v2_apply_research_queue_fields" in low
    assert "delete " not in low
    assert "truncate " not in low
    assert "drop table" not in low


def test_rollback_clears_only_marked_fields_and_restores_add_firm():
    undo = _body(UNDO)
    assert "v2_research_queue_copy" in undo
    assert "filled_country" in undo and "filled_city" in undo and "filled_state" in undo
    assert "filled_crd" in undo
    assert "hq_country = case when c.filled_country then null else f.hq_country end" in undo
    assert "create or replace function public.v2_research_add_firm" in undo
    assert "drop function if exists public.v2_apply_research_queue_fields" in undo
    assert "drop table if exists public.v2_research_queue_copy" in undo
    assert "refresh_firm_summary" in undo
    assert "truncate " not in undo
    # Does not wipe whole firm rows
    assert "drop table if exists public.v2_firms" not in undo


def test_guide_says_add_firm_copies_queue_hq():
    assert "v2_research_add_firm" in GUIDE
    assert "hq_country" in GUIDE and "hq_city" in GUIDE and "hq_state" in GUIDE
    assert "SEC CRD" in GUIDE
    assert "never overwrites a value that is already set" in GUIDE
