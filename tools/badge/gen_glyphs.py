"""Letter shapes for the firm badges (launch/edge/card/badge.mjs).

The badge renderer on the live site cannot load fonts, so the badge's words are drawn from these outlines:
the site's own Geist SemiBold (titles, initials) and Geist Mono (the small capitals). Run after a font change:
    python3 tools/badge/gen_glyphs.py
"""
import json, os
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SETS = {
    'SEMI': ('Geist-SemiBold.ttf', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 &.-?'),
    'MONO': ('GeistMono-Regular.ttf', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ·'),
}
out = []
for name, (file, chars) in SETS.items():
    f = TTFont(os.path.join(ROOT, 'launch', 'assets', 'fonts', file)); gs = f.getGlyphSet(); cmap = f.getBestCmap(); hmtx = f['hmtx']
    adv, d = {}, {}
    for ch in chars:
        g = cmap.get(ord(ch))
        if g is None: continue
        pen = SVGPathPen(gs, ntos=lambda v: str(int(round(v)))); gs[g].draw(pen)
        adv[ch] = hmtx[g][0]; d[ch] = pen.getCommands()
    out.append(f"export const {name} = {json.dumps({'upm': f['head'].unitsPerEm, 'adv': adv, 'd': d}, ensure_ascii=False, separators=(',', ':'))};")
open(os.path.join(ROOT, 'launch', 'edge', 'card', 'badge-glyphs.mjs'), 'w').write(
    "// Letter outlines for the firm badges, made by tools/badge/gen_glyphs.py from the site's Geist fonts (font units, y up).\n" + '\n'.join(out) + '\n')
