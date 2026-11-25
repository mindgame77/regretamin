-- Deal rows that name no round (founder, 24 Nov: "lets do 100 of those 683"). 92 of the first 100: the startup has
-- a known round with the same amount at about the same time, so the row is given that round's name and the database's
-- own trigger files it under that round. A cheaper model judged each row; only the ones it was sure of and that pass
-- the rule checks are applied. A row keeps its own date when it has a full one; otherwise it takes the round's date.
-- Old values are kept in v2_round_dedupe_20261124. Four accepted rows are archived and are left alone.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_round_dedupe_20261124') is null then
    raise notice 'v2_deals or the backup table not present, skipping';
    return;
  end if;
  create temp table _fix(deal_id bigint primary key, event_id bigint) on commit drop;
  insert into _fix values
(4864,4178),(3431,82),(4863,4657),(3374,10207),(4861,10207),(3932,1324),(3680,4003),(214665,23161),(3373,4653),(3919,8715),(3372,3995),(3378,6301),
(4734,3454),(3042,10307),(3437,9246),(3445,2730),(4007,10307),(4417,9246),(4890,9246),(12954,9670),(19166,10307),(22180,9199),(312575,14075),(3425,13311),
(219472,12850),(3404,3351),(4005,13705),(4006,7064),(4959,3351),(3679,9249),(12964,9249),(3392,8606),(4373,9120),(11035,9120),(267716,9120),(3377,4656),
(4867,4659),(4907,10202),(133478,10815),(291486,4658),(3643,9876),(91,4005),(474,4005),(263837,11058),(3388,9735),(128871,2431),(3371,10206),(13510,11791),
(67624,15172),(65718,6407),(3057,5118),(3381,10159),(6975,6829),(12976,5763),(19164,6392),(360696,5763),(66101,8469),(127559,9636),(3660,2560),(4376,4284),
(4895,11169),(4948,10741),(14274,11169),(346505,11169),(3406,10162),(4166,3574),(3041,5237),(3393,9253),(3420,12060),(3918,9873),(4388,9337),(4958,5747),
(3391,10205),(3450,2566),(3709,2566),(3703,6627),(10980,13205),(3418,10051),(3016,9831),(3901,2888),(4363,4426),(29734,10623),(137246,21809),(9504,5212),
(3963,8567),(472,9875),(3029,10294),(3642,9875),(4820,3300),(4982,7062),(130057,9135),(14163,11097);

  insert into public.v2_round_dedupe_20261124 (deal_id, old_round, old_deal_date, old_precision, old_event_id, new_round, new_deal_date, new_precision, note)
  select d.deal_id, d.round, d.deal_date, d.deal_date_precision, d.event_id, e.round,
         case when d.deal_date_precision = 'full date' or e.event_date is null then d.deal_date else e.event_date end,
         case when d.deal_date_precision = 'full date' or e.event_date is null then d.deal_date_precision else e.event_date_precision end,
         'row with no round name, filed under its round (round record ' || e.event_id || '); judged by a cheaper model, checked by rule'
  from _fix f join public.v2_deals d using (deal_id) join public.v2_events e on e.event_id = f.event_id
  where d.is_current and not d.archived and not coalesce(d.nothing_found, false)
    and (d.round is null or btrim(d.round) = '') and d.event_id is null
    and e.kind = 'round' and e.startup_id = d.startup_id and e.round is not null
  on conflict (deal_id) do nothing;

  update public.v2_deals d set round = b.new_round, deal_date = b.new_deal_date, deal_date_precision = b.new_precision
  from _fix f join public.v2_round_dedupe_20261124 b using (deal_id)
  where d.deal_id = f.deal_id and b.note like 'row with no round name, filed under its round (round record ' || f.event_id || ')%';
end $wrapci$;
