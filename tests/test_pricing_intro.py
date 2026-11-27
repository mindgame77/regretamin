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


def test_first_month_offer_is_only_shown_when_the_promotion_code_is_valid_and_once_off():
    pr = json.loads((ROOT / 'copy.json').read_text())['site']['pricing']
    assert pr['first']['code'] == 'FIRSTMONTH'
    # validate-code must say ok, a discount, a percentage and a once-off duration before anything on the page changes
    assert "data.ok && data.discount && data.percent_off && data.duration === 'once'" in APP
    # monthly plans only: never the yearly kinds or the hidden plan
    assert "!/_y$/.test(kind) && AUTO.kinds.includes(kind)" in APP
    # the checkout sends the same code the page showed
    assert "(off(kind) || CODE).code" in APP


def test_the_popup_is_one_narrow_column_that_fits_a_phone():
    css = (ROOT / 'style.css').read_text()
    assert re.search(r'\.md\.w\{width:600px;max-width:calc\(100vw - 24px\)', css)
