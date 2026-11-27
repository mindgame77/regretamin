"""The Pricing pop-up opens with a personal note and photo, explains credits under each plan, and fits a phone."""
import re, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent / 'launch'


def test_note_photo_and_explanation_are_wired():
    copy = (ROOT / 'copy.json').read_text()
    assert 'with or without us' in copy and '"name": "Olexi Masky"' in copy
    assert 'class="fnote"' in (ROOT / 'build.py').read_text()
    assert (ROOT / 'assets' / 'team' / 'olexi.jpg').exists()
    assert "C.copy.site.pricing.explain" in (ROOT / 'js' / 'app.js').read_text()


def test_the_wide_popup_shrinks_to_the_phone_screen():
    css = (ROOT / 'style.css').read_text()
    assert re.search(r'@media \(max-width:820px\)\{\.md\.w\{width:calc\(100vw - 24px\)', css)
