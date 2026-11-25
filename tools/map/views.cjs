// The one place that says how each map view is framed and fitted: the size of the picture and the projection.
// Both generators read it (gen_assets.cjs for the site's grey land, lines and places; gen_founders.cjs for the shapes and
// positions the Founders view lays over that land), so the two can never be drawn with different settings again.
// On 25 Nov 2026 each generator had its own copy and the US copies differed: every state sat 25 to 35 px beside the land.
//
//   const MV = require('./views.cjs')(d3, topo, atlas110)   atlas110 = world-atlas countries-110m.json, parsed
//   MV.SIZE.us            { w, h } of the picture, in map units
//   MV.world() / MV.us() / MV.eu()   a fresh projection each time (clipExtent changes a projection in place)
//   MV.EU_FRAME           the Europe picture's own edges, for clipExtent
module.exports = function mapViews(d3, topo, atlas110) {
  const SIZE = { world: { w: 1060, h: 620 }, us: { w: 900, h: 540 }, eu: { w: 876, h: 600 } };
  // The US is fitted to the United States of the 1:110m world atlas (country 840), whatever outline is then drawn with it.
  const usa = topo.feature(atlas110, atlas110.objects.countries).features.find((f) => f.id === '840');
  const corners = (w, s, e, n) => ({ type: 'MultiPoint', coordinates: [[w, s], [e, n], [w, n], [e, s]] });
  return {
    SIZE, usa,
    EU_FRAME: [[0, 0], [SIZE.eu.w, SIZE.eu.h]],
    world: () => d3.geoNaturalEarth1().fitExtent([[20, 70], [1040, 580]], corners(-170, -52, 180, 72)),
    us: () => d3.geoAlbersUsa().fitExtent([[10, 10], [890, 530]], usa),
    // Europe is framed from Iceland (top left) to the Caspian (right), at the same scale as before the frame was widened (23 Nov).
    eu: () => d3.geoMercator().fitExtent([[0, 0], [SIZE.eu.w, SIZE.eu.h]], corners(-25, 34.5, 50.5, 67)),
  };
};
