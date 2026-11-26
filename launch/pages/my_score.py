def render(c):
    """My score (founder, 26 Nov 2026): the account's "Am I ready to pitch?" reports on a page of their own.
    Each row opens the saved report; "Download PDF" opens it and starts the browser's save-as-PDF."""
    P = c.S['pages']
    return f'''<main class="ac" id="myscore"><h1>{P["account/score"]["nav_label"]}</h1>{c.signed_out("account")}<div data-in hidden>
<div class="card rpl" id="myrepl" hidden></div>
<a class="btn" id="msgo" href="../../ready/" hidden>{P["ready"]["nav_label"]}</a></div></main>'''
