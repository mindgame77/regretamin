"""v2 door action deals: any research key reads one firm's current deals with deal_id (read-only)."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/migrations/20261118180000_v2_research_firm_deals.sql").read_text()
UNDO = (ROOT / "supabase/rollbacks/20261118180000_v2_research_firm_deals.sql").read_text()
FN = (ROOT / "supabase/functions/research-ingest-v2/index.ts").read_text()
SIG = "public.v2_research_firm_deals(uuid, bigint, boolean, int, int)"


def test_migration_is_read_only_and_server_only():
    low = SQL.lower()
    for bad in ("alter table", "drop table", "insert into", "update ", "delete from", "create policy", "create trigger"):
        assert bad not in low, bad
    assert "security definer" in low and "set search_path = public, bots" in low and "stable" in low
    assert "k.active" in SQL
    assert "d.is_current and not d.archived" in SQL
    assert "to_regclass('public.v2_deals') is null" in low
    assert f"revoke all on function {SIG} from public, anon, authenticated" in low
    assert f"grant execute on function {SIG} to service_role" in low
    for role in ("to anon", "to authenticated", "to public"):
        assert f"grant execute on function {SIG} {role}" not in low
    assert f"drop function if exists {SIG};" in UNDO


def test_edge_routes_deals_from_the_key():
    assert 'body.action === "deals"' in FN
    assert 'db.rpc("v2_research_firm_deals"' in FN
    block_start = FN.index('body.action === "deals"')
    block = FN[block_start:FN.index('body.action !== "submit"', block_start)]
    assert "p_key: auth.key_id" in block
    assert "body.bot_id" not in block
    assert "deals" in FN[FN.index("const HINT"):FN.index(";", FN.index("const HINT"))]
