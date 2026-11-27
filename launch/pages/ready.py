import hashlib, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _v(name):
    return hashlib.sha256(open(os.path.join(HERE, 'js', name), 'rb').read()).hexdigest()[:10]


STEPS = ('Reading your deck, slide by slide', 'Listing every claim and how well it is proven', 'Checking the 217 points investors look at',
         'Comparing with 80,000 deals in our database', 'Matching you with 5,732 investors', 'Reading what those investors say they look for',
         'Writing your report')


def render(c):
    """"Am I ready to pitch?" (founder, 26 Nov 2026): one page in three states, the upload, the wait and the report.
    js/ready.js moves between them; the report itself comes from functions/api/ready.js. Designs: ui-1-upload-v6,
    ui-2-wait-v3, ui-3-result-v4 (project brief, 26 Nov)."""
    steps = ''.join(f'<li><i></i>{s}</li>' for s in STEPS)
    return f'''<main class="rdy" id="rdy">
<section class="rd-up" id="rd-up"><div class="rd-pitch"><p class="rd-cap">The #1 feedback on your pitch deck</p>
<h1>May save years<br>of your life.</h1>
<p class="rd-lede">We love helping founders at the early stage. Nobody loves this problem like we do, so we built the best tool for it.</p></div>
<form class="rd-card" id="rd-form" novalidate>
<label class="rd-drop" id="rd-drop"><input type="file" id="rd-file" accept="application/pdf,.pdf" hidden><b id="rd-dropb">Drop your deck here</b><span id="rd-drops">PDF only, up to 20 MB. From PowerPoint or Keynote? Export as PDF.</span></label>
<label class="rd-lab" for="rd-li">Your LinkedIn</label><input class="rd-in" id="rd-li" type="url" inputmode="url" maxlength="200" placeholder="linkedin.com/in/yourname" autocomplete="url">
<label class="rd-lab" for="rd-note">Anything the deck doesn't say</label>
<div class="rd-ta"><textarea id="rd-note" rows="4" placeholder="Your strategy, what investors told you, what worries you."></textarea><span id="rd-count">0 / 1,000 words</span></div>
<button type="submit" class="rd-go" id="rd-go">Get my report · 10 credits</button><p class="rd-msg" id="rd-msg" aria-live="polite"></p>
<p class="rd-fine">By uploading, you agree we can store and use your deck as described in our <a href="/privacy/" target="_blank" rel="noopener">Privacy Policy</a> and <a href="/terms/" target="_blank" rel="noopener">Terms</a>.</p>
<button type="button" id="rd-signin" data-open="signup" hidden></button></form></section>
<section class="rd-wait" id="rd-wait" hidden><h1>We're reading your deck.</h1>
<p>Your report will be ready in a few minutes.<br>Keep this page open.</p><ol class="rd-prog" id="rd-prog">{steps}</ol></section>
<section class="rd-res" id="rd-res" hidden></section>
</main><script defer src="/ready.js?v={_v('ready.js')}"></script>'''
