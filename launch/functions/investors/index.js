import { renderInvestors } from '../../edge/firm.mjs';
// /investors/ with plain firm links in the first HTML (crawlers). Same visible page once js/firms.js has loaded.
export const onRequestGet = (ctx) => renderInvestors({ request: ctx.request, env: ctx.env, assets: ctx.env.ASSETS });
