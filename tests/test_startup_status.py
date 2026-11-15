"""Deal rows gain st_status. The firm page colors the startup name and adds no tag."""
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261114234500_v2_deals_startup_status.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261114234500_v2_deals_startup_status.sql").read_text(encoding="utf-8")


def test_migration_adds_only_st_status_and_skips_when_v2_is_missing():
    assert "to_regprocedure('public._v2_deals(bigint)') is null" in MIG
    assert "raise notice 'v2 schema missing, skipped'" in MIG
    assert "v2_startups.st_status is missing" in MIG
    assert "'st_status', s.st_status" in MIG
    assert "create table" not in MIG.lower()
    assert "add column" not in MIG.lower()
    assert "update " not in MIG.lower()
    assert "insert " not in MIG.lower()
    assert "'company', s.startup_name" in MIG
    assert "'industry_name', sec.industry_name" in MIG
    assert "'website_url', s.website_url) x" in MIG
    assert "'website_url', s.website_url, 'st_status', s.st_status) x" in MIG


def test_undo_removes_st_status_only():
    assert "to_regprocedure('public._v2_deals(bigint)') is null" in UNDO
    assert "raise notice 'v2 schema missing, skipped'" in UNDO
    assert "'website_url', s.website_url, 'st_status', s.st_status) x" in UNDO
    assert "'website_url', s.website_url) x" in UNDO
    assert "update " not in UNDO.lower()
    assert "drop table" not in UNDO.lower()
    assert "drop function" not in UNDO.lower()


@pytest.mark.skipif(not shutil.which("node"), reason="node not installed")
def test_startup_name_color_render():
    r = subprocess.run(["node", "--test", "tests/startup_status.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]
