-- One round stored as two, second pass (founder, 24 Nov: "yes" to a web check of the cases the model was unsure of).
-- 29 of 66 cases: same startup, same amount, two round records a few days apart under two different names. A cheaper
-- model searched the web for each; a case is applied only when it found a source naming the round, the name is one
-- of the two on record and the date matches a recorded date. Every deal row of both records gets that one name and
-- date, so the database's own trigger files them under one round. Old values are kept in v2_round_dedupe_20261124;
-- the source found is in the note.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_round_dedupe_20261124') is null then
    raise notice 'v2_deals or the backup table not present, skipping';
    return;
  end if;
  create temp table _fix(pid int, ea bigint, eb bigint, new_round text, new_date date, src text) on commit drop;
  insert into _fix values
(75,18633,20508,'Series A','2026-06-30','https://pulse2.com/taxwire-raises-25-million-series-a-to-scale-indirect-tax-compliance-platform/'),
(83,15883,21399,'Series A','2021-03-03','https://startupintros.com/news/bionaut-labs-series-a-2021-03'),
(98,28017,29511,'Series A','2026-07-06','https://bebeez.eu/2026/07/06/curifylabs-raises-14m-series-a-to-power-the-future-of-personalized-medicine/'),
(107,19325,21742,'Seed','2026-05-12','https://thequantuminsider.com/2026/05/12/casimir-launches-with-12-million-oversubscribed-seed-round-to-bring-quantum-energy-chip-to-market/'),
(121,7304,10629,'Seed','2025-10-28','https://www.artificiallawyer.com/2025/10/28/vesence-bags-9m-seed-for-contract-review-agents/'),
(127,18157,20769,'Pre-seed','2024-08-22','https://www.theblock.co/post/312646/bitcoin-restaking-platform-satlayer-funding'),
(134,5021,15283,'Pre-seed','2026-09-30','https://wowtale.net/2026/10/01/265595/'),
(142,38938,40594,'Seed','2026-06-09','https://www.trysignalbase.com/news/funding/algebra-ai-raises-7m-seed-round'),
(152,27844,31844,'Seed','2025-09-23','https://seedtable.com/companies/wexler/funding-rounds/seed-2025-09'),
(155,5300,9480,'Seed','2022-10-11','https://startupintros.com/news/fidu-seed-2022-10'),
(160,27712,29599,'Pre-seed','2023-01-23','https://thequantuminsider.com/2023/01/23/welinq-closes-e5-million-pre-seed-round/'),
(170,16229,18128,'Seed','2022-03-02','https://www.artificiallawyer.com/2022/03/01/common-paper-the-contracts-as-apis-startup-bags-4-5m-seed-funding/'),
(172,22191,22429,'Seed','2024-09-24','https://seedtable.com/companies/sandgarden/funding-rounds/seed-2024-09'),
(180,16799,20380,'Pre-seed','2025-03-26','https://founderlodge.com/round/ConfigHub-Inc-raises-4000000-Pre-Seed-2025-03-27-Alexis-Richardson-MjIyOTU'),
(181,19147,21576,'Pre-seed','2023-04-05','https://startupintros.com/news/2023-04-05-flyby-robotics-pre-seed'),
(182,19243,23448,'Pre-seed','2023-06-27','https://www.law.com/legaltechnews/2023/06/27/patented-ai-launches-free-personal-access-to-llm-shield-amid-4m-in-pre-seed-funding-from-cooley-llp-others/'),
(184,27621,27873,'Seed','2026-11-11','https://tech.eu/2026/11/11/cherry-ventures-backs-tano-with-4m-to-challenge-the-traditional-influencer-agency-model/'),
(188,11290,11477,'Seed','2024-05-09','https://startupintros.com/news/2024-05-09-mnzl-seed'),
(209,26968,30126,'Seed','2024-10-15','https://www.vcaonline.com/news/2024101512/platformr-secures-2-5m-seed-round-to-power-growth-aws-cloudops-innovation/'),
(210,37766,37782,'Pre-seed','2026-06-30','https://femtechinsider.com/mila-raises-2-5m-pre-seed-to-build-design-led-intimate-wellness-brand/'),
(216,331,29553,'Pre-seed','2024-02-21','https://startupintros.com/news/samphire-neuroscience-pre-seed-2024-02-21'),
(235,28359,29310,'Pre-seed','2026-03-12','https://tech.eu/2026/03/12/neuramancer-lands-eur17m-pre-seed-to-scale-deepfake-detection-tools/'),
(236,39905,39964,'Pre-seed','2025-06-03','https://startupintros.com/news/2025-06-05-finnecto-pre-seed'),
(237,40770,42978,'Series A','2022-01-10','https://e27.co/wootag-raises-us1-7m-cornerstone-venture-wavemaker-20220110/'),
(239,607,27290,'Pre-seed','2025-01-15','https://tech.eu/2025/01/15/ukrainian-founded-disinformation-startup-raises-1-6m-pre-seed/'),
(243,57511,58236,'Pre-seed','2023-05-03','https://startupintros.com/news/holocron-technologies-pre-seed-2023-05-02'),
(245,40388,41759,'Pre-seed','2022-01-17','https://techcrunch.com/2022/01/17/rebundle-raises-1-4m-for-plant-based-hair-extensions/amp/'),
(249,29597,32013,'Pre-seed','2023-09-29','https://tech.eu/2023/09/29/pandasai-raises-11m-in-pre-seed-round-for-ai-powered-data-analysis/'),
(252,40581,45029,'Pre-seed','2022-11-22','https://www.manufacturingtomorrow.com/news/2022/11/22/rosotics-raises-750000-pre-seed-round-led-by-draper-associates-for-novel-approach-to-heavy-industry-3d-printing/19723');

  create temp table _rows on commit drop as
    select d.deal_id, f.pid, f.new_round, f.new_date, f.src,
      (select x.deal_date_precision from public.v2_deals x where x.is_current and x.event_id in (f.ea, f.eb) and x.deal_date = f.new_date
       order by (x.deal_date_precision = 'full date') desc limit 1) new_prec
    from _fix f join public.v2_deals d on d.event_id in (f.ea, f.eb) and d.is_current;
  delete from _rows where new_prec is null;  -- the date is not one of the recorded dates: leave that case alone
  delete from _rows r using public.v2_deals d where d.deal_id = r.deal_id and d.round is not distinct from r.new_round and d.deal_date is not distinct from r.new_date;

  insert into public.v2_round_dedupe_20261124 (deal_id, old_round, old_deal_date, old_precision, old_event_id, new_round, new_deal_date, new_precision, note)
  select d.deal_id, d.round, d.deal_date, d.deal_date_precision, d.event_id, r.new_round, r.new_date, r.new_prec,
         'one round stored as two (case ' || r.pid || '); web-checked by a cheaper model, checked by rule; source: ' || r.src
  from _rows r join public.v2_deals d using (deal_id)
  on conflict (deal_id) do nothing;

  update public.v2_deals d set round = b.new_round, deal_date = b.new_deal_date, deal_date_precision = b.new_precision
  from _rows r join public.v2_round_dedupe_20261124 b using (deal_id)
  where d.deal_id = r.deal_id and b.note like 'one round stored as two (case ' || r.pid || '); web-checked%' and b.new_round = r.new_round and b.new_deal_date = r.new_date;
end $wrapci$;
