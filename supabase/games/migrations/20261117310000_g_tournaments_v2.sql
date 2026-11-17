-- NEXORA GAMES · tournaments v2 (owner spec 2026-11-17): any best-of N, online match length (3/5/7 min or N goals),
-- check-in 10 minutes before the start (only checked-in players enter the automatic draw), per-manager gem prize budget.
alter table public.nx_t_entries add column if not exists checked_in_at timestamptz;
alter table public.nx_t_matches drop constraint if exists nx_t_matches_best_of_check;
alter table public.nx_t_matches add constraint nx_t_matches_best_of_check check (best_of between 1 and 15);
alter table public.nx_t_entries drop constraint if exists nx_t_entries_status_check;
alter table public.nx_t_entries add constraint nx_t_entries_status_check
  check (status in ('pending', 'approved', 'rejected', 'waitlist', 'withdrawn', 'removed', 'no_checkin'));


create or replace function public.nx_t_gem_budget_left(u uuid default auth.uid(), p_except uuid default null) returns integer
language sql stable security definer set search_path = public as $$
  select case when nx_unlimited(u) then 2147483647
    else greatest(0, coalesce((select gem_budget from nx_staff where user_id = u), 0)
      - coalesce((select sum(_nx_t_cfg_int(prize, 'fixed_gems', 0)) from nx_tournaments
                   where created_by = u and status <> 'cancelled' and (p_except is null or id <> p_except)), 0)::int) end
$$;
grant execute on function public.nx_t_gem_budget_left(uuid, uuid) to authenticated;

CREATE OR REPLACE FUNCTION public._nx_t_validate_cfg(c jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare o jsonb := coalesce(c, '{}'::jsonb); k text;
begin
  foreach k in array array['bo_early', 'bo_semi', 'bo_final'] loop
    if _nx_t_cfg_int(o, k, 1) not between 1 and 15 then o := o || jsonb_build_object(k, 1); end if;
  end loop;
  -- online match length: 3 / 5 / 7 minutes, or first to N goals (0 = game default)
  if _nx_t_cfg_int(o, 'match_minutes', 0) not in (0, 3, 5, 7) then o := o || '{"match_minutes": 5}'::jsonb; end if;
  o := o || jsonb_build_object('goal_target', greatest(0, least(_nx_t_cfg_int(o, 'goal_target', 0), 20)),
                               'checkin', _nx_t_cfg_bool(o, 'checkin', true));
  if _nx_t_cfg_int(o, 'goal_target', 0) > 0 then o := o || '{"match_minutes": 0}'::jsonb; end if;
  o := o || jsonb_build_object(
    'groups', greatest(1, least(_nx_t_cfg_int(o, 'groups', 2), 16)),
    'advance', greatest(1, least(_nx_t_cfg_int(o, 'advance', 2), 8)),
    'swiss_rounds', greatest(0, least(_nx_t_cfg_int(o, 'swiss_rounds', 0), 12)),
    'points_win', greatest(0, least(_nx_t_cfg_int(o, 'points_win', 3), 10)),
    'points_draw', greatest(0, least(_nx_t_cfg_int(o, 'points_draw', 1), 10)),
    'ready_seconds', greatest(30, least(_nx_t_cfg_int(o, 'ready_seconds', 300), 3600)),
    'round_minutes', greatest(1, least(_nx_t_cfg_int(o, 'round_minutes', 20), 10080)),
    'max_game_minutes', greatest(5, least(_nx_t_cfg_int(o, 'max_game_minutes', 30), 240)));
  return o;
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_bo(t nx_tournaments, p_kind text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare v int;
begin
  if t.format = 'two_legs' then
    if p_kind = 'final' and _nx_t_cfg_bool(t.config, 'final_one_leg', false) then return 1; end if;
    return 2;
  end if;
  v := _nx_t_cfg_int(t.config, 'bo_' || p_kind, _nx_t_cfg_int(t.config, 'bo_early', 1));
  if v not between 1 and 15 then v := 1; end if;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_launch(p_m uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; t nx_tournaments; home uuid; away uuid; rid uuid; mid uuid; sd bigint; c text; golden boolean;
        st jsonb;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'ready_check' then return null; end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  if m.games % 2 = 0 then home := m.p1; away := m.p2; else home := m.p2; away := m.p1; end if;
  golden := m.games >= m.best_of;
  st := jsonb_build_object('tmatch', m.id, 'tournament', t.id, 'game_no', m.games + 1, 'golden_goal', golden,
                           'grace_sec', 60, 'best_of', m.best_of, 'aggregate', m.aggregate,
                           'match_minutes', _nx_t_cfg_int(t.config, 'match_minutes', 0),
                           'goal_target', _nx_t_cfg_int(t.config, 'goal_target', 0),
                           'lineup', true);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, status, is_private, quick, settings)
  values (c, t.game, home, 2, 'playing', true, false, st) returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, home, 0, true), (rid, away, 1, true);
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings)
  values (rid, t.game, array[home, away],
          array[coalesce((select username from profiles where id = home), 'Pilot'),
                coalesce((select username from profiles where id = away), 'Pilot')], sd, st)
  returning id into mid;
  update nx_rooms set match_id = mid where id = rid;
  insert into nx_t_games(game_match, tmatch, n, home, away, golden) values (mid, m.id, m.games + 1, home, away, golden);
  update nx_t_matches set status = 'playing', game_match = mid, ready_deadline = null, updated_at = now() where id = m.id;
  perform _nx_t_audit(t.id, null, 'game_started', jsonb_build_object('match', m.id, 'game_match', mid, 'n', m.games + 1));
  return mid;
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_sync_jobs(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or t.status in ('draft', 'finished', 'cancelled') then return; end if;
  perform _nx_t_job('open_reg', t.id, null, t.reg_open_at, 'open_reg:' || t.id);
  perform _nx_t_job('close_reg', t.id, null, t.reg_close_at, 'close_reg:' || t.id);
  -- with check-in the draw happens at the start (after the check-in window)
  if not _nx_t_cfg_bool(t.config, 'checkin', false) then
    perform _nx_t_job('draw', t.id, null, t.draw_at, 'draw:' || t.id);
  end if;
  perform _nx_t_job('start', t.id, null, t.start_at, 'start:' || t.id);
  if t.start_at - interval '10 minutes' > now() then
    if _nx_t_cfg_bool(t.config, 'checkin', false) then
      delete from nx_t_jobs where idem_key = 'remind_start:' || t.id and done_at is null;
      perform _nx_t_job('checkin_open', t.id, null, t.start_at - interval '10 minutes', 'checkin_open:' || t.id);
    else
      delete from nx_t_jobs where idem_key = 'checkin_open:' || t.id and done_at is null;
      perform _nx_t_job('remind_start', t.id, null, t.start_at - interval '10 minutes', 'remind_start:' || t.id);
    end if;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_run_job(j nx_t_jobs)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; m nx_t_matches;
begin
  select * into t from nx_tournaments where id = j.tournament_id;
  if t.id is null or t.status in ('finished', 'cancelled', 'draft') then return; end if;
  case j.kind
    when 'open_reg' then
      update nx_tournaments set status = 'registering', updated_at = now() where id = t.id and status = 'scheduled';
    when 'close_reg' then
      update nx_tournaments set status = 'closed', updated_at = now() where id = t.id and status = 'registering';
    when 'checkin_open' then
      if t.status in ('registering', 'closed') then
        perform _nx_t_notify_all(t.id, 'checkin_open', jsonb_build_object('start_at', t.start_at), 'checkin:' || t.id);
      end if;
    when 'draw' then
      if _nx_t_cfg_bool(t.config, 'checkin', false) then return; end if;
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_draw(t.id);
    when 'start' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_start(t.id);
    when 'remind_start' then
      if t.status in ('registering', 'closed', 'drawn') then
        perform _nx_t_notify_all(t.id, 'starting_soon', jsonb_build_object('start_at', t.start_at), 'soon:' || t.id);
      end if;
    when 'remind_match' then
      select * into m from nx_t_matches where id = j.ref;
      if m.id is not null and m.status = 'scheduled' and m.p1 is not null and m.p2 is not null then
        perform _nx_t_notify(m.p1, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
        perform _nx_t_notify(m.p2, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
      end if;
    else
      null;
  end case;
end $function$
;

CREATE OR REPLACE FUNCTION public._nx_t_draw(p_t uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int; players uuid[]; g int; a int; i int; grp int; r record; maxr int := 0; rr int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status not in ('registering', 'closed') then return; end if;
  -- check-in: approved players who did not check in are left out (fee refunded)
  if _nx_t_cfg_bool(t.config, 'checkin', false) then
    for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'approved' and checked_in_at is null loop
      perform _nx_t_refund(p_t, r.user_id, 'no_checkin');
      update nx_t_entries set status = 'no_checkin', note = 'no_checkin', updated_at = now()
       where tournament_id = p_t and user_id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'no_checkin', '{}'::jsonb, 'nocheckin:' || p_t);
    end loop;
  end if;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  if n < greatest(2, t.min_players) then
    perform _nx_t_cancel(p_t, 'not_enough_players', p_actor);
    return;
  end if;
  -- whoever did not make it (pending approval / waitlist) gets the fee back
  for r in select user_id from nx_t_entries where tournament_id = p_t and status in ('pending', 'waitlist') loop
    perform _nx_t_refund(p_t, r.user_id, 'not_drawn');
    update nx_t_entries set status = 'rejected', note = 'not_drawn', updated_at = now()
     where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'rejected', jsonb_build_object('reason', 'not_drawn'), 'notdrawn:' || p_t);
  end loop;
  if t.seed is null then
    t.seed := floor(random() * 2147483646)::bigint + 1;
    update nx_tournaments set seed = t.seed where id = p_t;
  end if;
  select array_agg(user_id order by
           case when t.seeding = 'manual' then coalesce(seed, 100000) else 0 end,
           case when t.seeding = 'rating' then -rating else 0 end,
           md5(t.seed::text || user_id::text))
    into players from nx_t_entries where tournament_id = p_t and status = 'approved';
  for i in 1..n loop
    update nx_t_entries set seed = i, group_no = null where tournament_id = p_t and user_id = players[i];
  end loop;
  delete from nx_t_matches where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs') then
    perform _nx_t_gen_se(p_t, players, 'main', 0, 0);
  elsif t.format = 'double_elim' then
    perform _nx_t_gen_de(p_t, players);
  elsif t.format = 'round_robin' then
    perform _nx_t_gen_rr(p_t, players, null, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'RR', 'main');
  elsif t.format = 'groups_ko' then
    g := greatest(1, least(_nx_t_cfg_int(t.config, 'groups', 2), n / 2));
    for i in 1..n loop
      -- snake: 1..g, g..1, ...
      grp := case when ((i - 1) / g) % 2 = 0 then ((i - 1) % g) + 1 else g - ((i - 1) % g) end;
      update nx_t_entries set group_no = grp where tournament_id = p_t and user_id = players[i];
    end loop;
    for grp in 1..g loop
      rr := _nx_t_gen_rr(p_t, (select array_agg(user_id order by seed) from nx_t_entries
                                where tournament_id = p_t and status = 'approved' and group_no = grp),
                         grp, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'G', 'groups');
    end loop;
    update nx_tournaments set stage = 'groups' where id = p_t;
  elsif t.format = 'swiss' then
    perform _nx_t_swiss_round(p_t, 1);
  end if;
  update nx_tournaments set status = 'drawn', drawn_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'drawn', '{}'::jsonb, 'drawn:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'drawn', jsonb_build_object('seed', t.seed, 'players', n, 'seeding', t.seeding));
end $function$
;

CREATE OR REPLACE FUNCTION public.nx_t_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; old nx_tournaments; isnew boolean; adm boolean; paid boolean;
        n_appr int; times_changed boolean := false; prize jsonb; dsum int := 0; v jsonb;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  adm := nx_t_is_admin(me);
  isnew := (p ->> 'id') is null;
  if isnew then
    if not nx_t_is_organizer(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    t.id := gen_random_uuid(); t.status := 'draft'; t.created_by := me; t.config := '{}'; t.prize := '{}';
    t.game := 'finger_soccer'; t.format := 'single_elim'; t.capacity := 16; t.min_players := 2; t.reg_mode := 'open';
    t.min_level := 0; t.min_xp := 0; t.min_rating := 0; t.fee_coins := 0; t.fee_gems := 0; t.seeding := 'random';
    t.description := ''; t.rules := ''; t.paused := false; t.stage := 'main'; t.escrow_coins := 0; t.escrow_gems := 0;
    t.paid_out := false; t.created_at := now();
  else
    select * into t from nx_tournaments where id = (p ->> 'id')::uuid for update;
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  end if;
  old := t;
  -- always editable
  if p ? 'title' then t.title := left(trim(p ->> 'title'), 80); end if;
  if p ? 'description' then t.description := left(coalesce(p ->> 'description', ''), 4000); end if;
  if p ? 'rules' then t.rules := left(coalesce(p ->> 'rules', ''), 4000); end if;
  if p ? 'reg_open_at' and t.status in ('draft', 'scheduled') then t.reg_open_at := (p ->> 'reg_open_at')::timestamptz; end if;
  if p ? 'reg_close_at' and t.status in ('draft', 'scheduled', 'registering') then t.reg_close_at := (p ->> 'reg_close_at')::timestamptz; end if;
  if p ? 'draw_at' and t.status in ('draft', 'scheduled', 'registering', 'closed') then t.draw_at := (p ->> 'draw_at')::timestamptz; end if;
  if p ? 'start_at' and t.status in ('draft', 'scheduled', 'registering', 'closed', 'drawn') then t.start_at := (p ->> 'start_at')::timestamptz; end if;
  if p ? 'config' then
    if t.status in ('draft', 'scheduled', 'registering', 'closed') then
      t.config := _nx_t_validate_cfg(p -> 'config');
    else
      -- after the draw only timing settings may change
      v := p -> 'config';
      t.config := _nx_t_validate_cfg(t.config || jsonb_strip_nulls(jsonb_build_object(
        'round_starts', v -> 'round_starts', 'round_minutes', v -> 'round_minutes', 'ready_seconds', v -> 'ready_seconds',
        'max_game_minutes', v -> 'max_game_minutes')));
    end if;
  end if;
  if t.status in ('draft', 'scheduled', 'registering', 'closed') then
    select count(*) into n_appr from nx_t_entries where tournament_id = t.id and status = 'approved';
    select exists (select 1 from nx_t_entries where tournament_id = t.id and (paid_coins > 0 or paid_gems > 0)) into paid;
    if p ? 'game' then t.game := p ->> 'game'; end if;
    if p ? 'format' then t.format := p ->> 'format'; end if;
    if p ? 'capacity' then t.capacity := greatest(n_appr, (p ->> 'capacity')::int); end if;
    if p ? 'min_players' then t.min_players := greatest(2, least((p ->> 'min_players')::int, t.capacity)); end if;
    if p ? 'reg_mode' then t.reg_mode := p ->> 'reg_mode'; end if;
    if p ? 'min_level' then t.min_level := greatest(0, (p ->> 'min_level')::int); end if;
    if p ? 'min_xp' then t.min_xp := greatest(0, (p ->> 'min_xp')::int); end if;
    if p ? 'min_rating' then t.min_rating := greatest(0, (p ->> 'min_rating')::int); end if;
    if p ? 'seeding' then t.seeding := p ->> 'seeding'; end if;
    if not paid then
      if p ? 'fee_coins' then t.fee_coins := greatest(0, (p ->> 'fee_coins')::int); end if;
      if p ? 'fee_gems' then t.fee_gems := greatest(0, (p ->> 'fee_gems')::int); end if;
    elsif (p ? 'fee_coins' and (p ->> 'fee_coins')::int <> t.fee_coins) or (p ? 'fee_gems' and (p ->> 'fee_gems')::int <> t.fee_gems) then
      return jsonb_build_object('ok', false, 'error', 'fee_locked');
    end if;
    if p ? 'prize' then
      prize := coalesce(p -> 'prize', '{}'::jsonb);
      prize := jsonb_build_object(
        'fixed_coins', greatest(0, _nx_t_cfg_int(prize, 'fixed_coins', 0)),
        'fixed_gems', greatest(0, _nx_t_cfg_int(prize, 'fixed_gems', 0)),
        'pool_pct', greatest(0, least(_nx_t_cfg_int(prize, 'pool_pct', 0), 100)),
        'fee_pct', greatest(0, least(_nx_t_cfg_int(prize, 'fee_pct', 0), 50)),
        'dist', case when jsonb_typeof(prize -> 'dist') = 'array' then prize -> 'dist' else '[60,30,10]'::jsonb end);
      select coalesce(sum(greatest(0, x::numeric::int)), 0) into dsum from jsonb_array_elements_text(prize -> 'dist') x;
      if dsum > 100 or jsonb_array_length(prize -> 'dist') > 64 then
        return jsonb_build_object('ok', false, 'error', 'bad_distribution'); end if;
      -- minting coins/gems out of nothing is an admin decision
      -- (admins, the owner and tournament admins with the 'unlimited' perk; nothing is deducted from their balance,
      --  every payout is still written to nx_t_ledger)
      if (_nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0)
          or _nx_t_cfg_int(prize, 'fixed_gems', 0) > _nx_t_cfg_int(old.prize, 'fixed_gems', 0)) then
        if not (adm or nx_unlimited(me)) then
          -- limited managers: gem prizes within their budget (set by the main admin); coin prizes stay admin-only
          if _nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0) then
            return jsonb_build_object('ok', false, 'error', 'fixed_prize_admin_only'); end if;
          if _nx_t_cfg_int(prize, 'fixed_gems', 0) > nx_t_gem_budget_left(me, t.id) then
            return jsonb_build_object('ok', false, 'error', 'gem_budget_exceeded',
                                      'left', nx_t_gem_budget_left(me, t.id)); end if;
        end if;
        perform _nx_t_audit(t.id, me, 'fixed_prize_minted', jsonb_build_object(
          'fixed_coins', _nx_t_cfg_int(prize, 'fixed_coins', 0), 'fixed_gems', _nx_t_cfg_int(prize, 'fixed_gems', 0),
          'by', case when adm then 'admin' when nx_unlimited(me) then 'manager_unlimited' else 'manager_budget' end));
      end if;
      t.prize := prize;
    end if;
  end if;
  if t.title is null or char_length(t.title) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if t.format not in ('single_elim', 'double_elim', 'two_legs', 'round_robin', 'groups_ko', 'swiss', 'custom') then
    return jsonb_build_object('ok', false, 'error', 'bad_format'); end if;
  if t.capacity is null or t.capacity < 2 or t.capacity > 64 then return jsonb_build_object('ok', false, 'error', 'bad_capacity'); end if;
  if t.game not in ('finger_soccer', 'carrom', 'billiards', 'backgammon', 'quiz') then
    return jsonb_build_object('ok', false, 'error', 'bad_game'); end if;
  if t.reg_open_at is null or t.reg_close_at is null or t.draw_at is null or t.start_at is null
     or not (t.reg_open_at < t.reg_close_at and t.reg_close_at <= t.draw_at and t.draw_at <= t.start_at) then
    return jsonb_build_object('ok', false, 'error', 'bad_times'); end if;
  if t.format = 'groups_ko' and t.capacity < 4 then return jsonb_build_object('ok', false, 'error', 'groups_need_4'); end if;
  times_changed := not isnew and old.status <> 'draft' and (old.reg_open_at, old.reg_close_at, old.draw_at, old.start_at, old.config -> 'round_starts', old.config -> 'round_minutes')
                   is distinct from (t.reg_open_at, t.reg_close_at, t.draw_at, t.start_at, t.config -> 'round_starts', t.config -> 'round_minutes');
  t.updated_at := now();
  if isnew then
    insert into nx_tournaments select t.*;
    perform _nx_t_audit(t.id, me, 'created', jsonb_build_object('title', t.title, 'format', t.format));
  else
    update nx_tournaments set title = t.title, description = t.description, rules = t.rules, game = t.game, format = t.format,
           capacity = t.capacity, min_players = t.min_players, config = t.config, reg_mode = t.reg_mode, min_level = t.min_level,
           min_xp = t.min_xp, min_rating = t.min_rating, fee_coins = t.fee_coins, fee_gems = t.fee_gems, prize = t.prize,
           reg_open_at = t.reg_open_at, reg_close_at = t.reg_close_at, draw_at = t.draw_at, start_at = t.start_at,
           seeding = t.seeding, updated_at = now()
     where id = t.id;
    perform _nx_t_audit(t.id, me, 'edited', jsonb_build_object('times_changed', times_changed));
  end if;
  if times_changed then
    perform _nx_t_sync_jobs(t.id);
    perform _nx_t_reschedule(t.id);
    perform _nx_t_notify_all(t.id, 'time_changed', jsonb_build_object('start_at', t.start_at, 'reg_close_at', t.reg_close_at,
              'draw_at', t.draw_at), 'time:' || t.id || ':' || floor(extract(epoch from clock_timestamp()))::bigint,
              array['approved', 'pending', 'waitlist']);
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $function$
;


-- Check-in: from 10 minutes before the start until the start, approved players confirm they are here.
create or replace function public.nx_t_checkin(p_t uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select * into t from nx_tournaments where id = p_t;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is null or e.status <> 'approved' then return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  if not _nx_t_cfg_bool(t.config, 'checkin', false) then return jsonb_build_object('ok', true, 'checkin', false); end if;
  if e.checked_in_at is not null then return jsonb_build_object('ok', true, 'checked_in_at', e.checked_in_at); end if;
  if t.status not in ('registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'checkin_closed'); end if;
  if now() < t.start_at - interval '10 minutes' then
    return jsonb_build_object('ok', false, 'error', 'checkin_not_open', 'opens_at', t.start_at - interval '10 minutes'); end if;
  update nx_t_entries set checked_in_at = now(), updated_at = now() where tournament_id = p_t and user_id = me;
  perform _nx_t_audit(p_t, me, 'checked_in', '{}'::jsonb);
  return jsonb_build_object('ok', true, 'checked_in_at', now());
end $$;
revoke all on function public.nx_t_checkin(uuid) from public, anon;
grant execute on function public.nx_t_checkin(uuid) to authenticated;
-- re-sync jobs of open tournaments so the check-in job replaces the old reminder
do $$ declare r record; begin
  for r in select id from nx_tournaments where status in ('scheduled', 'registering', 'closed') loop
    perform _nx_t_sync_jobs(r.id);
  end loop;
end $$;

