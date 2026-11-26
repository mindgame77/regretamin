import { badgeResponse } from '../../../edge/card/badge.mjs';
import resvg from '../../../edge/card/resvg.wasm';
// /badge/<slug>/<signal>-<look>.png: a firm's badge (edge/card/badge.mjs). The edge keeps a drawn badge for an hour.
export async function onRequestGet(ctx) {
  const cache = caches.default, key = new Request(new URL(ctx.request.url).toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return hit;
  const res = await badgeResponse({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS, slug: ctx.params.slug, file: ctx.params.file, wasm: { resvg } });
  if (res.status === 200) ctx.waitUntil(cache.put(key, res.clone()));
  return res;
}
