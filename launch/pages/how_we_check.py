import re
from .video import render_video

SOURCE_PILL_JS = """
<script>
(function(){
  document.querySelectorAll(".checks10").forEach(function(grid){
    grid.addEventListener("click", function(e){
      var p = e.target.closest(".srcpill");
      if(!p || !grid.contains(p)) return;
      var card = p.closest(".c10");
      var on = p.classList.contains("is-on");
      grid.querySelectorAll(".srcpill.is-on").forEach(function(x){ x.classList.remove("is-on"); });
      grid.querySelectorAll(".srcpill-why").forEach(function(w){ w.hidden = true; w.textContent = ""; });
      if(on) return;
      p.classList.add("is-on");
      var why = card && card.querySelector(".srcpill-why");
      if(why && p.getAttribute("data-why")){ why.hidden = false; why.textContent = p.getAttribute("data-why"); }
    });
  });
})();
</script>
"""

def render(c):
    """How we check in the new look (founder, 2026-11-22): the vertical video on the left, a short headline and four
    lines on the right, then three short sections. Plan: project doc claude/plans/small-pages-design.md."""
    S, E = c.S, c.E
    H = S['how_we_check']
    media = render_video(H.get('video'), H.get('video_caption') or 'How Regretamin checks a firm')
    steps = ['We collect public records', 'We match them to the right firm', 'We link every fact to its source', 'You decide']
    lines = ''.join(f'<li><span>0{i}</span><b>{E(t)}</b></li>' for i, t in enumerate(steps, 1))
    ring = ('<span class="hw-ring" aria-hidden="true"><i></i></span>')
    bars = '<span class="hw-bars" aria-hidden="true">' + ''.join(f'<i style="height:{h}px"></i>' for h in (40, 62, 34, 52, 78, 84)) + '</span>'
    flow = ('<svg aria-hidden="true" width="170" height="84" viewBox="0 0 170 84"><path d="M30 18C70 18 70 42 85 42M30 66C70 66 70 42 85 42" fill="none" stroke="#F3E3A3" stroke-width="7" stroke-linecap="round"/>'
            '<path d="M140 18C100 18 100 42 85 42M140 66C100 66 100 42 85 42" fill="none" stroke="#A8D8B4" stroke-width="7" stroke-linecap="round"/>'
            '<circle cx="30" cy="18" r="11" fill="#F3E3A3" stroke="#10201C" stroke-width="1.5"/><circle cx="30" cy="66" r="11" fill="#F3E3A3" stroke="#10201C" stroke-width="1.5"/>'
            '<circle cx="140" cy="18" r="11" fill="#A8D8B4" stroke="#10201C" stroke-width="1.5"/><circle cx="140" cy="66" r="11" fill="#A8D8B4" stroke="#10201C" stroke-width="1.5"/><circle cx="85" cy="42" r="17" fill="#10201C"/></svg>')
    quote = ('<svg aria-hidden="true" width="150" height="88" viewBox="0 0 150 88"><path d="M12 6h92a8 8 0 0 1 8 8v30a8 8 0 0 1-8 8H42L26 66V52H12a8 8 0 0 1-8-8V14a8 8 0 0 1 8-8z" fill="#fff" stroke="#10201C" stroke-width="1.5"/>'
             '<rect x="24" y="20" width="68" height="6" rx="3" fill="#10201C"/><rect x="24" y="34" width="44" height="6" rx="3" fill="#A3AEAA"/>'
             '<path d="M68 40h70a8 8 0 0 1 8 8v22a8 8 0 0 1-8 8h-10v8l-12-8H68a8 8 0 0 1-8-8V48a8 8 0 0 1 8-8z" fill="#DDEFE3" stroke="#10201C" stroke-width="1.5"/><rect x="74" y="54" width="56" height="6" rx="3" fill="#10201C"/></svg>')
    cards = ''.join(f'<div class="hw-card"><div>{pic}</div><b>{E(t)}</b></div>' for t, pic in (
        ('What they invest in', ring), ('Deals, year by year', bars), ('Who invests around them', flow), ('What founders say', quote)))
    checks = ''.join(
        f'<details class="hw-chk"><summary><span>{i:02d}</span><b>{E(item["name"])}</b><i aria-hidden="true">+</i></summary><ul>'
        + ''.join(f'<li><b>{E(src["name"])}</b> {E(src["why"])}</li>' for src in item.get('sources') or []) + '</ul></details>'
        for i, item in enumerate(H.get('checks10') or [], 1))
    pills = ''.join(f'<div class="hw-pill"><span class="{cls}">{E(t)}</span><p>{E(d)}</p></div>' for cls, t, d in (
        ('c', 'Clear', 'Nothing found in the sources we checked.'), ('r', 'Review', 'A possible match we are still confirming.'),
        ('w', 'Worth knowing', 'Not a problem, but useful to know.'), ('n', 'Not checked yet', 'Run the check to see the result.')))
    return f"""<main class="hw">
<section class="hw-top"><div class="hw-video">{media}</div>
<div class="hw-say"><h1>Everything here<br>has a source.</h1><ol class="hw-steps">{lines}</ol>
<p class="hw-go"><a class="hw-btn on" href="../investors/">Browse investors</a><a class="hw-btn" href="../">Open the map</a></p></div></section>
<section><h2>What a firm page shows</h2><div class="hw-cards">{cards}</div></section>
<section><h2>10 background checks <em>Coming back soon</em></h2><div class="hw-chks">{checks}</div></section>
<section><h2>How to read a result</h2><div class="hw-pills">{pills}</div></section>
<p class="hw-fine">{E(H.get('disclaimer') or '')}</p>
</main>"""
