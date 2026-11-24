// /share/vc/<slug>.png: the firm share card, drawn from the database when it is asked for.
// One database read (v2_firm_share_card), three fonts from the site's own files, a PNG back. Kept for an hour.
import { satori, initSatori, initYoga, Resvg, initResvg } from './lib.mjs';
import { cardTree, W, H } from './card.mjs';
import { sectorColor } from './sectors.mjs';

export const FALLBACK = '/assets/share/home.png';  // the site's general share picture, when a card cannot be drawn
const FONTS = [['Geist', 400, '/assets/fonts/Geist-Regular.ttf'], ['Geist', 600, '/assets/fonts/Geist-SemiBold.ttf'], ['Geist Mono', 400, '/assets/fonts/GeistMono-Regular.ttf']];

export function slugOf(param) {
  const m = /^([a-z0-9][a-z0-9-]{0,119})\.png$/.exec(String(param || ''));
  return m ? m[1] : null;
}
// The database row -> what the card shows.
export function cardData(row) {
  if (!row || !row.name) return null;
  return {
    name: row.name, hq: row.hq || '', status: row.status || 'Not checked yet', last_deal: row.last_deal || null,
    deals_year: Number(row.deals_year) || 0, deals_all: Number(row.deals_all) || 0,
    signals: Array.isArray(row.signals) ? row.signals : [],
    sectors: (Array.isArray(row.sectors) ? row.sectors : []).filter(Boolean).slice(0, 3).map((name) => ({ name, color: sectorColor(name) })),
  };
}

let ready = null, fontData = null;
// wasm: { yoga, resvg } as WebAssembly modules (the function imports them) or bytes (tests).
function engine(wasm) {
  if (!ready) ready = (async () => { initSatori(await initYoga(wasm.yoga)); await initResvg(wasm.resvg); })().catch((e) => { ready = null; throw e; });
  return ready;
}
async function fonts(assets, origin) {
  if (!fontData) {
    fontData = Promise.all(FONTS.map(async ([name, weight, path]) => {
      const r = await assets.fetch(new URL(path, origin));
      if (!r.ok) throw new Error('font ' + path + ' ' + r.status);
      return { name, weight, style: 'normal', data: await r.arrayBuffer() };
    })).catch((e) => { fontData = null; throw e; });
  }
  return fontData;
}
export async function drawCard(data, { wasm, fontList }) {
  await engine(wasm);
  const svg = await satori(cardTree(data), { width: W, height: H, fonts: fontList });
  return new Resvg(svg, { fitTo: { mode: 'width', value: W } }).render().asPng();
}

export async function shareCard({ request, env, assets, param, wasm, fetchImpl = fetch }) {
  const url = new URL(request.url);
  const fallback = () => Response.redirect(new URL(FALLBACK, url.origin).toString(), 302);
  const slug = slugOf(param);
  if (!slug) return new Response('Not found', { status: 404 });
  try {
    const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/v2_firm_share_card`, {
      method: 'POST',
      headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'content-type': 'application/json' },
      body: JSON.stringify({ p_slug: slug }),
    });
    if (!r.ok) return fallback();
    const data = cardData(await r.json());
    if (!data) return fallback();   // not a public firm: the general picture
    const png = await drawCard(data, { wasm, fontList: await fonts(assets, url.origin) });
    return new Response(png, { headers: { 'content-type': 'image/png', 'cache-control': 'public, max-age=3600' } });
  } catch (e) {
    return fallback();
  }
}
