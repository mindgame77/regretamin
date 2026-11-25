"""The map page (/map/): where VC firms are based and what they invest in.

The page is drawn by js/map.js from three read-only database functions (docs/map_functions.sql).
It is not linked from the navigation and is not indexed while it is being reviewed.
"""


def render(c, root='../'):
    v = c._v('js/map.js'); vf = c._v('js/founders.js')
    return ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
            '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap">'
            # The headline and one line of text are in the page source for search engines and for the moment before the
            # map draws; js/map.js replaces everything inside <main> with the map, which shows the same headline.
            '<main class="vm" id="vm"><div class="vm-seo"><h1>What VCs are investing in.</h1>'
            '<p>A live map of venture capital: where VC firms are based, which sectors they back and where it is heating up. '
            'Pick a place to see its investors, then research any firm before you take the meeting or the money.</p></div>'
            '<noscript><p class="vm-msg">The map needs JavaScript.</p></noscript></main>'
            # founders.js first: map.js may open the Founders view as soon as it starts (a link with ?view=founders, or coming back to it)
            f'<script defer src="{root}founders.js?v={vf}"></script><script defer src="{root}map.js?v={v}"></script>')


def render_home(c):
    # The map is the home page of the new site (founder's decision, 2026-11-22).
    return render(c, '')
