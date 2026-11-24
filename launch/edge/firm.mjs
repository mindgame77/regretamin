import STATIC from './static-pages.mjs';
// Edge rendering for firm pages (Cloudflare Pages Functions). Mirrors launch/build.py firm_desc/firm_head/fill:
// keep the two identical (tests/test_dynamic_pages.py renders both and compares byte for byte).
export const SITE = 'https://regretamin.com/';
export const SUFFIX = ' · Regretamin';
export const BRAND = 'Regretamin';
export const SITEMAP_SIZE = 1000; // firms per sitemap file: the API returns at most 1,000 rows (1 URL each; /full/ is noindex and not listed)
export const DIR_SIZE = 100; // /investors/ plain links per page
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,99}$/;

// Same as Python html.escape(s, quote=True)
export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');

export function firmDesc(F) {
  const bits = [F.firm_type, F.hq].filter(Boolean).map(esc).join(', ');
  return `Background check on ${esc(F.name)}` + (bits ? ` (${bits})` : '') + ': SEC filings, legal matters, team changes and 10 checks before you take the meeting or the money.';
}

// SEO title / description come from v2_firm_seo (firm_meta_seo). No stored row: today's text.
export const firmTitle = (F) => (F.seo_title && String(F.seo_title).trim()) ? String(F.seo_title).trim() : F.name + SUFFIX;
export const firmDescText = (F) => (F.seo_description && String(F.seo_description).trim()) ? esc(String(F.seo_description).trim()) : firmDesc(F);
const facts = (F) => (F.seo_facts && typeof F.seo_facts === 'object' && !Array.isArray(F.seo_facts)) ? F.seo_facts : null;
const str = (v) => (typeof v === 'string' && v.trim()) ? v.trim() : null;
const https = (u) => (typeof u === 'string' && /^https?:\/\/[^\s"<>]+$/i.test(u)) ? u : null;
const list = (v) => Array.isArray(v) ? v : [];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// "2026-03-31" -> "Mar 31, 2026" (same as launch/js/dates.js for a plain date)
export function fmtDay(d) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(d || ''));
  return m ? `${MON[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}` : '';
}
const hostOf = (u) => { const m = /^https?:\/\/(?:www\.)?([^/:?#]+)/i.exec(u || ''); return m ? m[1].toLowerCase() : ''; };

function orgLd(F, X) {
  const org = { '@type': 'Organization', name: F.name };
  const legal = (X && str(X.legal_name)) || F.legal_name;
  if (legal) org.legalName = legal;
  const site = (X && https(X.website)) || (F.primary_domain ? 'https://' + F.primary_domain : null);
  if (site) org.url = site;
  const a = X && X.address && typeof X.address === 'object' ? X.address : null;
  if (a && (str(a.city) || str(a.region) || str(a.country))) {
    const pa = { '@type': 'PostalAddress' };
    if (str(a.street)) pa.streetAddress = str(a.street);
    if (str(a.city)) pa.addressLocality = str(a.city);
    if (str(a.region)) pa.addressRegion = str(a.region);
    if (str(a.postal)) pa.postalCode = str(a.postal);
    if (str(a.country)) pa.addressCountry = str(a.country);
    org.address = pa;
  } else if (F.hq) org.address = F.hq;
  const fy = (X && X.founded) || F.founded_year;
  if (fy) org.foundingDate = String(fy);
  if (X) {
    const same = [...list(X.social).map(https), ...list(X.registry).map((r) => r && https(r.url))].filter(Boolean);
    if (same.length) org.sameAs = [...new Set(same)];
    const ids = list(X.registry).filter((r) => r && str(r.type) && str(r.value)).map((r) => ({ '@type': 'PropertyValue', propertyID: str(r.type), value: str(r.value) }));
    if (ids.length) org.identifier = ids;
    const ppl = list(X.leaders).filter((p) => p && str(p.name));
    const person = (p) => { const o = { '@type': 'Person', name: str(p.name) }; if (str(p.title)) o.jobTitle = str(p.title); return o; };
    if (ppl.some((p) => p.founder)) org.founder = ppl.filter((p) => p.founder).map(person);
    if (ppl.some((p) => !p.founder)) org.employee = ppl.filter((p) => !p.founder).map(person);
  }
  return org;
}

// Python json.dumps(ensure_ascii=False, separators=(',', ':')) == JSON.stringify for these plain objects
export function firmHead(F, full = false) {
  const url = `${SITE}vc/${F.slug}/` + (full ? 'full/' : '');
  const X = facts(F);
  const title = esc(firmTitle(F));
  const d = firmDescText(F);
  // Paywalled-content markup: the check table (.gveil, blurred until 1 credit is spent) is not free.
  const page = { '@type': 'WebPage', '@id': url, name: firmTitle(F), url };
  if (str(F.seo_description)) page.description = str(F.seo_description);
  if (X && str(X.last_checked)) page.dateModified = str(X.last_checked);
  page.mainEntity = orgLd(F, X);
  page.breadcrumb = { '@id': url + '#breadcrumb' };
  page.isAccessibleForFree = false;
  page.hasPart = { '@type': 'WebPageElement', isAccessibleForFree: false, cssSelector: '.gveil' };
  const crumbs = { '@type': 'BreadcrumbList', '@id': url + '#breadcrumb', itemListElement: [
    { '@type': 'ListItem', position: 1, name: BRAND, item: SITE },
    { '@type': 'ListItem', position: 2, name: 'Investors', item: SITE + 'investors/' },
    { '@type': 'ListItem', position: 3, name: F.name, item: `${SITE}vc/${F.slug}/` }] };
  const ld = { '@context': 'https://schema.org', '@graph': [page, crumbs] };
  const ldj = JSON.stringify(ld).replace(/</g, '\\u003c').replace(/>/g, '\\u003e').replace(/&/g, '\\u0026');
  // /full/ is noindex, follow (Alex, Oct 23) with a self canonical; it is also left out of the sitemaps.
  // Firms not ready for Google (v2_firm_seo.seo_indexable false: not researched or too few facts) are noindex, follow too, and not in the sitemaps.
  return (full || F.indexable === false ? '<meta name="robots" content="noindex, follow">' : '') + `<meta name="description" content="${d}"><link rel="canonical" href="${url}">` +
    `<meta property="og:type" content="website"><meta property="og:site_name" content="${BRAND}"><meta property="og:title" content="${title}">` +
    `<meta property="og:description" content="${d}"><meta property="og:url" content="${url}">` +
    // The firm share card is drawn on request by functions/share/vc/[slug].js. Keep identical to launch/build.py.
    `<meta property="og:image" content="${SITE}share/vc/${F.slug}.png"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">` +
    `<meta name="twitter:card" content="summary_large_image">` +
    `<script type="application/ld+json">${ldj}</script>`;
}

// Server-rendered facts in the first HTML (crawlers and AI tools that do not run JS). Only facts the page already
// shows: HQ, founded, website, sectors, stages, latest deal, team. js/company.js replaces both blocks on load, so the
// page looks exactly as before once it has loaded. No stored facts: today's grey loading shapes.
export const SK_META = '<i class="sk" style="width:300px"></i>';
export function firmMeta(F) {
  const X = facts(F);
  if (!X) return SK_META;
  const site = https(X.website), host = hostOf(site);
  const bits = [str(X.hq) ? esc(str(X.hq)) : '', X.founded ? esc(`Founded ${X.founded}`) : '',
    host ? `<a href="${esc(site)}" target="_blank" rel="noopener">${esc(host)}</a>` : ''].filter(Boolean);
  return bits.length ? bits.join(' · ') : SK_META;
}
export function firmMain(F, skeleton) {
  const X = facts(F);
  if (!X) return skeleton;
  const n = esc(F.name);
  const kv = (k, v) => `<div class="kv"><span class="k">${esc(k)}</span><span>${v}</span></div>`;
  const rows = [];
  if (str(X.hq)) rows.push(kv('HQ', esc(str(X.hq))));
  if (X.founded) rows.push(kv('Founded', esc(String(X.founded))));
  const site = https(X.website);
  if (site) rows.push(kv('Website', `<a href="${esc(site)}" target="_blank" rel="noopener">${esc(hostOf(site))}</a>`));
  const sec = list(X.sectors).map(str).filter(Boolean);
  if (sec.length) rows.push(kv('Sectors', esc(sec.join(', '))));
  const stg = list(X.stages).map(str).filter(Boolean);
  if (stg.length) rows.push(kv('Stages', esc(stg.join(', '))));
  if (str(X.latest_company) && str(X.latest_deal_date)) rows.push(kv('Last deal', esc(`${str(X.latest_company)} · ${fmtDay(X.latest_deal_date)}`)));
  const team = list(X.leaders).filter((p) => p && str(p.name));
  let out = '';
  if (rows.length) out += `<section class="ps" id="seo-facts"><h2>${n} at a glance</h2><div class="kvs">${rows.join('')}</div></section>`;
  if (team.length) out += `<section class="ps" id="seo-team"><h2>${n} team</h2><div class="kvs">${team.map((p) => kv(str(p.name), esc(str(p.title) || ''))).join('')}</div></section>`;
  return out || skeleton;
}

// Official SEC names arrive in ALL CAPS; /full/ shows them in normal (title) case, display only. Keep identical to sec_title() in launch/build.py.
const SEC_KEEP = {'LLC': 'LLC', 'L.L.C.': 'L.L.C.', 'L.L.C': 'L.L.C', 'LP': 'LP', 'L.P.': 'L.P.', 'L.P': 'L.P', 'LLP': 'LLP', 'L.L.P.': 'L.L.P.',
  'INC': 'Inc', 'INC.': 'Inc.', 'LTD': 'Ltd', 'LTD.': 'Ltd.', 'CO': 'Co', 'CO.': 'Co.', 'CORP': 'Corp', 'CORP.': 'Corp.',
  'PLC': 'PLC', 'GP': 'GP', 'SA': 'SA', 'S.A.': 'S.A.', 'AG': 'AG', 'GMBH': 'GmbH', 'SARL': 'SARL', 'S.A.R.L.': 'S.à r.l.',
  'BV': 'BV', 'B.V.': 'B.V.', 'NV': 'NV', 'AB': 'AB', 'AS': 'AS', 'SPA': 'SpA', 'PTE': 'Pte', 'PTY': 'Pty', 'LLLP': 'LLLP',
  'A16Z': 'a16z', 'YC': 'YC', 'ES20': 'ES20', 'US': 'US', 'USA': 'USA', 'UK': 'UK', 'VC': 'VC', 'AI': 'AI', 'II': 'II', 'III': 'III', 'IV': 'IV', 'VI': 'VI',
  'VII': 'VII', 'VIII': 'VIII', 'IX': 'IX', 'XI': 'XI', 'XII': 'XII', 'NEA': 'NEA', 'IVP': 'IVP', 'KKR': 'KKR', 'TPG': 'TPG',
  'GGV': 'GGV', 'USV': 'USV', 'TCV': 'TCV', 'IDG': 'IDG', 'NFX': 'NFX', 'DST': 'DST', 'EQT': 'EQT', 'QED': 'QED', 'SOSV': 'SOSV',
  'HV': 'HV', 'GV': 'GV', 'DCM': 'DCM', 'JMI': 'JMI', 'TA': 'TA', 'RRE': 'RRE', 'FPV': 'FPV', 'AVF': 'AVF', 'ESP': 'ESP', 'HIG': 'HIG',
  'H.I.G.': 'H.I.G.', 'UBS': 'UBS', 'LGT': 'LGT', 'GCM': 'GCM', 'HGGC': 'HGGC', 'BVP': 'BVP',
  'SEC': 'SEC', 'FEC': 'FEC', 'PAC': 'PAC', 'CRD': 'CRD', 'LEI': 'LEI', 'FINRA': 'FINRA', 'OFAC': 'OFAC', 'FCA': 'FCA', 'EU': 'EU', 'UN': 'UN', 'SBIC': 'SBIC', 'ERISA': 'ERISA', 'NYC': 'NYC', 'IAPD': 'IAPD', 'ADV': 'ADV', 'RIA': 'RIA', 'AUM': 'AUM', 'LDA': 'LDA', 'FTX': 'FTX', 'RD': 'Rd', 'RD.': 'Rd.', 'ST.': 'St.', 'AVE': 'Ave', 'AVE.': 'Ave.', 'STE': 'Ste', 'STE.': 'Ste.', 'BLVD': 'Blvd', 'BLVD.': 'Blvd.'};
const SEC_SMALL = new Set(['A', 'AN', 'AND', 'AT', 'DE', 'DER', 'DES', 'DU', 'ET', 'FOR', 'IN', 'LA', 'LE', 'OF', 'ON', 'THE', 'VAN', 'VON']);
const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
function secPart(w) {
  if (!/[A-Z]/.test(w)) return w;
  if (has(SEC_KEEP, w)) return SEC_KEEP[w];
  const core = w.replace(/[^A-Z]/g, '');
  if (/^[IVX]{2,5}$/.test(core)) return w;
  if (core.length <= 4 && !/[AEIOUY]/.test(core)) return w;
  const lo = w.toLowerCase(), i = lo.search(/[a-z]/);
  return lo.slice(0, i) + lo[i].toUpperCase() + lo.slice(i + 1);
}
export function secTitle(s) {
  s = s || '';
  if (!s || /[a-z]/.test(s)) return s;
  return s.split(' ').map((w, i) => {
    const bare = w.replace(/^[,;()]+|[,;()]+$/g, '');
    if (i && SEC_SMALL.has(bare)) return w.toLowerCase();
    const k = has(SEC_KEEP, bare) ? bare : bare.replace(/[.,]+$/, '');
    if (has(SEC_KEEP, k)) return w.replace(k, SEC_KEEP[k]);
    return w.replace(/[^\s\-/'’&]+/g, secPart);
  }).join(' ');
}

// Header title and search use the common name on every view. legalName in the page head stays the SEC name.
// {{TITLE}} sits in <title>; {{META}} and {{PMAIN}} are the server-rendered facts (filled last, so stored text is never re-read as a placeholder).
export const SK_PMAIN_MARK = '{{PMAIN}}';
export const fillFirm = (tpl, F, full = false, skeleton = '') =>
  tpl.split('{{HEAD}}').join(firmHead(F, full)).split('{{TITLE}}').join(esc(firmTitle(F))).split('{{NAME}}').join(esc(F.name)).split('{{SLUG}}').join(esc(F.slug))
    .split('{{META}}').join(firmMeta(F)).split('{{PMAIN}}').join(firmMain(F, skeleton));

// /vc/<slug>/ and /vc/<slug>/full/ are Full report. /vc/<slug>/checks/ is Checks.
// -> {slug, full, checks} | {redirect} | null
export function parseFirmPath(pathname) {
  const m = pathname.match(/^\/vc\/([^/]+)(\/(?:full|checks))?(\/?)$/);
  if (!m) return null;
  const slug = decodeURIComponent(m[1]);
  if (!SLUG_RE.test(slug.toLowerCase())) return null;
  const tail = m[2] ? m[2].slice(1) + '/' : '';
  const want = `/vc/${slug.toLowerCase()}/` + tail;
  if (want !== pathname) return { redirect: want };
  return { slug, full: tail === 'full/', checks: tail === 'checks/' };
}

async function rpc(env, fetchImpl, fn, args) {
  const r = await fetchImpl(`${env.SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${env.SUPABASE_ANON_KEY}`, 'content-type': 'application/json' },
    body: JSON.stringify(args),
  });
  if (!r.ok) { const e = new Error(`rpc ${fn} ${r.status}`); e.status = r.status; throw e; }
  return r.json();
}
// New RPC first; before its migration is applied PostgREST answers 404 and the old one is used.
async function rpcOr(env, fetchImpl, fn, old, args) {
  try { return await rpc(env, fetchImpl, fn, args); }
  catch (e) { if (e.status === 404) return rpc(env, fetchImpl, old, args); throw e; }
}

const HTML = 'text/html; charset=utf-8';
const cacheHdr = (s) => `public, max-age=0, s-maxage=${s}, stale-while-revalidate=86400`;

export async function renderFirm({ request, env, assets, fetchImpl = fetch }) {
  const url = new URL(request.url);
  const p = parseFirmPath(url.pathname);
  const asset = async (path) => (await assets.fetch(new URL(path, url.origin))).text();
  const notFound = async () => new Response(await asset('/_tpl/404'), { status: 404, headers: { 'content-type': HTML, 'cache-control': cacheHdr(300) } });
  if (!p) return notFound();
  if (p.redirect) return Response.redirect(new URL(p.redirect + url.search, url.origin).toString(), 301);
  let rows;
  try { rows = await rpcOr(env, fetchImpl, 'firm_meta_seo', 'firm_meta', { p_slug: p.slug }); }
  catch (e) { return new Response('Temporary error, please retry.', { status: 503, headers: { 'cache-control': 'no-store', 'retry-after': '30' } }); }
  const F = Array.isArray(rows) ? rows[0] : null;
  if (!F) {
    // merged duplicate pages: old slug 301s to the surviving page (firm_slug_redirects, docs/DEDUPE.md)
    let to = null;
    try { to = await rpc(env, fetchImpl, 'firm_redirect', { p_slug: p.slug }); } catch (e) { to = null; }
    if (typeof to === 'string' && /^[a-z0-9-]+$/.test(to) && to !== p.slug) {
      return new Response(null, { status: 301, headers: { location: new URL(`/vc/${to}/${p.checks ? "checks/" : p.full ? "full/" : ""}${url.search}`, url.origin).toString(), 'cache-control': cacheHdr(3600) } });
    }
    return notFound();
  }
  const tpl = await asset(p.checks ? '/_tpl/checks' : p.full ? '/_tpl/full' : '/_tpl/summary');
  const skr = await assets.fetch(new URL('/_tpl/pmain', url.origin)); // loading shapes for a firm with no stored facts
  const skeleton = skr.ok ? await skr.text() : '';
  const headers = { 'content-type': HTML, 'cache-control': cacheHdr(3600) };
  if (env.NOINDEX === '1') headers['x-robots-tag'] = 'noindex';
  return new Response(fillFirm(tpl, F, p.full, skeleton), { status: 200, headers });
}

// Generated from the same registry as navigation and page heads.
// Rebuilt by python3 launch/build.py before every deployment.
const XML = 'application/xml; charset=utf-8';
const xmlEsc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// Firm sitemap rows: firm_seo_sitemap (indexable firms only, lastmod = last checked date).
// Before that migration: firm_sitemap (every live firm, lastmod = date the page went live).
async function sitemapRows(env, fetchImpl, page, size) {
  try { return (await rpc(env, fetchImpl, 'firm_seo_sitemap', { p_page: page, p_size: size })).map((r) => ({ slug: r.slug, lastmod: r.lastmod, total: r.total })); }
  catch (e) {
    if (e.status !== 404) throw e;
    return (await rpc(env, fetchImpl, 'firm_sitemap', { p_page: page, p_size: size })).map((r) => ({ slug: r.slug, lastmod: r.updated_at, total: r.total }));
  }
}

export async function sitemapIndex({ env, fetchImpl = fetch }) {
  const rows = await sitemapRows(env, fetchImpl, 1, 1);
  const total = rows.length ? Number(rows[0].total) : 0;
  const n = Math.max(1, Math.ceil(total / SITEMAP_SIZE));
  const locs = ['sitemaps/static.xml', ...Array.from({ length: n }, (_, i) => `sitemaps/firms-${i + 1}.xml`)];
  const body = '<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    locs.map((l) => `<sitemap><loc>${SITE}${l}</loc></sitemap>\n`).join('') + '</sitemapindex>\n';
  return new Response(body, { headers: { 'content-type': XML, 'cache-control': cacheHdr(3600) } });
}

export async function sitemapPart({ name, env, fetchImpl = fetch }) {
  let urls;
  if (name === 'static.xml') urls = STATIC.map((p) => ({ loc: SITE + p }));
  else {
    const m = /^firms-([1-9][0-9]{0,4})\.xml$/.exec(name);
    if (!m) return new Response('Not found', { status: 404 });
    const rows = await sitemapRows(env, fetchImpl, Number(m[1]), SITEMAP_SIZE);
    if (!rows.length) return new Response('Not found', { status: 404 });
    urls = rows.map((r) => ({ loc: `${SITE}vc/${r.slug}/`, lastmod: r.lastmod ? String(r.lastmod).slice(0, 10) : null })); // /full/ is noindex: not listed
  }
  // No priority / changefreq: search engines ignore them.
  const body = '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
    urls.map((u) => `<url><loc>${xmlEsc(u.loc)}</loc>${u.lastmod ? `<lastmod>${u.lastmod}</lastmod>` : ''}</url>\n`).join('') + '</urlset>\n';
  return new Response(body, { headers: { 'content-type': XML, 'cache-control': cacheHdr(3600) } });
}

// /investors/: the list is drawn by js/firms.js after load. The first HTML gets the same firms as plain
// <a href> links (100 per page, ?page=N, prev/next links) inside #firms-list, which firms.js clears on load,
// so the page looks the same once it has loaded. Any DB error: the static page as it is today.
export function investorsLinks(rows, page, total) {
  const pages = Math.max(1, Math.ceil(total / DIR_SIZE));
  const a = rows.map((r) => `<a class="frow" href="/vc/${esc(r.slug)}/"><span class="fnm"><b>${esc(r.name)}</b></span><span class="fcity">${esc(r.city || '')}</span></a>`).join('');
  const nav = [page > 1 ? `<a href="/investors/${page > 2 ? '?page=' + (page - 1) : ''}" rel="prev">Previous page</a>` : '',
    page < pages ? `<a href="/investors/?page=${page + 1}" rel="next">Next page</a>` : ''].filter(Boolean).join(' ');
  return a + (nav ? `<p class="hint">${nav}</p>` : '');
}
export async function renderInvestors({ request, env, assets, fetchImpl = fetch }) {
  const url = new URL(request.url);
  const res = await assets.fetch(new URL('/investors/', url.origin));
  if (!res.ok) return res;
  const html = await res.text();
  const raw = url.searchParams.get('page');
  const page = raw === null ? 1 : (/^[1-9][0-9]{0,3}$/.test(raw) ? Number(raw) : 0);
  const plain = () => new Response(html, { status: 200, headers: { 'content-type': HTML, 'cache-control': cacheHdr(300) } });
  if (!page) return plain();
  let rows;
  try { rows = await rpc(env, fetchImpl, 'firm_seo_directory', { p_page: page, p_size: DIR_SIZE }); } catch (e) { return plain(); }
  if (!Array.isArray(rows) || !rows.length) return page === 1 ? plain() : new Response(await (await assets.fetch(new URL('/_tpl/404', url.origin))).text(), { status: 404, headers: { 'content-type': HTML, 'cache-control': cacheHdr(300) } });
  const total = Number(rows[0].total) || rows.length;
  const mark = '<div class="flist" id="firms-list"></div>';
  if (!html.includes(mark)) return plain();
  let out = html.replace(mark, `<div class="flist" id="firms-list">${investorsLinks(rows, page, total)}</div>`);
  if (page > 1) out = out.replace(`<link rel="canonical" href="${SITE}investors/">`, `<link rel="canonical" href="${SITE}investors/?page=${page}">`);
  const headers = { 'content-type': HTML, 'cache-control': cacheHdr(3600) };
  if (env.NOINDEX === '1') headers['x-robots-tag'] = 'noindex';
  return new Response(out, { status: 200, headers });
}
