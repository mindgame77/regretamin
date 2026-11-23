-- v2_top_firms_external_time_2026 (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_top_firms_external_time_2026 skipped';
    return;
  end if;
  execute $designmig$
create table if not exists public.v2_top_firms_external (
  list_year int not null,
  source text not null,
  rank int not null,
  firm_name text not null,
  domain text,
  firm_id bigint,
  primary key (list_year, source, rank)
);
comment on table public.v2_top_firms_external is 'Outside rankings used for Regretamin Top Firms, kept as published. 2026: top 100 of TIME / Statista America''s Top Venture Capital Firms 2026. See docs/top-firms.md.';
alter table public.v2_top_firms_external enable row level security;
revoke all on public.v2_top_firms_external from anon, authenticated;
insert into public.v2_top_firms_external (list_year, source, rank, firm_name, domain)
select 2026, 'TIME', rk, name, dom from (values (1,'Sequoia Capital','sequoiacap.com'),(2,'Andreessen Horowitz','a16z.com'),(3,'Lightspeed','lsvp.com'),(4,'General Catalyst','generalcatalyst.com'),(5,'Accel','accel.com'),(6,'Insight Partners','insightpartners.com'),(7,'Bain Capital Ventures','baincapitalventures.com'),(8,'Khosla Ventures','khoslaventures.com'),(9,'Bessemer Venture Partners','bvp.com'),(10,'Lux Capital','luxcapital.com'),(11,'Battery','battery.com'),(12,'OrbiMed Advisors','orbimed.com'),(13,'Founders Fund','foundersfund.com'),(14,'Kleiner Perkins','kleinerperkins.com'),(15,'Tiger Global Management','tigerglobal.com'),(16,'Menlo Ventures','menlovc.com'),(17,'8VC','8vc.com'),(18,'Thrive Capital','thrivecap.com'),(19,'Data Collective (DCVC)','dcvc.com'),(20,'CRV','crv.com'),(21,'Greylock','greylock.com'),(22,'Redpoint Ventures','redpoint.com'),(23,'Felicis','felicis.com'),(24,'Madrona','madrona.com'),(25,'Foundation Capital','foundationcapital.com'),(26,'F-Prime Capital','fprimecapital.com'),(27,'Greenoaks','greenoaks.com'),(28,'Oak HC/FT','oakhcft.com'),(29,'First Round','firstround.com'),(30,'New Enterprise Associates (NEA)','nea.com'),(31,'Eclipse','eclipse.capital'),(32,'SOSV','sosv.com'),(33,'Ribbit Capital','ribbitcap.com'),(34,'Altimeter Capital','altimeter.com'),(35,'Initialized Capital','initialized.com'),(36,'True Ventures','trueventures.com'),(37,'Nexus Venture Partners','nexusvp.com'),(38,'Benchmark','benchmark.com'),(39,'Uncork Capital','uncorkcapital.com'),(40,'Greycroft','greycroft.com'),(41,'Costanoa Ventures','costanoa.vc'),(42,'Flagship Pioneering','flagshippioneering.com'),(43,'Emergence Capital','emcap.com'),(44,'Alumni Ventures','av.vc'),(45,'Sands Capital Alternatives','sandscapital.com'),(46,'RA Capital Management','racap.com'),(47,'Forerunner','forerunnerventures.com'),(48,'Frazier Life Sciences','frazierls.com'),(49,'Amplify Partners','amplifypartners.com'),(50,'Plug and Play','plugandplaytechcenter.com'),(51,'Primary Venture Partners','primary.vc'),(52,'SV Angel','svangel.com'),(53,'Techstars','techstars.com'),(54,'Base10','base10.vc'),(55,'FJ Labs','fjlabs.com'),(56,'Pelion Venture Partners','pelionvp.com'),(57,'Upfront Ventures','upfront.com'),(58,'BoxGroup','boxgroup.com'),(59,'Gradient','gradient.com'),(60,'Lerer Hippeau','lererhippeau.com'),(61,'Vivo Capital','vivocapital.com'),(62,'Drive','drivecapital.com'),(63,'Foresite Capital','foresitecapital.com'),(64,'Index Ventures','indexventures.com'),(65,'Crosslink Capital','crosslinkcapital.com'),(66,'Goodwater','goodwatercap.com'),(67,'Energy Impact Partners','energyimpactpartners.com'),(68,'Playground Ventures','playground.vc'),(69,'Gaingels','gaingels.com'),(70,'NFX','nfx.com'),(71,'defy','defy.vc'),(72,'Catalio Capital Management','cataliocapital.com'),(73,'Spark Capital','sparkcapital.com'),(74,'Tribe Capital','tribecap.co'),(75,'Deerfield','deerfield.com'),(76,'Pear VC','pear.vc'),(77,'Draper Associates','draper.vc'),(78,'Trinity Ventures','trinityventures.com'),(79,'Paradigm','paradigm.xyz'),(80,'Atlas Venture','atlasventure.com'),(81,'Norwest','norwest.com'),(82,'Coatue Management','coatue.com'),(83,'Pantera Capital','panteracapital.com'),(84,'Liquid 2','liquid2.vc'),(85,'Fifth Wall','fifthwall.com'),(86,'Altos Ventures','altos.vc'),(87,'S2G Investments','s2ginvestments.com'),(88,'Obvious Ventures','obvious.com'),(89,'WNDR','wndr.vc'),(90,'Maverick Ventures','maverickcapital.com'),(91,'Slow Ventures','slow.co'),(92,'Omega Funds','omegafunds.com'),(93,'The Column Group','thecolumngroup.com'),(94,'S3 Ventures','s3vc.com'),(95,'ARCH Venture Partners','archventure.com'),(96,'Breakthrough Energy Ventures','breakthroughenergy.org'),(97,'Longitude Capital','longitudecapital.com'),(98,'TTV Capital','ttvcapital.com'),(99,'Notable Capital','notablecap.com'),(100,'SR One','srone.com')) v(rk,name,dom)
on conflict do nothing;
$designmig$;
end
$wrapci$;
