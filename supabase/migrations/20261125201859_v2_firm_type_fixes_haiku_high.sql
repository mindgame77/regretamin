-- Firm type tags corrected after a check of all 5,732 listed firms by a cheaper model (founder, 25 Nov: "run a research by
-- Haiku ... okay, fix it"). The model flagged 86 tags; these are the 48 it was sure of ("high"), after a rule check
-- (real firm, name matches, allowed tag). Left out on purpose: the 31 it was only fairly sure of, the 4 already retagged
-- with the map rule, and 3 that would move a firm to PE or Hedge fund and so off the map (Andera Partners, Maverick
-- Capital, Yorktown Partners): those wait for the founder's word.
-- Old values are kept in v2_firm_type_retag_20261125 (undo statement in its comment); each change is one line in the
-- register v2_map_rules_log. Seven of these become Accelerator and two Incubator, so they leave the map.
do $wrapci$
declare
  r record; v_old int; v_new int;
begin
  if to_regclass('public.v2_firm_types_firms') is null or to_regclass('public.v2_firm_type_retag_20261125') is null or to_regclass('public.v2_map_rules_log') is null then
    raise notice 'type tables or the register not present, skipping';
    return;
  end if;
  comment on table public.v2_firm_type_retag_20261125 is 'Old type tags of firms retagged on 25 Nov 2026 (the founder''s seven accelerators, and the tag check by a cheaper model). Undo: update v2_firm_types_firms t set firm_type_id = b.old_firm_type_id, source_type = b.old_source_type, source_owner = b.old_source_owner, source_date = b.old_source_date from v2_firm_type_retag_20261125 b where t.row_id = b.row_id;';
  create temp table _fix(firm_id bigint, old_type text, new_type text, why text) on commit drop;
  insert into _fix values
(2632,'VC','Accelerator','Former YC China; runs cohort-based seed accelerator programmes with standard investments.'),
(1552,'VC','Accelerator','Name says ''Accelerator''; firm runs an accelerator programme.'),
(4454,'VC','Accelerator','Jordan-based startup accelerator running cohort programmes.'),
(1833,'VC','Accelerator','Name says ''Accelerator''; Temasek life sciences accelerator for biomedical startups.'),
(4975,'VC','Accelerator','Runs agtech accelerator cohorts with a fixed amount invested per startup.'),
(4976,'VC','Accelerator','LatAm arm of The Yield Lab, which runs accelerator cohorts.'),
(4992,'VC','Accelerator','Runs cohort-based accelerator programmes for bootstrapped SaaS startups.'),
(2462,'VC','Angel group','Name and domain describe a network of individual angel investors.'),
(3899,'VC','Angel group','Name says it is an angel investor network.'),
(5289,'VC','Angel group','Known LGBTQ+ angel investor network, an angel syndicate rather than a fund.'),
(2502,'VC','Angel group','Name and domain describe a network of individual angel investors.'),
(1396,'VC','Angel group','Israeli angel investment network, per Globes coverage.'),
(4837,'VC','Angel group','Name says Angels, indicating an individual angel network.'),
(687,'VC','Corporate VC','Corporate venture arm of American Family Insurance.'),
(481,'VC','Corporate VC','Website airbusventures.vc; the venture arm of aircraft maker Airbus.'),
(3530,'VC','Corporate VC','Venture arm of BMW Group, an operating car company.'),
(3630,'VC','Corporate VC','Fund launched by Circle, the operating stablecoin company, per press.'),
(3656,'VC','Corporate VC','Venture arm of Comcast, an operating telecom and media company.'),
(1131,'VC','Corporate VC','Venture arm of Deutsche Telekom, an operating telecoms company.'),
(3810,'VC','Corporate VC','Strategic investment arm of Fidelity Investments, an operating financial firm.'),
(3909,'VC','Corporate VC','Venture arm of General Electric, an operating industrial company.'),
(3199,'VC','Corporate VC','Venture arm of GREE, a Japanese operating internet company.'),
(14,'VC','Corporate VC','Google''s venture arm; named as a Corporate VC example in the definitions.'),
(502,'VC','Corporate VC','Venture arm of genomics company Illumina.'),
(307,'VC','Corporate VC','Corporate venture arm of Optum, a UnitedHealth Group business.'),
(4621,'VC','Corporate VC','Strategic venture arm of Qualcomm, an operating chip company.'),
(2542,'VC','Corporate VC','Sony Innovation Fund is the venture arm of operating company Sony.'),
(408,'VC','Corporate VC','Venture arm of Toyota, an operating car company.'),
(5601,'VC','Corporate VC','Venture arm of United Airlines, an operating company.'),
(5111,'VC','Corporate VC','Strategic venture arm of operating telecom company Verizon.'),
(5329,'VC','Growth','Its own fundraises are described as growth equity funds.'),
(699,'VC','Incubator','Describes itself as a venture studio; studios count as Incubator.'),
(4239,'VC','Incubator','Domain and programme name show a startup studio, which counts as Incubator.'),
(7136,'Accelerator','Incubator','Known semiconductor incubator; it hosts early chip startups rather than running a standard-investment cohort.'),
(3863,'VC','University fund','Name ties it to Universidad EAN, a university-run fund.'),
(2282,'VC','University fund','Run by KAUST, a university (kaust.edu.sa domain), as its innovation fund.'),
(4147,'VC','University fund','Investment arm of Keio University, a Japanese university.'),
(4172,'VC','University fund','Name shows a fund run for Kobe University.'),
(4183,'VC','University fund','Name and domain show an innovation fund tied to Kyoto University.'),
(4492,'VC','University fund','Name shows a venture fund run for Osaka University.'),
(4456,'VC','University fund','Name shows a venture capital fund run for Obuda University.'),
(1852,'VC','University fund','Alumni investment fund of École polytechnique, per university press releases.'),
(5004,'VC','University fund','Name shows a fund run for Tokyo University of Science.'),
(5005,'VC','University fund','Name shows investment management for Tokyo University of Science.'),
(5072,'VC','University fund','Name shows a fund set up by the University of Tokyo.'),
(5076,'VC','University fund','Domain lsf.uzh.ch indicates the University of Zurich life sciences fund.'),
(5063,'VC','University fund','Name shows the University of Tokyo''s innovation investment platform.'),
(5142,'VC','University fund','Fund named for and run by Waseda University.');

  for r in
    select f.*, tf.row_id, tf.source_type, tf.source_owner, tf.source_date, s.display_name, o.firm_type_id old_id, n.firm_type_id new_id
    from _fix f
    join public.v2_firm_type o on o.name = f.old_type
    join public.v2_firm_type n on n.name = f.new_type
    join public.v2_firm_types_firms tf on tf.firm_id = f.firm_id and tf.firm_type_id = o.firm_type_id and coalesce(tf.is_current, true) and not coalesce(tf.archived, false)
    join public.firm_summary s on s.firm_id = f.firm_id
    where not exists (select 1 from public.v2_firm_types_firms x where x.firm_id = f.firm_id and x.firm_type_id = n.firm_type_id)
      and not exists (select 1 from public.v2_firm_type_retag_20261125 b where b.row_id = tf.row_id)
  loop
    insert into public.v2_firm_type_retag_20261125 (row_id, firm_id, old_firm_type_id, new_firm_type_id, old_source_type, old_source_owner, old_source_date, note)
    values (r.row_id, r.firm_id, r.old_id, r.new_id, r.source_type, r.source_owner, r.source_date, 'tag check by a cheaper model, sure: high. ' || r.why);
    update public.v2_firm_types_firms
       set firm_type_id = r.new_id, source_type = 'Tag check 25 Nov 2026 (cheaper model, sure: high): ' || r.why, source_owner = 'claude-website', source_date = current_date
     where row_id = r.row_id;
    insert into public.v2_map_rules_log (what, was, now_is, why)
    values ('firm "' || r.display_name || '" type', r.old_type, r.new_type, 'tag check by a cheaper model (sure: high): ' || r.why);
  end loop;
end $wrapci$;
