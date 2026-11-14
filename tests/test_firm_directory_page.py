"""Paged investors directory: a new function, the old one left in place."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261114190000_firm_directory_page.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261114190000_firm_directory_page.sql").read_text(encoding="utf-8")
SIG = "public.firm_directory_page(int, int, text, boolean, text[], text[], text[], text[], text[], text[], text[])"


def test_migration_adds_a_page_function_and_leaves_firm_directory_alone():
    assert "create or replace function public.firm_directory_page(" in MIG
    assert "p_limit int default 100" in MIG
    assert "p_offset int default 0" in MIG
    assert "p_search text[] default null" in MIG
    assert "p_region text[] default null" in MIG
    assert "p_industry text[] default null" in MIG
    assert "p_stage text[] default null" in MIG
    assert "p_legal text[] default null" in MIG
    assert "p_info text[] default null" in MIG
    assert "p_status text[] default null" in MIG
    assert "security definer" in MIG
    assert "set search_path to 'public', 'pg_temp'" in MIG
    assert "set statement_timeout to '3s'" in MIG
    assert "v2_firm_live" in MIG
    assert "v2_firms" in MIG
    assert "v2_deals" in MIG
    assert f"revoke all on function {SIG} from public" in MIG
    assert f"grant execute on function {SIG} to anon, authenticated" in MIG
    assert "create or replace function public.firm_directory(" not in MIG
    assert "drop function" not in MIG.lower()
    assert "drop table" not in MIG.lower()


def test_rollback_drops_only_the_page_function():
    assert f"drop function if exists {SIG}" in UNDO
    assert "drop function if exists public.firm_directory()" not in UNDO
    assert "drop function public.firm_directory()" not in UNDO
    assert "drop table" not in UNDO.lower()


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_investors_page_loads_a_page_then_the_next():
    r = subprocess.run(
        ["node", "--test", "tests/firm_directory_cache.test.mjs"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]
