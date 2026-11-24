import { shareCard } from '../../../edge/card/share.mjs';
import yoga from '../../../edge/card/yoga.wasm';
import resvg from '../../../edge/card/resvg.wasm';
// /share/vc/<slug>.png: the picture for a shared firm link. The edge keeps a drawn card for an hour.
export async function onRequestGet(ctx) {
  const cache = caches.default, key = new Request(new URL(ctx.request.url).toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return hit;
  const res = await shareCard({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS, param: ctx.params.slug, wasm: { yoga, resvg } });
  if (res.status === 200) ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}
