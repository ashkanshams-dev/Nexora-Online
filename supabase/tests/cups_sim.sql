-- Full server simulation of a 5-player cup (prize 100, split 50/30/20, best of 3) inside one transaction that is
-- rolled back at the end: the result is raised as the error message. Run: tools/sql.py supabase/tests/cups_sim.sql
do $$
declare u uuid[]; c cups; g0 int; gc int; r jsonb := '{}'; m cup_matches; mt matches; i int; k int; rid uuid; tot int; q text; begin
  select array_agg(id order by created_at) into u from (select id, created_at from profiles where username is not null order by created_at limit 7) x;
  update profiles set gems = 500 where id = any(u);
  perform set_config('request.jwt.claims', json_build_object('sub', u[1], 'role', 'authenticated')::text, true);
  c := cup_create('Sim Cup', 5, 3, 3, now() + interval '20 minutes', 100, '{50,30,20}', true);
  select gems into gc from profiles where id = u[1];
  r := r || jsonb_build_object('code', c.code, 'creator_gems_after_escrow', gc);
  for i in 2..7 loop
    perform set_config('request.jwt.claims', json_build_object('sub', u[i], 'role', 'authenticated')::text, true);
    perform cup_join(c.code);
  end loop;
  r := r || jsonb_build_object('reg', (select jsonb_object_agg(status, n) from (select status, count(*) n from cup_players where cup_id = c.id group by 1) z));
  -- jump into the last 4 minutes: everyone except u[5] checks in (u[6], u[7] are on the waitlist)
  update cups set starts_at = now() + interval '4 minutes' where id = c.id;
  foreach rid in array array[u[1],u[2],u[3],u[4],u[6],u[7]] loop
    perform set_config('request.jwt.claims', json_build_object('sub', rid, 'role', 'authenticated')::text, true);
    perform cup_checkin(c.id);
  end loop;
  r := r || jsonb_build_object('after_checkin', (select jsonb_object_agg(user_id::text, status || coalesce('/' || note, '')) from cup_players where cup_id = c.id));
  -- start time
  update cups set starts_at = now() - interval '1 second' where id = c.id;
  perform _cup_draw(c.id);
  select * into c from cups where id = c.id;
  r := r || jsonb_build_object('status', c.status, 'size', c.bracket_size, 'rounds', c.rounds,
     'matches', (select jsonb_agg(jsonb_build_object('k', kind, 'r', round, 'i', idx, 's', status, 'p1', p1 is not null, 'p2', p2 is not null) order by kind, round, idx) from cup_matches where cup_id = c.id));
  -- play the real round-1 pairing: game 1 and 2 won by p1 -> 2-0 in a best of 3
  select * into m from cup_matches where cup_id = c.id and round = 1 and status = 'ready';
  perform set_config('request.jwt.claims', json_build_object('sub', m.p1, 'role', 'authenticated')::text, true);
  perform cup_enter(m.id);
  perform set_config('request.jwt.claims', json_build_object('sub', m.p2, 'role', 'authenticated')::text, true);
  perform cup_enter(m.id);
  -- the room host cannot start a game himself (no lineup window / bots)
  perform set_config('request.jwt.claims', json_build_object('sub', (select host from rooms where id = (select room_id from cup_matches where id = m.id)), 'role', 'authenticated')::text, true);
  begin
    perform start_match((select room_id from cup_matches where id = m.id));
    r := r || '{"host_start_blocked": false}';
  exception when others then r := r || jsonb_build_object('host_start_blocked', sqlerrm);
  end;
  for k in 1..2 loop
    update cup_matches set lineup_until = now() - interval '1 second' where id = m.id;
    perform cup_kick(m.id);
    select * into mt from matches where id = (select current_match from rooms where id = (select room_id from cup_matches where id = m.id));
    if mt.id is null then raise exception 'game % did not start: %', k, (select to_jsonb(x) from cup_matches x where id = m.id); end if;
    update matches set status = 'done', score_a = 3, score_b = k - 1 where id = mt.id;
    update rooms set status = 'waiting', current_match = null where id = mt.room_id;
  end loop;
  select * into m from cup_matches where id = m.id;
  r := r || jsonb_build_object('r1_series', jsonb_build_object('status', m.status, 'w', m.wins1 || '-' || m.wins2, 'games', m.games_played, 'winner_is_p1', m.winner = m.p1));
  -- the rest by schedule + no-show walkovers (nobody enters), driven by the tick
  for k in 1..6 loop
    update cup_matches set scheduled_at = now() - interval '1 minute', wait_from = now() - interval '10 minutes' where cup_id = c.id and status in ('pending','ready');
    perform cup_tick();
    update cup_matches set wait_from = now() - interval '10 minutes' where cup_id = c.id and status in ('ready');
    perform cup_tick();
    exit when (select status from cups where id = c.id) = 'finished';
  end loop;
  select * into c from cups where id = c.id;
  select coalesce(sum(gems), 0) into tot from cup_ledger where cup_id = c.id and kind in ('prize','refund');
  r := r || jsonb_build_object('final_status', c.status, 'prize_paid', c.prize_paid,
     'places', (select jsonb_agg(jsonb_build_object('place', final_place, 'gems', (select gems from profiles where id = user_id)) order by final_place) from cup_players where cup_id = c.id and final_place is not null),
     'ledger', (select jsonb_agg(jsonb_build_object('kind', kind, 'place', place, 'gems', gems) order by id) from cup_ledger where cup_id = c.id), 'paid_total', tot);
  -- idempotence: finishing again pays nothing
  update cups set status = 'running' where id = c.id;
  perform _cup_finish(c.id);
  r := r || jsonb_build_object('ledger_rows_after_refinish', (select count(*) from cup_ledger where cup_id = c.id));
  r := r || jsonb_build_object('notif_kinds', (select jsonb_object_agg(kind, n) from (select kind, count(*) n from notifications where data->>'cup' = c.id::text group by 1) z));
  raise exception 'SIMRESULT %', r;
end $$;
