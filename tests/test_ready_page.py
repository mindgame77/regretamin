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
    assert "<span>Score</span>" in js and "What's good" in js and "tile('Deck', scores.deck) + tile('Founders', scores.founders)" in js   # 10 is best; good things first


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
