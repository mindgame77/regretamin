-- Research hold for non-VC firms (2026-11-22).
-- Only firms with a VC type row in v2_firm_types_firms are issued to research bots right away.
-- Every other live firm (Corporate VC, University fund, Angel group, Accelerator, Incubator,
-- Angel investor, PE, Growth, Hedge fund, or no type yet) is held until it has 5 or more
-- shown deals dated 2021-01-01 or later, then it is released automatically.
-- The firm stays on the site with its name and deals. Current unexpired claims finish normally;
-- only new hand-outs skip held firms. The site does not change.

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-22 as written below; the wrapper only lets a fresh test database skip it.
do $mig$
begin
  if to_regclass('public.v2_firms') is null
     or to_regclass('public.v2_firm_type') is null
     or to_regclass('public.v2_firm_types_firms') is null then
    raise notice 'v2 tables missing: firm research hold skipped';
    return;
  end if;
  execute $holdci$
-- 1. Two more firm types.
insert into public.v2_firm_type (firm_type_id, name) overriding system value values (9, 'University fund'), (10, 'Angel group')
on conflict do nothing;
select setval(pg_get_serial_sequence('public.v2_firm_type', 'firm_type_id'), (select max(firm_type_id) from public.v2_firm_type));

-- 2. One shared rule for every hand-out path.
create or replace function public.v2_firm_research_held(p_firm_id bigint)
returns boolean
language sql
stable
set search_path to 'public'
as $fn$
  select not exists (
           select 1 from public.v2_firm_types_firms t
            where t.firm_id = p_firm_id and t.firm_type_id = 1
              and t.is_current and not coalesce(t.archived, false))
     and (select count(*) from public.v2_deals d
           where d.firm_id = p_firm_id and d.shown is true
             and d.is_current is not false and not coalesce(d.archived, false)
             and d.deal_date >= date '2021-01-01') < 5
$fn$;
comment on function public.v2_firm_research_held(bigint) is
  'True when a firm is not VC (no current VC row in v2_firm_types_firms) and has fewer than 5 shown deals dated 2021+. Research hand-outs skip held firms.';
revoke all on function public.v2_firm_research_held(bigint) from public, anon, authenticated;

-- Read-only list for checks: every live firm, its types, shown 2021+ deals, and whether it is held.
create or replace view public.v2_firm_research_hold as
select f.firm_id, f.display_name, f.slug,
       (select string_agg(ft.name, ', ' order by ft.firm_type_id)
          from public.v2_firm_types_firms t join public.v2_firm_type ft on ft.firm_type_id = t.firm_type_id
         where t.firm_id = f.firm_id and t.is_current and not coalesce(t.archived, false)) as firm_types,
       (select count(*) from public.v2_deals d
         where d.firm_id = f.firm_id and d.shown is true and d.is_current is not false
           and not coalesce(d.archived, false) and d.deal_date >= date '2021-01-01') as shown_deals_2021,
       public.v2_firm_research_held(f.firm_id) as held
  from public.v2_firms f
 where not coalesce(f.archived, false) and f.merged_into_firm_id is null;
revoke all on public.v2_firm_research_hold from public, anon, authenticated;

-- 3. VC rows for live firms the old database marked VC that have no type row yet.
insert into public.v2_firm_types_firms (firm_id, firm_type_id, source_type, source_owner, source_date)
select f.firm_id, 1, 'Old database (firms.firm_type = VC)', 'db-admin-firm-type-hold-20261122', date '2026-11-22'
  from public.v2_firms f
 where not coalesce(f.archived, false) and f.merged_into_firm_id is null
   and exists (select 1 from public.firms o where o.slug = f.slug and o.firm_type = 'VC')
   and not exists (select 1 from public.v2_firm_types_firms t where t.firm_id = f.firm_id)
on conflict (firm_id, firm_type_id) do nothing;

-- 4. One primary type for each live firm that had no type and no old VC mark (classification.csv).
insert into public.v2_firm_types_firms (firm_id, firm_type_id, source_url, source_type, source_owner, source_date)
select c.firm_id, c.firm_type_id, nullif(c.url, ''), 'Manual classification (name, website, deals): ' || c.reason, 'db-admin-firm-type-hold-20261122', date '2026-11-22'
  from (values
  (17, 1, 'https://www.bvp.com', 'Venture capital firm by name, website and venture deal record'),
  (23, 1, 'http://www.ribbitcap.com', 'Venture capital firm by name, website and venture deal record'),
  (33, 1, 'http://www.nea.com', 'Venture capital firm by name, website and venture deal record'),
  (36, 3, 'http://www.encapinvestments.com', 'Energy private equity (buyout/growth capital for energy companies)'),
  (172, 2, 'https://www.highlandeurope.com/', 'Growth equity investor by name and website'),
  (175, 1, 'https://www.hsgcap.com', 'Venture capital firm by name, website and venture deal record'),
  (176, 1, 'https://benchmark.com', 'Venture capital firm by name, website and venture deal record'),
  (177, 1, 'https://www.cyberstarts.com/', 'Venture capital firm by name, website and venture deal record'),
  (178, 1, 'https://www.indexventures.com', 'Venture capital firm by name, website and venture deal record'),
  (183, 1, 'https://acapital.com', 'Venture capital firm by name, website and venture deal record'),
  (185, 1, 'https://www.firstround.com', 'Venture capital firm by name, website and venture deal record'),
  (186, 1, 'https://paradigm.xyz', 'Venture capital firm by name, website and venture deal record'),
  (193, 3, 'https://toptiercapitalpartners.com', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (198, 1, 'https://quiet.com', 'Venture capital firm by name, website and venture deal record'),
  (201, 5, 'https://openai.fund', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (205, 1, 'https://venrock.com', 'Venture capital firm by name, website and venture deal record'),
  (206, 1, 'https://mayfield.com', 'Venture capital firm by name, website and venture deal record'),
  (210, 1, 'https://crosslinkcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (212, 1, 'https://versantventures.com', 'Venture capital firm by name, website and venture deal record'),
  (215, 1, 'https://emcap.com', 'Venture capital firm by name, website and venture deal record'),
  (216, 1, 'https://tribecap.co', 'Venture capital firm by name, website and venture deal record'),
  (218, 1, 'https://dragonfly.xyz', 'Venture capital firm by name, website and venture deal record'),
  (221, 1, 'https://greenbayventures.com', 'Venture capital firm by name, website and venture deal record'),
  (225, 1, 'https://nexusvp.com', 'Venture capital firm by name, website and venture deal record'),
  (228, 1, 'https://pop.pinegrove.vc', 'Venture capital firm by name, website and venture deal record'),
  (229, 1, 'https://decheng.com', 'Venture capital firm by name, website and venture deal record'),
  (231, 1, 'https://electriccapital.com', 'Venture capital firm by name, website and venture deal record'),
  (236, 1, 'https://haun.co', 'Venture capital firm by name, website and venture deal record'),
  (238, 1, 'https://srone.com', 'Venture capital firm by name, website and venture deal record'),
  (239, 1, 'https://wilab.com', 'Venture capital firm by name, website and venture deal record'),
  (240, 1, 'https://lobby.vc', 'Venture capital firm by name, website and venture deal record'),
  (246, 1, 'https://abstractvc.com', 'Venture capital firm by name, website and venture deal record'),
  (247, 1, 'https://cotacapital.com', 'Venture capital firm by name, website and venture deal record'),
  (252, 1, 'https://founderscirclecapital.com', 'Venture capital firm by name, website and venture deal record'),
  (253, 1, 'https://amity.vc', 'Venture capital firm by name, website and venture deal record'),
  (257, 1, 'https://fin.capital', 'Venture capital firm by name, website and venture deal record'),
  (262, 1, 'https://kindredventures.com', 'Venture capital firm by name, website and venture deal record'),
  (264, 1, 'https://princeville-capital.com', 'Venture capital firm by name, website and venture deal record'),
  (265, 1, 'https://standardcryptovc.com', 'Venture capital firm by name, website and venture deal record'),
  (267, 1, 'https://www.draper.vc', 'Venture capital firm by name, website and venture deal record'),
  (268, 1, 'https://thrivecap.com', 'Venture capital firm by name, website and venture deal record'),
  (269, 1, 'https://finestructure.vc', 'Venture capital firm by name, website and venture deal record'),
  (270, 1, 'https://www.battery.com', 'Venture capital firm by name, website and venture deal record'),
  (271, 1, 'https://gigafund.com', 'Venture capital firm by name, website and venture deal record'),
  (272, 1, 'https://colcap.com', 'Venture capital firm by name, website and venture deal record'),
  (274, 1, 'https://8vc.com', 'Venture capital firm by name, website and venture deal record'),
  (276, 1, 'https://www.baincapitalventures.com', 'Venture capital firm by name, website and venture deal record'),
  (279, 1, 'https://www.crosspointcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (280, 1, 'https://usitfund.com', 'Venture capital firm by name, website and venture deal record'),
  (283, 1, 'https://www.hofvc.com', 'Venture capital firm by name, website and venture deal record'),
  (285, 1, 'https://k5global.com', 'Venture capital firm by name, website and venture deal record'),
  (289, 1, 'https://energyimpactpartners.com', 'Venture capital firm by name, website and venture deal record'),
  (290, 1, 'https://www.greycroft.com/', 'Venture capital firm by name, website and venture deal record'),
  (298, 1, 'https://soundventures.com', 'Venture capital firm by name, website and venture deal record'),
  (299, 1, 'https://www.elephantvc.com', 'Venture capital firm by name, website and venture deal record'),
  (300, 1, 'https://appletreepartners.com', 'Venture capital firm by name, website and venture deal record'),
  (305, 1, 'https://www.boxgroup.com', 'Venture capital firm by name, website and venture deal record'),
  (310, 1, 'https://bedrock.org', 'Venture capital firm by name, website and venture deal record'),
  (313, 1, 'https://www.align.vc', 'Venture capital firm by name, website and venture deal record'),
  (314, 1, 'https://accomplice.co/', 'Venture capital firm by name, website and venture deal record'),
  (315, 1, 'https://www.augustcap.com', 'Venture capital firm by name, website and venture deal record'),
  (317, 1, 'https://www.libertycityventures.com/', 'Venture capital firm by name, website and venture deal record'),
  (320, 7, 'https://www.kairoshq.com/', 'Venture studio / company builder / commercialization incubator'),
  (323, 1, 'https://www.fifthwall.com/', 'Venture capital firm by name, website and venture deal record'),
  (327, 1, 'https://iaventures.com/', 'Venture capital firm by name, website and venture deal record'),
  (331, 1, 'https://energizecap.com/', 'Venture capital firm by name, website and venture deal record'),
  (341, 1, 'https://www.anthoscapital.com', 'Venture capital firm by name, website and venture deal record'),
  (345, 1, 'https://www.sevensevensix.com', 'Venture capital firm by name, website and venture deal record'),
  (347, 1, 'https://www.canapi.com', 'Venture capital firm by name, website and venture deal record'),
  (348, 1, 'https://core-capital.com', 'Venture capital firm by name, website and venture deal record'),
  (349, 1, 'https://01a.com', 'Venture capital firm by name, website and venture deal record'),
  (352, 1, 'https://factorialfunds.com', 'Venture capital firm by name, website and venture deal record'),
  (353, 1, 'https://layerglobal.com', 'Venture investor by name; site tagline only'),
  (370, 1, 'https://www.atoneventures.com', 'Venture capital firm by name, website and venture deal record'),
  (371, 1, 'https://www.bipventures.vc', 'Venture capital firm by name, website and venture deal record'),
  (372, 1, 'https://www.bluecloudventures.com', 'Venture capital firm by name, website and venture deal record'),
  (373, 1, 'https://www.dimensioncap.com', 'Venture capital firm by name, website and venture deal record'),
  (383, 1, 'https://www.congruentvc.com', 'Venture capital firm by name, website and venture deal record'),
  (392, 1, 'https://marcypen.com', 'Venture investor by name; website looks wrong (unrelated WordPress site)'),
  (400, 1, 'https://www.5amventures.com', 'Venture capital firm by name, website and venture deal record'),
  (411, 1, 'https://3lcap.com', 'Venture capital firm by name, website and venture deal record'),
  (412, 1, 'https://omegafunds.com', 'Venture capital firm by name, website and venture deal record'),
  (418, 1, 'https://www.villageglobal.com', 'Venture capital firm by name, website and venture deal record'),
  (449, 1, 'https://definitioncap.com', 'Venture capital firm by name, website and venture deal record'),
  (455, 1, 'https://www.coinfund.io', 'Venture capital firm by name, website and venture deal record'),
  (463, 1, 'https://www.crcmvc.com', 'Venture capital firm by name, website and venture deal record'),
  (498, 1, 'https://www.rosecliff.com', 'Venture capital firm by name, website and venture deal record'),
  (522, 2, 'https://alignmentgrowth.com', 'Growth equity investor by name and website'),
  (527, 2, 'https://www.angelenogroup.com', 'Growth equity investor by name and website'),
  (594, 1, 'https://www.wrg.vc', 'Venture capital firm by name, website and venture deal record'),
  (646, 1, 'https://innoviuscapital.com', 'Venture capital firm by name, website and venture deal record'),
  (665, 1, 'https://newscienceventures.com', 'Venture capital firm by name, website and venture deal record'),
  (667, 1, 'https://rpmvc.com', 'Venture capital firm by name, website and venture deal record'),
  (670, 1, 'https://mercuryfund.com', 'Venture capital firm by name, website and venture deal record'),
  (696, 2, 'https://accelmed.com', 'Growth equity investor by name and website'),
  (698, 1, 'https://tamarackglobal.com', 'Venture capital firm by name, website and venture deal record'),
  (703, 1, 'https://threshold.vc', 'Venture capital firm by name, website and venture deal record'),
  (720, 1, 'https://thehouse.fund', 'Venture capital firm by name, website and venture deal record'),
  (732, 1, 'https://ampfoundry.com', 'Venture investor by name; site gave no text'),
  (735, 1, 'https://112capital.com', 'Venture capital firm by name, website and venture deal record'),
  (738, 1, 'https://causeway.vc', 'Venture capital firm by name, website and venture deal record'),
  (743, 1, 'https://mhscapital.com', 'Venture capital firm by name, website and venture deal record'),
  (791, 1, 'https://uphonestcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (818, 1, 'https://futaleufu-partners.com', 'Venture capital firm by name, website and venture deal record'),
  (826, 1, 'https://authentic-ventures.com', 'Venture capital firm by name, website and venture deal record'),
  (835, 1, 'https://emeraldmanagers.com', 'Venture capital firm by name, website and venture deal record'),
  (837, 1, 'https://goaheadvc.com', 'Venture capital firm by name, website and venture deal record'),
  (858, 1, 'https://entradaventures.com', 'Venture capital firm by name, website and venture deal record'),
  (893, 1, 'https://expa.com', 'Venture capital firm by name, website and venture deal record'),
  (901, 1, 'https://scenicmanagement.co', 'Venture capital firm by name, website and venture deal record'),
  (904, 1, 'https://altaventures.com', 'Venture capital firm by name, website and venture deal record'),
  (909, 1, 'https://defencebuilder.com/fund', 'Venture capital firm by name, website and venture deal record'),
  (914, 1, '', 'Venture investor by name; no website on file'),
  (919, 6, 'https://www.sikorskychallenge.com/', 'Accelerator / startup program'),
  (920, 6, 'https://brave1.gov.ua/', 'Government startup grant / support program, not a VC (closest type)'),
  (921, 7, 'https://www.skelar.tech/', 'Venture studio / company builder / commercialization incubator'),
  (922, 1, 'https://sd.capital', 'Venture capital firm by name, website and venture deal record'),
  (923, 6, 'https://usf.com.ua/', 'Government startup grant / support program, not a VC (closest type)'),
  (925, 1, 'https://a1x.capital/', 'Venture capital firm by name, website and venture deal record'),
  (929, 1, 'https://nezlamni.fund/', 'Venture investor by name; site gave no text'),
  (932, 1, 'https://uptf.vc/', 'Venture capital firm by name, website and venture deal record'),
  (935, 10, 'https://www.angelone.fund/', 'Angel network / angel club fund'),
  (938, 10, 'https://iclub.vc/', 'Angel network / angel club fund'),
  (1031, 1, 'https://www.atomico.com', 'Venture capital firm by name, website and venture deal record'),
  (1034, 3, 'https://dbayadvisors.com', 'Private equity / buyout or private-markets manager by name and website'),
  (1035, 1, 'https://www.pointnine.com', 'Venture capital firm by name, website and venture deal record'),
  (1040, 1, 'https://seedcamp.com', 'Venture capital firm by name, website and venture deal record'),
  (1041, 1, 'https://www.cherry.vc', 'Venture capital firm by name, website and venture deal record'),
  (1045, 1, 'https://seraphim.vc/', 'Venture capital firm by name, website and venture deal record'),
  (1048, 1, 'https://468cap.com', 'Venture capital firm by name, website and venture deal record'),
  (1051, 1, 'https://www.quantonation.com', 'Venture capital firm by name, website and venture deal record'),
  (1052, 1, 'https://www.jeito.life', 'Venture capital firm by name, website and venture deal record'),
  (1054, 1, 'https://biogenerationventures.com', 'Venture capital firm by name, website and venture deal record'),
  (1056, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (1057, 3, 'https://www.h2ep.com', 'Private equity / buyout or private-markets manager by name and website'),
  (1058, 1, 'https://alpinespace.vc', 'Venture capital firm by name, website and venture deal record'),
  (1060, 1, 'https://www.rockawayx.com', 'Venture capital firm by name, website and venture deal record'),
  (1062, 1, 'https://www.nosaracapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1065, 1, 'https://www.anthemis.com', 'Venture capital firm by name, website and venture deal record'),
  (1077, 1, 'https://www.transition.vc', 'Venture capital firm by name, website and venture deal record'),
  (1079, 1, 'https://www.airstreet.com', 'Venture capital firm by name, website and venture deal record'),
  (1082, 1, 'https://www.healthcap.eu', 'Venture capital firm by name, website and venture deal record'),
  (1086, 1, 'https://www.arcadiagames.vc/', 'Venture capital firm by name, website and venture deal record'),
  (1087, 3, 'https://iqeq.com', 'Fund administrator / fund-formation service, not an investor; no matching type, held as non-VC'),
  (1089, 1, 'https://nordstar.com', 'Venture capital firm by name, website and venture deal record'),
  (1091, 1, 'https://www.dig.ventures', 'Venture capital firm by name, website and venture deal record'),
  (1092, 1, 'https://www.metaplanet.com', 'Venture capital firm by name, website and venture deal record'),
  (1094, 1, 'https://www.tiny.vc', 'Venture capital firm by name, website and venture deal record'),
  (1107, 1, 'https://www.morethancapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1109, 1, 'https://www.redriverwest.com', 'Venture capital firm by name, website and venture deal record'),
  (1112, 1, 'https://www.greentrailcap.com', 'Venture investor by name; site gave no text, 0 deals'),
  (1116, 3, 'https://www.infra.one', 'Fund administrator / fund-formation service, not an investor; no matching type, held as non-VC'),
  (1129, 1, 'https://www.cfh.de', 'Venture capital firm by name, website and venture deal record'),
  (1140, 1, 'https://www.bm-t.de', 'Venture capital firm by name, website and venture deal record'),
  (1158, 1, 'https://sff.vc', 'Venture capital firm by name, website and venture deal record'),
  (1163, 1, 'https://www.bom.nl', 'Venture capital firm by name, website and venture deal record'),
  (1164, 1, 'https://www.dff.ventures', 'Venture capital firm by name, website and venture deal record'),
  (1187, 1, 'https://eifo.dk', 'Venture capital firm by name, website and venture deal record'),
  (1191, 1, 'https://fundplus.be', 'Venture capital firm by name, website and venture deal record'),
  (1193, 1, 'https://idekapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1209, 9, 'https://www.vivesfund.com', 'University (or university research institute) investment fund/company'),
  (1236, 1, 'https://parkwalk.vc', 'Venture capital firm by name, website and venture deal record'),
  (1237, 9, 'https://ucltf.co.uk', 'University (or university research institute) investment fund/company'),
  (1253, 1, 'https://entreecap.com', 'Venture capital firm by name, website and venture deal record'),
  (1265, 1, 'https://www.oxfordtechnology.com', 'Venture capital firm by name, website and venture deal record'),
  (1357, 1, 'https://glilotcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1360, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (1363, 1, 'https://www.vertexventures.co.il', 'Venture capital firm by name, website and venture deal record'),
  (1366, 1, 'https://www.pitango.com', 'Venture capital firm by name, website and venture deal record'),
  (1371, 1, 'https://www.indiaquotient.in', 'Venture capital firm by name, website and venture deal record'),
  (1374, 1, 'https://omnivore.vc/', 'Venture capital firm by name, website and venture deal record'),
  (1377, 1, 'https://www.tvm-lifescience.com', 'Venture capital firm by name, website and venture deal record'),
  (1378, 1, 'https://kalaari.com', 'Venture capital firm by name, website and venture deal record'),
  (1385, 1, 'https://www.pioneerfund.vc', 'Venture capital firm by name, website and venture deal record'),
  (1386, 1, 'https://key1capital.com', 'Venture capital firm by name, website and venture deal record'),
  (1387, 1, 'https://www.viola-group.com/fund/violaventures/', 'Venture capital firm by name, website and venture deal record'),
  (1389, 1, 'https://www.f2vc.com', 'Venture capital firm by name, website and venture deal record'),
  (1391, 1, 'https://blume.vc', 'Venture capital firm by name, website and venture deal record'),
  (1394, 1, 'https://www.vgames.vc', 'Venture capital firm by name, website and venture deal record'),
  (1398, 1, 'https://firesideventures.com', 'Venture capital firm by name, website and venture deal record'),
  (1401, 1, 'https://www.maya.capital', 'Venture capital firm by name, website and venture deal record'),
  (1402, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (1404, 1, 'https://www.lionbird.com', 'Venture capital firm by name, website and venture deal record'),
  (1406, 1, 'https://www.scapitalvc.com', 'Venture capital firm by name, website and venture deal record'),
  (1408, 1, 'https://stellarisvp.com', 'Venture capital firm by name, website and venture deal record'),
  (1410, 1, 'https://www.triventures.vc', 'Venture capital firm by name, website and venture deal record'),
  (1415, 1, 'https://www.epiqcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1418, 3, 'https://www.turimbr.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (1419, 1, 'https://www.viola-group.com/fund/violafintech', 'Venture capital firm by name, website and venture deal record'),
  (1427, 1, 'https://www.atlantico.vc', 'Venture capital firm by name, website and venture deal record'),
  (1428, 1, 'https://www.bewater.vc', 'Venture capital firm by name, website and venture deal record'),
  (1429, 1, 'https://incubatefund.com', 'Venture capital firm by name, website and venture deal record'),
  (1430, 1, 'https://www.tantalloncapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1431, 1, 'https://www.techaviv.com', 'Venture capital firm by name, website and venture deal record'),
  (1433, 1, 'https://www.kh2cap.com', 'Venture investor by name; site unclear'),
  (1436, 1, 'https://gefencapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1439, 1, 'https://www.northbasemedia.com', 'Venture capital firm by name, website and venture deal record'),
  (1442, 1, 'https://www.climecap.com', 'Venture capital firm by name, website and venture deal record'),
  (1448, 1, 'https://ibf.fund', 'Venture capital firm by name, website and venture deal record'),
  (1450, 1, 'https://www.ivycapventures.com', 'Venture capital firm by name, website and venture deal record'),
  (1451, 1, 'https://www.aera.vc', 'Venture capital firm by name, website and venture deal record'),
  (1452, 1, 'https://highgrowth.patria.com/', 'Venture capital firm by name, website and venture deal record'),
  (1453, 3, 'https://www.stratusbr.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (1454, 1, 'https://www.rippleventures.com', 'Venture capital firm by name, website and venture deal record'),
  (1456, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (1457, 1, 'https://northpointvc.com/', 'Venture capital firm by name, website and venture deal record'),
  (1458, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (1459, 1, 'https://www.unboxcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (1461, 1, 'https://www.mvcapital.vc', 'Venture capital firm by name, website and venture deal record'),
  (1551, 1, 'https://auxxo.de', 'Venture capital firm by name, website and venture deal record'),
  (1615, 3, 'https://www.activecapitalcompany.com', 'Private equity / buyout or private-markets manager by name and website'),
  (1670, 1, 'https://expeditionsfund.com', 'Venture capital firm by name, website and venture deal record'),
  (1681, 1, 'https://fundingbox.vc', 'Venture capital firm by name, website and venture deal record'),
  (1688, 1, 'https://lsifund.pl', 'Venture capital firm by name, website and venture deal record'),
  (1691, 1, 'https://polishventurefund.pl', 'Venture capital firm by name, website and venture deal record'),
  (1710, 1, 'https://www.bioventure.de', 'Venture capital firm by name, website and venture deal record'),
  (1712, 1, 'https://gruenderfonds-ruhr.com', 'Venture capital firm by name, website and venture deal record'),
  (1713, 1, 'https://www.hp-vc.com/', 'Venture capital firm by name, website and venture deal record'),
  (1715, 1, 'https://mbg-bw.ermoeglicher.de', 'Venture capital firm by name, website and venture deal record'),
  (1717, 1, 'https://isb.rlp.de', 'Venture capital firm by name, website and venture deal record'),
  (1735, 1, 'https://www.cedarfund.com', 'Venture capital firm by name, website and venture deal record'),
  (1739, 1, 'https://www.atooro.com', 'Venture capital firm by name, website and venture deal record'),
  (1741, 1, 'https://sibf.vc', 'Venture capital firm by name, website and venture deal record'),
  (1742, 1, 'https://www.docor.co.il', 'Venture investor by name; site gave no text'),
  (1749, 1, 'https://www.skyfund.co.il', 'Venture capital firm by name, website and venture deal record'),
  (1754, 1, 'https://www.elahfund.com', 'Venture capital firm by name, website and venture deal record'),
  (1809, 1, 'https://nventures.sg', 'Venture capital firm by name, website and venture deal record'),
  (1814, 1, 'https://www.tanphifmc.com', 'Venture capital firm by name, website and venture deal record'),
  (1817, 1, 'https://newenergynexus.ventures', 'Venture capital firm by name, website and venture deal record'),
  (1821, 1, 'https://kkfund.co', 'Venture capital firm by name, website and venture deal record'),
  (1825, 1, 'https://blockchainff.com', 'Venture capital firm by name, website and venture deal record'),
  (1831, 1, 'https://www.verge.fund', 'Venture capital firm by name, website and venture deal record'),
  (1838, 1, 'https://avpcap.com', 'Venture capital firm by name, website and venture deal record'),
  (1840, 5, 'https://www.creditmutuel-innovation.eu', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (1848, 1, 'https://merieux-partners.com', 'Venture capital firm by name, website and venture deal record'),
  (1849, 1, 'https://odysseeventure.com', 'Venture capital firm by name, website and venture deal record'),
  (1860, 1, 'https://aglaeventures.com', 'Venture capital firm by name, website and venture deal record'),
  (1867, 1, 'https://pleiadeventure.com', 'Venture capital firm by name, website and venture deal record'),
  (1873, 1, 'https://inceptionfund.vc', 'Venture capital firm by name, website and venture deal record'),
  (1904, 1, 'https://www.designimpactfund.com', 'Venture investor by name; site gave no text'),
  (1942, 1, 'https://www.deeptechcapitalpartners.com', 'Venture capital firm by name, website and venture deal record'),
  (1955, 1, 'https://bluesparrows.nl', 'Venture capital firm by name, website and venture deal record'),
  (1957, 1, 'https://futurefoodfund.nl', 'Venture capital firm by name, website and venture deal record'),
  (1975, 1, 'https://ltif.nl/', 'Venture capital firm by name, website and venture deal record'),
  (1985, 3, 'https://www.crp.com.br/', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (1992, 1, 'https://grao.vc', 'Venture capital firm by name, website and venture deal record'),
  (2054, 1, 'https://tesi.fi', 'Venture capital firm by name, website and venture deal record'),
  (2059, 1, 'https://aboaventure.fi', 'Venture capital firm by name, website and venture deal record'),
  (2064, 9, 'https://lrd.kuleuven.be', 'University (or university research institute) investment fund/company'),
  (2066, 9, 'https://www.imecistartfuturefund.com', 'University (or university research institute) investment fund/company'),
  (2076, 1, 'https://www.seederfund.be', 'Venture capital firm by name, website and venture deal record'),
  (2077, 1, 'https://shapingimpact.vc', 'Venture capital firm by name, website and venture deal record'),
  (2081, 6, 'https://www.thefaktory.com', 'Accelerator / startup program'),
  (2092, 1, 'https://epimede.com', 'Venture capital firm by name, website and venture deal record'),
  (2093, 1, 'https://innovationfund.eu/', 'Venture capital firm by name, website and venture deal record'),
  (2104, 1, 'https://www.kfund.vc', 'Venture capital firm by name, website and venture deal record'),
  (2105, 1, 'https://capytaliza.com', 'Venture capital firm by name, website and venture deal record'),
  (2121, 1, 'https://www.ivf.gva.es', 'Venture capital firm by name, website and venture deal record'),
  (2122, 1, 'https://www.spri.eus', 'Venture capital firm by name, website and venture deal record'),
  (2147, 3, 'https://siena.ee', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (2151, 1, 'https://www.outlastfund.com', 'Venture capital firm by name, website and venture deal record'),
  (2166, 1, 'https://bonitasktk.hu', 'Venture capital firm by name, website and venture deal record'),
  (2169, 1, 'https://szta.hu', 'Venture capital firm by name, website and venture deal record'),
  (2177, 4, 'https://www.morningsidehill.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (2178, 1, 'https://ballenaventures.eu', 'Venture capital firm by name, website and venture deal record'),
  (2182, 1, 'https://vff.sk', 'Venture capital firm by name, website and venture deal record'),
  (2185, 1, 'https://www.cbim.sk', 'Venture capital firm by name, website and venture deal record'),
  (2186, 1, 'https://www.fondfit.sk', 'Venture capital firm by name, website and venture deal record'),
  (2204, 1, 'https://mevp.com', 'Venture capital firm by name, website and venture deal record'),
  (2209, 1, 'https://woodstockfund.com', 'Venture capital firm by name, website and venture deal record'),
  (2230, 5, 'https://sdf.ae', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (2262, 1, 'https://dfdf.vc', 'Venture capital firm by name, website and venture deal record'),
  (2273, 1, 'https://rua.vc', 'Venture capital firm by name, website and venture deal record'),
  (2285, 9, 'https://rvc.com.sa', 'University (or university research institute) investment fund/company'),
  (2289, 1, 'https://minvest.sa', 'Venture investor by name; site unclear'),
  (2297, 1, 'https://www.jic.vc', 'Venture capital firm by name, website and venture deal record'),
  (2333, 3, 'https://k1.com', 'Private equity / buyout or private-markets manager by name and website'),
  (2334, 1, 'https://multicoin.capital', 'Venture capital firm by name, website and venture deal record'),
  (2335, 1, 'https://panteracapital.com', 'Venture capital firm by name, website and venture deal record'),
  (2336, 4, 'https://racap.com', 'Hedge fund / crossover or public-markets manager'),
  (2337, 1, 'https://sofinnova.com', 'Venture capital firm by name, website and venture deal record'),
  (2338, 1, 'https://www.transposeplatform.vc', 'Venture capital firm by name, website and venture deal record'),
  (2339, 2, 'https://valorep.com', 'Growth equity investor by name and website'),
  (2344, 1, 'https://www.nextlegacy.com', 'Venture capital firm by name, website and venture deal record'),
  (2348, 1, 'https://www.fifthdown.com', 'Venture capital firm by name, website and venture deal record'),
  (2350, 1, 'https://idgcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (2351, 1, 'https://jvpvc.com', 'Venture capital firm by name, website and venture deal record'),
  (2352, 1, 'https://www.lavfund.com', 'Venture capital firm by name, website and venture deal record'),
  (2353, 1, 'https://shunwei.com', 'Venture capital firm by name, website and venture deal record'),
  (2363, 3, 'https://pearl-energy.com', 'Energy private equity (buyout/growth capital for energy companies)'),
  (2364, 1, 'https://medicxi.com', 'Venture capital firm by name, website and venture deal record'),
  (2368, 3, 'https://energyspectrum.com', 'Energy private equity (buyout/growth capital for energy companies)'),
  (2378, 6, 'https://joinef.com', 'Accelerator / startup program'),
  (2379, 1, 'https://earlybird.com', 'Venture capital firm by name, website and venture deal record'),
  (2380, 1, 'https://www.hummingbird.vc/', 'Venture capital firm by name, website and venture deal record'),
  (2447, 1, 'https://thelegaltechfund.com', 'Venture capital firm by name, website and venture deal record'),
  (2543, 1, 'https://allaboard.vc/', 'Venture capital firm by name, website and venture deal record'),
  (2588, 3, 'https://www.clearcreekinv.com/', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (2913, 1, 'https://capital49.com/', 'Venture capital firm by name, website and venture deal record'),
  (2945, 1, 'https://foodlabs.de', 'Venture capital firm by name, website and venture deal record'),
  (2946, 1, 'https://www.healcapital.com/', 'Venture capital firm by name, website and venture deal record'),
  (2947, 1, 'https://www.maetch.vc', 'Venture capital firm by name, website and venture deal record'),
  (2960, 3, 'https://hillhouseinvestment.cn', 'Private equity / buyout or private-markets manager by name and website'),
  (3005, 1, 'https://www.activeimpactinvestments.com', 'Venture capital firm by name, website and venture deal record'),
  (3033, 5, 'https://www.aozora-ci.co.jp/', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (3065, 1, 'https://biotrackcapital.com/', 'Venture capital firm by name, website and venture deal record'),
  (3123, 5, 'https://daiwa-inv.co.jp/', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (3303, 3, 'https://idinvest.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (3304, 1, 'https://northzone.com/', 'Venture capital firm by name, website and venture deal record'),
  (3306, 3, 'https://eurazeo.com', 'Private equity / buyout or private-markets manager by name and website'),
  (3307, 1, 'https://realventures.com', 'Venture capital firm by name, website and venture deal record'),
  (3308, 1, 'https://acceleratefund.ca/', 'Venture capital firm by name, website and venture deal record'),
  (3309, 7, 'https://admarebio.com', 'Venture studio / company builder / commercialization incubator'),
  (3310, 1, 'https://aheadventures.com.br', 'Venture capital firm by name, website and venture deal record'),
  (3311, 1, 'https://amorchem.com', 'Venture capital firm by name, website and venture deal record'),
  (3312, 1, 'https://anteragr.com.br/pt/', 'Venture capital firm by name, website and venture deal record'),
  (3313, 1, 'https://bridgeventures.com.br', 'Venture capital firm by name, website and venture deal record'),
  (3314, 1, 'https://brightspark.com/en', 'Venture capital firm by name, website and venture deal record'),
  (3315, 1, 'https://www.celtic.vc/', 'Venture capital firm by name, website and venture deal record'),
  (3316, 1, 'https://fundepar.com.br/', 'Venture investor by name; site unclear'),
  (3317, 1, 'https://gr8ventures.com.br', 'Venture capital firm by name, website and venture deal record'),
  (3318, 1, 'https://kx.ventures/', 'Venture capital firm by name, website and venture deal record'),
  (3319, 1, 'https://lupacapital.com.br', 'Venture capital firm by name, website and venture deal record'),
  (3320, 1, 'https://quartzocapital.com.br/', 'Venture capital firm by name, website and venture deal record'),
  (3321, 1, 'https://razzo.ventures', 'Venture capital firm by name, website and venture deal record'),
  (3322, 1, 'https://staminavc.com', 'Venture capital firm by name, website and venture deal record'),
  (3323, 1, 'https://saopedro.capital', 'Venture capital firm by name, website and venture deal record'),
  (3324, 1, 'https://unitedfounders.vc', 'Venture capital firm by name, website and venture deal record'),
  (3326, 1, 'https://wind.capital/', 'Venture capital firm by name, website and venture deal record'),
  (3360, 1, 'https://www.agate-invest.com', 'Venture capital firm by name, website and venture deal record'),
  (3368, 1, 'https://ajuib.co.kr', 'Venture capital firm by name, website and venture deal record'),
  (3529, 3, 'https://bmcecapital.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (3668, 1, 'https://ccvc.co.kr', 'Venture capital firm by name, website and venture deal record'),
  (3698, 1, 'https://davalueinvest.com', 'Venture capital firm by name, website and venture deal record'),
  (3746, 1, 'https://esquared.org.za', 'Venture capital firm by name, website and venture deal record'),
  (3823, 1, 'https://felixstrategic.com', 'Venture capital firm by name, website and venture deal record'),
  (3879, 1, 'https://fourcitiescapital.com', 'Venture capital firm by name, website and venture deal record'),
  (3921, 3, 'https://gpalminvestments.org', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (3963, 1, 'https://haranginvest.com', 'Venture capital firm by name, website and venture deal record'),
  (3978, 1, 'https://heimventure.com', 'Venture capital firm by name, website and venture deal record'),
  (4000, 1, 'https://www.hkic.org.hk/', 'Venture capital firm by name, website and venture deal record'),
  (4107, 1, 'https://jaic-vc.co.jp/', 'Venture capital firm by name, website and venture deal record'),
  (4116, 1, 'https://j-vgi.co.jp/', 'Venture capital firm by name, website and venture deal record'),
  (4256, 1, 'https://mtivc.com', 'Venture capital firm by name, website and venture deal record'),
  (5230, 1, 'https://unitedventures.com/', 'Venture capital firm by name, website and venture deal record'),
  (5231, 1, 'https://ecapital.vc', 'Venture capital firm by name, website and venture deal record'),
  (5233, 1, 'https://desaiventures.io', 'Venture investor by name; family office doing seed deals'),
  (5234, 6, 'https://antler.co', 'Accelerator / startup program'),
  (5235, 1, 'https://findus-venture.com', 'Venture capital firm by name, website and venture deal record'),
  (5236, 1, 'https://e2mc.space', 'Venture capital firm by name, website and venture deal record'),
  (5238, 4, 'https://www.coatue.com', 'Hedge fund / crossover or public-markets manager'),
  (5279, 2, 'https://insightpartners.com', 'Growth equity investor by name and website'),
  (5280, 1, 'https://orbimed.com', 'Venture capital firm by name, website and venture deal record'),
  (5281, 4, 'https://tigerglobal.com', 'Hedge fund / crossover or public-markets manager'),
  (5282, 4, 'https://altimeter.com', 'Hedge fund / crossover or public-markets manager'),
  (5284, 2, 'https://sandscapital.com', 'Growth equity investor by name and website'),
  (5285, 1, 'https://frazierls.com', 'Venture capital firm by name, website and venture deal record'),
  (5288, 1, 'https://vivocapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5290, 1, 'https://cataliocapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5292, 1, 'https://silvertonpartners.com', 'Venture capital firm by name, website and venture deal record'),
  (5293, 1, 'https://liveoakvp.com', 'Venture capital firm by name, website and venture deal record'),
  (5295, 1, 'https://polarispartners.com', 'Venture capital firm by name, website and venture deal record'),
  (5297, 1, 'https://arthurventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5298, 1, 'https://mpmbioimpact.com', 'Venture capital firm by name, website and venture deal record'),
  (5300, 1, 'https://fpvventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5301, 1, 'https://hustlefund.vc', 'Venture capital firm by name, website and venture deal record'),
  (5302, 2, 'https://vmgpartners.com', 'Growth equity investor by name and website'),
  (5304, 1, 'https://boldcapitalpartners.com', 'Venture capital firm by name, website and venture deal record'),
  (5305, 1, 'https://springtide.com', 'Venture capital firm by name, website and venture deal record'),
  (5306, 1, 'https://presight.vc', 'Venture capital firm by name, website and venture deal record'),
  (5307, 1, 'https://1kx.capital', 'Venture capital firm by name, website and venture deal record'),
  (5308, 1, 'https://restive.com', 'Venture capital firm by name, website and venture deal record'),
  (5310, 1, 'https://femalefoundersfund.com', 'Venture capital firm by name, website and venture deal record'),
  (5311, 6, 'https://capitalfactory.com', 'Accelerator / startup program'),
  (5315, 1, 'https://healthxventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5316, 1, 'https://theimpactengine.com', 'Venture capital firm by name, website and venture deal record'),
  (5317, 1, 'https://lewisandclarkventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5319, 3, 'https://www.ares.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5320, 3, 'https://stepstonegroup.com', 'Private-markets / fund-of-funds manager (no fund-of-funds type; PE is the closest)'),
  (5321, 3, 'https://stonepeak.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5322, 3, 'https://www.blackstone.com/our-businesses/strategic-partners/', 'Private equity / buyout or private-markets manager by name and website'),
  (5323, 3, 'https://hig.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5324, 3, 'https://adamsstreetpartners.com', 'Private-markets / fund-of-funds manager (no fund-of-funds type; PE is the closest)'),
  (5325, 3, 'https://www.morganstanley.com/im/capitalpartners', 'Private equity / buyout or private-markets manager by name and website'),
  (5326, 4, 'https://alkeoncapital.com', 'Hedge fund / crossover or public-markets manager'),
  (5327, 3, 'https://horsleybridge.com', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (5328, 3, 'https://aquiline.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5330, 1, 'https://www.137ventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5331, 3, 'https://truebridgecapital.com', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (5332, 3, 'https://franklinparkllc.com', 'Private-markets / fund-of-funds manager (no fund-of-funds type; PE is the closest)'),
  (5334, 3, 'https://fisherlynch.com', 'Private-markets / fund-of-funds manager (no fund-of-funds type; PE is the closest)'),
  (5335, 3, 'https://sagard.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5337, 4, 'https://atreidesmgmt.com', 'Hedge fund / crossover or public-markets manager'),
  (5338, 3, 'https://orionrp.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5339, 3, 'https://www.harbert.net', 'Private equity / buyout or private-markets manager by name and website'),
  (5340, 1, 'https://troycapitalpartners.com', 'Venture capital firm by name, website and venture deal record'),
  (5341, 3, 'https://www.frazierhealthcare.com/', 'Private equity / buyout or private-markets manager by name and website'),
  (5343, 1, 'https://cercanolp.com', 'Venture capital firm by name, website and venture deal record'),
  (5344, 2, 'https://gcsllc.com', 'Growth equity investor by name and website'),
  (5345, 2, 'https://leadedge.com/', 'Growth equity investor by name and website'),
  (5346, 3, 'https://motivepartners.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5347, 5, 'https://standardindustries.com/our-businesses/standard-investments', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5348, 4, 'https://redmilegroup.com', 'Hedge fund / crossover or public-markets manager'),
  (5349, 3, 'https://bowriverevergreen.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5350, 4, 'https://www.tigerironcapital.com', 'Hedge fund / crossover or public-markets manager'),
  (5352, 4, 'https://www.ecor1cap.com', 'Hedge fund / crossover or public-markets manager'),
  (5353, 1, 'https://smashcap.com', 'Venture capital firm by name, website and venture deal record'),
  (5357, 3, 'https://northgate.com/', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (5358, 4, 'https://casdincapital.com', 'Hedge fund / crossover or public-markets manager'),
  (5359, 1, 'https://peakline.com', 'Venture investor by name; site blocked'),
  (5361, 1, 'https://1789capital.io', 'Venture capital firm by name, website and venture deal record'),
  (5362, 3, 'https://www.1sharpe.com/', 'Private equity / buyout or private-markets manager by name and website'),
  (5363, 1, 'https://precisioncapital.com', 'Venture investor by name; site unclear'),
  (5364, 3, '', 'Private equity / buyout or private-markets manager by name and website'),
  (5365, 3, 'https://petersonpartners.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5366, 2, 'https://www.edisonpartners.com', 'Growth equity investor by name and website'),
  (5368, 3, 'https://www.spruceviewpartners.com', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (5370, 4, 'https://www.logoscapital.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5371, 1, 'https://rethink-capital.com/', 'Venture capital firm by name, website and venture deal record'),
  (5372, 2, 'https://carrickcapitalpartners.com', 'Growth equity investor by name and website'),
  (5373, 2, 'https://ewhealthcare.com', 'Growth equity investor by name and website'),
  (5375, 4, 'https://parafi.com', 'Hedge fund / crossover or public-markets manager'),
  (5376, 2, 'https://healthquestcapital.com', 'Growth equity investor by name and website'),
  (5377, 1, 'https://lithos.com', 'Venture capital firm by name, website and venture deal record'),
  (5378, 1, 'https://uprising.us', 'Venture capital firm by name, website and venture deal record'),
  (5379, 3, '', 'Private equity / buyout or private-markets manager by name and website'),
  (5380, 4, 'https://silverarccapital.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5381, 1, 'https://alphasquaregroup.com', 'Venture capital firm by name, website and venture deal record'),
  (5384, 3, 'https://riceparkcapital.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5388, 3, 'https://greenpointpartners.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5390, 1, 'https://strategycapital.com', 'Venture investor by name; site blocked, 0 deals'),
  (5391, 2, 'https://rizvitraverse.com', 'Growth equity investor by name and website'),
  (5392, 1, 'https://www.newlegacy.com', 'Venture investor by name; site unclear'),
  (5393, 1, 'https://sovereignscapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5396, 4, 'https://trinityalpscapital.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5397, 1, '', 'Venture capital firm by name, website and venture deal record'),
  (5402, 3, 'https://northskycapital.com/', 'Private-markets / fund-of-funds manager (no fund-of-funds type; PE is the closest)'),
  (5403, 1, 'https://www.petrichorcap.com', 'Venture capital firm by name, website and venture deal record'),
  (5405, 1, '', 'Venture investor by name; no website on file'),
  (5406, 3, 'https://www.astoconsumer.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5407, 1, 'https://www.distributedglobal.com/', 'Venture capital firm by name, website and venture deal record'),
  (5408, 1, 'https://1confirmation.com', 'Venture capital firm by name, website and venture deal record'),
  (5409, 4, 'https://arosacapital.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5410, 3, 'https://hauserprivateequity.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5412, 1, 'https://claritascapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5413, 3, 'https://www.felicitasgp.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5414, 2, 'https://elsewhere.partners', 'Growth equity investor by name and website'),
  (5415, 1, 'https://corner.xyz', 'Venture capital firm by name, website and venture deal record'),
  (5417, 2, 'https://carbondirectcapital.com', 'Growth equity investor by name and website'),
  (5520, 3, 'https://highpost.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5521, 3, 'https://www.viafunds.com', 'LP / fund-of-funds investor in VC funds (no fund-of-funds type; PE is the closest)'),
  (5522, 2, 'https://www.roseparkadvisors.com', 'Growth equity investor by name and website'),
  (5523, 3, 'https://www.crosstimbers.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5525, 3, 'https://www.424capital.com/', 'Private equity / buyout or private-markets manager by name and website'),
  (5527, 1, 'https://www.deepwatermgmt.com', 'Venture capital firm by name, website and venture deal record'),
  (5528, 3, 'https://waveep.com/', 'Private equity / buyout or private-markets manager by name and website'),
  (5529, 1, 'https://ionpacific.com', 'Venture investor by name; site blocked; merchant bank/VC'),
  (5530, 4, 'https://ahoycap.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5531, 2, 'https://www.thekfund.com/', 'Growth equity investor by name and website'),
  (5532, 1, 'https://euph.com', 'Venture capital firm by name, website and venture deal record'),
  (5533, 3, 'https://broadoak.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5534, 4, 'https://boardmanbay.com', 'Hedge fund / crossover or public-markets manager'),
  (5535, 1, 'https://selbylane.com', 'Venture investor by name; site unclear'),
  (5536, 1, 'https://blueopalcapital.com', 'Venture investor by name; site unclear'),
  (5541, 4, 'https://vanterra.com', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5542, 1, 'https://closedloopcapital.com/', 'Venture capital firm by name, website and venture deal record'),
  (5543, 1, 'https://worthventure.com', 'Venture investor by name; site unclear'),
  (5545, 1, 'https://northisland.ventures/', 'Venture capital firm by name, website and venture deal record'),
  (5546, 1, 'https://www.groundforcecapital.com/', 'Venture capital firm by name, website and venture deal record'),
  (5547, 1, 'https://republiccapital.co', 'Venture capital firm by name, website and venture deal record'),
  (5548, 1, 'https://www.autiluspartners.com', 'Venture investor by name; site unclear'),
  (5549, 3, 'https://fifthpartners.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5551, 3, 'https://sunmountaincapital.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5552, 1, 'https://sjfventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5553, 3, 'https://camdenpartners.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5554, 1, 'https://www.hcgfunds.com/', 'Venture investor by name; site unclear'),
  (5555, 1, 'https://vedantacapital.com', 'Venture investor by name; site blocked'),
  (5558, 1, 'https://spero.vc', 'Venture capital firm by name, website and venture deal record'),
  (5563, 1, 'https://www.optimist.vc', 'Venture capital firm by name, website and venture deal record'),
  (5564, 1, 'https://levelvc.com', 'Venture capital firm by name, website and venture deal record'),
  (5567, 3, 'https://fepfund.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5568, 1, 'https://www.siddhicapital.co/', 'Venture capital firm by name, website and venture deal record'),
  (5570, 1, 'https://searchfundaccelerator.com', 'Venture capital firm by name, website and venture deal record'),
  (5573, 3, 'https://sgofund.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5577, 1, 'https://www.camponeventures.com/', 'Venture capital firm by name, website and venture deal record'),
  (5578, 3, 'https://www.newvintagepartners.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5583, 4, 'https://lasolascap.com/', 'Public-equity / multi-strategy or wealth manager per website (low confidence)'),
  (5585, 1, 'https://coastalinvestmentco.com', 'Venture investor by name; site unclear'),
  (5586, 1, 'https://www.accion.org/how-we-work/investment-strategies/accion-impact-management', 'Venture capital firm by name, website and venture deal record'),
  (5587, 1, 'https://room40.xyz', 'Venture capital firm by name, website and venture deal record'),
  (5588, 1, 'https://3spokecapital.com/', 'Venture capital firm by name, website and venture deal record'),
  (5591, 3, 'https://www.bcmexico.com', 'Private equity / multi-strategy private capital or holding company (site and name)'),
  (5592, 1, 'https://unless.co', 'Venture capital firm by name, website and venture deal record'),
  (5596, 1, 'https://www.propelbio.com', 'Venture capital firm by name, website and venture deal record'),
  (5598, 3, 'https://www.rivoniaroad.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5602, 1, 'https://strobe.fund', 'Venture capital firm by name, website and venture deal record'),
  (5606, 1, 'https://gvpclimate.com', 'Venture capital firm by name, website and venture deal record'),
  (5608, 1, '', 'Venture investor by name; no website on file'),
  (5611, 1, 'https://primevp.in/', 'Venture capital firm by name, website and venture deal record'),
  (5799, 5, 'https://aliad.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5800, 1, 'https://alven.co', 'Venture capital firm by name, website and venture deal record'),
  (5801, 10, 'https://angelinvest.ventures', 'Angel network / angel club fund'),
  (5802, 1, 'https://antifund.com', 'Venture capital firm by name, website and venture deal record'),
  (5803, 1, 'https://asterisk.vc', 'Venture capital firm by name, website and venture deal record'),
  (5804, 1, 'https://av8.vc', 'Venture capital firm by name, website and venture deal record'),
  (5805, 4, 'https://avorocapital.com', 'Hedge fund / crossover or public-markets manager'),
  (5806, 1, 'https://ce-ventures.com', 'Venture investor by name; site gave no text'),
  (5808, 5, 'https://www.coinbase.com/ventures', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5809, 1, 'https://colam-impact.com', 'Venture capital firm by name, website and venture deal record'),
  (5810, 4, 'https://deerfield.com', 'Hedge fund / crossover or public-markets manager'),
  (5811, 2, 'https://dst-global.com', 'Growth equity investor by name and website'),
  (5812, 5, 'https://edbi.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5813, 1, 'https://www.ejfventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5814, 1, 'https://evidenced.vc', 'Venture capital firm by name, website and venture deal record'),
  (5815, 1, 'https://feldventures.com', 'Venture capital firm by name, website and venture deal record'),
  (5816, 1, 'https://finality.capital', 'Venture capital firm by name, website and venture deal record'),
  (5817, 1, 'https://fndr.vc', 'Venture capital firm by name, website and venture deal record'),
  (5818, 5, 'https://www.galaxy.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5820, 1, 'https://www.hcvc.co', 'Venture capital firm by name, website and venture deal record'),
  (5821, 1, 'https://www.htgf.de', 'Venture capital firm by name, website and venture deal record'),
  (5822, 2, 'https://www.iconiq.com', 'Growth equity investor by name and website'),
  (5823, 5, 'https://www.intelcapital.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5824, 2, 'https://www.intrepidgp.com', 'Growth equity investor by name and website'),
  (5825, 1, 'https://j17.vc', 'Venture capital firm by name, website and venture deal record'),
  (5826, 4, 'https://www.janushenderson.com', 'Hedge fund / crossover or public-markets manager'),
  (5828, 3, 'https://www.kkr.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5829, 1, 'https://lowercarbon.com', 'Venture capital firm by name, website and venture deal record'),
  (5831, 1, 'https://manresa.vc', 'Venture capital firm by name, website and venture deal record'),
  (5833, 5, 'https://www.mckessonventures.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5836, 1, 'https://www.mourocapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5837, 5, 'https://munichreventures.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5839, 1, 'https://neuron.vc', 'Venture capital firm by name, website and venture deal record'),
  (5840, 1, 'https://nextladderventures.org', 'Venture capital firm by name, website and venture deal record'),
  (5841, 1, 'https://www.norrsken.vc', 'Venture capital firm by name, website and venture deal record'),
  (5842, 1, 'https://orionindustrialventures.com', 'Venture investor by name; site gave no text'),
  (5844, 1, 'https://www.parable.vc', 'Venture capital firm by name, website and venture deal record'),
  (5845, 1, 'https://www.peakxv.com', 'Venture capital firm by name, website and venture deal record'),
  (5846, 1, 'https://www.pivotal.com', 'Venture investor by name; Pivotal is a Melinda French Gates philanthropic/investment group'),
  (5848, 5, 'https://www.prosperity7vc.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5849, 4, 'https://qube-rt.com', 'Hedge fund / crossover or public-markets manager'),
  (5850, 5, 'https://www.sanofiventures.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5851, 1, 'https://satstreet.com', 'Venture capital firm by name, website and venture deal record'),
  (5853, 9, 'https://universitygrowth.com', 'University (or university research institute) investment fund/company'),
  (5854, 5, 'https://enterprises.upmc.com', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5855, 1, 'https://veteranventures.us', 'Venture capital firm by name, website and venture deal record'),
  (5856, 3, 'https://vistaequitypartners.com', 'Private equity / buyout or private-markets manager by name and website'),
  (5858, 1, 'https://zkv.xyz', 'Venture capital firm by name, website and venture deal record'),
  (5874, 5, 'https://www.are.com/venture-investments.html', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5875, 1, 'https://ascentcapital.ai', 'Venture capital firm by name, website and venture deal record'),
  (5876, 9, 'https://www.buffgoldventures.com', 'University (or university research institute) investment fund/company'),
  (5877, 5, 'https://www.chevron.com/what-we-do/technology-and-innovation/technology-ventures', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5878, 1, 'https://www.formationvc.com', 'Venture capital firm by name, website and venture deal record'),
  (5879, 1, 'https://www.humanelementvc.com', 'Venture capital firm by name, website and venture deal record'),
  (5880, 5, 'https://www.intuit.com/ventures/', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5881, 5, 'https://www.labcorp.com/venture-fund', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5882, 5, 'https://www.lockheedmartin.com/en-us/who-we-are/lockheed-martin-ventures.html', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5883, 1, 'https://vc.miraeassetcapital.com', 'Venture capital firm by name, website and venture deal record'),
  (5884, 1, 'https://www.lifesci.miraeasset.com', 'Venture capital firm by name, website and venture deal record'),
  (5885, 1, 'https://momentumpartners.no', 'Venture investor by name; site unclear'),
  (5886, 5, 'https://www.nvidia.com/en-us/startups/nventures/', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5887, 5, 'https://www.obos.no/samfunnsansvar/obos-ventures', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned'),
  (5888, 5, 'https://www.shell.com/what-we-do/technology-and-innovation/innovate-with-shell/shell-ventures.html', 'Venture arm of a company (or bank/securities group); investor page on parent site or parent-owned')
  ) c(firm_id, firm_type_id, url, reason)
  join public.v2_firms f on f.firm_id = c.firm_id
 where not exists (select 1 from public.v2_firm_types_firms t where t.firm_id = c.firm_id)
on conflict (firm_id, firm_type_id) do nothing;

-- 5. Hand-out paths skip held firms. Signatures and all other behaviour unchanged.
CREATE OR REPLACE FUNCTION public.v2_next_firm(p_key_id uuid, p_job text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
declare
  bk public.v2_bot_keys;
  v_job text := coalesce(public.v2_work_current_job(), p_job);
  fn text := public.v2_work_job_fn(v_job);
  c public.v2_work_claims;
  r record;
  held boolean := true;
  n_held int;
  v_held jsonb;
  v_info jsonb;
  frm public.v2_firms;
  v_extra jsonb := '{}'::jsonb;
begin
  bk := public.v2_work_bot(p_key_id);
  if bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', format('Key frozen: %s, %s',
      coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;
  if fn is null then
    return jsonb_build_object('ok', false, 'bot_id', bk.bot_name, 'error', 'unknown job');
  end if;
  if p_job is not null and p_job <> v_job then
    v_extra := jsonb_build_object('asked_job', p_job);
  end if;

  -- One call per key at a time, so parallel helpers of one bot never go past 10.
  perform pg_advisory_xact_lock(hashtext('v2_work_keys:' || v_job), bk.bot_key_id::int);

  -- A bot may hold up to 10 live claims for this job. At 10 it gets its oldest one back.
  select count(*) into n_held from public.v2_work_claims w
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if n_held >= 10 then
    select * into c from public.v2_work_claims w
     where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now()
     order by w.claimed_at, w.firm_id limit 1;
  else
    held := false;
    for r in execute format(
      'select g.firm_id from public.%I(null) g
         join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
        where (case when $1 = ''deal_gaps'' then public.v2_work_hq_known(f.hq_country) else true end)
          and not public.v2_firm_research_held(g.firm_id)
          and not exists (select 1 from public.v2_work_claims w
                           where w.job = $1 and w.firm_id = g.firm_id
                             and (w.done_at is not null or w.expires_at > now()))
        order by g.sort_key desc, g.firm_id
        limit 50', fn) using v_job
    loop
      -- Skip a firm another bot is claiming right now (no waiting).
      continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
      insert into public.v2_work_claims as w (job, firm_id, bot_key_id, claimed_at, expires_at, done_at)
      values (v_job, r.firm_id, bk.bot_key_id, now(), now() + interval '2 hours', null)
      on conflict (job, firm_id) do update
         set bot_key_id = excluded.bot_key_id, claimed_at = excluded.claimed_at, expires_at = excluded.expires_at
       where w.done_at is null and w.expires_at <= now()
      returning * into c;
      exit when found;
    end loop;

    -- deal_gaps only: reopen a done-but-still-gappy firm someone else finished.
    if c.firm_id is null and v_job = 'deal_gaps' then
      for r in execute format(
        'select g.firm_id from public.%I(null) g
           join public.v2_firms f on f.firm_id = g.firm_id and not coalesce(f.archived, false)
           join public.v2_work_claims w on w.job = $1 and w.firm_id = g.firm_id
          where public.v2_work_hq_known(f.hq_country)
            and not public.v2_firm_research_held(g.firm_id)
            and w.done_at is not null
            and w.bot_key_id is distinct from $2
          order by (g.sort_key - coalesce((g.info->>''dated_or_staged'')::bigint, 0)) desc, g.firm_id
          limit 50', fn) using v_job, bk.bot_key_id
      loop
        continue when not pg_try_advisory_xact_lock(hashtext('v2_work_claims:' || v_job), r.firm_id::int);
        update public.v2_work_claims as w
           set bot_key_id = bk.bot_key_id, claimed_at = now(), expires_at = now() + interval '2 hours', done_at = null
         where w.job = v_job and w.firm_id = r.firm_id
           and w.done_at is not null
           and w.bot_key_id is distinct from bk.bot_key_id
        returning * into c;
        exit when found;
      end loop;
    end if;
  end if;

  -- The key's live claims for this job after this call.
  select coalesce(jsonb_agg(w.firm_id order by w.claimed_at, w.firm_id), '[]'::jsonb) into v_held
    from public.v2_work_claims w
   where w.job = v_job and w.bot_key_id = bk.bot_key_id and w.done_at is null and w.expires_at > now();

  if c.firm_id is null then
    return jsonb_build_object('ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'firm', null,
      'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held)) || v_extra;
  end if;

  execute format('select info from public.%I($1)', fn) into v_info using c.firm_id;
  select * into frm from public.v2_firms where firm_id = c.firm_id;
  return jsonb_build_object(
    'ok', true, 'bot_id', bk.bot_name, 'job', v_job, 'held', held,
    'claimed_at', c.claimed_at, 'expires_at', c.expires_at,
    'held_firm_ids', v_held, 'held_count', jsonb_array_length(v_held),
    'firm', jsonb_build_object('firm_id', frm.firm_id, 'name', frm.display_name, 'slug', frm.slug, 'website', frm.website_url)
            || coalesce(v_info, '{}'::jsonb)) || v_extra;
end
$function$;

CREATE OR REPLACE FUNCTION public.v2_section_claim(p_key_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
declare
  v_ik bots.ingest_keys;
  v_bk public.v2_bot_keys;
  v_bot text;
  v_section text;
  v_fid bigint;
  v_got bigint;
  v_frm public.v2_firms;
  v_skip bigint[] := '{}';
  v_try int;
  v_hold_limit int := 10;
  v_held_ids bigint[] := '{}';
begin
  v_section := lower(btrim(coalesce(p_section, '')));
  if v_section not in ('legal', 'reviews', 'youtube') then
    return jsonb_build_object('ok', false, 'error', 'section must be legal, reviews, or youtube');
  end if;

  select * into v_ik from bots.ingest_keys where id = p_key_id and active;
  if not found or v_ik.bot_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  v_bot := v_ik.bot_id;
  -- Read the existing v2_bot_keys row. Do not rewrite it. Insert only when this bot has none yet.
  select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  if not found then
    insert into public.v2_bot_keys (bot_name, key_hash)
    values (v_bot, v_ik.key_hash)
    on conflict (bot_name) do nothing;
    select * into v_bk from public.v2_bot_keys where bot_name = v_bot;
  end if;
  if v_bk.bot_key_id is null then
    return jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  end if;
  if v_bk.frozen then
    return jsonb_build_object('ok', false, 'bot_id', v_bot, 'error', format('Key frozen: %s, %s', coalesce(v_bk.freeze_reason, 'no reason'), to_char(v_bk.freeze_date at time zone 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  end if;

  -- Lock this key's open holds in this section so two claims cannot pass the limit together.
  -- FOR UPDATE cannot be combined with array_agg, so the lock is a separate statement.
  perform 1
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours'
   for update of h;
  select coalesce(array_agg(h.firm_id order by h.claimed_at, h.firm_id), '{}'::bigint[])
    into v_held_ids
    from public.v2_section_holds h
   where h.section = v_section
     and h.bot_key_id = v_bk.bot_key_id
     and h.checked_at is null
     and h.claimed_at > now() - interval '6 hours';
  if cardinality(v_held_ids) >= v_hold_limit then
    return jsonb_build_object(
      'ok', false,
      'bot_id', v_bot,
      'section', v_section,
      'error', format(
        'hold_limit: finish or mark done one of your %s firms first; held_firm_ids: %s',
        v_hold_limit,
        array_to_string(v_held_ids, ', ')),
      'held_firm_ids', to_jsonb(v_held_ids));
  end if;

  for v_try in 1..32 loop
    v_fid := null;
    select f.firm_id into v_fid
      from public.firm_summary s
      join public.v2_firms f on f.firm_id = s.firm_id
     where s.listed
       and s.firm_status = 'Active'
       and not coalesce(f.archived, false)
       and not (f.firm_id = any (v_skip))
       and not public.v2_firm_research_held(f.firm_id)
       and case v_section
             when 'legal' then not exists (
               select 1 from public.v2_legal_items li
                where li.firm_id = f.firm_id and li.is_current and not li.archived)
             when 'reviews' then not exists (
               select 1 from public.v2_reviews r
                where r.firm_id = f.firm_id and r.is_current and not r.archived)
             else not exists (
               select 1 from public.v2_interviews iv
                where iv.firm_id = f.firm_id and iv.is_current and not iv.archived)
           end
       and not exists (
             select 1 from public.v2_section_holds h
              where h.firm_id = f.firm_id
                and h.section = v_section
                and (h.checked_at is not null or h.claimed_at > now() - interval '6 hours'))
     order by s.deals desc, s.firm_id
     limit 1
     for update of f skip locked;
    if v_fid is null then
      return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
    end if;

    v_got := null;
    insert into public.v2_section_holds (firm_id, section, bot_key_id, claimed_at)
    values (v_fid, v_section, v_bk.bot_key_id, now())
    on conflict (firm_id, section) do update
      set bot_key_id = excluded.bot_key_id,
          claimed_at = excluded.claimed_at
      where v2_section_holds.checked_at is null
        and v2_section_holds.claimed_at <= now() - interval '6 hours'
    returning firm_id into v_got;
    if found then
      exit;
    end if;
    v_skip := v_skip || v_fid;
  end loop;

  if v_got is null then
    return jsonb_build_object('ok', true, 'bot_id', v_bot, 'section', v_section, 'none_left', true);
  end if;
  select * into v_frm from public.v2_firms where firm_id = v_got;
  return jsonb_build_object(
    'ok', true, 'bot_id', v_bot, 'section', v_section,
    'firm_id', v_frm.firm_id, 'slug', v_frm.slug, 'name', v_frm.display_name, 'website', v_frm.website_url);
end
$function$;

CREATE OR REPLACE FUNCTION public.v2_research_claim(p_key_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'bots'
 SET statement_timeout TO '30s'
 SET lock_timeout TO '5s'
AS $function$
DECLARE
  ik bots.ingest_keys;
  bk public.v2_bot_keys;
  bot text;
  fid bigint;
  frm public.v2_firms;
BEGIN
  SELECT * INTO ik FROM bots.ingest_keys WHERE id = p_key_id AND active;
  IF NOT FOUND OR ik.bot_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'this key is not linked to a bot');
  END IF;
  bot := ik.bot_id;
  SELECT * INTO bk FROM public.v2_bot_keys WHERE bot_name = bot;
  IF NOT FOUND OR bk.key_hash IS DISTINCT FROM ik.key_hash THEN
  INSERT INTO public.v2_bot_keys (bot_name, key_hash) VALUES (bot, ik.key_hash)
    ON CONFLICT (bot_name) DO UPDATE SET key_hash = EXCLUDED.key_hash RETURNING * INTO bk;
  END IF;
  IF bk.frozen THEN
    RETURN jsonb_build_object('ok', false, 'bot_id', bot, 'error', format('Key frozen: %s, %s', coalesce(bk.freeze_reason, 'no reason'), to_char(bk.freeze_date AT TIME ZONE 'America/Los_Angeles', 'YYYY-MM-DD HH24:MI "PT"')));
  END IF;

  fid := null;
  WITH picked AS (
    SELECT q.firm_id
      FROM public.v2_research_assignments q
      JOIN public.v2_firms f ON f.firm_id = q.firm_id
     WHERE q.done_at IS NULL
       AND NOT coalesce(f.archived, false)
       AND NOT public.v2_firm_research_held(q.firm_id)
       AND (
         q.claimed_by IS NULL
         OR coalesce(q.expires_at, q.claimed_at + interval '6 hours') <= now()
       )
     ORDER BY CASE q.priority WHEN 'top' THEN 0 ELSE 1 END, q.firm_id
     FOR UPDATE OF q SKIP LOCKED
     LIMIT 1
  )
  UPDATE public.v2_research_assignments a
     SET claimed_by = bot,
         claimed_at = now(),
         expires_at = now() + interval '6 hours'
    FROM picked
   WHERE a.firm_id = picked.firm_id
  RETURNING a.firm_id INTO fid;

  IF fid IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'bot_id', bot, 'none_left', true);
  END IF;

  SELECT * INTO frm FROM public.v2_firms WHERE firm_id = fid;
  RETURN jsonb_build_object(
    'ok', true,
    'bot_id', bot,
    'firm_id', frm.firm_id,
    'slug', frm.slug,
    'name', frm.display_name,
    'website', frm.website_url);
END
$function$;
$holdci$;
end
$mig$;
