"""Complete firm directory country-to-region map, including Australia & Oceania."""
import os
import pathlib
import re

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIG = (ROOT / "supabase/migrations/20261118270000_firm_region_complete.sql").read_text(encoding="utf-8")
UNDO = (ROOT / "supabase/rollbacks/20261118270000_firm_region_complete.sql").read_text(encoding="utf-8")
JS = (ROOT / "launch/js/firms.js").read_text(encoding="utf-8")
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()

# Official ISO 3166-1 alpha-2 codes (249). XK is user-assigned (Kosovo).
OFFICIAL_ISO2 = frozenset(
    "AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ "
    "BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR "
    "CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR "
    "GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU "
    "ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ "
    "LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ "
    "MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF "
    "PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI "
    "SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR "
    "TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW".split()
)
UNMAPPED_OFFICIAL = frozenset({"AQ"})  # Antarctica is not a country and fits no region.
EXAMPLES = {
    "US": "north_america",
    "CA": "north_america",
    "MX": "north_america",
    "GB": "europe",
    "UA": "europe",
    "PL": "europe",
    "BY": "europe",
    "XK": "europe",
    "AU": "oceania",
    "NZ": "oceania",
    "FJ": "oceania",
    "PG": "oceania",
    "TR": "middle_east",
    "OM": "middle_east",
    "IQ": "middle_east",
    "MA": "africa",
    "TN": "africa",
    "MU": "africa",
    "GH": "africa",
    "UY": "latam",
    "VE": "latam",
    "VG": "latam",
    "BM": "latam",
    "KY": "latam",
    "MY": "asia",
    "VN": "asia",
    "KZ": "asia",
    "UZ": "asia",
    "AZ": "asia",
    "GE": "asia",
    "AM": "asia",
}


def _js_region():
    m = re.search(r"const REGION = \{([^}]+)\}", JS, re.S)
    assert m, "REGION object missing from launch/js/firms.js"
    pairs = re.findall(r"([A-Z]{2}): '([a-z_]+)'", m.group(1))
    assert pairs
    return dict(pairs)


def _js_options():
    m = re.search(r"const REGION_OPTIONS = \[(.*?)\];", JS, re.S)
    assert m, "REGION_OPTIONS missing from launch/js/firms.js"
    return re.findall(r"\['([a-z_]+)', '([^']+)'\]", m.group(1))


def _sql_region(src):
    body = re.search(
        r"create or replace function public\.firm_summary_region\(p_country text\).*?\$\$;(?:\n|$)",
        src,
        re.S,
    )
    assert body, "firm_summary_region missing"
    pairs = re.findall(r"when '([A-Z]{2})' then '([a-z_]+)'", body.group(0))
    assert pairs
    return dict(pairs)


def test_js_and_sql_maps_are_identical_and_complete():
    js_map = _js_region()
    sql_map = _sql_region(MIG)
    assert js_map == sql_map
    assert len(js_map) == len(set(js_map))
    assert set(js_map) - OFFICIAL_ISO2 == {"XK"}
    assert OFFICIAL_ISO2 - set(js_map) == UNMAPPED_OFFICIAL
    assert js_map["TR"] == "middle_east"
    assert js_map["MA"] == "africa"
    assert js_map["UY"] == "latam"
    assert js_map["AU"] == "oceania"
    for code, region in EXAMPLES.items():
        assert js_map[code] == region, (code, js_map[code], region)
    assert "create or replace function public.v2_work_hq_na_europe" not in MIG
    assert "create or replace function public.v2_next_firm" not in MIG


def test_oceania_option_sits_before_not_disclosed():
    opts = _js_options()
    values = [v for v, _ in opts]
    assert values == [
        "north_america",
        "europe",
        "asia",
        "latam",
        "africa",
        "middle_east",
        "oceania",
        "unknown",
    ]
    assert dict(opts)["oceania"] == "Australia & Oceania"
    assert dict(opts)["unknown"] == "Not disclosed"
    assert dict(opts)["latam"] == "LatAm"


def test_rollback_restores_the_old_map():
    old = _sql_region(UNDO)
    assert "oceania" not in old.values()
    assert old["US"] == "north_america"
    assert old["GB"] == "europe"
    assert old["QA"] == "middle_east"
    assert "AU" not in old
    assert "TR" not in old
    assert "update public.firm_summary" in UNDO
    assert "drop table" not in UNDO.lower()
    assert "v2_work_hq_na_europe" not in UNDO


def test_migration_recomputes_stored_region_and_leaves_research_filter():
    assert "create or replace function public.firm_summary_region(p_country text)" in MIG
    assert "when 'AU' then 'oceania'" in MIG
    assert "when 'TR' then 'middle_east'" in MIG
    assert "update public.firm_summary s" in MIG
    assert "to_regclass('public.firm_summary')" in MIG
    assert "to_regclass('public.firm_summary')" in UNDO
    assert "set region = public.firm_summary_region(s.hq_country)" in MIG
    assert "drop table" not in MIG.lower()
    assert "drop function" not in MIG.lower()


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL is not set")
def test_firm_summary_region_on_the_migrated_database():
    import psycopg

    with psycopg.connect(DATABASE_URL) as conn:
        for code, region in EXAMPLES.items():
            got = conn.execute("select public.firm_summary_region(%s)", (code,)).fetchone()[0]
            assert got == region, (code, got, region)
        for raw in (None, "", "  ", "USA", "A", "1A", "AQ", "uk"):
            got = conn.execute("select public.firm_summary_region(%s)", (raw,)).fetchone()[0]
            assert got == "unknown", (raw, got)
        # case and padding should not matter
        assert conn.execute("select public.firm_summary_region(%s)", (" au ",)).fetchone()[0] == "oceania"
        assert conn.execute("select public.firm_summary_region(%s)", ("tr",)).fetchone()[0] == "middle_east"
