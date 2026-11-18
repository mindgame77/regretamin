// node --test launch/edge/firm.test.mjs   (needs python3 launch/build.py first)
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { renderFirm, sitemapIndex, sitemapPart, parseFirmPath, fillFirm, firmHead, secTitle, renderInvestors, firmMain, fmtDay } from './firm.mjs';

const OUT = new URL('../../site-launch/', import.meta.url);
const DATA = new URL('../../data/launch/', import.meta.url);
const read = (p) => readFileSync(new URL(p, OUT), 'utf8');
const assets = { fetch: async (u) => new Response(read(`.${new URL(u).pathname}.html`)) };
const env = { SUPABASE_URL: 'https://db.test', SUPABASE_ANON_KEY: 'anon' };
const FIRMS = { sequoia: { slug: 'sequoia', name: 'Sequoia Capital', hq: 'Menlo Park, CA', firm_type: 'VC', updated_at: '2026-10-20T00:00:00Z' },
  evil: { slug: 'evil', name: 'A&B <script>"x"</script> \'Co\'', hq: null, firm_type: null } };
const db = (calls = []) => async (url, init) => {
  const fn = url.split('/rpc/')[1]; const a = JSON.parse(init.body); calls.push(fn);
  assert.equal(init.headers.apikey, 'anon');
  if (fn === 'firm_meta') return Response.json(FIRMS[a.p_slug] ? [FIRMS[a.p_slug]] : []);
  if (fn === 'firm_redirect') return Response.json(a.p_slug === 'sequoia-capital-2' ? 'sequoia' : null);
  if (fn === 'firm_sitemap') {
    const all = Array.from({ length: 12345 }, (_, i) => ({ slug: `f${i}`, updated_at: '2026-10-01T00:00:00Z', total: 12345 }));
    return Response.json(all.slice((a.p_page - 1) * a.p_size, a.p_page * a.p_size));
  }
  return new Response('x', { status: 404 });
};
const get = (path, fetchImpl = db()) => renderFirm({ request: new Request('https://regretamin.com' + path), env, assets, fetchImpl });

test('static pages from a build match the edge renderer', () => {
  const src = readFileSync(new URL('../build.py', import.meta.url), 'utf8');
  assert.equal(src.includes('LAB_SLUGS'), false);
  const built = readdirSync(new URL('vc/', OUT), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name);
  const snaps = readdirSync(DATA).filter((x) => x.endsWith('.json')).map((x) => x.replace(/\.json$/, ''));
  assert.deepEqual([...built].sort(), [...snaps].sort());
  const tpl = { s: read('_tpl/summary.html'), f: read('_tpl/full.html') }, sk = read('_tpl/pmain.html');
  for (const slug of built) {
    const F = JSON.parse(readFileSync(new URL(slug + '.json', DATA), 'utf8')).firm;
    assert.equal(fillFirm(tpl.s, F, false, sk), read(`vc/${slug}/index.html`), slug);
    assert.equal(fillFirm(tpl.f, F, true, sk), read(`vc/${slug}/full/index.html`), slug);
  }
});

test('published firm not in launch set gets a 200 page with SEO tags', async () => {
  for (const [path, canon] of [['/vc/sequoia/', 'https://regretamin.com/vc/sequoia/'], ['/vc/sequoia/full/', 'https://regretamin.com/vc/sequoia/full/']]) {
    const r = await get(path); const h = await r.text();
    assert.equal(r.status, 200);
    assert.match(r.headers.get('cache-control'), /s-maxage=3600/);
    assert.ok(h.includes('<title>Sequoia Capital · Regretamin</title>'));
    assert.ok(h.includes(`<link rel="canonical" href="${canon}">`));
    assert.ok(h.includes('og:description') && h.includes('application/ld+json') && h.includes('<h1>Sequoia Capital'));
    assert.ok(h.includes('data-firm="sequoia"') && !h.includes('{{'));
  }
});

test('unknown, bad and template slugs are real 404s', async () => {
  for (const p of ['/vc/not-a-firm/', '/vc/not-a-firm/full/', '/vc/a%20b/', '/vc/../x/', '/vc/x/y/z/']) {
    const r = await get(p); assert.equal(r.status, 404, p); assert.match(await r.text(), /noindex/);
  }
});

test('normalises: missing slash / uppercase -> 301', async () => {
  for (const [p, to] of [['/vc/sequoia', '/vc/sequoia/'], ['/vc/Sequoia/full', '/vc/sequoia/full/']]) {
    const r = await get(p); assert.equal(r.status, 301); assert.equal(new URL(r.headers.get('location')).pathname, to);
  }
  assert.equal(parseFirmPath('/vc/'), null);
});

test('names are escaped in HTML and JSON-LD', async () => {
  const h = await (await get('/vc/evil/')).text();
  assert.ok(!h.includes('<script>"x"'));
  assert.ok(h.includes('A&amp;B &lt;script&gt;'));
  assert.ok(h.includes('\\u003cscript\\u003e'));
});

test('DB down -> 503, not cached as a 404', async () => {
  const r = await get('/vc/sequoia/', async () => new Response('down', { status: 500 }));
  assert.equal(r.status, 503); assert.equal(r.headers.get('cache-control'), 'no-store');
});

test('full report is noindex, follow with self canonical; summary indexable; paywall JSON-LD', () => {
  const F = { name: 'A', slug: 'a' };
  const s = firmHead(F), f = firmHead(F, true);
  assert.ok(!s.includes('noindex')); assert.ok(s.includes('<link rel="canonical" href="https://regretamin.com/vc/a/">'));
  assert.ok(f.startsWith('<meta name="robots" content="noindex, follow">')); assert.ok(f.includes('<link rel="canonical" href="https://regretamin.com/vc/a/full/">'));
  for (const h of [s, f]) assert.ok(h.includes('"isAccessibleForFree":false,"hasPart":{"@type":"WebPageElement","isAccessibleForFree":false,"cssSelector":".gveil"}'));
});

test('split sitemaps: 1,000 per file (the API row cap), every firm once; old RPC used until the migration is applied', async () => {
  const idx = await (await sitemapIndex({ env, fetchImpl: db() })).text();
  assert.equal((idx.match(/<sitemap>/g) || []).length, 14); // static + 13 firm files for 12,345 firms
  assert.ok(idx.includes('https://regretamin.com/sitemaps/firms-13.xml'));
  const seen = new Set();
  for (let i = 1; i <= 13; i++) {
    const body = await (await sitemapPart({ name: `firms-${i}.xml`, env, fetchImpl: db() })).text();
    for (const m of body.matchAll(/<loc>https:\/\/regretamin\.com\/vc\/([^/]+)\/<\/loc>/g)) { assert.ok(!seen.has(m[1])); seen.add(m[1]); }
    assert.ok(!body.includes('/full/') && !body.includes('priority') && !body.includes('changefreq'));
  }
  assert.equal(seen.size, 12345);
  const p13 = await (await sitemapPart({ name: 'firms-13.xml', env, fetchImpl: db() })).text();
  assert.equal((p13.match(/<url>/g) || []).length, 345);
  assert.ok(p13.includes('<lastmod>2026-10-01</lastmod>'));
  assert.equal((await sitemapPart({ name: 'firms-14.xml', env, fetchImpl: db() })).status, 404);
  assert.equal((await sitemapPart({ name: 'x.xml', env, fetchImpl: db() })).status, 404);
  assert.match(await (await sitemapPart({ name: 'static.xml', env, fetchImpl: db() })).text(), /how-we-check/);
});

// After the migration: firm_meta_seo / firm_seo_sitemap / firm_seo_directory exist.
const SEO = { slug: 'lux', name: 'Lux & Co', hq: 'New York, NY', firm_type: null, legal_name: 'LUX CAPITAL MANAGEMENT, LLC', primary_domain: 'lux.com',
  founded_year: 2000, indexable: true, seo_title: 'Lux & Co: Deep tech VC in New York | Regretamin',
  seo_description: 'Lux & Co is a seed VC firm in New York, founded 2000. 219 investments. Checked Nov 8, 2026 against SEC, court and sanctions records.',
  seo_facts: { name: 'Lux & Co', hq: 'New York, NY', founded: 2000, website: 'https://www.lux.com', sectors: ['Deep tech', 'Bio <x>'], stages: ['Pre-seed', 'Growth'],
    latest_company: 'Crosby', latest_deal_date: '2026-03-31', last_checked: '2026-11-08',
    address: { street: '920 Broadway', city: 'New York', region: 'NY', country: 'US' },
    leaders: [{ name: 'Josh Wolfe', title: 'Co-Founder', founder: true }, { name: 'Ann Lee', title: 'Managing Partner', founder: false }],
    registry: [{ type: 'SEC CRD', value: '163026', url: 'https://adviserinfo.sec.gov/firm/summary/163026' }], social: ['https://x.com/lux'] } };
const THIN = { slug: 'thin', name: 'Thin Capital', hq: null, indexable: false, seo_title: 'Thin Capital: Venture Capital Firm | Regretamin', seo_description: 'Thin Capital is a VC firm.', seo_facts: { name: 'Thin Capital' } };
const seoDb = (calls = []) => async (url, init) => {
  const fn = url.split('/rpc/')[1]; const a = JSON.parse(init.body); calls.push(fn);
  if (fn === 'firm_meta_seo') return Response.json({ lux: [SEO], thin: [THIN] }[a.p_slug] || []);
  if (fn === 'firm_seo_sitemap') {
    const all = Array.from({ length: 2500 }, (_, i) => ({ slug: `s${i}`, lastmod: '2026-11-08', total: 2500 }));
    return Response.json(all.slice((a.p_page - 1) * a.p_size, a.p_page * a.p_size));
  }
  if (fn === 'firm_seo_directory') {
    const all = Array.from({ length: 250 }, (_, i) => ({ slug: `d${i}`, name: i ? `Firm ${i}` : 'A&B <i>', city: i % 2 ? 'Boston' : null, total: 250 }));
    return Response.json(all.slice((a.p_page - 1) * a.p_size, a.p_page * a.p_size));
  }
  return db(calls)(url, init);
};

test('stored SEO title and description, one query per page, JSON-LD WebPage + Organization + BreadcrumbList', async () => {
  const calls = [];
  const h = await (await get('/vc/lux/', seoDb(calls))).text();
  assert.deepEqual(calls, ['firm_meta_seo']);
  assert.ok(h.includes('<title>Lux &amp; Co: Deep tech VC in New York | Regretamin</title>'));
  assert.ok(h.includes('<meta name="description" content="Lux &amp; Co is a seed VC firm in New York, founded 2000. 219 investments.'));
  assert.ok(h.includes('<meta property="og:title" content="Lux &amp; Co: Deep tech VC in New York | Regretamin">'));
  assert.ok(!h.includes('noindex'));
  const ld = JSON.parse(h.match(/<script type="application\/ld\+json">(.*?)<\/script>/)[1]);
  const [pg, bc] = ld['@graph'];
  assert.equal(pg['@type'], 'WebPage'); assert.equal(pg.dateModified, '2026-11-08');
  const o = pg.mainEntity;
  assert.equal(o['@type'], 'Organization'); assert.equal(o.legalName, 'LUX CAPITAL MANAGEMENT, LLC'); assert.equal(o.url, 'https://www.lux.com');
  assert.deepEqual(o.address, { '@type': 'PostalAddress', streetAddress: '920 Broadway', addressLocality: 'New York', addressRegion: 'NY', addressCountry: 'US' });
  assert.equal(o.foundingDate, '2000');
  assert.deepEqual(o.identifier, [{ '@type': 'PropertyValue', propertyID: 'SEC CRD', value: '163026' }]);
  assert.deepEqual(o.sameAs, ['https://x.com/lux', 'https://adviserinfo.sec.gov/firm/summary/163026']);
  assert.deepEqual(o.founder, [{ '@type': 'Person', name: 'Josh Wolfe', jobTitle: 'Co-Founder' }]);
  assert.deepEqual(o.employee, [{ '@type': 'Person', name: 'Ann Lee', jobTitle: 'Managing Partner' }]);
  assert.equal(bc['@type'], 'BreadcrumbList'); assert.deepEqual(bc.itemListElement.map((x) => x.name), ['Regretamin', 'Investors', 'Lux & Co']);
  assert.ok(h.includes('"isAccessibleForFree":false,"hasPart":{"@type":"WebPageElement","isAccessibleForFree":false,"cssSelector":".gveil"}'));
});

test('first HTML: the heading is the firm name only, facts the page shows, section headings carry the firm name', async () => {
  const h = await (await get('/vc/lux/', seoDb())).text();
  assert.ok(h.includes('<div class="ph1"><h1>Lux &amp; Co</h1><button type="button" class="sv" data-save'));
  assert.equal((h.match(/<h1[ >]/g) || []).length, 1); // the unlock popup title is no longer a second, empty h1 (it is a styled <p>, filled when the popup opens)
  assert.ok(!/<h2[^>]*>\s*<\/h2>|<h2><i class="sk"/.test(h)); // no empty headings
  assert.ok(h.includes('<p class="m">New York, NY · Founded 2000 · <a href="https://www.lux.com" target="_blank" rel="noopener">lux.com</a></p>'));
  assert.ok(h.includes('<h2>Lux &amp; Co at a glance</h2>') && h.includes('<h2>Lux &amp; Co team</h2>'));
  assert.ok(h.includes('<span>Deep tech, Bio &lt;x&gt;</span>') && h.includes('<span>Crosby · Mar 31, 2026</span>'));
  assert.ok(!h.includes('163026</span>')); // the SEC number is not drawn on the page, so it is not in the first HTML either
  assert.ok(!h.includes('{{'));
  // a firm with no stored facts keeps today's loading shapes; no team -> no team heading
  const t = await (await get('/vc/thin/', seoDb())).text();
  assert.ok(t.includes('<p class="m"><i class="sk" style="width:300px"></i></p>') && !t.includes('Thin Capital team') && t.includes('<p class="skh">'));
  assert.equal(fmtDay('2026-11-08'), 'Nov 8, 2026');
  assert.equal(firmMain({ name: 'X', seo_facts: {} }, 'SK'), 'SK');
});

test('not ready for Google: noindex, follow; old firm_meta used while firm_meta_seo does not exist', async () => {
  const t = await (await get('/vc/thin/', seoDb())).text();
  assert.ok(t.startsWith('<!doctype html>') && t.includes('<meta name="robots" content="noindex, follow">'));
  const calls = [];
  const h = await (await get('/vc/sequoia/', db(calls))).text();
  assert.deepEqual(calls, ['firm_meta_seo', 'firm_meta']);
  assert.ok(h.includes('<title>Sequoia Capital · Regretamin</title>') && h.includes('Background check on Sequoia Capital'));
});

test('sitemap after the migration: indexable firms only, real last-checked date', async () => {
  const calls = [];
  const idx = await (await sitemapIndex({ env, fetchImpl: seoDb(calls) })).text();
  assert.equal((idx.match(/<sitemap>/g) || []).length, 4); // static + 3 files for 2,500 firms
  assert.deepEqual(calls, ['firm_seo_sitemap']);
  const p3 = await (await sitemapPart({ name: 'firms-3.xml', env, fetchImpl: seoDb() })).text();
  assert.equal((p3.match(/<url>/g) || []).length, 500);
  assert.ok(p3.includes('<url><loc>https://regretamin.com/vc/s2000/</loc><lastmod>2026-11-08</lastmod></url>'));
});

test('/investors/: plain firm links in the first HTML, 100 per page, inside the list firms.js redraws', async () => {
  const base = '<html><head><link rel="canonical" href="https://regretamin.com/investors/"></head><body><div class="flist" id="firms-list"></div></body></html>';
  const as = { fetch: async (u) => new Response(new URL(u).pathname === '/investors/' ? base : read('_tpl/404.html')) };
  const go = (q, f = seoDb()) => renderInvestors({ request: new Request('https://regretamin.com/investors/' + q), env, assets: as, fetchImpl: f });
  let h = await (await go('')).text();
  assert.equal((h.match(/<a class="frow" href="\/vc\/d\d+\/">/g) || []).length, 100);
  assert.ok(h.includes('<a class="frow" href="/vc/d0/"><span class="fnm"><b>A&amp;B &lt;i&gt;</b></span><span class="fcity"></span></a>'));
  assert.ok(h.includes('<a href="/investors/?page=2" rel="next">') && !h.includes('rel="prev"'));
  h = await (await go('?page=3')).text();
  assert.equal((h.match(/class="frow"/g) || []).length, 50);
  assert.ok(h.includes('rel="prev"') && !h.includes('rel="next"') && h.includes('href="https://regretamin.com/investors/?page=3"'));
  assert.equal((await go('?page=9')).status, 404);
  assert.equal(await (await go('?page=abc')).text(), base);
  assert.equal(await (await go('', async () => new Response('down', { status: 500 }))).text(), base); // DB down: today's page
});

test('merged duplicate slug 301s to the surviving page (summary and full, query kept)', async () => {
  let r = await get('/vc/sequoia-capital-2/');
  assert.equal(r.status, 301); assert.equal(r.headers.get('location'), 'https://regretamin.com/vc/sequoia/');
  r = await get('/vc/sequoia-capital-2/full/?x=1');
  assert.equal(r.status, 301); assert.equal(r.headers.get('location'), 'https://regretamin.com/vc/sequoia/full/?x=1');
  assert.equal((await get('/vc/not-a-firm/')).status, 404);
});

test('full report header uses the common name; the SEC legal name stays in the page head', () => {
  const F = { name: 'Andreessen Horowitz', legal_name: 'AH Capital Management, L.L.C.', slug: 'a16z', primary_domain: 'a16z.com' };
  const html = fillFirm('<title>{{NAME}}</title>{{HEAD}}<h1>{{NAME}}</h1><input value="{{NAME}}">', F, true);
  assert.match(html, /<h1>Andreessen Horowitz<\/h1><input value="Andreessen Horowitz">/);
  assert.equal((html.match(/AH Capital Management, L\.L\.C\./g) || []).length, 1);
  assert.ok(html.includes('"legalName":"AH Capital Management, L.L.C."'));
  const built = read('vc/a16z/full/index.html');
  assert.ok(built.includes('<h1>Andreessen Horowitz'));
  assert.ok(built.includes('value="Andreessen Horowitz"'));
  assert.ok(!built.includes('<h1>AH Capital'));
  assert.ok(built.includes('legalName'));
});

test('Pricing and Sign in go to real pages, and those pages exist', () => {
  const home = read('index.html');
  assert.match(home, /href="plans\/"[^>]*data-open="paywall"/);
  assert.match(home, /href="login\/"[^>]*data-open="signup"/);
  assert.match(home, /dates\.js\?v=/);
  const plans = read('plans/index.html'), login = read('login/index.html');
  assert.match(plans, /noindex/);
  assert.ok(plans.includes('data-plans="nav"') && plans.includes('id="signup"') && !plans.includes('id="paywall"'));
  assert.match(login, /noindex/);
  assert.ok(login.includes('id="google"') && login.includes('id="paywall"') && !login.includes('id="signup"'));
  assert.match(read('_tpl/full.html'), /href="\.\.\/\.\.\/\.\.\/plans\/"/);
  assert.match(read('_tpl/summary.html'), /href="\.\.\/\.\.\/login\/"/);
});

test('SEC legal names shown in title case on the full check (display only)', () => {
  const cases = {
    'IVP MANAGEMENT, L.L.C.': 'IVP Management, L.L.C.',
    'INSTITUTIONAL VENTURE PARTNERS XVII, L.P.': 'Institutional Venture Partners XVII, L.P.',
    'BRV GP, INC.': 'BRV GP, Inc.',
    'H.I.G. CAPITAL, LLC': 'H.I.G. Capital, LLC',
    'SEQUOIA CAPITAL OPERATIONS LLC': 'Sequoia Capital Operations LLC',
    'BAIN CAPITAL VENTURE INVESTORS, LP': 'Bain Capital Venture Investors, LP',
    'Already Mixed Case LLC': 'Already Mixed Case LLC',
  };
  for (const [a, b] of Object.entries(cases)) assert.equal(secTitle(a), b, a);
});
