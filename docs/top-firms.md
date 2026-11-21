# Regretamin Top Firms

_First edition: 2026. Made on 2026-11-21. Owner: the founder. Next edition: November 2027._

## What it is

Our own list of the venture firms we call "top". It is made once a year and then frozen, so it does not move when new deals arrive. The 2026 edition has 509 firms.

It exists for one reason: the map's "Top firms" filter (Hot right now view) needs to know which firms count as top, in the world and in each region.

## Why we made our own list

We looked at the outside rankings first. None of them fits:

- **Forbes Midas List** ranks people, not firms, and is mostly US names.
- **TIME and Statista, America's Top Venture Capital Firms** covers the United States only.
- **Venture Capital Journal's VCJ 50** has 50 firms and measures money raised, not quality.
- **PitchBook's performance tables** score a few hundred fund families and sit behind a paid product.

No outside list covers Asia, Latin America or Africa well enough to fill a region. Reusing a publisher's ranking inside a paid product would also need a rights check.

## How a firm gets on the list

**By the number of rounds it led in the last three years** (21 Nov 2023 to 21 Nov 2026).

- "Led" means the firm set the terms of the round and the others followed.
- We did not use plain deal count. Accelerators do hundreds of small deals and would crowd out the firms founders actually mean by "top". Accelerators almost never lead, so this rule drops them without a hand-made exclusion list.
- We did not use money managed. We know it for only 674 of about 4,900 firms.
- Ties are broken by total deals in the same three years, then by name.
- A firm needs at least one led round to be ranked.

## What is on it

Each firm can hold up to four ranks:

| Rank | Meaning | Firms in 2026 |
|---|---|---|
| World | Top 100 of all listed firms | 100 |
| Region | Top 25 inside its own map region (17 regions) | 389 |
| United States | Top 100 among US firms | 100 |
| Europe | Top 100 among European firms | 100 |

Two regions have fewer than 25 firms that led a round: Caribbean (9) and Central Asia and Caucasus (5). Every other region has a full 25.

The world top 100 is 74 US firms, 16 European and 10 from the rest of the world. That is why the region ranks exist: without them, most of the map would be empty.

## How the map uses it

The "Top firms" filter follows the zoom:

- **World map:** world top 100 plus the top 25 of every region (416 firms).
- **United States:** the US top 100.
- **Europe:** the European top 100.

## Where it lives

- **Database table:** `v2_top_firms`, one row per firm per year. Columns: `list_year`, `firm_id`, `region`, `led`, `deals`, `world_rank`, `region_rank`, `us_rank`, `eu_rank`, `added_by`, `note`.
- **The exact SQL that made it:** `docs/top_firms_2026.sql`. It was applied to production on 2026-11-21 and still has to be added to `supabase/migrations/` by the developer.
- The table is not readable from the website directly. Only the map functions read it.

To see the list, run this in the Supabase SQL editor:

```sql
select t.world_rank, t.region, t.region_rank, s.display_name, t.led, t.deals
from v2_top_firms t join firm_summary s using (firm_id)
where t.list_year = 2026
order by t.world_rank nulls last, t.region, t.region_rank;
```

## How to change it

- **Add or remove a firm by hand:** insert or delete its row, set `added_by` to `hand`, and write the reason in `note`. That way next year we can tell a judgment call from the ranking. No hand edits have been made to the 2026 edition.
- **Next year's edition:** run the insert from `docs/top_firms_2026.sql` again with the new year and the new dates. Compare it with 2026 to see who came in and who dropped out. The 2026 rows stay in the table.
- **Switching the map to a new edition:** the map functions read one year. Change that year when the new edition is approved.

## Known weak spots

- The list is only as good as our "led" data. A firm whose lead rounds we have not recorded ranks too low.
- Three years favours firms that were busy recently. A great firm that slowed down drops, which is the intent, but worth knowing.
- Some names look odd (for example "Plural France"). Those are firm-name clean-ups for the Data owner, not ranking errors.

## The world top 100, 2026

1–25: General Catalyst; Andreessen Horowitz; Sequoia Capital; Bessemer Venture Partners; SFC Capital; Accel; Kleiner Perkins; Index Ventures; Lightspeed Venture Partners; Khosla Ventures; Felicis Ventures; GV; Base10 Partners; Paradigm; Draper Associates; Founders Fund; First Round Capital; Initialized Capital; Bain Capital Ventures; Lux Capital; NEA; Forbion; Menlo Ventures; Pantera Capital; Greylock.

26–50: DCVC; QED Investors; FirstMark Capital; Plural France; True Ventures; Battery Ventures; Madrona Venture Group; Nexus Venture Partners; NFX Capital; Merak Capital; B Capital; Radical Ventures; Partech Partners; RA Capital; Haatch; Benchmark; Northzone; Headline; Kindred Ventures; Founderful; Uniiq; Venture Catalysts; Costanoa Ventures; Left Lane Capital; TQ Ventures.

51–75: Vertex Ventures Southeast Asia & India; Blockchain Capital; Thrive Capital; CDP Venture Capital SGR; Alleycorp; Spark Capital; Blackbird Ventures; Altos Ventures; Emergence Capital; Blume Venture Investment Manager; Oak HCFT; 8VC; Arch Venture Partners; RTP Global Management; Bitkraft Ventures; Dragonfly; Bonfire Ventures; 20VC; Upfront Ventures; Avp; Sapphire Ventures; M13 Ventures; SignalFire; Electric Capital; Hack VC.

76–100: Singular Capital Partners; Craft Ventures; Energy Impact Partners; Wing Venture Partners; Greenoaks; Mayfield; Ribbit Capital; Crosslink Capital; Globis Capital Partners; Wavemaker Partners; Ten Eleven Ventures; Standard Capital Ventures; Pear Ventures; IVP; PXN Ventures; LB Investment; Notable Capital; Delight Ventures; Soma Capital; South Park Commons; Parkwalk Advisors; Albion Capital; Greycroft; Reach; Scale Venture Partners.

The region, US and Europe lists are in the table.
