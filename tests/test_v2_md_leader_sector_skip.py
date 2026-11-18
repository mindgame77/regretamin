"""Managing Director is a leader title; a repeat startup sector is a quiet skip. Nothing else changes."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261118020500_v2_md_leader_sector_skip.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()


def _leader_regex(sql):
    m = re.search(r"select coalesce\(t,''\) ~\* '([^']+)'", sql)
    assert m
    return m.group(1).replace(r"\m", r"\b").replace(r"\M", r"\b")


def test_managing_director_is_a_leader_but_plain_partner_is_not():
    rx = re.compile(_leader_regex(MIG), re.I)
    for t in ["Managing Director", "MANAGING DIRECTOR", "Managing Director, Investments", "CEO", "Managing Partner", "Steward"]:
        assert rx.search(t), t
    for t in ["Partner", "General Partner", "Investment Director", "Executive Director", "Director", "Managing Directorate"]:
        assert not rx.search(t), t


def test_rollback_restores_the_old_leader_title():
    rx = re.compile(_leader_regex(UNDO), re.I)
    assert not rx.search("Managing Director")
    assert rx.search("Managing Partner")


def test_repeat_sector_is_skipped_not_rejected():
    assert "reason := 'sector already set for this startup'" not in MIG
    assert "SET status = 'Skipped: sector already set' WHERE submission_id = sid" in MIG
    assert "'status','Skipped: sector already set'" in MIG
    assert "reason := 'startup already has 2 sectors (max 2)'" in MIG
    assert "'skipped', CASE WHEN v_skipped > 0 THEN v_skipped END" in MIG
    assert "check (status ~ '^(Accepted|Rejected: .+|Held: .+|Skipped: .+)$')" in MIG
    # The gentle freeze still counts Rejected only, so a skip never pauses a firm.
    assert "status LIKE 'Rejected:%'" in MIG


def test_migration_is_guarded_and_changes_only_two_functions_and_one_check():
    low = MIG.lower()
    assert "raise notice 'v2 schema missing, skipped'" in low
    assert low.count("create or replace function") == 2
    assert "function public.v2_is_leader_title(t text)" in low
    assert "function public.v2_research_submit(p_key_id uuid, p_items jsonb, p_dry_run boolean default false)" in low
    assert "v2_firm_page" not in low and "api_firm" not in low
    assert "v2_change_log_result_check" not in low


def test_rollback_turns_skips_back_into_rejections_first():
    assert "set status = 'Rejected: sector already set for this startup'" in UNDO
    assert UNDO.index("where status = 'Skipped: sector already set'") < UNDO.index("check (status ~ '^(Accepted|Rejected: .+|Held: .+)$')")
    assert "reason := 'sector already set for this startup'" in UNDO
    assert "Skipped: sector already set'" not in UNDO.split("$fn$")[-2]
