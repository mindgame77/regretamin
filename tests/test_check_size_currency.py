"""A non-USD check size uses the original amounts. USD stays the dollar pill."""
import os
import re
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MIG = ROOT / "supabase/migrations/20261114220000_v2_check_size_original_currency.sql"
UNDO = ROOT / "supabase/rollbacks/20261114220000_v2_check_size_original_currency.sql"
PREV = ROOT / "supabase/migrations/20261109000100_v2_check_size_bounds.sql"
GUIDE = ROOT / "docs/PAGE_DATA_GUIDE.md"
WHOLE = re.compile(r"^[1-9][0-9]*$")


def money_display(amount, currency="USD"):
    """Same abbreviation as public._money_display. Symbol for USD, EUR, GBP, JPY; otherwise the code."""
    if amount is None:
        return None
    amount = Decimal(str(amount))
    if amount <= 0:
        return None
    code = (currency or "USD").strip().upper()
    prefix = {"USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥"}.get(code, code + " ")
    for div, suffix in ((Decimal(10**9), "B"), (Decimal(10**6), "M"), (Decimal(10**3), "K")):
        if amount >= div:
            q = amount / div
            places = Decimal("1") if q >= 100 else Decimal("0.01")
            q = q.quantize(places, rounding=ROUND_HALF_UP)
            text = format(q, "f")
            if "." in text:
                text = text.rstrip("0").rstrip(".")
            return prefix + text + suffix
    return prefix + format(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP), "f")


def whole(value):
    if value is None:
        return False
    return WHOLE.fullmatch(str(value).strip()) is not None


def check_size_label(min_usd, max_usd, min_amount=None, max_amount=None, currency=None):
    """Page label. Null currency, or USD, uses the dollar columns. Any other currency uses the original amounts."""
    code = str(currency or "").strip().upper()
    if code and code != "USD":
        lo, hi, cur = min_amount, max_amount, code
    else:
        lo, hi, cur = min_usd, max_usd, "USD"
    if whole(lo) and whole(hi) and int(str(lo).strip()) == int(str(hi).strip()):
        return money_display(lo, cur)
    if whole(lo) and whole(hi) and int(str(lo).strip()) < int(str(hi).strip()):
        return money_display(lo, cur) + "\u2013" + money_display(hi, cur)
    if lo is None and whole(hi):
        return "Up to " + money_display(hi, cur)
    if hi is None and whole(lo):
        return money_display(lo, cur) + "+"
    return None


def _quoted(text, name):
    return text.split(f"${name}$", 2)[1]


def test_usd_labels_stay_the_dollar_shapes():
    assert check_size_label(1000000, 10000000) == "$1M\u2013$10M"
    assert check_size_label(25000000, 25000000) == "$25M"
    assert check_size_label(25000000, 75000000) == "$25M\u2013$75M"
    assert check_size_label(None, 25000000) == "Up to $25M"
    assert check_size_label(25000000, None) == "$25M+"
    assert check_size_label(500000, 2000000) == "$500K\u2013$2M"
    assert check_size_label(None, None) is None
    # A dollar row ignores original-currency columns that are empty, and an explicit USD stays on min_usd.
    assert check_size_label(1000000, 10000000, None, None, None) == "$1M\u2013$10M"
    assert check_size_label(1000000, 10000000, 5000000, 5000000, "USD") == "$1M\u2013$10M"
    assert check_size_label(1000000, 10000000, 9000000, 9000000, "usd") == "$1M\u2013$10M"


def test_other_currencies_use_the_original_amounts_in_the_same_shapes():
    assert check_size_label(900000, 9000000, 1000000, 10000000, "EUR") == "€1M\u2013€10M"
    assert check_size_label(None, None, 500000, 2000000, "GBP") == "£500K\u2013£2M"
    assert check_size_label(None, None, 1000000, 1000000, "CHF") == "CHF 1M"
    assert check_size_label(None, None, 13200000, 13200000, "EUR") == "€13.2M"
    assert check_size_label(None, None, None, 10000000, "EUR") == "Up to €10M"
    assert check_size_label(None, None, 1000000, None, "JPY") == "¥1M+"
    assert check_size_label(None, None, 500, 500, "GBP") == "£500"
    # The dollar conversion is not drawn beside the original amount.
    label = check_size_label(1000000, 10000000, 1000000, 10000000, "EUR")
    assert label == "€1M\u2013€10M"
    assert "$" not in label
    assert "about" not in label.lower()
    assert check_size_label(1000000, 10000000, None, None, "EUR") is None
    assert check_size_label(None, None, 10000000, 1000000, "EUR") is None
    assert check_size_label(None, None, "1.5", 10000000, "EUR") is None


def test_migration_keeps_the_dollar_branch_and_adds_the_original_columns():
    text = MIG.read_text(encoding="utf-8")
    undo = UNDO.read_text(encoding="utf-8")
    prev = _quoted(PREV.read_text(encoding="utf-8"), "new")
    old = _quoted(text, "old")
    new = _quoted(text, "new")
    guide = GUIDE.read_text(encoding="utf-8")
    assert old == prev
    usd_case = prev[len("'check_size',(select "):].split(" from v2_firm_check_sizes", 1)[0]
    assert " else " + usd_case + " end from v2_firm_check_sizes" in new
    assert new.startswith("'check_size',(select case when c.currency is not null and c.currency <> 'USD' then ")
    assert "c.min_amount" in new and "c.max_amount" in new and "c.currency" in new
    assert "public._money_display(c.min_amount,c.currency)" in new
    assert "public._money_display(c.max_amount,c.currency)" in new
    assert "public._money_display(c.min_usd,'USD')" in new
    assert "'Up to '" in new and "|| '+'" in new and "\u2013" in new
    assert "about" not in text.lower()
    assert "add column" not in text.lower()
    assert "delete from" not in text.lower()
    assert "v2_research_submit" not in text
    assert "v2 schema missing, skipped page" in text
    assert "min_amount, max_amount, or currency is missing" in text
    assert _quoted(undo, "old") == new
    assert _quoted(undo, "new") == prev
    assert "€1M–€10M" in guide
    assert "£500K–£2M" in guide
    assert "CHF 1M" in guide
    assert "No usable positive whole-dollar bound: no label and no divider." in guide


def _page_case(text):
    select = _quoted(text, "new")
    return "select " + select.split("(select ", 1)[1].split(" from v2_firm_check_sizes", 1)[0]


@pytest.mark.skipif(not os.environ.get("DATABASE_URL", "").strip(), reason="DATABASE_URL is not set")
def test_page_sql_matches_money_display_for_original_currency():
    import psycopg

    case = _page_case(MIG.read_text(encoding="utf-8"))
    cases = [
        (1000000, 10000000, None, None, None, "$1M\u2013$10M"),
        (25000000, 25000000, None, None, None, "$25M"),
        (None, 25000000, None, None, None, "Up to $25M"),
        (25000000, None, None, None, None, "$25M+"),
        (1000000, 10000000, 5000000, 5000000, "USD", "$1M\u2013$10M"),
        (900000, 9000000, 1000000, 10000000, "EUR", "€1M\u2013€10M"),
        (None, None, 500000, 2000000, "GBP", "£500K\u2013£2M"),
        (None, None, 1000000, 1000000, "CHF", "CHF 1M"),
        (None, None, None, 10000000, "EUR", "Up to €10M"),
        (None, None, 1000000, None, "JPY", "¥1M+"),
        (1000000, 10000000, None, None, "EUR", None),
        (None, None, 10000000, 1000000, "EUR", None),
    ]
    with psycopg.connect(os.environ["DATABASE_URL"]) as conn, conn.cursor() as cur:
        cur.execute("select to_regprocedure('public._money_display(numeric,text)')")
        if cur.fetchone()[0] is None:
            pytest.skip("_money_display is not installed")
        for lo, hi, amin, amax, cur_code, expected in cases:
            cur.execute(
                f"{case} from (values (%s::numeric, %s::numeric, %s::numeric, %s::numeric, %s::text)) as c(min_usd, max_usd, min_amount, max_amount, currency)",
                (lo, hi, amin, amax, cur_code),
            )
            assert cur.fetchone()[0] == expected
