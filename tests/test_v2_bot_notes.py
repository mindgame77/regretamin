"""Feedback inbox: notes belong to one bot key, are read and acked only by that key, and never touch submissions."""
import json
import os
import pathlib
import uuid

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
NAME = "20261118040000_v2_bot_notes.sql"
MIG = (ROOT / "supabase/migrations" / NAME).read_text()
UNDO = (ROOT / "supabase/rollbacks" / NAME).read_text()


def test_migration_only_adds_and_rollback_only_drops_the_new_objects():
    low = MIG.lower()
    assert low.count("create or replace function") == 2
    for name in ("v2_research_submit", "v2_research_claim", "v2_section_claim", "ingest_auth", "v2_is_leader_title"):
        assert name not in low, name
    assert "enable row level security" in low and "create policy" not in low
    code = "\n".join(l for l in low.splitlines() if not l.lstrip().startswith("--"))
    assert "v2_research_submissions" not in code and "freeze" not in code
    assert "raise notice 'bots.ingest_keys missing, skipped'" in low
    assert "drop table if exists bots.bot_notes" in UNDO.lower()
    assert "v2_research_submit" not in UNDO.lower()


DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()
db = pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")


def _j(v):
    return v if isinstance(v, (dict, list)) else json.loads(v)


def _conn():
    psycopg = pytest.importorskip("psycopg")
    return psycopg.connect(DATABASE_URL)


def _key(cur, bot):
    return cur.execute(
        "insert into bots.ingest_keys (name, key_hash, bot_id) values (%s, %s, %s) returning id",
        (bot, uuid.uuid4().hex + uuid.uuid4().hex, bot)).fetchone()[0]


@db
def test_notes_are_per_key_and_ack_marks_read():
    with _conn() as conn, conn.cursor() as cur:
        a, b = _key(cur, "zz-notes-a"), _key(cur, "zz-notes-b")
        na = cur.execute("insert into bots.bot_notes (bot_key_id, bot_id, body) values (%s,'zz-notes-a','use person_name') returning note_id", (a,)).fetchone()[0]
        nb = cur.execute("insert into bots.bot_notes (bot_key_id, bot_id, body) values (%s,'zz-notes-b','for b') returning note_id", (b,)).fetchone()[0]

        got = _j(cur.execute("select public.v2_bot_notes_unread(%s)", (a,)).fetchone()[0])
        assert [n["note_id"] for n in got] == [str(na)]
        assert set(got[0]) == {"note_id", "body", "created_at"}

        # A cannot ack B's note.
        r = _j(cur.execute("select public.v2_bot_notes_ack(%s, %s::uuid[], 'read')", (a, [str(nb)])).fetchone()[0])
        assert r == {"ok": True, "acked": [], "not_found": [str(nb)]}
        assert cur.execute("select read_at from bots.bot_notes where note_id = %s", (nb,)).fetchone()[0] is None

        r = _j(cur.execute("select public.v2_bot_notes_ack(%s, %s::uuid[], 'done, switched to person_name')", (a, [str(na)])).fetchone()[0])
        assert r == {"ok": True, "acked": [str(na)], "not_found": []}
        assert cur.execute("select ack_text from bots.bot_notes where note_id = %s", (na,)).fetchone()[0] == "done, switched to person_name"
        assert _j(cur.execute("select public.v2_bot_notes_unread(%s)", (a,)).fetchone()[0]) == []
        assert [n["note_id"] for n in _j(cur.execute("select public.v2_bot_notes_unread(%s)", (b,)).fetchone()[0])] == [str(nb)]
        # Acking again is harmless.
        assert _j(cur.execute("select public.v2_bot_notes_ack(%s, %s::uuid[])", (a, [str(na)])).fetchone()[0])["acked"] == []
        assert _j(cur.execute("select public.v2_bot_notes_ack(%s, '{}'::uuid[])", (a,)).fetchone()[0])["ok"] is False
        conn.rollback()


@db
def test_notes_table_is_service_role_only():
    with _conn() as conn, conn.cursor() as cur:
        assert cur.execute("select relrowsecurity from pg_class where oid = 'bots.bot_notes'::regclass").fetchone()[0] is True
        assert cur.execute("select count(*) from pg_policies where schemaname='bots' and tablename='bot_notes'").fetchone()[0] == 0
        for role in ("anon", "authenticated"):
            if cur.execute("select 1 from pg_roles where rolname = %s", (role,)).fetchone():
                assert not cur.execute("select has_table_privilege(%s, 'bots.bot_notes', 'select')", (role,)).fetchone()[0]
                assert not cur.execute("select has_function_privilege(%s, 'public.v2_bot_notes_ack(uuid, uuid[], text)', 'execute')", (role,)).fetchone()[0]
                assert not cur.execute("select has_function_privilege(%s, 'public.v2_bot_notes_unread(uuid)', 'execute')", (role,)).fetchone()[0]
