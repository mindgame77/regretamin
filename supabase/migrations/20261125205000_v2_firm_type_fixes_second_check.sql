-- Firm type tags, second check (founder, 25 Nov: "just double check ... maybe a more advanced model like Opus ... when you
-- will be sure, change or leave it"). The 31 tags the cheaper model was only fairly sure of were looked up on the web by a
-- more advanced model under the founder's rule: not strict; a firm with a real venture fund stays VC. 13 came back
-- "change"; these 11 are applied (each with its evidence and source). Not applied: Mirae Asset Venture Investment (it has
-- two tags, PE and VC, which is fine) and Techu Angels (one directory page only). The other 18 stay as they are.
-- Old values in v2_firm_type_retag_20261125; one line each in the register v2_map_rules_log.
do $wrapci$
declare
  r record;
begin
  if to_regclass('public.v2_firm_types_firms') is null or to_regclass('public.v2_firm_type_retag_20261125') is null or to_regclass('public.v2_map_rules_log') is null then
    raise notice 'type tables or the register not present, skipping';
    return;
  end if;
  create temp table _fix(firm_id bigint, old_type text, new_type text, why text, src text) on commit drop;
  insert into _fix values
(4557,'VC','Corporate VC','Profile says PKSHA Capital is a subsidiary of AI company PKSHA Technology, managing an AI/robotics startup fund.','https://altss.com/profile/pksha-capital.md'),
(296,'VC','Growth','Profile: Avenir Growth Capital focuses on growth equity investments in US consumer and technology companies.','https://altss.com/profile/avenir-growth-capital.md'),
(3654,'VC','Accelerator','The Block: Solana accelerator''s $60M fund invests only in selected hackathon winners, a standard $250,000 per startup.','https://www.theblock.co/post/301795/solana-accelerator-colosseum-first-fund'),
(3357,'VC','Accelerator','Iowa State Research Park initiative described as an ag accelerator offering mentoring, prototyping and funding; not an ordinary fund.','https://globalaginvesting.com/iowa-state-launches-ag-accelerator/'),
(906,'VC','Corporate VC','Mitsui & Co. says MGI is its wholly owned venture investment subsidiary, established 2001 in California.','https://www.mitsui.com/jp/en/topics/2023/1248007_13949.html'),
(5052,'VC','University fund','Own site: ''the investment arm of University Mohammed VI Polytechnic'', created by the university, running two early-stage funds.','https://um6pventures.com/'),
(2618,'VC','University fund','SkyDeck is UC Berkeley''s official accelerator; its fund invests $100K per startup and shares 50% of profits with the university.','https://skydeck.berkeley.edu/uc-berkeley-skydeck-closes-24m-venture-capital-fund'),
(4440,'VC','University fund','National Taiwan University formed NTU Ventures to invest in startups of its alumni, students and professors.','https://globalventuring.com/corporate/asia/national-taiwan-university-launches-30m-fund-to-kickstart-local-innovation'),
(335,'VC','PE','New York private equity firm, ~$6B AUM, $100M-500M deals in energy and financial services, mainly buyouts and growth capital.','https://mergr.com/investor/pine-brook-partners'),
(5153,'VC','University fund','Research commercialisation office of Victoria University of Wellington (wgtn.ac.nz pages), creating spin-outs and licensing university research.','https://www.wgtn.ac.nz/research/partnerships/commercialisation/working-with-wellington-univentures'),
(5570,'VC','Accelerator','INSEAD: Boston programme selecting, training and mentoring searcher cohorts, with a fund backing their acquisitions; not venture.','https://knowledge.insead.edu/entrepreneurship/help-entrepreneurs-who-want-buy-business');

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
    values (r.row_id, r.firm_id, r.old_id, r.new_id, r.source_type, r.source_owner, r.source_date, 'second check by a more advanced model with web search. ' || r.why || ' Source: ' || r.src);
    update public.v2_firm_types_firms
       set firm_type_id = r.new_id, source_type = 'Tag check 25 Nov 2026 (second check, web): ' || r.why, source_url = r.src, source_owner = 'claude-website', source_date = current_date
     where row_id = r.row_id;
    insert into public.v2_map_rules_log (what, was, now_is, why)
    values ('firm "' || r.display_name || '" type', r.old_type, r.new_type, 'second check with web search: ' || r.why || ' Source: ' || r.src);
  end loop;
end $wrapci$;
