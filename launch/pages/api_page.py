"""Public API docs. Uses the existing page shell, type, and section classes."""

def render(c):
    E = c.E
    P = c.S['pages']['api']
    blocks = []
    for block in P['blocks']:
        method = f'<p class="psub">{E(block["method"])}</p>' if block.get('method') else ''
        example = ''
        if block.get('example'):
            example = (
                '<div class="card"><p style="overflow-wrap:anywhere;white-space:pre-wrap">'
                f'{E(block["example"])}</p></div>'
            )
        blocks.append(
            f'<section class="ps"><h2>{E(block["h2"])}</h2>{method}<p>{E(block["text"])}</p>{example}</section>'
        )
    return (
        f'<main class="wrap"><div class="hd"><div><h1>{E(P["h1"])}</h1>'
        f'<p class="m">{E(P["lead"])}</p></div></div>'
        + ''.join(blocks)
        + f'<p class="fine">{E(P["fine"])}</p></main>'
    )
