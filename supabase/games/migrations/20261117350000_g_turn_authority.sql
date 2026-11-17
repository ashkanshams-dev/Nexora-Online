-- Server-authoritative turn clock for physics matches.
-- Runtime data is untouched; this migration only adds columns and replaces the move RPC.
alter table public.nx_matches
  add column if not exists turn_seat integer not null default 0,
  add column if not exists turn_deadline timestamptz not null default (now() + interval '10 seconds');

update public.nx_matches
   set turn_seat = greatest(0, least(turn_seat, array_length(players, 1) - 1)),
       turn_deadline = coalesce(turn_deadline, now() + interval '10 seconds')
 where status = 'playing';

create or replace function public.nx_push_move(
  p_match uuid,
  p_seq integer,
  p_kind text,
  p_move jsonb,
  p_hash text,
  p_seat integer default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  m nx_matches;
  caller_seat int;
  effective_seat int;
  n int;
  k text := left(coalesce(p_kind, 'move'), 16);
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  caller_seat := array_position(m.players, me) - 1;
  if caller_seat is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', false, 'reason', 'over', 'last_seq', m.last_seq);
  end if;
  if p_seq <> m.last_seq + 1 then
    return jsonb_build_object('ok', false, 'reason', 'seq', 'last_seq', m.last_seq);
  end if;

  -- Host/authority may post a snapshot or a timeout for a disconnected seat;
  -- ordinary gameplay moves must always be posted for the caller's own seat.
  if p_seat is not null and p_seat <> caller_seat and k not in ('snap', 'timeout', 'forfeit', 'system') then
    raise exception 'seat mismatch';
  end if;
  effective_seat := coalesce(p_seat, caller_seat);

  -- Snapshots do not represent a turn. Every gameplay move and timeout does.
  if k not in ('snap', 'system', 'forfeit') then
    if effective_seat <> m.turn_seat then
      return jsonb_build_object('ok', false, 'reason', 'turn', 'turn_seat', m.turn_seat);
    end if;
    if k <> 'timeout' and now() > m.turn_deadline then
      return jsonb_build_object('ok', false, 'reason', 'timeout', 'turn_seat', m.turn_seat);
    end if;
    if k = 'timeout' and now() < m.turn_deadline then
      return jsonb_build_object('ok', false, 'reason', 'too_early', 'turn_seat', m.turn_seat);
    end if;
  end if;

  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, effective_seat, me, k, coalesce(p_move, '{}'::jsonb), p_hash);

  n := greatest(1, coalesce(array_length(m.players, 1), 1));
  if k not in ('snap', 'system', 'forfeit') then
    update nx_matches
       set last_seq = p_seq,
           state_hash = coalesce(p_hash, state_hash),
           turn_seat = (m.turn_seat + 1) % n,
           turn_deadline = now() + interval '10 seconds'
     where id = p_match;
  else
    update nx_matches
       set last_seq = p_seq, state_hash = coalesce(p_hash, state_hash)
     where id = p_match;
  end if;
  return jsonb_build_object('ok', true, 'seq', p_seq, 'turn_seat', (m.turn_seat + 1) % n);
end;
$$;

revoke all on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) from public, anon, authenticated;
grant execute on function public.nx_push_move(uuid, integer, text, jsonb, text, integer) to anon, authenticated, service_role;
