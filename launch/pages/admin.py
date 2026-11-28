import hashlib, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _v(name):
    return hashlib.sha256(open(os.path.join(HERE, 'js', name), 'rb').read()).hexdigest()[:10]


def render(c):
    """The admin analytics page (28 Nov 2026, claude/plans/admin-analytics.md). It is not linked anywhere and everyone starts on the
    normal "page not found" below. js/admin.js asks the database whether the signed-in account is an admin and only then draws the page;
    the numbers themselves come from admin_report(), which returns nothing to anyone else, so this page is the polite door, the database is the lock."""
    p = c.S["pages"]["404"]
    return (f'<main class="wrap" id="adm404"><div class="hero"><h1>{c.E(p["h1"])}</h1><p>{c.E(p["body"])}</p>{c.SB()}</div></main>'
            f'<main class="adm" id="adm" hidden></main><script defer src="/admin.js?v={_v("admin.js")}"></script>')
