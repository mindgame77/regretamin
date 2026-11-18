"""One activity label (api_activity_label, read by the list and the firm page) and firm_summary.added as the checked date."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261118140000_one_activity_label_added_checked.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()


def test_label_is_decided_once_in_the_database():
    low = MIG.lower()
    assert "create or replace function public.api_activity_label(p_deals integer, p_dates date[], p_investments integer, p_researched boolean)" in low
    assert "'activity', public.api_activity_label(o.deals, o.dated_dates, o.investments, o.researched)" in low
    assert "'label',(select public.api_activity_label(s.deals, s.dated_dates, s.investments, s.researched) from firm_summary s" in low
    assert "create trigger" not in low and "insert into" not in low and "update public." not in low


def test_checked_date_is_added():
    assert "s.added::date as last_checked_date" in MIG
    assert "fs.added::date is distinct from s.last_checked_date" in MIG


def test_rollback_undoes_each_insertion():
    assert "drop function if exists public.api_activity_label(integer, date[], integer, boolean)" in UNDO
    assert "f.last_checked_date is distinct from s.last_checked_date" in UNDO
    assert "E'f.last_checked_date,\\n'" in UNDO


def test_pages_display_the_stored_label():
    company = (ROOT / "launch/js/company.js").read_text()
    firms = (ROOT / "launch/js/firms.js").read_text()
    assert "rule.fromText(A.label)" in company
    assert "rule.fromText(f.activity)" in firms and "rule.fromText(row.activity)" in firms
