"""The firm share card: drawn by launch/edge/card, linked from the firm page head in both renderers."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_card_node_tests():
    r = subprocess.run(["node", "--test", "launch/edge/card/card.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-2000:]


def test_both_firm_heads_name_the_card():
    build = (ROOT / "launch" / "build.py").read_text()
    edge = (ROOT / "launch" / "edge" / "firm.mjs").read_text()
    assert 'property="og:image" content="{SITE}share/vc/{F["slug"]}.png"' in build
    assert 'property="og:image" content="${SITE}share/vc/${F.slug}.png"' in edge
    for text in (build, edge):
        assert 'name="twitter:card" content="summary_large_image"' in text
    assert (ROOT / "launch" / "functions" / "share" / "vc" / "[slug].js").exists()
