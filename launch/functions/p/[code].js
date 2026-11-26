// /p/<code>: a personal share link (share to unlock; founder, 25 Nov). It counts the visit, notes when it is X opening
// the link (X's preview robot reads a link the moment it is posted, and a visitor can arrive from X), and sends everyone
// on to the Pathfinders view. The database keeps the codes (v2_share_codes); nothing here knows who the code belongs to.
export async function onRequest(ctx) {
  const code = String((ctx.params && ctx.params.code) || '').toUpperCase();
  const ua = ctx.request.headers.get('user-agent') || '', ref = ctx.request.headers.get('referer') || '';
  const fromX = /Twitterbot/i.test(ua) || /^https?:\/\/(t\.co|x\.com|([a-z]+\.)?twitter\.com)(\/|$)/i.test(ref);
  const env = ctx.env || {};
  if (/^[A-Z0-9]{4,12}$/.test(code) && env.SUPABASE_URL && env.SUPABASE_ANON_KEY) {
    ctx.waitUntil(fetch(`${env.SUPABASE_URL}/rest/v1/rpc/v2_share_hit`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ p_code: code, p_from_x: fromX }),
    }).catch(() => {}));
  }
  return Response.redirect(new URL('/?view=pathfinders', ctx.request.url).toString(), 302);
}
