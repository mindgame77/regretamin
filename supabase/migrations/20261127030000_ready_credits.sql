-- "Am I ready to pitch?": credits (26 Nov 2026, founder: a report costs 10 credits, the full research 25; a new account gets 10 free
-- credits; "add like 50 credits to an account").
--   * credit_log: one row per charge or gift (no client access).
--   * ready_credits_ok(kind): can this signed-in user afford a report / research now? Changes nothing.
--   * ready_charge(report, kind): takes the credits once per report and kind (paid credits first, they refill monthly; then
--     free ones). Called by the server only after the report or research is made, so a failed run costs nothing.
--     At most 30 charges in 24 hours per account.
--   * grant_credits_admin(email, amount, note): adds (or, with a minus, takes) free credits. Not callable by visitors.
--   * _balance: the sign-up gift is now 10 credits (was 4). Existing accounts keep what they have.
do $wrapci$
begin
  if to_regclass('public.check_balances') is null or to_regclass('public.ready_reports') is null then
    raise notice 'tables not present, skipping';
    return;
  end if;

  execute $t$
create table if not exists public.credit_log (
  id bigint generated always as identity primary key,
  balance_id uuid not null references public.check_balances(id) on delete cascade,
  report_id uuid,
  kind text not null,
  amount integer not null,
  free_part integer not null default 0,
  paid_part integer not null default 0,
  note text,
  created_at timestamptz not null default now()
)$t$;
  execute 'create index if not exists credit_log_report on public.credit_log(report_id, kind)';
  execute 'create index if not exists credit_log_day on public.credit_log(balance_id, created_at)';
  execute 'alter table public.credit_log enable row level security';
  execute 'revoke all on public.credit_log from anon, authenticated';

  execute $fn$
create or replace function public._balance(p_anon uuid) returns public.check_balances
language plpgsql security definer set search_path to 'public' as $body$
declare b public.check_balances;
begin
  if auth.uid() is not null then
    insert into check_balances(user_id, free_left) values (auth.uid(), 0) on conflict (user_id) do nothing;
    select * into b from check_balances where user_id = auth.uid() for update;
    if not b.signup_bonus_given then
      update check_balances set free_left = free_left + 10, signup_bonus_given = true, updated_at = now() where id = b.id returning * into b;
      insert into check_events(balance_id, kind, amount) values (b.id, 'grant_signup', 10);
    end if;
  else
    if p_anon is null then raise exception 'anon id required'; end if;
    insert into check_balances(anon_id) values (p_anon) on conflict (anon_id) do nothing;
    select * into b from check_balances where anon_id = p_anon and user_id is null for update;
  end if;
  return b;
end $body$$fn$;

  execute $fn$
create or replace function public.ready_credits_ok(p_kind text) returns jsonb
language plpgsql security definer set search_path to 'public' as $body$
declare b public.check_balances; cost integer; n integer;
begin
  if auth.uid() is null then return jsonb_build_object('status', 'sign_in'); end if;
  if p_kind not in ('report', 'research') then return jsonb_build_object('status', 'bad_kind'); end if;
  cost := case p_kind when 'report' then 10 else 25 end;
  b := _balance(null);
  select count(*) into n from credit_log where balance_id = b.id and kind in ('report', 'research') and created_at > now() - interval '24 hours';
  if n >= 30 then return jsonb_build_object('status', 'limit', 'need', cost, 'left', b.free_left + b.paid_left); end if;
  if b.free_left + b.paid_left < cost then return jsonb_build_object('status', 'out', 'need', cost, 'left', b.free_left + b.paid_left); end if;
  return jsonb_build_object('status', 'ok', 'need', cost, 'left', b.free_left + b.paid_left);
end $body$$fn$;

  execute $fn$
create or replace function public.ready_charge(p_report uuid, p_kind text) returns jsonb
language plpgsql security definer set search_path to 'public' as $body$
declare uid uuid := auth.uid(); b public.check_balances; cost integer; n integer; pp integer; fp integer;
begin
  if uid is null then return jsonb_build_object('status', 'sign_in'); end if;
  if p_kind not in ('report', 'research') then return jsonb_build_object('status', 'bad_kind'); end if;
  if not exists (select 1 from ready_reports where id = p_report and user_id = uid) then return jsonb_build_object('status', 'not_found'); end if;
  cost := case p_kind when 'report' then 10 else 25 end;
  b := _balance(null);
  if exists (select 1 from credit_log where balance_id = b.id and report_id = p_report and kind = p_kind) then
    return jsonb_build_object('status', 'ok', 'cost', 0, 'left', b.free_left + b.paid_left, 'already', true);
  end if;
  select count(*) into n from credit_log where balance_id = b.id and kind in ('report', 'research') and created_at > now() - interval '24 hours';
  if n >= 30 then return jsonb_build_object('status', 'limit', 'need', cost, 'left', b.free_left + b.paid_left); end if;
  if b.free_left + b.paid_left < cost then return jsonb_build_object('status', 'out', 'need', cost, 'left', b.free_left + b.paid_left); end if;
  pp := least(b.paid_left, cost);
  fp := cost - pp;
  update check_balances set paid_left = paid_left - pp, free_left = free_left - fp, updated_at = now() where id = b.id;
  insert into credit_log(balance_id, report_id, kind, amount, free_part, paid_part) values (b.id, p_report, p_kind, -cost, fp, pp);
  return jsonb_build_object('status', 'ok', 'cost', cost, 'left', b.free_left + b.paid_left - cost);
end $body$$fn$;

  execute $fn$
create or replace function public.grant_credits_admin(p_email text, p_amount integer, p_note text default null) returns jsonb
language plpgsql security definer set search_path to 'public' as $body$
declare uid uuid; b public.check_balances;
begin
  if p_amount is null or p_amount = 0 then raise exception 'amount must not be 0'; end if;
  select id into uid from auth.users where lower(email) = lower(btrim(p_email));
  if uid is null then raise exception 'no account with email %', p_email; end if;
  insert into check_balances(user_id, free_left) values (uid, 0) on conflict (user_id) do nothing;
  update check_balances set free_left = greatest(0, free_left + p_amount), updated_at = now() where user_id = uid returning * into b;
  insert into credit_log(balance_id, kind, amount, free_part, note) values (b.id, 'grant_admin', p_amount, p_amount, p_note);
  return jsonb_build_object('email', lower(btrim(p_email)), 'free_left', b.free_left, 'paid_left', b.paid_left, 'total', b.free_left + b.paid_left);
end $body$$fn$;

  execute 'revoke all on function public.ready_credits_ok(text), public.ready_charge(uuid, text), public.grant_credits_admin(text, integer, text) from public, anon, authenticated';
  execute 'grant execute on function public.ready_credits_ok(text), public.ready_charge(uuid, text) to authenticated';
end $wrapci$;
