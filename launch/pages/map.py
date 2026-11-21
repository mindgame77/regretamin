"""The map page (/map/): where VC firms are based and what they invest in.

The page is drawn by js/map.js from three read-only database functions (docs/map_functions.sql).
It is not linked from the navigation and is not indexed while it is being reviewed.
"""


def render(c):
    v = c._v('js/map.js')
    return ('<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
            '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap">'
            '<main class="vm" id="vm"><noscript><p class="vm-msg">The map needs JavaScript.</p></noscript></main>'
            f'<script defer src="../map.js?v={v}"></script>')
