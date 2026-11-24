// Generates the static map backgrounds and place coordinates used by launch/js/map.js.
// Run once when the place list or the look of the dots changes:
//   npm i --no-save d3-geo topojson-client world-atlas && node tools/map/gen_assets.cjs
// (D3, TOPO and ATLAS can point at local copies instead.)
// Output: launch/assets/map/{world,us,eu}.svg and launch/assets/map/places.json
const fs = require('fs'), path = require('path');
const d3 = require(process.env.D3 || 'd3-geo'), topo = require(process.env.TOPO || 'topojson-client');
const atlas = JSON.parse(fs.readFileSync(process.env.ATLAS || require.resolve('world-atlas/countries-110m.json')));
const OUT = path.join(__dirname, '..', '..', 'launch', 'assets', 'map');
const land = topo.feature(atlas, atlas.objects.land);
const usa = topo.feature(atlas, atlas.objects.countries).features.find((f) => f.id === '840');
// The Europe view shows no Russian territory (founder, 23 Nov): its land, Kaliningrad included, is left out.
// Crimea is Ukraine and stays on the map; the atlas files it under Russia, so it is named here by its box.
const russia = topo.feature(atlas, atlas.objects.countries).features.find((f) => f.id === '643');
const crimea = ([lon, lat]) => lon > 32.3 && lon < 36.6 && lat > 44.3 && lat < 46.3;
const inRussia = (ll) => d3.geoContains(russia, ll) && !crimea(ll);
// The frame reaches east to the Caspian so Georgia, Armenia and Azerbaijan are on the map; the corner of Kazakhstan that would float above them is left out.
const kazakhstan = topo.feature(atlas, atlas.objects.countries).features.find((f) => f.id === '398');

// The US view is drawn from the detailed US outline (us-atlas, 1:10m), the same data the state lines come from, so coast
// and lines agree; the 110m world outline was too rough for it (founder, 23 Nov: "not accurate, looks weird").
const usDetail = (() => { try { return JSON.parse(fs.readFileSync(process.env.US_ATLAS || require.resolve('us-atlas/states-10m.json'))); } catch (e) { return null; } })();
const usNation = usDetail ? topo.feature(usDetail, usDetail.objects.nation) : null;
const VIEWS = {
  world: { w: 1060, h: 620, step: 8, proj: d3.geoNaturalEarth1().fitExtent([[20, 70], [1040, 580]], { type: 'MultiPoint', coordinates: [[-170, -52], [180, 72], [-170, 72], [180, -52]] }), inside: (ll) => d3.geoContains(land, ll) },
  us: { w: 900, h: 540, step: 8, proj: d3.geoAlbersUsa().fitExtent([[10, 10], [890, 530]], usa), inside: (ll) => d3.geoContains(usNation || usa, ll) },
  // Europe is framed from Iceland (top left) to the Caspian (right), at the same scale as before the frame was widened (23 Nov).
  eu: { w: 876, h: 600, step: 6, proj: d3.geoMercator().fitExtent([[0, 0], [876, 600]], { type: 'MultiPoint', coordinates: [[-25, 34.5], [50.5, 34.5], [-25, 67], [50.5, 67]] }), inside: (ll) => d3.geoContains(land, ll) && !inRussia(ll) && !d3.geoContains(kazakhstan, ll) },
};
// [lat, lon] per place. World regions are hand-placed; the rest are city or country centres.
const PLACES = {
  world: { 'US West': [38, -121], 'US Central': [40, -97], 'US East': [39, -76], 'Canada': [50, -100], 'Caribbean': [20, -72], 'Latin America': [-12, -55],
    'Europe': [49, 10], 'Israel': [31.5, 35], 'Middle East': [23, 50], 'Africa': [0, 22], 'Central Asia and Caucasus': [45, 66], 'India': [21, 78],
    'China, HK, Taiwan': [33, 108], 'South Korea': [36.5, 127.5], 'Japan': [36, 138.5], 'Southeast Asia': [3, 108], 'Australia and NZ': [-27, 138] },
  us: { 'Bay Area': [37.6, -122.2], 'New York': [40.71, -74], 'Boston': [42.36, -71.06], 'Los Angeles': [34.05, -118.24], 'Miami': [25.9, -80.19], 'Chicago': [41.88, -87.63],
    'Washington DC': [38.9, -77.04], 'Seattle': [47.6, -122.33], 'Austin': [30.27, -97.74], 'Denver': [39.74, -104.99], 'San Diego': [32.72, -117.16], 'Atlanta': [33.75, -84.39],
    'Philadelphia': [39.95, -75.17], 'Salt Lake City': [40.76, -111.89], 'Minneapolis': [44.98, -93.27], 'St. Louis': [38.63, -90.2], 'Houston': [29.76, -95.37], 'Dallas': [32.78, -96.8],
    'Vail': [39.64, -106.37], 'Raleigh-Durham': [35.9, -78.8], 'Nashville': [36.16, -86.78], 'Portland': [45.52, -122.68], 'Dover': [39.16, -75.52], 'Oklahoma City': [35.47, -97.52],
    'Baltimore': [39.29, -76.61], 'Las Vegas': [36.17, -115.14], 'Indianapolis': [39.77, -86.16], 'Tampa': [27.95, -82.46], 'Santa Rosa': [38.44, -122.71], 'Phoenix': [33.45, -112.07],
    'Des Moines': [41.59, -93.62], 'Santa Barbara': [34.42, -119.7], 'Princeton': [40.35, -74.66], 'Kansas City': [39.1, -94.58], 'Charleston': [32.78, -79.93], 'Jackson': [43.48, -110.76],
    'Columbus': [39.96, -83], 'Cincinnati': [39.1, -84.51], 'Ann Arbor': [42.28, -83.74], 'Sacramento': [38.58, -121.49], 'Aspen': [39.19, -106.82], 'Memphis': [35.15, -90.05],
    'East Lansing': [42.74, -84.48], 'Chattanooga': [35.05, -85.31], 'Portsmouth': [43.07, -70.76], 'Omaha': [41.26, -95.93], 'Tulsa': [36.15, -95.99], 'Bend': [44.06, -121.31],
    'Providence': [41.82, -71.41], 'Pittsburgh': [40.44, -80], 'Detroit': [42.33, -83.05], 'Charlotte': [35.23, -80.84], 'Madison': [43.07, -89.4], 'Milwaukee': [43.04, -87.91] },
  eu: { GB: ['United Kingdom', 53, -1.5], DE: ['Germany', 51, 10.3], FR: ['France', 46.6, 2.5], NL: ['Netherlands', 52.4, 5.3], CH: ['Switzerland', 46.8, 8.2], BE: ['Belgium', 50.6, 4.5],
    SE: ['Sweden', 60, 15], CZ: ['Czechia', 49.8, 15.5], ES: ['Spain', 40, -3.7], LU: ['Luxembourg', 49.7, 6.1], PL: ['Poland', 52, 19.5], FI: ['Finland', 62, 26], DK: ['Denmark', 56, 9.5],
    IT: ['Italy', 43, 12.5], PT: ['Portugal', 39.5, -8], EE: ['Estonia', 58.7, 25.5], IE: ['Ireland', 53.3, -8], NO: ['Norway', 61, 8.5], BG: ['Bulgaria', 42.7, 25.3], LT: ['Lithuania', 55.3, 24],
    UA: ['Ukraine', 49, 31], GR: ['Greece', 39, 22], IS: ['Iceland', 65, -18.5], AT: ['Austria', 47.6, 14.5], SK: ['Slovakia', 48.7, 19.5], LV: ['Latvia', 57, 25], SI: ['Slovenia', 46.1, 14.8],
    HU: ['Hungary', 47.2, 19.4], RO: ['Romania', 45.8, 25], HR: ['Croatia', 45.2, 16.3], CY: ['Cyprus', 35, 33], RS: ['Serbia', 44, 21], MT: ['Malta', 35.9, 14.4], MC: ['Monaco', 43.7, 7.4],
    LI: ['Liechtenstein', 47.2, 9.5], AD: ['Andorra', 42.5, 1.5], GG: ['Guernsey', 49.45, -2.6], JE: ['Jersey', 49.2, -2.1], IM: ['Isle of Man', 54.2, -4.5] },
};
// Thin white lines over the smooth land: country borders on the Europe view, state borders on the US view (founder, 23 Nov).
// No border is drawn against Russia, so nothing cuts Crimea off from Ukraine. Needs us-atlas for the states (US_ATLAS=path).
const usStates = usDetail;
const atlas50 = (() => { try { return JSON.parse(fs.readFileSync(process.env.ATLAS50 || require.resolve('world-atlas/countries-50m.json'))); } catch (e) { return null; } })();
let euLand = null, euPath = null;
const lines = {};
{
  const eu = VIEWS.eu, proj = d3.geoMercator().fitExtent([[0, 0], [eu.w, eu.h]], { type: 'MultiPoint', coordinates: [[-25, 34.5], [50.5, 34.5], [-25, 67], [50.5, 67]] }).clipExtent([[0, 0], [eu.w, eu.h]]);
  // Europe is drawn from the 1:50m atlas (land and lines from the same data, so they agree); the world from 1:110m.
  const A = atlas50 || atlas, out = (g) => g.id === '643' || g.id === '398';
  lines.eu = d3.geoPath(proj).digits(1)(topo.mesh(A, A.objects.countries, (a, b) => a !== b && !out(a) && !out(b))) || '';
  // Europe's land: every country but Russia and Kazakhstan, as one shape, plus Crimea (the atlas keeps it as a separate piece of Russia).
  const ru = topo.feature(A, A.objects.countries).features.find((f) => f.id === '643');
  const pieces = ru ? (ru.geometry.type === 'MultiPolygon' ? ru.geometry.coordinates : [ru.geometry.coordinates]).filter((poly) => crimea(d3.geoCentroid({ type: 'Polygon', coordinates: poly }))) : [];
  euLand = { type: 'GeometryCollection', geometries: [topo.merge(A, A.objects.countries.geometries.filter((g) => !out(g))), { type: 'MultiPolygon', coordinates: pieces }] };
  euPath = d3.geoPath(proj).digits(1);
  console.log('crimea pieces kept:', pieces.length);
  // World view: every country border, minus the stretch the atlas draws between Crimea and the rest of Ukraine.
  const all = topo.mesh(atlas, atlas.objects.countries, (a, b) => a !== b), kept = [];
  for (const line of all.coordinates) { let run = []; for (const pt of line) { if (crimea(pt)) { if (run.length > 1) kept.push(run); run = []; } else run.push(pt); } if (run.length > 1) kept.push(run); }
  lines.world = d3.geoPath(VIEWS.world.proj).digits(1)({ type: 'MultiLineString', coordinates: kept }) || '';
  if (usStates) lines.us = d3.geoPath(VIEWS.us.proj).digits(1)(topo.mesh(usStates, usStates.objects.states, (a, b) => a !== b)) || '';
}
fs.writeFileSync(path.join(OUT, 'lines.json'), JSON.stringify(lines) + '\n');
// Exact land shapes, where we have them: the build draws these instead of the smoothed dots.
const landShapes = {};
if (usNation) landShapes.us = d3.geoPath(VIEWS.us.proj).digits(1)(usNation) || '';
if (euLand) landShapes.eu = euPath(euLand) || '';
// The world's land and its lines both come from the 1:110m atlas; the frame cuts off what lies outside the picture.
landShapes.world = d3.geoPath(d3.geoNaturalEarth1().fitExtent([[20, 70], [1040, 580]], { type: 'MultiPoint', coordinates: [[-170, -52], [180, 72], [-170, 72], [180, -52]] }).clipExtent([[0, 0], [VIEWS.world.w, VIEWS.world.proj([0, -58])[1]]])).digits(1)(land) || '';  // the frame ends above Antarctica
fs.writeFileSync(path.join(OUT, 'land.json'), JSON.stringify(landShapes) + '\n');
const places = {};
for (const [k, v] of Object.entries(VIEWS)) {
  let d = '';
  for (let y = v.step / 2; y < v.h; y += v.step) for (let x = v.step / 2; x < v.w; x += v.step) { const ll = v.proj.invert([x, y]); if (ll && v.inside(ll)) d += `M${x} ${y}h0`; }
  fs.writeFileSync(path.join(OUT, k + '.svg'), `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${v.w} ${v.h}"><path d="${d}" fill="none" stroke="#C9D1CE" stroke-width="3" stroke-linecap="round"/></svg>\n`);
  const o = {};
  for (const [name, c] of Object.entries(PLACES[k])) { const [n, lat, lon] = c.length === 3 ? c : [name, c[0], c[1]]; const p = v.proj([lon, lat]); if (p) o[name] = { n, x: Math.round(p[0]), y: Math.round(p[1]) }; }
  places[k] = { w: v.w, h: v.h, places: o };
}
fs.writeFileSync(path.join(OUT, 'places.json'), JSON.stringify(places) + '\n');
console.log(Object.entries(places).map(([k, v]) => k + ':' + Object.keys(v.places).length).join(' '));
