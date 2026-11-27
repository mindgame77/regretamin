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
    assert 'env.ANTHROPIC_API_KEY ? [askClaude, askGemini] : [askGemini, askClaude]' in fn and 'both && (got.error' in fn   # Claude is asked first; Gemini is the spare when both keys are set
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
    assert js.index("const mark = await fingerprint(buf)") < js.index("sb.storage.from('decks').upload")   # before any upload or model call


def test_firm_links_open_in_a_new_page_and_reports_are_listed_in_the_account():
    """Founder, 26 Nov: "those links should open in new pages", "save reports in your account", then "separate page ... my score ... or you can download the PDF"."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    assert js.count('target="_blank" rel="noopener" href="/vc/') == 2 and 'href="/vc/${' not in js.replace('rel="noopener" href="/vc/${', '')
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
    assert "fetch('/api/research'" in js and 'id="rd-s3"' in js and "researchHtml(r.research, r)" in js   # saved research reopens with the report
    assert "Pitch these instead" not in js   # it repeated step 4 (founder, 26 Nov)
    for words in ("Your competitors", "Your investors", "Skip these firms", 'class="rd-pb"', "Who tried this before", "Your ask against similar rounds", "Our data", "Looked up",
                  "They have", "In the news", "Your move", "Do this next", "Read what happened", "'ABCD'"):   # lettered parts, each ending with one thing to do
        assert words in js, words
    assert 'class="rd-ft' in js and "const ICON = {" in js and "the firm badges' own" in js   # facts are icon rows in blocks
    assert "const AWARDED = [" in js and js.count("bdg(") == 1   # the pill is kept for badges the site awarded a firm (founder, 26 Nov: "pill system no ... something special")
    assert open(os.path.join(ROOT, "launch", "edge", "card", "badge.mjs")).read().count("M13.800 1.500L4.500 13.600h6.300L9.200 22.500l10.300-12.700h-6.600z") == 1 and "M13.800 1.500L4.500 13.600h6.300L9.200 22.500l10.300-12.700h-6.600z" in js   # the same bolt
    fn = open(os.path.join(ROOT, "launch", "functions", "api", "research.js")).read()
    assert "web_search_20250305" in fn and "v2_ready_research" in fn and "temperature" not in fn.replace("no temperature", "") and "pause_turn" in fn
    assert 'rel="noopener nofollow"' in js and "↗" in js   # a link that leaves the site says so and opens in a new page
    assert "worked_at" in open(os.path.join(ROOT, "supabase", "migrations", "20261126223349_v2_ready_research_founders.sql")).read()
    assert "v2_ready_firm_tips" in fn and os.path.exists(os.path.join(ROOT, "supabase", "migrations", "20261126225255_v2_ready_firm_tips.sql"))
    mig = open(os.path.join(ROOT, "supabase", "migrations", "20261126221958_v2_ready_research.sql")).read()
    assert "to_regclass('public.v2_deals') is null" in mig and "from public, anon" in mig   # skips on a database without the v2 tables; signed-in callers only


def test_the_free_report_shows_two_firms_and_the_research_holds_the_reasoning():
    """Founder, 26 Nov: "on the first step we should show 2 VCs, and here we should show reasoning"; "no one cares how many LinkedIn followers they have"."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    assert "const FREE_FIRMS = 2;" in js and "firms.slice(0, FREE_FIRMS).map(firmRow)" in js
    assert "more firm${rest === 1 ? '' : 's'}, and why each one fits you, in the full research." in js
    row = js[js.index("function firmRow(f, i) {"):js.index("function moreFirms(r) {")]
    assert "stage_pct" not in row and "f.say" not in row and "summary" not in row   # the reasoning is not in the free rows
    assert "Why we suggest it" in js and "How to get in" in js and "What to say" in js and "Then these: big firms" in js
    rules = open(os.path.join(ROOT, "launch", "functions", "api", "_ready", "research.js")).read()
    assert "followers on" not in rules and "k: 'aud'" not in rules


def test_feedback_of_26_nov_after_the_first_real_research():
    """Founder, 26 Nov: the paid part is orange and step 4 goes once it is there; no "go now" under 8; flags say Rewrite or Earn it;
    no news older than ten years; the PDF is plain text."""
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    css = open(os.path.join(ROOT, "launch", "style.css")).read()
    assert "'rd-st3', 'rd-paid')" in js and "if (st4) st4.remove();" in js and 'Full research <span class="rd-tag">Paid</span>' in js
    assert ".rd-paid .rd-box{background:#FDEBD7" in css
    assert "deck >= 8" in js and "Fix your red flags first, then go." in js and "Fix the red flags in step ${redStep(r)} first. Then press Pitch." in js
    assert "'Earn it' : 'Rewrite'" in js
    assert "new Date().getFullYear() - 10" in js
    assert "no squares" in css and ".rd-paid .rd-box{background:none!important" in css.replace(",.rd-paid .rd-box{", ".rd-paid .rd-box{")


def test_firms_where_you_are_peers_feedback_and_copy_for_ai():
    """Founder, 26 Nov: firms that invest where the founder is (asked when the deck does not say), what founders who raised as much
    had, the rounds a firm usually joins, a feedback box, and the report as text for an AI."""
    for name in ("api.test.mjs",):
        r = subprocess.run(['node', '--test', os.path.join(ROOT, 'launch', 'functions', 'api', '_ready', name)], capture_output=True, text=True)
        assert r.returncode == 0, r.stdout[-2000:] + r.stderr[-2000:]
    js = open(os.path.join(ROOT, "launch", "js", "ready.js")).read()
    api = open(os.path.join(ROOT, "launch", "functions", "api", "ready.js")).read()
    assert "v2_ready_firms_geo" in api and "|| (await ask('v2_ready_firms', args))" in api   # the older pick answers until the new one is there
    assert "Where are you based?" in js and "Update the firms" in js and "body: JSON.stringify({ id: REPORT, country: c })" in js
    assert "from your country" in js and "Usually joins rounds of" in js and "What the founders who raised" in js
    assert 'id="rd-ai">Copy for AI' in js and "Do not invent numbers, customers or facts." in js and "navigator.clipboard.writeText(forAI(r))" in js
    # Feedback is one box with one line that opens when pressed (founder, 26 Nov: "Make it one box ... just a line").
    assert js.count("<textarea") == 1 and 'id="rd-fbt" rows="1"' in js and "What\\'s good, what\\'s missing, what\\'s wrong?" in js
    assert "from('ready_feedback').insert(row)" in js and "t.classList.add('on')" in js
    # Every block is numbered down the page, What's good first and Feedback last (founder, 26 Nov: "one should be at what's good").
    assert "step(1, `<h2>What's good</h2>" in js and 'class="rd-step rd-fb" id="rd-fb" hidden><div class="rd-rail">' in js
    assert js.count("renumber();") >= 3 and "rail.querySelector('span').textContent = i + 1" in js
    css = open(os.path.join(ROOT, "launch", "style.css")).read()
    assert ".rd-step[hidden]{display:none}" in css and ".rd-good .rd-box{background:#EAF4EC}" in css
    assert "probe.error" in js   # the feedback box stays hidden until its table exists


def test_the_upload_form_points_to_the_privacy_policy_and_terms():
    """Founder, 26 Nov: the Terms and the upload form must say that uploading lets us use the deck."""
    src = open(os.path.join(ROOT, "launch", "pages", "ready.py")).read()
    assert 'By uploading, you agree we can store and use your deck as described in our' in src
    assert 'href="/privacy/" target="_blank"' in src and 'href="/terms/" target="_blank"' in src


def test_a_person_can_delete_their_own_deck_and_report():
    app = read('launch', 'js', 'app.js')
    assert "storage.from('decks').remove([r.deck_path])" in app and "from('ready_reports').delete().eq('id', r.id)" in app
    assert app.index("storage.from('decks').remove") < app.index(".delete().eq('id', r.id)")   # the file goes first, then the report
    assert "We cannot bring them back." in app and "Delete for good" in app and "Keep it" in app    # asks before deleting
    sql = read('supabase', 'migrations', '20261127021405_ready_delete.sql')
    assert "ready_reports_owner_delete" in sql and "user_id = auth.uid()" in sql
    assert "decks_owner_delete" in sql and "(storage.foldername(name))[1] = auth.uid()::text" in sql
    assert "to anon" not in sql


def test_the_deck_is_uploaded_from_a_copy_in_memory_and_a_dropped_connection_gets_one_more_go():
    """27 Nov 2026, 8:02 AM PT: three tries from an Android phone, the server saw the preflight and never the upload."""
    js = open(os.path.join(ROOT, 'launch/js/ready.js')).read()
    assert 'buf = await file.arrayBuffer()' in js and 'We could not read that file' in js   # unreadable file: said plainly, no upload
    assert 'new Blob([buf], { type: \'application/pdf\' })' in js and "upload(path, body," in js   # uploaded from the copy, never from the picked file
    assert js.count("sb.storage.from('decks').upload(") == 2 and 'upsert: false' in js            # one quiet second go
    assert '413' in js and 'That file is too large' in js                                          # too big is not retried and is said as it is
    assert 'Check your connection and try again.' in js


def test_a_file_that_is_not_a_pdf_is_told_what_we_accept_and_how_to_make_a_pdf():
    """Founder, 27 Nov 2026: say which formats we do not take (pictures, PowerPoint, Keynote) and that PDF is the one."""
    js = open(os.path.join(ROOT, 'launch/js/ready.js')).read()
    assert 'We cannot open PowerPoint files yet' in js and 'File, then Save As, then PDF' in js
    assert 'We cannot open Keynote files yet' in js and 'File, then Export To, then PDF' in js
    assert 'We cannot read pictures' in js and 'in Google Slides: File, Download, PDF' in js
    assert 'notPdf(f)' in js
    html = open(os.path.join(ROOT, 'launch/pages/ready.py')).read()
    assert 'PDF only, up to 20 MB. From PowerPoint or Keynote? Export as PDF.' in html
