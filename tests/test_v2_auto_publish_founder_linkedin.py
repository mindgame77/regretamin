"""Founder LinkedIn fills (v2_people changed-key-fact) go live through auto-publish.

Static checks only; the v2 schema is not built by repo migrations.
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261118320000_v2_auto_publish_founder_linkedin.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261118320000_v2_auto_publish_founder_linkedin.sql").read_text()


def test_only_the_three_auto_publish_functions_are_replaced():
    low = SQL.lower()
    assert low.count("create or replace function") == 3
    for fn in ("v2_auto_publish_apply_queue(p_queue_id bigint)",
               "v2_auto_publish_take_down(p_queue_id bigint, p_mode text, p_reason text)",
               "v2_auto_publish_restore_one(p_queue_id bigint)"):
        assert f"create or replace function public.{fn}" in low
        assert f"create or replace function public.{fn}" in UNDO.lower()
    assert "function public.v2_research_submit" not in low


def test_people_branch_never_overwrites_and_skips_duplicates():
    assert "q.kind = 'changed-key-fact' and q.table_name = 'v2_people'" in SQL
    assert "return 'skipped: linkedin already set'" in SQL
    assert "return 'skipped: linkedin on another person'" in SQL
    assert "and nullif(btrim(p.linkedin_url), '') is null;" in SQL
    assert "public.v2_norm_url(p2.linkedin_url) = public.v2_norm_url(q.new_value->>'linkedin_url')" in SQL
    # x_url is never written by this change.
    assert "set x_url" not in SQL.lower()


def test_pull_reverts_the_link_instead_of_hiding_the_person():
    assert SQL.count("ap.prior ? 'applied' and ap.table_name = 'v2_people'") == 2
    assert "v2_people" not in UNDO.split("$rb$")[1].split("execute $ddl$")[0]


def test_backfill_uses_the_same_rule_oldest_first():
    assert "s.status like 'Held: empty person url%'" in SQL
    assert "order by q.queue_id" in SQL
    assert "msg := public.v2_auto_publish_apply_queue(r.queue_id);" in SQL
    assert "raise notice 'v2 auto-publish missing, skipped'" in SQL
