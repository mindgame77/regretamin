"""Am I ready to pitch? (founder, 26 Nov 2026): the orange header link on every page, the upload page, and the
function that turns a deck into a report. First working version: no credits, no email, PDF only."""
import json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'launch'))


def read(*p):
    return open(os.path.join(ROOT, *p), encoding='utf-8').read()


def test_the_header_link_is_on_every_page_and_orange():
    from pages import registry
    site = json.loads(read('launch', 'copy.json'))['site']
    assert site['pages']['ready']['nav_label'] == 'Am I ready to pitch?'
    nav = registry.nav_links(site, '../', 'main', 'ready')
    assert '<a href="../ready/" class="on" aria-current="page" id="readynav">Am I ready to pitch?</a>' in nav
    assert nav.index('how-we-check') < nav.index('readynav') < nav.index('login')
    assert re.search(r'nav a#readynav\{[^}]*background:#F0861E', read('launch', 'style.css'))
    # the black firm-page button it replaces is no longer put into the header
    assert 'readyButton(main);' not in read('launch', 'js', 'company.js')


def test_the_page_asks_only_for_the_deck_linkedin_and_a_note():
    from pages import ready
    html = ready.render(None)
    assert 'May save years<br>of your life.' in html and 'The #1 feedback on your pitch deck' in html
    assert html.count('<input') == 2 and html.count('<textarea') == 1          # the file, LinkedIn, the note
    assert 'accept="application/pdf,.pdf"' in html and 'up to 20 MB' in html
    for gone in ('Stage', 'Raising', 'Based in'):
        assert gone not in html
    assert html.count('<li><i></i>') == 7 and 'Get my report' in html
    js = read('launch', 'js', 'ready.js')
    assert "20 * 1024 * 1024" in js and "from('decks').upload(" in js and "fetch('/api/ready'" in js
    assert "'js/ready.js'" in read('launch', 'build.py')
    assert 'class="rd-cup"' in js and 'g.score >= 9 ? CUP' in js and 'class="rd-mark">${CUP}' in js   # great points and great fits carry the cup
    assert 'class="rd-fire"' in js and 'Special in your field' in js
    assert '12<i>/10</i>' in js   # founder, 26 Nov: the fire is 12 out of 10   # the fire: rare, only what is special in the field
    assert "<span>Score</span>" in js and "What's good" in js and "tile('Deck', scores.deck)" in js and 'Founders for this startup' not in js and 'rd-plan' not in js   # 10 is best; good things first


def test_the_function_keeps_the_key_on_the_server_and_only_serves_the_owner():
    fn = read('launch', 'functions', 'api', 'ready.js')
    assert 'env.ANTHROPIC_API_KEY' in fn and 'env.GEMINI_API_KEY' in fn and "error: 'no_key'" in fn
    assert "'gemini-4-neon'" in fn and 'x-goog-api-key' in fn   # Gemini is used when its key is there
    assert 'env.GEMINI_API_KEY && env.ANTHROPIC_API_KEY && (got.error' in fn      # and Claude is the spare when both keys are set
    assert '/auth/v1/user' in fn and 'startsWith(`${user.id}/`)' in fn
    assert "type: 'document', source: { type: 'url'" in fn and 'expiresIn: 900' in fn
    assert 'API_KEY' not in read('launch', 'js', 'ready.js')
    assert 'temperature' not in fn.replace('no temperature', '')   # Opus 5.5 refuses the setting; the first live try failed on it


def test_the_fixed_rules():
    r = subprocess.run(['node', '--test', os.path.join(ROOT, 'launch', 'functions', 'api', '_ready', 'rules.test.mjs')], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]


def test_the_same_deck_sent_again_shows_the_saved_report():
    """Founder, 26 Nov: "if the deck is the same, we just say ... you already sent us this deck. Here is the result"."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    assert "You already sent us this deck. Here is the result." in js
    assert "crypto.subtle.digest('SHA-256'" in js                      # the file's fingerprint
    assert ".like('deck_path', session.user.id + '/' + mark + '-%')" in js   # looked up among the founder's own reports only
    assert js.index("const mark = await fingerprint(file)") < js.index("sb.storage.from('decks').upload")   # before any upload or model call


def test_firm_links_open_in_a_new_page_and_reports_are_listed_in_the_account():
    """Founder, 26 Nov: "those links should open in new pages", "save reports in your account", then "separate page ... my score ... or you can download the PDF"."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    assert js.count('target="_blank" rel="noopener" href="/vc/') == 3 and 'href="/vc/${' not in js.replace('rel="noopener" href="/vc/${', '')
    app = open(os.path.join(ROOT, "launch", "js", "app.js")).read()
    assert "paintMyScore" in app and "from('ready_reports')" in app and "ready/?report=" in app and "&pdf=1" in app
    reg = open(os.path.join(ROOT, "launch", "pages", "registry.py")).read()
    assert "Page('account/score', my_score.render, nav='account', noindex=True)" in reg   # its own page, "My score", in the account menu
    assert json.load(open(os.path.join(ROOT, "launch", "copy.json")))["site"]["pages"]["account/score"]["nav_label"] == "My score"
    assert "get('pdf')" in js and "window.print()" in js   # Download PDF opens the report and the save-as-PDF box


def test_the_pdf_says_it_was_made_with_regretamin():
    """Founder, 26 Nov: "in PDF, there should be something about Regretamin, like done with Regretamin"."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    css = open(os.path.join(ROOT, "launch", "style.css")).read()
    assert "Made with Regretamin · regretamin.com" in js
    assert ".rd-made{display:none}" in css and "@media print{.rd-made{display:flex!important" in css   # in the PDF only, not on the page


def test_the_full_research():
    """Founder, 26 Nov: "What's next? Full research." Step 3 opens in place; looked-up rows need a real source."""
    r = subprocess.run(['node', '--test', os.path.join(ROOT, 'launch', 'functions', 'api', '_ready', 'research.test.mjs')], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    assert "fetch('/api/research'" in js and 'id="rd-s3"' in js and "researchHtml(r.research)" in js   # saved research reopens with the report
    assert "Pitch these instead" not in js   # it repeated step 4 (founder, 26 Nov)
    for words in ("Your competitors", "Firms that hold a competitor", "Who tried this before", "Your ask against similar rounds", "Our data", "Looked up",
                  "They have", "In the news", "Your move", "Do this next", "Read what happened", "'ABCD'"):   # lettered parts, each ending with one thing to do
        assert words in js, words
    fn = open(os.path.join(ROOT, "launch", "functions", "api", "research.js")).read()
    assert "web_search_20250305" in fn and "v2_ready_research" in fn and "temperature" not in fn.replace("no temperature", "") and "pause_turn" in fn
    assert 'rel="noopener nofollow"' in js and "↗" in js   # a link that leaves the site says so and opens in a new page
    assert "worked_at" in open(os.path.join(ROOT, "supabase", "migrations", "20261126223349_v2_ready_research_founders.sql")).read()
    mig = open(os.path.join(ROOT, "supabase", "migrations", "20261126221958_v2_ready_research.sql")).read()
    assert "to_regclass('public.v2_deals') is null" in mig and "from public, anon" in mig   # skips on a database without the v2 tables; signed-in callers only
