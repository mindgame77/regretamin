"""The Pricing popup: a personal note with photo, a radio list of plans with one Start button, a standing first-month offer
that shows only while its promotion code is valid, and a layout that fits a phone."""
import re, json, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent / 'launch'
APP = (ROOT / 'js' / 'app.js').read_text()


def test_note_photo_and_plan_list_are_wired():
    copy = (ROOT / 'copy.json').read_text()
    assert 'with or without us' in copy and '"name": "Olexi Masky"' in copy
    assert 'class="fnote"' in (ROOT / 'build.py').read_text()
    assert (ROOT / 'assets' / 'team' / 'olexi.jpg').exists()
    assert 'P.explain' in APP and 'function planList' in APP and 'data-pick' in APP


def test_first_month_offer_matches_the_coupon_checkout_applies():
    pr = json.loads((ROOT / 'copy.json').read_text())['site']['pricing']
    assert pr['first']['percent'] == 50  # must match the coupon create-checkout applies
    assert 'FIRST_MONTH_COUPON = "regretamin_first_month_50"' in (ROOT.parent / 'supabase/functions/create-checkout/index.ts').read_text()
    # the page shows the offer without a lookup, and checkout adds the coupon itself
    assert "AUTO = { percent_off: f.percent" in APP and "validate-code', { body: { code: f.code" not in APP
    assert "CODE ? { code: CODE.code } : {})" in APP  # the page never sends a made-up code
    # monthly plans only: never the yearly kinds or the hidden plan
    assert "!/_y$/.test(kind) && AUTO.kinds.includes(kind)" in APP
    # the checkout sends the same code the page showed


def test_the_popup_is_one_narrow_column_that_fits_a_phone():
    css = (ROOT / 'style.css').read_text()
    assert re.search(r'\.md\.w\{width:600px;max-width:calc\(100vw - 24px\)', css)


def test_the_out_of_credits_popup_uses_the_same_plan_rows_and_offer():
    css = (ROOT / 'style.css').read_text()
    assert '.sgi .orow:has(input:checked){border:2px solid #10201C' in css and '.sgi .btn.y{background:#10201C' in css
    assert "c && c === AUTO ? fmt(P.first.sub" in APP and 'AUTO_READY' in APP


def test_owner_test_sale_link_only_calls_the_guarded_kind():
    assert "get('rg_test') === '1'" in APP and "if (session) checkout('test1')" in APP
    assert 'OWNER_IDS.includes(uid)' in (ROOT.parent / 'supabase/functions/create-checkout/index.ts').read_text()
