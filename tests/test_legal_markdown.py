"""Terms and Privacy are rendered from launch/legal/*.md into the existing page shell."""
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Load the renderer by file path. launch/ is not a Python package.
_spec = importlib.util.spec_from_file_location("launch_legal", ROOT / "launch" / "legal" / "__init__.py")
legal = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(legal)


def test_terms_and_privacy_render_the_approved_pages():
    terms, privacy = legal.terms(), legal.privacy()
    for page in (terms, privacy):
        assert page.startswith('<main class="hp lg"><span class="ey">Legal</span><h1>')
        assert '<p class="lead">' in page and '<p class="eff">' in page and '<div class="toc">' in page
        assert "[DATE]" not in page
        assert "[DATE]" not in page and "{{" not in page
        assert "Know Your Group INC." in page
        assert 'href="mailto:malytskyyo@gmail.com"' in page
        assert page.count("<h2>") >= 10
        assert page.count('<a href="#') == page.count("<h2>")
    assert "November 26, 2026" in terms and "7c. Pitch decks you upload" in terms and "reviews your deck" in terms  # pitch decks 26 Nov
    assert "November 26, 2026" in privacy and "Google Analytics" in privacy  # cookie bar, batch 8; host line corrected 25 Nov; pitch decks 26 Nov
    assert "Pitch decks and reports" in privacy and "Anthropic and Google (Gemini)" in privacy and "sell your deck, and we don" in privacy
    assert "<b>Cloudflare:</b> hosts the website" in privacy and "GitHub Pages" not in privacy  # the site moved to Cloudflare
    assert "Terms of Service" in terms and 'href="../privacy/"' in terms
    assert "Privacy Policy" in privacy and 'href="../terms/"' in privacy
    assert "not a consumer reporting agency" in terms
    assert "<code>regretamin.anon</code>" in privacy
    assert "2 free credits on your device" in privacy
    assert "its own 4 credits" in privacy and "Device credits are not transferred" in privacy
    assert "those searches move to your account" not in privacy
    assert "Starter" in terms and "$19" in terms and "$190" in terms
    assert "Pro" in terms and "$49" in terms and "$490" in terms and "$10" in terms
    assert 'id="8-credits"' in terms and 'id="10-subscriptions-and-promo-codes"' in terms
    # A heading in the table of contents points at the section it names.
    assert '<a href="#1-agreement">1. Agreement</a>' in terms
    assert '<section id="1-agreement"><h2>1. Agreement</h2>' in terms


def test_unknown_plan_placeholder_fails_the_build():
    try:
        legal._fill("Costs {{plan.nope.price}}.")
    except ValueError as err:
        assert "plan.nope.price" in str(err)
    else:
        raise AssertionError("missing plan placeholder was filled")
