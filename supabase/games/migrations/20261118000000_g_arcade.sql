-- NEXORA arcade (redesign-2): 20 new games.
--  * nx_known_game / nx_game_bounds / nx_create_room accept the 10 new multiplayer games (rooms, quick match,
--    invites, tournaments and ratings reuse the existing engine — no separate game server).
--  * nx_arcade_best + nx_arcade_runs: server-validated solo scores (global + daily boards).
--    nx_arcade_submit rejects impossible scores (per-game max score and max score-per-second, minimum run time)
--    and rate-limits submissions; nx_arcade_top returns the boards with names.

create or replace function public.nx_known_game(p_game text) returns boolean
language sql immutable as $$
  select p_game in ('finger_soccer','carrom','billiards','backgammon','ludo','snakes_ladders','uno','quiz','mafia',
                    'kart_racing','obstacle_race','bomb_arena','pool8','mini_golf','basketball_battle','spy_mafia',
                    'stickman_arena','ludo_battle','chess_blitz')
$$;

create or replace function public.nx_game_bounds(p_game text, out min_seats integer, out max_seats integer)
returns record language sql immutable as $$
  select case p_game when 'ludo' then 2 when 'snakes_ladders' then 2 when 'uno' then 2 when 'quiz' then 2
                     when 'mafia' then 6 when 'spy_mafia' then 3 else 2 end,
         case p_game when 'ludo' then 4 when 'snakes_ladders' then 4 when 'uno' then 4 when 'quiz' then 2
                     when 'mafia' then 10
                     when 'kart_racing' then 4 when 'obstacle_race' then 4 when 'bomb_arena' then 4
                     when 'mini_golf' then 4 when 'spy_mafia' then 8 when 'stickman_arena' then 4
                     when 'ludo_battle' then 4 else 2 end
$$;

create or replace function public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean default false,
                                                 p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare me uuid := auth.uid(); b record; s int; rid uuid; c text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into b from nx_game_bounds(p_game);
  if not nx_known_game(p_game) then raise exception 'unknown game'; end if;
  s := greatest(b.min_seats, least(coalesce(p_seats, b.min_seats), b.max_seats));
  perform _nx_leave_all(me);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, is_private, quick, settings)
  values (c, p_game, me, s, coalesce(p_private, false), coalesce(p_quick, false), coalesce(p_settings, '{}'::jsonb))
  returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, me, 0, true);
  return jsonb_build_object('room_id', rid, 'code', c, 'seats', s);
end $function$;

-- ---------------------------------------------------------------- solo score boards
create table if not exists public.nx_arcade_best (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  best integer not null default 0,
  best_at timestamptz not null default now(),
  daily_day date,
  daily_best integer not null default 0,
  plays integer not null default 0,
  last_submit timestamptz,
  primary key (user_id, game)
);
create index if not exists nx_arcade_best_game_idx on public.nx_arcade_best(game, best desc);
create index if not exists nx_arcade_best_daily_idx on public.nx_arcade_best(game, daily_day, daily_best desc);

create table if not exists public.nx_arcade_runs (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  game text not null,
  score integer not null,
  duration_ms integer not null,
  daily boolean not null default false,
  accepted boolean not null,
  reason text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists nx_arcade_runs_user_idx on public.nx_arcade_runs(user_id, created_at desc);

alter table public.nx_arcade_best enable row level security;
alter table public.nx_arcade_runs enable row level security;
drop policy if exists nx_arcade_best_read on public.nx_arcade_best;
create policy nx_arcade_best_read on public.nx_arcade_best for select using (true);
drop policy if exists nx_arcade_runs_own on public.nx_arcade_runs;
create policy nx_arcade_runs_own on public.nx_arcade_runs for select using (user_id = auth.uid());
revoke insert, update, delete on public.nx_arcade_best, public.nx_arcade_runs from anon, authenticated;

-- Anti-cheat sanity limits: max total score, max score per second of play, min run length (ms).
create or replace function public.nx_arcade_limits(p_game text, out max_score integer, out max_rate numeric, out min_ms integer)
returns record language sql immutable as $$
  select case p_game
           when 'endless_runner' then 200000 when 'tetris_rush' then 9999999 when 'helix_jump' then 500000
           when 'fruit_ninja' then 20000 when 'geo_dash' then 100000 when 'traffic_racer' then 2000000
           when 'stack_tower' then 2000 when 'bubble_shooter' then 5000000 when 'knife_hit' then 50000
           when 'game_2048' then 4000000 else 0 end,
         case p_game
           when 'endless_runner' then 40 when 'tetris_rush' then 3000 when 'helix_jump' then 120
           when 'fruit_ninja' then 25 when 'geo_dash' then 30 when 'traffic_racer' then 400
           when 'stack_tower' then 4 when 'bubble_shooter' then 2500 when 'knife_hit' then 12
           when 'game_2048' then 1500 else 0 end,
         case p_game when 'stack_tower' then 800 else 1500 end
$$;

create or replace function public.nx_arcade_submit(p_game text, p_score integer, p_duration_ms integer,
                                                   p_daily boolean default false, p_meta jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare
  me uuid := auth.uid();
  l record;
  ok boolean := true;
  why text := null;
  today date := (now() at time zone 'utc')::date;
  b nx_arcade_best;
  r int;
  slack numeric;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into l from nx_arcade_limits(p_game);
  if l.max_score = 0 then raise exception 'unknown game'; end if;
  if not exists (select 1 from profiles where id = me) then raise exception 'call nx_g_hello first'; end if;
  select * into b from nx_arcade_best where user_id = me and game = p_game;
  -- rate limit: one submit per 3 s per game
  if b.last_submit is not null and b.last_submit > now() - interval '3 seconds' then
    ok := false; why := 'rate_limited';
  end if;
  slack := 1.0 + 15.0 * l.max_rate;  -- small bonus burst allowance
  if ok and (p_score is null or p_score < 0 or p_score > l.max_score) then ok := false; why := 'score_out_of_range'; end if;
  if ok and p_score > 0 and coalesce(p_duration_ms, 0) < l.min_ms then ok := false; why := 'too_short'; end if;
  if ok and p_score > slack + l.max_rate * greatest(0, coalesce(p_duration_ms, 0)) / 1000.0 then
    ok := false; why := 'too_fast';
  end if;
  if ok and coalesce(p_duration_ms, 0) > 6 * 3600 * 1000 then ok := false; why := 'too_long'; end if;
  insert into nx_arcade_runs(user_id, game, score, duration_ms, daily, accepted, reason, meta)
  values (me, p_game, greatest(0, least(coalesce(p_score, 0), 2000000000)), greatest(0, coalesce(p_duration_ms, 0)),
          coalesce(p_daily, false), ok, why, coalesce(p_meta, '{}'::jsonb));
  if not ok then
    if why <> 'rate_limited' then
      insert into nx_arcade_best(user_id, game, last_submit) values (me, p_game, now())
      on conflict (user_id, game) do update set last_submit = now();
    end if;
    return jsonb_build_object('ok', false, 'reason', why);
  end if;
  insert into nx_arcade_best(user_id, game, best, best_at, daily_day, daily_best, plays, last_submit)
  values (me, p_game, p_score, now(), case when p_daily then today end, case when p_daily then p_score else 0 end, 1, now())
  on conflict (user_id, game) do update set
    best = greatest(nx_arcade_best.best, excluded.best),
    best_at = case when excluded.best > nx_arcade_best.best then now() else nx_arcade_best.best_at end,
    daily_day = case when p_daily then today else nx_arcade_best.daily_day end,
    daily_best = case when not p_daily then nx_arcade_best.daily_best
                      when nx_arcade_best.daily_day = today then greatest(nx_arcade_best.daily_best, p_score)
                      else p_score end,
    plays = nx_arcade_best.plays + 1,
    last_submit = now()
  returning * into b;
  -- mirror into the per-game stats used by the generic leaderboard / profile
  insert into nx_game_stats(user_id, game, played, won, lost, draw, rating, best)
  values (me, p_game, 1, 0, 0, 0, 1000, p_score)
  on conflict (user_id, game) do update set played = nx_game_stats.played + 1,
    best = greatest(nx_game_stats.best, excluded.best), updated_at = now();
  select count(*) + 1 into r from nx_arcade_best x where x.game = p_game and x.best > b.best;
  return jsonb_build_object('ok', true, 'best', b.best, 'rank', r, 'daily_best', b.daily_best);
end $function$;

create or replace function public.nx_arcade_top(p_game text, p_daily boolean default false, p_limit integer default 50)
returns table(user_id uuid, username text, avatar text, score integer, plays integer, at timestamptz)
language sql stable security definer set search_path to 'public' as $$
  select b.user_id, p.username, p.avatar,
         case when p_daily then b.daily_best else b.best end as score, b.plays, b.best_at
    from nx_arcade_best b join profiles p on p.id = b.user_id
   where b.game = p_game
     and (case when p_daily then b.daily_day = (now() at time zone 'utc')::date and b.daily_best > 0 else b.best > 0 end)
   order by 4 desc, b.best_at asc
   limit greatest(1, least(coalesce(p_limit, 50), 100))
$$;

grant execute on function public.nx_arcade_submit(text, integer, integer, boolean, jsonb) to authenticated;
grant execute on function public.nx_arcade_top(text, boolean, integer) to authenticated, anon;
grant execute on function public.nx_known_game(text) to authenticated;
