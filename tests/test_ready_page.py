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


def test_the_function_keeps_the_key_on_the_server_and_only_serves_the_owner():
    fn = read('launch', 'functions', 'api', 'ready.js')
    assert 'env.ANTHROPIC_API_KEY' in fn and "error: 'no_key'" in fn
    assert '/auth/v1/user' in fn and 'startsWith(`${user.id}/`)' in fn
    assert "type: 'document', source: { type: 'url'" in fn and 'expiresIn: 900' in fn
    assert 'ANTHROPIC_API_KEY' not in read('launch', 'js', 'ready.js')


def test_the_fixed_rules():
    r = subprocess.run(['node', '--test', os.path.join(ROOT, 'launch', 'functions', 'api', '_ready', 'rules.test.mjs')], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
