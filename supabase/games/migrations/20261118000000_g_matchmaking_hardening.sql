-- Matchmaking hardening: durable request contract and idempotent retry/cancel.
-- Existing nx_quick remains compatible for older clients; new clients use nx_quick_match.

create table if not exists public.nx_matchmaking_requests (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  idem_key text not null,
  game text not null,
  seats integer not null,
  rating_min integer not null default 0,
  rating_max integer not null default 3000,
  max_ping_ms integer not null default 250,
  region text not null default 'auto',
  status text not null default 'searching',
  room_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  constraint nx_matchmaking_requests_pk primary key (id),
  constraint nx_matchmaking_requests_idem unique (user_id, idem_key),
  constraint nx_matchmaking_requests_status check
    (status = any (array['searching','matched','cancelled','timed_out','failed'])),
  constraint nx_matchmaking_requests_seats check (seats between 2 and 12),
  constraint nx_matchmaking_requests_rating check (rating_min >= 0 and rating_max >= rating_min),
  constraint nx_matchmaking_requests_ping check (max_ping_ms between 20 and 2000)
);

create index if not exists nx_matchmaking_search
  on public.nx_matchmaking_requests (game, seats, region, status, created_at)
  where status = 'searching';
create unique index if not exists nx_matchmaking_one_active_per_user
  on public.nx_matchmaking_requests (user_id)
  where status = 'searching';

alter table public.nx_matchmaking_requests enable row level security;

drop policy if exists nx_matchmaking_requests_self on public.nx_matchmaking_requests;
create policy nx_matchmaking_requests_self on public.nx_matchmaking_requests
  for select to authenticated using (user_id = auth.uid());

create or replace function public.nx_quick_match(
  p_game text,
  p_seats integer,
  p_rating_min integer default 0,
  p_rating_max integer default 3000,
  p_max_ping_ms integer default 250,
  p_region text default 'auto',
  p_idem_key text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $function$
declare
  me uuid := auth.uid();
  request_row nx_matchmaking_requests;
  bounds record;
  result jsonb;
  rid uuid;
  n integer;
  key text := left(nullif(trim(coalesce(p_idem_key, '')), ''), 96);
begin
  if me is null then raise exception 'not signed in'; end if;
  if key is null then raise exception 'idempotency key required'; end if;
  if p_region is null or p_region !~ '^[a-zA-Z0-9_-]{2,16}$' then
    raise exception 'invalid region';
  end if;
  select * into bounds from nx_game_bounds(p_game);
  if bounds.min_seats is null then raise exception 'unknown game'; end if;
  if p_seats < bounds.min_seats or p_seats > bounds.max_seats then
    raise exception 'invalid player count';
  end if;
  if p_rating_min < 0 or p_rating_max < p_rating_min then
    raise exception 'invalid rating range';
  end if;
  if p_max_ping_ms not between 20 and 2000 then raise exception 'invalid ping'; end if;

  select * into request_row
    from nx_matchmaking_requests
   where user_id = me and idem_key = key
   for update;
  if request_row.id is not null then
    return jsonb_build_object(
      'request_id', request_row.id, 'room_id', request_row.room_id,
      'status', request_row.status, 'idempotent', true);
  end if;
  select * into request_row
    from nx_matchmaking_requests
   where user_id = me and status = 'searching'
   order by created_at desc
   limit 1
   for update;
  if request_row.id is not null then
    return jsonb_build_object(
      'request_id', request_row.id, 'room_id', request_row.room_id,
      'status', request_row.status, 'idempotent', true);
  end if;

  insert into nx_matchmaking_requests
    (user_id, idem_key, game, seats, rating_min, rating_max, max_ping_ms, region)
  values (me, key, p_game, p_seats, p_rating_min, p_rating_max, p_max_ping_ms,
          lower(p_region))
  returning * into request_row;

  begin
    select x.id into rid
      from nx_rooms x
     where x.game = p_game and x.status = 'lobby' and x.quick
       and not x.is_private and x.seats = p_seats
       and (p_region = 'auto' or coalesce(x.settings->'matchmaking'->>'region', 'auto') = lower(p_region))
       and coalesce((x.settings->'matchmaking'->>'rating_max')::int, 3000) >= p_rating_min
       and coalesce((x.settings->'matchmaking'->>'rating_min')::int, 0) <= p_rating_max
       and coalesce((x.settings->'matchmaking'->>'max_ping_ms')::int, 250) <= p_max_ping_ms
       and (select count(*) from nx_room_players rp where rp.room_id = x.id) < x.seats
     order by x.created_at
     limit 1
     for update skip locked;
    if rid is null then
      result := nx_create_room(
        p_game, p_seats, false, true,
        jsonb_build_object('matchmaking', jsonb_build_object(
          'rating_min', p_rating_min, 'rating_max', p_rating_max,
          'max_ping_ms', p_max_ping_ms, 'region', lower(p_region))));
      rid := nullif(result->>'room_id', '')::uuid;
    else
      result := nx_join_room(null, rid);
      select count(*) into n from nx_room_players where room_id = rid;
      if n >= p_seats then
        result := result || nx_start_match_quick(rid);
      end if;
    end if;
    rid := nullif(result->>'room_id', '')::uuid;
    if result ? 'match_id' then
      update nx_matchmaking_requests set status = 'matched', updated_at = now()
       where room_id = rid and status = 'searching';
    end if;
    update nx_matchmaking_requests
       set room_id = rid,
           status = case when (result ? 'match_id') then 'matched' else 'searching' end,
           updated_at = now()
     where id = request_row.id;
  exception when others then
    update nx_matchmaking_requests set status = 'failed', updated_at = now()
     where id = request_row.id;
    raise;
  end;

  return result || jsonb_build_object(
    'request_id', request_row.id,
    'status', (select status from nx_matchmaking_requests where id = request_row.id),
    'idempotent', false);
end;
$function$;

create or replace function public.nx_cancel_matchmaking(p_idem_key text)
returns jsonb
language plpgsql security definer set search_path = public
as $function$
declare
  me uuid := auth.uid();
  request_row nx_matchmaking_requests;
  room_status text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into request_row from nx_matchmaking_requests
   where user_id = me and idem_key = left(trim(p_idem_key), 96) for update;
  if request_row.id is null then
    return jsonb_build_object('ok', true, 'status', 'cancelled', 'already', true);
  end if;
  if request_row.status = 'matched' then
    return jsonb_build_object('ok', false, 'status', 'matched', 'room_id', request_row.room_id);
  end if;
  if request_row.room_id is not null then
    select status into room_status from nx_rooms where id = request_row.room_id for update;
    if room_status = 'lobby' then perform nx_leave_room(request_row.room_id); end if;
  end if;
  update nx_matchmaking_requests set status = 'cancelled', cancelled_at = now(), updated_at = now()
   where id = request_row.id;
  return jsonb_build_object('ok', true, 'status', 'cancelled', 'request_id', request_row.id);
end;
$function$;

revoke all on function public.nx_quick_match(text, integer, integer, integer, integer, text, text)
  from public, anon, authenticated;
grant execute on function public.nx_quick_match(text, integer, integer, integer, integer, text, text)
  to anon, authenticated, service_role;
revoke all on function public.nx_cancel_matchmaking(text) from public, anon, authenticated;
grant execute on function public.nx_cancel_matchmaking(text) to anon, authenticated, service_role;
