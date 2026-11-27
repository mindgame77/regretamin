"""Phone header: one burger button opens a panel with the header's links (no ids repeated, no Pricing)."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = (ROOT / 'launch' / 'build.py').read_text()
APP = (ROOT / 'launch' / 'js' / 'app.js').read_text()
CSS = (ROOT / 'launch' / 'style.css').read_text()


def test_the_header_has_a_burger_and_a_panel_without_repeated_ids():
    assert 'id="burger"' in BUILD and 'aria-controls="mpn"' in BUILD and 'id="mpn" hidden' in BUILD
    # the panel's links come from the same registry as the header, with ids stripped so #signin / #readynav / #signout stay unique
    assert "re.sub(r' id=\"[^\"]*\"', ''" in BUILD
    assert '(?:plans|login)' in BUILD  # Pricing stays out of the panel, like the header


def test_the_burger_opens_and_closes_and_sign_out_reuses_the_real_button():
    assert "const bg = $('#burger'), mpn = $('#mpn')" in APP
    for piece in ("burger(mpn.hidden)", "e.key === 'Escape'", "window.innerWidth > 640", "$('#signout').click()"):
        assert piece in APP


def test_only_phones_see_the_burger_and_the_links_are_hidden_there():
    assert 'body>nav .bg,.mpn{display:none}' in CSS
    m = re.search(r'/\* Burger menu.*', CSS, re.S).group(0)
    assert '@media (max-width:640px)' in m
    assert 'body>nav .r>a:not(#zz):not(#zy),body>nav .r>#acct:not(#zz){display:none!important}' in m
    assert 'html.au-in .mpn .mac{display:block}' in m
