// Makes the map files of the "Founders" view (js/founders.js):
//   launch/assets/founders/geo.json   each country (world, Europe) and each US state as its own shape, in the same
//                                     projections as the main map (tools/map/gen_assets.cjs)
//   launch/assets/founders/orgs.json  where each university and company sits on each view, the country and state
//                                     it is in, a university's country (for the flag), and its logo file
// Source: tools/map/founders_orgs.json (name, lat, lon). Logo files and whether a logo fills its circle ("fb") are
// kept from the existing orgs.json; this script does not make logos.
// Rules kept here (founder, Nov 2026): Crimea is Ukraine; the Europe view shows no Russian territory; land far from
// a country's main body (French Guiana) is not drawn as that country.
// Run: npm i --no-save d3-geo topojson-client world-atlas us-atlas && node tools/map/gen_founders.cjs
const fs = require('fs'), path = require('path');
const d3 = require(process.env.D3 || 'd3-geo'), topo = require(process.env.TOPO || 'topojson-client');
const A110 = JSON.parse(fs.readFileSync(process.env.ATLAS || require.resolve('world-atlas/countries-110m.json')));
const A50 = JSON.parse(fs.readFileSync(process.env.ATLAS50 || require.resolve('world-atlas/countries-50m.json')));
const US = JSON.parse(fs.readFileSync(process.env.US_ATLAS || require.resolve('us-atlas/states-10m.json')));
const OUT = path.join(__dirname, '..', '..', 'launch', 'assets', 'founders');
const SRC = JSON.parse(fs.readFileSync(path.join(__dirname, 'founders_orgs.json')));
const OLD = (() => { try { return JSON.parse(fs.readFileSync(path.join(OUT, 'orgs.json'))); } catch (e) { return { unis: [], cos: [] }; } })();
const FIPS = {'01':'AL','02':'AK','04':'AZ','05':'AR','06':'CA','08':'CO','09':'CT','10':'DE','11':'DC','12':'FL','13':'GA','15':'HI','16':'ID','17':'IL','18':'IN','19':'IA','20':'KS','21':'KY','22':'LA','23':'ME','24':'MD','25':'MA','26':'MI','27':'MN','28':'MS','29':'MO','30':'MT','31':'NE','32':'NV','33':'NH','34':'NJ','35':'NM','36':'NY','37':'NC','38':'ND','39':'OH','40':'OK','41':'OR','42':'PA','44':'RI','45':'SC','46':'SD','47':'TN','48':'TX','49':'UT','50':'VT','51':'VA','53':'WA','54':'WV','55':'WI','56':'WY'};
// country code (as stored for a founder) -> the atlas's country name
const CC = {'us':'United States of America','gb':'United Kingdom','il':'Israel','ca':'Canada','in':'India','de':'Germany','fr':'France','ch':'Switzerland','br':'Brazil','mx':'Mexico','es':'Spain','ae':'United Arab Emirates','au':'Australia','nl':'Netherlands','jp':'Japan','se':'Sweden','pt':'Portugal','co':'Colombia','ar':'Argentina','cn':'China','it':'Italy','be':'Belgium','dk':'Denmark','id':'Indonesia','cl':'Chile','sa':'Saudi Arabia','ng':'Nigeria','kr':'South Korea','no':'Norway','fi':'Finland','pl':'Poland','ie':'Ireland','eg':'Egypt','tr':'Turkey','at':'Austria','nz':'New Zealand','ke':'Kenya','ee':'Estonia','cz':'Czechia','za':'South Africa','uy':'Uruguay','lt':'Lithuania','ua':'Ukraine','tw':'Taiwan','hu':'Hungary','vn':'Vietnam','bg':'Bulgaria','my':'Malaysia','ro':'Romania','pr':'Puerto Rico','cy':'Cyprus','si':'Slovenia','hr':'Croatia','ma':'Morocco','bd':'Bangladesh','th':'Thailand','ph':'Philippines','zm':'Zambia','lu':'Luxembourg','sk':'Slovakia','et':'Ethiopia','cm':'Cameroon','sn':'Senegal','bs':'Bahamas','cr':'Costa Rica','mg':'Madagascar','ve':'Venezuela','pk':'Pakistan','dz':'Algeria','pa':'Panama','kz':'Kazakhstan','ci':"Côte d'Ivoire",'kw':'Kuwait','lb':'Lebanon','am':'Armenia','gr':'Greece','gh':'Ghana','uz':'Uzbekistan','pe':'Peru','mt':'Malta','sg':'Singapore','hk':'Hong Kong','bh':'Bahrain','mc':'Monaco','bm':'Bermuda'};
// places with no shape at world size: drawn as a small circle
const DOTS = { sg: ['Singapore', 1.35, 103.82], hk: ['Hong Kong', 22.30, 114.17], mt: ['Malta', 35.90, 14.45], bh: ['Bahrain', 26.07, 50.55], mc: ['Monaco', 43.74, 7.42], bm: ['Bermuda', 32.30, -64.78] };
const EUROPE = ['gb','de','fr','ch','es','nl','se','pt','it','be','dk','no','fi','pl','ie','at','ee','cz','lt','ua','hu','bg','ro','cy','si','hr','lu','sk','gr','mt','mc','tr','am'];
// countries whose far-away parts do belong on the map as that country
const KEEP = ['United States of America','Russia','Canada','Indonesia','Japan','Chile','New Zealand','Australia','Fiji','Norway','Denmark','Greece','Italy','Spain','Portugal','United Kingdom','Philippines','Malaysia','China','India','Kiribati','Antarctica'];
const name2cc = {}; for (const [c, n] of Object.entries(CC)) name2cc[n] = c;
const crimea = ([lon, lat]) => lon > 32.3 && lon < 36.6 && lat > 44.3 && lat < 46.3;
const polys = (g) => g.type === 'MultiPolygon' ? g.coordinates : [g.coordinates];
const nice = (n) => n.replace('United States of America', 'United States');
const V = { world: { w: 1060, h: 620 }, us: { w: 900, h: 540 }, eu: { w: 876, h: 600 } };
const P = {
  world: d3.geoNaturalEarth1().fitExtent([[20, 70], [1040, 580]], { type: 'MultiPoint', coordinates: [[-170, -52], [180, 72], [-170, 72], [180, -52]] }),
  us: d3.geoAlbersUsa().fitExtent([[10, 10], [890, 530]], topo.feature(US, US.objects.nation)),
  eu: d3.geoMercator().fitExtent([[0, 0], [876, 600]], { type: 'MultiPoint', coordinates: [[-25, 34.5], [50.5, 34.5], [-25, 67], [50.5, 67]] }).clipExtent([[0, 0], [876, 600]]) };
const geo = { views: V, shapes: { world: [], us: [], eu: [] }, dots: {}, europe: EUROPE };
function countries(A, view, skip) {
  const p = d3.geoPath(P[view]).digits(1), feats = topo.feature(A, A.objects.countries).features;
  const ru = feats.find((f) => f.properties.name === 'Russia'); const cr = polys(ru.geometry).filter((x) => crimea(d3.geoCentroid({ type: 'Polygon', coordinates: x })));
  for (const f of feats) {
    const n = f.properties.name; if (skip.includes(n) || n === 'Antarctica') continue;
    let ps = polys(f.geometry);
    if (n === 'Russia') ps = ps.filter((x) => !crimea(d3.geoCentroid({ type: 'Polygon', coordinates: x })));
    if (n === 'Ukraine') ps = ps.concat(cr);
    if (!KEEP.includes(n) && ps.length > 1) {
      let main = null, ma = -1; for (const x of ps) { const ar = d3.geoArea({ type: 'Polygon', coordinates: x }); if (ar > ma) { ma = ar; main = x; } }
      const c0 = d3.geoCentroid({ type: 'Polygon', coordinates: main }), far = ps.filter((x) => d3.geoDistance(d3.geoCentroid({ type: 'Polygon', coordinates: x }), c0) > 0.35);
      if (far.length) { ps = ps.filter((x) => !far.includes(x)); const fd = p({ type: 'MultiPolygon', coordinates: far }); if (fd) geo.shapes[view].push({ k: null, n: n + ' (overseas)', d: fd, x: 0, y: 0, a: 0 }); }
    }
    const d = p({ type: 'MultiPolygon', coordinates: ps }); if (!d) continue;
    let best = null, ba = -1; for (const x of ps) { const a = p.area({ type: 'Polygon', coordinates: x }); if (a > ba) { ba = a; best = x; } }
    const c = p.centroid({ type: 'Polygon', coordinates: best }); if (!isFinite(c[0])) continue;
    geo.shapes[view].push({ k: name2cc[n] || null, n: nice(n), d, x: Math.round(c[0]), y: Math.round(c[1]), a: Math.round(ba) });
  }
}
countries(A110, 'world', []); countries(A50, 'eu', ['Russia', 'Kazakhstan']);
const pu = d3.geoPath(P.us).digits(1), states = topo.feature(US, US.objects.states).features;
for (const f of states) { const k = FIPS[f.id]; if (!k) continue; const c = pu.centroid(f); geo.shapes.us.push({ k: 'US-' + k, n: f.properties.name, d: pu(f), x: Math.round(c[0]), y: Math.round(c[1]), a: Math.round(pu.area(f)) }); }
const inside = (v, p) => p && p[0] >= 0 && p[1] >= 0 && p[0] <= V[v].w && p[1] <= V[v].h;
for (const [c, [n, lat, lon]] of Object.entries(DOTS)) { geo.dots[c] = { n }; for (const v of ['world', 'eu']) { const p = P[v]([lon, lat]); if (inside(v, p)) geo.dots[c][v] = [Math.round(p[0]), Math.round(p[1])]; } }
// which country and state a point is in; a campus on the coast can fall just outside the simplified outline, so nearby points are tried too
const feats50 = topo.feature(A50, A50.objects.countries).features;
const tries = [[0, 0]]; for (const r of [0.08, 0.16, 0.3, 0.5]) for (let i = 0; i < 8; i++) tries.push([r * Math.cos(i * Math.PI / 4), r * Math.sin(i * Math.PI / 4)]);
const find = (fs2, lon, lat) => { for (const [dx, dy] of tries) { const f = fs2.find((x) => d3.geoContains(x, [lon + dx, lat + dy])); if (f) return f; } return null; };
const orgs = {};
for (const kind of ['unis', 'cos']) {
  const old = {}; for (const o of OLD[kind] || []) old[o.n] = o;
  orgs[kind] = SRC[kind].map((s) => {
    const e = { n: s.n, p: {} };
    for (const v of ['world', 'us', 'eu']) { const p = P[v]([s.lon, s.lat]); if (inside(v, p)) e.p[v] = [Math.round(p[0]), Math.round(p[1])]; }
    const c = find(feats50, s.lon, s.lat); let st = null;
    if (c && c.properties.name === 'United States of America') { const f = find(states, s.lon, s.lat); st = f && FIPS[f.id] ? 'US-' + FIPS[f.id] : null; }
    e.a = [c ? nice(c.properties.name) : null, st];
    if (s.c) e.c = s.c;
    const o = old[s.n] || {}; if (o.lg) { e.lg = o.lg; if (o.fb) e.fb = 1; }
    return e;
  });
}
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'geo.json'), JSON.stringify(geo));
fs.writeFileSync(path.join(OUT, 'orgs.json'), JSON.stringify(orgs));
console.log('shapes', geo.shapes.world.length, geo.shapes.eu.length, geo.shapes.us.length, '| universities', orgs.unis.length, 'companies', orgs.cos.length);
