-- NEXORA cups (tournament system v3, Flutter app) -- 2026-11-15
-- Single elimination for 2..64 players (byes when not a power of 2, standard seeding after a random draw),
-- every pairing is a series of N games (creator's choice, 1..9), 5-digit join code, check-in in the last
-- 15 minutes, waitlist players replace absentees in the last 5 minutes, prize (0..100 gems) escrowed from the
-- creator at creation and paid to places 1-3 exactly once when the final (and 3rd-place match) is done.
-- Everything is server-authoritative: clients only call the cup_* RPCs below; cup_tick() runs every 10 s
-- (pg_cron job 'nexora-cups') and a trigger on matches records every finished game of a cup series.
-- Idempotent: safe to run again.

-- ------------------------------------------------------------------ config (one place)
create or replace function public.cup_cfg() returns jsonb language sql immutable as $$
  select '{"lineup_s":3,"gap_s":12,"checkin_min":15,"replace_min":5,"noshow_min":5,"remind_min":15,
           "game_min":6,"buffer_min":4,"max_players":64,"max_prize":100,"max_games":9,"presence_s":45}'::jsonb $$;
create or replace function public._cupc(k text) returns int language sql immutable as $$ select (public.cup_cfg()->>k)::int $$;

-- ------------------------------------------------------------------ tables
create table if not exists public.cups (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[1-9][0-9]{4}$'),
  name text not null check (char_length(name) between 3 and 40),
  created_by uuid not null references public.profiles(id) on delete cascade,
  max_players int not null check (max_players between 2 and 64),
  games int not null default 1 check (games between 1 and 9),
  goals int not null default 3 check (goals between 1 and 10),
  starts_at timestamptz not null,
  status text not null default 'registration' check (status in ('registration','running','finished','cancelled')),
  prize int not null default 0 check (prize between 0 and 100),
  split int[] not null default '{60,30,10}',
  escrow int not null default 0,
  prize_paid boolean not null default false,
  bracket_size int, rounds int,
  reminded boolean not null default false,
  draw_at timestamptz, finished_at timestamptz, cancelled_reason text,
  created_at timestamptz not null default now()
);
create index if not exists cups_status_idx on public.cups(status, starts_at);

create table if not exists public.cup_players (
  cup_id uuid not null references public.cups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'main' check (status in ('main','wait','out')),
  joined_at timestamptz not null default clock_timestamp(),
  checked_in_at timestamptz,
  seed int, final_place int, eliminated boolean not null default false,
  note text,
  primary key (cup_id, user_id)
);
create index if not exists cup_players_user_idx on public.cup_players(user_id);

create table if not exists public.cup_matches (
  id uuid primary key default gen_random_uuid(),
  cup_id uuid not null references public.cups(id) on delete cascade,
  kind text not null default 'main' check (kind in ('main','third')),
  round int not null, idx int not null,
  p1 uuid references public.profiles(id), p2 uuid references public.profiles(id),
  wins1 int not null default 0, wins2 int not null default 0,
  goals1 int not null default 0, goals2 int not null default 0,
  games_played int not null default 0,
  winner uuid, loser uuid,
  status text not null default 'pending' check (status in ('pending','ready','live','done','bye')),
  walkover boolean not null default false,
  scheduled_at timestamptz, ready_at timestamptz, wait_from timestamptz, lineup_until timestamptz,
  room_id uuid references public.rooms(id) on delete set null,
  next_match uuid, next_slot smallint, loser_next uuid, loser_slot smallint,
  reminded boolean not null default false,
  finished_at timestamptz,
  unique (cup_id, kind, round, idx)
);
create index if not exists cup_matches_cup_idx on public.cup_matches(cup_id);
create index if not exists cup_matches_open_idx on public.cup_matches(status) where status in ('pending','ready','live');

create table if not exists public.cup_games (
  match_id uuid not null references public.cup_matches(id) on delete cascade,
  game_no int not null,
  match_ref uuid not null unique,              -- public.matches.id, a finished game counts once
  g1 int not null, g2 int not null, winner uuid,
  created_at timestamptz not null default now(),
  primary key (match_id, game_no)
);

-- every gem movement of a cup; the unique index makes each payout / refund happen at most once
create table if not exists public.cup_ledger (
  id bigserial primary key,
  cup_id uuid not null references public.cups(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  kind text not null check (kind in ('escrow','prize','refund')),
  place int not null default 0,
  gems int not null,
  created_at timestamptz not null default now()
);
create unique index if not exists cup_ledger_once on public.cup_ledger(cup_id, kind, place);

alter table public.rooms add column if not exists cup_match_id uuid;

alter table public.cups enable row level security;
alter table public.cup_players enable row level security;
alter table public.cup_matches enable row level security;
alter table public.cup_games enable row level security;
alter table public.cup_ledger enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename='cups' and policyname='cups read') then
    create policy "cups read" on public.cups for select using (true);
    create policy "cup_players read" on public.cup_players for select using (true);
    create policy "cup_matches read" on public.cup_matches for select using (true);
    create policy "cup_games read" on public.cup_games for select using (true);
    create policy "cup_ledger read" on public.cup_ledger for select using (true);
  end if;
end $$;
grant select on public.cups, public.cup_players, public.cup_matches, public.cup_games, public.cup_ledger to anon, authenticated;
revoke insert, update, delete on public.cups, public.cup_players, public.cup_matches, public.cup_games, public.cup_ledger from anon, authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.cups; exception when others then null; end;
  begin alter publication supabase_realtime add table public.cup_players; exception when others then null; end;
  begin alter publication supabase_realtime add table public.cup_matches; exception when others then null; end;
end $$;

-- ------------------------------------------------------------------ pure helpers (mirrored in lib/online/cup_logic.dart)
-- series result: 1 / 2 = that side won the series, 0 = play another game.
-- Clinched when the lead is bigger than the games left; after N games a tie on wins goes to goal difference,
-- then sudden-death decider games; after N+3 games the higher seed (side 1) advances.
create or replace function public._cup_series_winner(n int, w1 int, w2 int, g1 int, g2 int, played int)
returns int language plpgsql immutable as $$
declare rem int := greatest(n - played, 0); begin
  if w1 > w2 + rem then return 1; end if;
  if w2 > w1 + rem then return 2; end if;
  if played >= n then
    if g1 > g2 then return 1; end if;
    if g2 > g1 then return 2; end if;
    if played >= n + 3 then return 1; end if;
  end if;
  return 0; end $$;

-- seeds in bracket order (1, size, ... standard): pairs (o[2i-1], o[2i]) meet in round 1
create or replace function public._cup_seed_order(size int) returns int[] language plpgsql immutable as $$
declare o int[] := '{1,2}'; nx int[]; s int; l int; begin
  if size < 2 then return '{1}'; end if;
  while array_length(o,1) < size loop
    l := array_length(o,1); nx := '{}';
    foreach s in array o loop nx := nx || s || (2*l + 1 - s); end loop;
    o := nx;
  end loop;
  return o; end $$;

-- prize shares for places 1..3 (floor, remainder to 1st)
create or replace function public._cup_shares(p int, sp int[]) returns int[] language plpgsql immutable as $$
declare a int[] := array[floor(p*sp[1]/100.0)::int, floor(p*sp[2]/100.0)::int, floor(p*sp[3]/100.0)::int]; begin
  a[1] := a[1] + (p - a[1] - a[2] - a[3]);
  return a; end $$;

create or replace function public._cup_slot_min(games int) returns int language sql immutable as $$
  select games * public._cupc('game_min') + public._cupc('buffer_min') $$;

-- ------------------------------------------------------------------ RPCs: registration
create or replace function public.cup_now() returns timestamptz language sql stable as $$ select now() $$;

create or replace function public.cup_create(p_name text, p_max int, p_games int, p_goals int, p_starts timestamptz,
  p_prize int default 0, p_split int[] default '{60,30,10}', p_join boolean default true)
returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; cd text; sp int[] := coalesce(p_split, '{60,30,10}'); begin
  if uid is null then raise exception 'not signed in'; end if;
  if char_length(trim(coalesce(p_name,''))) < 3 then raise exception 'title required'; end if;
  if p_max is null or p_max < 2 or p_max > _cupc('max_players') then raise exception 'bad size'; end if;
  if p_games is null or p_games < 1 or p_games > _cupc('max_games') then raise exception 'bad format'; end if;
  if p_goals is null or p_goals < 1 or p_goals > 10 then raise exception 'bad format'; end if;
  if p_starts is null or p_starts < now() + interval '2 minutes' or p_starts > now() + interval '60 days' then raise exception 'bad start time'; end if;
  if p_prize is null or p_prize < 0 or p_prize > _cupc('max_prize') then raise exception 'bad prize'; end if;
  if coalesce(array_length(sp,1),0) <> 3 or sp[1] < sp[2] or sp[2] < sp[3] or sp[3] < 0 or sp[1]+sp[2]+sp[3] <> 100 then raise exception 'bad split'; end if;
  if (select count(*) from cups where created_by = uid and status in ('registration','running')) >= 3 then raise exception 'too many open tournaments'; end if;
  if p_prize > 0 then
    update profiles set gems = gems - p_prize where id = uid and gems >= p_prize;
    if not found then raise exception 'not enough gems'; end if;
  end if;
  loop
    cd := (10000 + floor(random()*90000))::int::text;
    exit when not exists (select 1 from cups where code = cd);
  end loop;
  insert into cups(code, name, created_by, max_players, games, goals, starts_at, prize, split, escrow)
    values (cd, trim(p_name), uid, p_max, p_games, p_goals, date_trunc('minute', p_starts), p_prize, sp, p_prize) returning * into c;
  if p_prize > 0 then insert into cup_ledger(cup_id, user_id, kind, place, gems) values (c.id, uid, 'escrow', 0, -p_prize); end if;
  if coalesce(p_join, true) then insert into cup_players(cup_id, user_id, status) values (c.id, uid, 'main'); end if;
  return c; end $$;

-- promote waitlisters into free main slots; inside the last replace_min minutes only checked-in waitlisters move
-- up, and while registration is full they replace main players who have not checked in (latest joiner first).
create or replace function public._cup_fill(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare c cups; w cup_players; a cup_players; late boolean; n int; begin
  select * into c from cups where id = p_cup;
  if c.status <> 'registration' then return; end if;
  late := now() >= c.starts_at - make_interval(mins => _cupc('replace_min'));
  loop
    select count(*) into n from cup_players where cup_id = p_cup and status = 'main';
    exit when n >= c.max_players;
    select * into w from cup_players where cup_id = p_cup and status = 'wait' and (not late or checked_in_at is not null) order by joined_at limit 1;
    exit when w.user_id is null;
    update cup_players set status = 'main' where cup_id = p_cup and user_id = w.user_id;
    perform _notify(w.user_id, 'cup_promoted', 'از صف وارد «' || c.name || '» شدی ✅', null, jsonb_build_object('cup', c.id));
  end loop;
  if not late then return; end if;
  loop
    select * into w from cup_players where cup_id = p_cup and status = 'wait' and checked_in_at is not null order by joined_at limit 1;
    exit when w.user_id is null;
    select * into a from cup_players where cup_id = p_cup and status = 'main' and checked_in_at is null order by joined_at desc limit 1;
    exit when a.user_id is null;
    update cup_players set status = 'out', note = 'replaced' where cup_id = p_cup and user_id = a.user_id;
    update cup_players set status = 'main' where cup_id = p_cup and user_id = w.user_id;
    perform _notify(a.user_id, 'cup_out', 'جایت در «' || c.name || '» به نفر صف رسید', 'اعلام حضور نکرده بودی', jsonb_build_object('cup', c.id));
    perform _notify(w.user_id, 'cup_promoted', 'از صف وارد «' || c.name || '» شدی ✅', 'جای یک غایب را گرفتی', jsonb_build_object('cup', c.id));
  end loop;
end $$;

create or replace function public.cup_join(p_code text) returns public.cups language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; st text; n int; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into c from cups where code = trim(p_code) for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if exists (select 1 from cup_players where cup_id = c.id and user_id = uid and status in ('main','wait')) then return c; end if;
  if c.status <> 'registration' or now() >= c.starts_at then raise exception 'registration closed'; end if;
  select count(*) into n from cup_players where cup_id = c.id and status = 'main';
  st := case when n < c.max_players then 'main' else 'wait' end;
  insert into cup_players(cup_id, user_id, status) values (c.id, uid, st)
    on conflict (cup_id, user_id) do update set status = excluded.status, joined_at = clock_timestamp(), checked_in_at = null, note = null;
  return c; end $$;

create or replace function public.cup_leave(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; begin
  select * into c from cups where id = p_cup for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if c.status <> 'registration' then raise exception 'already started'; end if;
  delete from cup_players where cup_id = p_cup and user_id = uid;
  perform _cup_fill(p_cup);
end $$;

create or replace function public.cup_checkin(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c cups; begin
  select * into c from cups where id = p_cup for update;
  if c.id is null then raise exception 'tournament not found'; end if;
  if c.status <> 'registration' or now() >= c.starts_at then raise exception 'registration closed'; end if;
  if now() < c.starts_at - make_interval(mins => _cupc('checkin_min')) then raise exception 'check-in not open'; end if;
  update cup_players set checked_in_at = coalesce(checked_in_at, now()) where cup_id = p_cup and user_id = uid and status in ('main','wait');
  if not found then raise exception 'not registered'; end if;
  perform _cup_fill(p_cup);
end $$;

create or replace function public._cup_refund(p_cup uuid, p_reason text) returns void language plpgsql security definer set search_path = public as $$
declare c cups; begin
  select * into c from cups where id = p_cup for update;
  if c.status in ('finished','cancelled') then return; end if;
  if c.escrow > 0 then
    insert into cup_ledger(cup_id, user_id, kind, place, gems) values (c.id, c.created_by, 'refund', 0, c.escrow) on conflict do nothing;
    if found then update profiles set gems = gems + c.escrow where id = c.created_by; end if;
  end if;
  update cups set status = 'cancelled', escrow = 0, cancelled_reason = p_reason, finished_at = now() where id = p_cup;
  insert into notifications(user_id, kind, title, body, data)
    select user_id, 'cup_cancel', '«' || c.name || '» لغو شد', p_reason, jsonb_build_object('cup', c.id) from cup_players where cup_id = p_cup;
end $$;

create or replace function public.cup_cancel(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare c cups; begin
  select * into c from cups where id = p_cup;
  if c.id is null then raise exception 'tournament not found'; end if;
  if c.created_by <> auth.uid() then raise exception 'organizer only'; end if;
  if c.status <> 'registration' then raise exception 'already started'; end if;
  perform _cup_refund(p_cup, 'برگزارکننده تورنمنت را لغو کرد');
end $$;

-- ------------------------------------------------------------------ bracket
create or replace function public._cup_check_ready(p_m uuid) returns void language plpgsql security definer set search_path = public as $$
declare m cup_matches; c cups; begin
  select * into m from cup_matches where id = p_m for update;
  if m.status <> 'pending' or m.p1 is null or m.p2 is null or now() < m.scheduled_at then return; end if;
  update cup_matches set status = 'ready', ready_at = now(), wait_from = now() where id = p_m;
  select * into c from cups where id = m.cup_id;
  perform _notify(u, 'cup_ready', 'مسابقه‌ات در «' || c.name || '» آماده است ⚽', 'همین حالا وارد شو؛ ' || _cupc('noshow_min') || ' دقیقه فرصت داری',
                  jsonb_build_object('cup', c.id, 'match', m.id)) from unnest(array[m.p1, m.p2]) u;
end $$;

create or replace function public._cup_place(p_m uuid, p_slot int, p_user uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  if p_m is null or p_user is null then return; end if;
  if p_slot = 1 then update cup_matches set p1 = p_user where id = p_m; else update cup_matches set p2 = p_user where id = p_m; end if;
  perform _cup_check_ready(p_m);
end $$;

-- third-place match: when both semis are over and one side has no loser (a bye semi), the other loser takes 3rd
create or replace function public._cup_third_check(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare t cup_matches; open_semis int; begin
  select * into t from cup_matches where cup_id = p_cup and kind = 'third' for update;
  if t.id is null or t.status <> 'pending' then return; end if;
  select count(*) into open_semis from cup_matches where loser_next = t.id and status not in ('done','bye');
  if open_semis > 0 or (t.p1 is not null and t.p2 is not null) then return; end if;
  perform _cup_advance(t.id, coalesce(t.p1, t.p2), null, false);
end $$;

create or replace function public._cup_finish(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare c cups; sh int[]; pl int; u uuid; begin
  select * into c from cups where id = p_cup for update;
  if c.status <> 'running' then return; end if;
  if exists (select 1 from cup_matches where cup_id = p_cup and status not in ('done','bye')) then return; end if;
  if not c.prize_paid and c.prize > 0 then
    sh := _cup_shares(c.prize, c.split);
    for pl in 1..3 loop
      continue when sh[pl] <= 0;
      select user_id into u from cup_players where cup_id = p_cup and final_place = pl limit 1;
      if u is not null then
        insert into cup_ledger(cup_id, user_id, kind, place, gems) values (p_cup, u, 'prize', pl, sh[pl]) on conflict do nothing;
        if found then
          update profiles set gems = gems + sh[pl] where id = u;
          perform _notify(u, 'cup_prize', '💎 ' || sh[pl] || ' الماس جایزه‌ی «' || c.name || '»', 'مقام ' || pl, jsonb_build_object('cup', c.id, 'place', pl));
        end if;
      else  -- nobody at this place (e.g. only 2 players): the share goes back to the creator
        insert into cup_ledger(cup_id, user_id, kind, place, gems) values (p_cup, c.created_by, 'refund', pl, sh[pl]) on conflict do nothing;
        if found then update profiles set gems = gems + sh[pl] where id = c.created_by; end if;
      end if;
    end loop;
  end if;
  update cups set status = 'finished', prize_paid = true, escrow = 0, finished_at = now() where id = p_cup;
  insert into notifications(user_id, kind, title, body, data)
    select user_id, 'cup_done', '«' || c.name || '» تمام شد 🏆', case when final_place between 1 and 3 then 'مقام ' || final_place else null end,
           jsonb_build_object('cup', c.id) from cup_players where cup_id = p_cup and status = 'main';
end $$;

create or replace function public._cup_advance(p_m uuid, p_win uuid, p_lose uuid, p_walkover boolean) returns void language plpgsql security definer set search_path = public as $$
declare m cup_matches; c cups; begin
  select * into m from cup_matches where id = p_m for update;
  if m.status in ('done','bye') then return; end if;
  update cup_matches set status = case when p_lose is null and (m.p1 is null or m.p2 is null) then 'bye' else 'done' end,
    winner = p_win, loser = p_lose, walkover = p_walkover, finished_at = now(), lineup_until = null where id = p_m;
  select * into c from cups where id = m.cup_id;
  if p_lose is not null then update cup_players set eliminated = true where cup_id = m.cup_id and user_id = p_lose; end if;
  if m.kind = 'third' then
    update cup_players set final_place = 3 where cup_id = m.cup_id and user_id = p_win;
    if p_lose is not null then update cup_players set final_place = 4 where cup_id = m.cup_id and user_id = p_lose; end if;
  elsif m.next_match is null then  -- the final
    update cup_players set final_place = 1 where cup_id = m.cup_id and user_id = p_win;
    if p_lose is not null then update cup_players set final_place = 2 where cup_id = m.cup_id and user_id = p_lose; end if;
  else
    perform _cup_place(m.next_match, m.next_slot, p_win);
  end if;
  if m.loser_next is not null then
    perform _cup_place(m.loser_next, m.loser_slot, p_lose);
    perform _cup_third_check(m.cup_id);
  end if;
  if p_walkover and p_lose is not null then
    perform _notify(p_lose, 'cup_out', 'در «' || c.name || '» با غیبت باختی', 'در زمان مقرر وارد مسابقه نشدی', jsonb_build_object('cup', c.id));
  end if;
  perform _cup_finish(m.cup_id);
end $$;

create or replace function public._cup_draw(p_cup uuid) returns void language plpgsql security definer set search_path = public as $$
declare c cups; pl uuid[]; n int; size int := 2; r int; nr int := 1; i int; o int[]; mid uuid; slot int; s1 int; s2 int; third uuid; begin
  select * into c from cups where id = p_cup for update;
  if c.status <> 'registration' then return; end if;
  perform _cup_fill(p_cup);
  update cup_players set status = 'out', note = 'no check-in' where cup_id = p_cup and status = 'main' and checked_in_at is null;
  select coalesce(array_agg(user_id order by random()), '{}') into pl from cup_players where cup_id = p_cup and status = 'main';
  n := coalesce(array_length(pl, 1), 0);
  if n < 2 then perform _cup_refund(p_cup, 'کمتر از ۲ بازیکن اعلام حضور کردند'); return; end if;
  while size < n loop size := size * 2; nr := nr + 1; end loop;
  for i in 1..n loop update cup_players set seed = i where cup_id = p_cup and user_id = pl[i]; end loop;
  for r in 1..nr loop
    for i in 1..(size >> r) loop
      insert into cup_matches(cup_id, kind, round, idx, scheduled_at, reminded)
        values (p_cup, 'main', r, i, c.starts_at + make_interval(mins => (r - 1) * _cup_slot_min(c.games)), r = 1);
    end loop;
  end loop;
  update cup_matches m set next_match = n2.id, next_slot = (2 - (m.idx % 2))::smallint
    from cup_matches n2 where m.cup_id = p_cup and n2.cup_id = p_cup and m.kind = 'main' and n2.kind = 'main'
      and n2.round = m.round + 1 and n2.idx = (m.idx + 1) / 2;
  if size >= 4 then
    insert into cup_matches(cup_id, kind, round, idx, scheduled_at)
      values (p_cup, 'third', nr, 1, c.starts_at + make_interval(mins => (nr - 1) * _cup_slot_min(c.games))) returning id into third;
    update cup_matches set loser_next = third, loser_slot = idx::smallint where cup_id = p_cup and kind = 'main' and round = nr - 1;
  end if;
  update cups set status = 'running', draw_at = now(), bracket_size = size, rounds = nr where id = p_cup;
  update cup_players set status = 'out', note = 'waitlist' where cup_id = p_cup and status = 'wait';
  o := _cup_seed_order(size);
  for i in 1..(size / 2) loop
    s1 := o[2*i - 1]; s2 := o[2*i];
    select id into mid from cup_matches where cup_id = p_cup and kind = 'main' and round = 1 and idx = i;
    update cup_matches set p1 = case when s1 <= n then pl[s1] end, p2 = case when s2 <= n then pl[s2] end where id = mid;
  end loop;
  insert into notifications(user_id, kind, title, body, data)
    select user_id, 'cup_draw', 'قرعه‌کشی «' || c.name || '» انجام شد 🎲', 'براکت را ببین؛ بازی‌ها خودکار شروع می‌شوند', jsonb_build_object('cup', c.id)
    from cup_players where cup_id = p_cup and status = 'main';
  -- byes first, then the real round-1 pairings become ready
  for mid in select id from cup_matches where cup_id = p_cup and kind = 'main' and round = 1 order by idx loop
    perform _cup_advance(mid, p1, null, false) from cup_matches where id = mid and (p1 is null or p2 is null);
    perform _cup_check_ready(mid);
  end loop;
end $$;

-- ------------------------------------------------------------------ playing a pairing
create or replace function public._cup_present(p_room uuid, p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from room_players where room_id = p_room and user_id = p_user and role = 'player'
                 and last_seen > now() - make_interval(secs => public._cupc('presence_s'))) $$;

-- start the next game of a pairing when both players sit in the room and the lineup window is over
create or replace function public._cup_try_start(p_m uuid) returns void language plpgsql security definer set search_path = public as $$
declare m cup_matches; r rooms; begin
  select * into m from cup_matches where id = p_m for update;
  if m.status not in ('ready','live') or m.room_id is null then return; end if;
  select * into r from rooms where id = m.room_id;
  if r.id is null or r.status <> 'waiting' then return; end if;
  if not (_cup_present(r.id, m.p1) and _cup_present(r.id, m.p2)) then
    if m.lineup_until is not null then update cup_matches set lineup_until = null where id = p_m; end if;
    return;
  end if;
  if m.lineup_until is null then
    update cup_matches set lineup_until = now() + make_interval(secs => _cupc('lineup_s')) where id = p_m; return;
  end if;
  if now() < m.lineup_until then return; end if;
  begin
    perform set_config('nexora.cup_start', '1', true);
    perform _start_match(r.id, false);
    perform set_config('nexora.cup_start', '', true);
  exception when others then
    perform set_config('nexora.cup_start', '', true);
    return;   -- seats not complete yet; the next call / tick retries
  end;
  update cup_matches set status = 'live', lineup_until = null, wait_from = now() where id = p_m;
end $$;

create or replace function public.cup_enter(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m cup_matches; c cups; r rooms; side smallint; begin
  if uid is null then raise exception 'not signed in'; end if;
  select * into m from cup_matches where id = p_match for update;
  if m.id is null then raise exception 'match not ready'; end if;
  if uid = m.p1 then side := 0; elsif uid = m.p2 then side := 1; else raise exception 'not in this match'; end if;
  if m.status not in ('ready','live') then raise exception 'match not ready'; end if;
  select * into c from cups where id = m.cup_id;
  select * into r from rooms where id = m.room_id;
  if r.id is null or r.status = 'finished' then
    perform leave_all_rooms();
    insert into rooms(code, name, host, mode, is_private, ranked, voice, settings, kind, cup_match_id)
      values (_gen_code(), left(c.name || ' · ' || case when m.kind = 'third' then 'رده‌بندی' when m.next_match is null then 'فینال' else 'دور ' || m.round end, 60),
              uid, '1v1', true, false, true,
              jsonb_build_object('goals', c.goals, 'win', c.goals, 'time', 0, 'turn', 15, 'shots', 0, 'field', 0, 'formations', true, 'cup', c.id),
              'tournament', m.id) returning * into r;
    update cup_matches set room_id = r.id where id = m.id;
  elsif not exists (select 1 from room_players where room_id = r.id and user_id = uid) then
    perform leave_all_rooms();
  end if;
  insert into room_players(room_id, user_id, role, team, slot, ready, last_seen) values (r.id, uid, 'player', side, 0, true, now())
    on conflict (room_id, user_id) do update set role = 'player', team = excluded.team, slot = 0, ready = true, last_seen = now();
  update rooms set updated_at = now() where id = r.id;
  perform _cup_try_start(m.id);
  select * into r from rooms where id = r.id;
  select * into m from cup_matches where id = m.id;
  return jsonb_build_object('room', to_jsonb(r), 'now', now(), 'lineup_until', m.lineup_until, 'status', m.status);
end $$;

create or replace function public.cup_kick(p_match uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m cup_matches; begin
  select * into m from cup_matches where id = p_match;
  if m.id is null or uid is null or uid not in (m.p1, m.p2) then raise exception 'not in this match'; end if;
  update room_players set last_seen = now() where room_id = m.room_id and user_id = uid;
  perform _cup_try_start(p_match);
  select * into m from cup_matches where id = p_match;
  return jsonb_build_object('now', now(), 'lineup_until', m.lineup_until, 'status', m.status, 'games_played', m.games_played);
end $$;

-- every finished online game whose room belongs to a cup pairing counts once for the series
create or replace function public._cup_on_match() returns trigger language plpgsql security definer set search_path = public as $$
declare mid uuid; m cup_matches; c cups; flip boolean; g1 int; g2 int; w int; begin
  if new.status = old.status or new.status = 'live' then return new; end if;
  select cup_match_id into mid from rooms where id = new.room_id;
  if mid is null then return new; end if;
  if new.bots then return new; end if;   -- never count a bot game (the insert guard below blocks them anyway)
  if new.status = 'abandoned' then   -- a dropped game is replayed; the no-show clock restarts now
    update cup_matches set wait_from = now(), lineup_until = null where id = mid and status in ('ready','live');
    return new;
  end if;
  select * into m from cup_matches where id = mid for update;
  if m.status not in ('ready','live') then return new; end if;
  flip := coalesce(new.team_a[1] = m.p2, false);
  g1 := coalesce(case when flip then new.score_b else new.score_a end, 0);
  g2 := coalesce(case when flip then new.score_a else new.score_b end, 0);
  insert into cup_games(match_id, game_no, match_ref, g1, g2, winner)
    values (mid, m.games_played + 1, new.id, g1, g2, case when g1 > g2 then m.p1 when g2 > g1 then m.p2 end) on conflict do nothing;
  if not found then return new; end if;
  update cup_matches set games_played = games_played + 1, wins1 = wins1 + (g1 > g2)::int, wins2 = wins2 + (g2 > g1)::int,
    goals1 = goals1 + g1, goals2 = goals2 + g2, wait_from = now(),
    lineup_until = now() + make_interval(secs => _cupc('gap_s') + _cupc('lineup_s')) where id = mid returning * into m;
  select * into c from cups where id = m.cup_id;
  w := _cup_series_winner(c.games, m.wins1, m.wins2, m.goals1, m.goals2, m.games_played);
  if w = 1 then perform _cup_advance(mid, m.p1, m.p2, false);
  elsif w = 2 then perform _cup_advance(mid, m.p2, m.p1, false); end if;
  return new;
end $$;
-- games in a cup room start only through _cup_try_start (lineup window, both players seated): a host pressing
-- start / rematch in the room cannot start one early or against bots.
create or replace function public._cup_guard_match_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.room_id is not null and exists (select 1 from rooms where id = new.room_id and cup_match_id is not null)
     and coalesce(current_setting('nexora.cup_start', true), '') <> '1' then
    raise exception 'match not ready';
  end if;
  return new; end $$;
drop trigger if exists trg_cup_guard_match_insert on public.matches;
create trigger trg_cup_guard_match_insert before insert on public.matches for each row execute function public._cup_guard_match_insert();

drop trigger if exists trg_cup_match on public.matches;
create trigger trg_cup_match after update of status on public.matches for each row execute function public._cup_on_match();

-- ------------------------------------------------------------------ the clock (pg_cron, every 10 s)
create or replace function public.cup_tick() returns void language plpgsql security definer set search_path = public as $$
declare c record; m record; p1 boolean; p2 boolean; w uuid; l uuid; begin
  if not pg_try_advisory_xact_lock(hashtext('nexora-cup-tick')) then return; end if;
  -- 15 min before start: reminder + check-in opens
  for c in select * from cups where status = 'registration' and not reminded and now() >= starts_at - make_interval(mins => _cupc('remind_min')) loop
    update cups set reminded = true where id = c.id;
    insert into notifications(user_id, kind, title, body, data)
      select user_id, 'cup_soon', '⏰ «' || c.name || '» ساعت ' || to_char(c.starts_at at time zone 'Asia/Tehran', 'HH24:MI') || ' شروع می‌شود',
             'اعلام حضور کن؛ بدون اعلام حضور از قرعه‌کشی حذف می‌شوی', jsonb_build_object('cup', c.id)
      from cup_players where cup_id = c.id and status in ('main','wait');
  end loop;
  -- last 5 min: waitlist replaces absentees
  for c in select id from cups where status = 'registration' and now() >= starts_at - make_interval(mins => _cupc('replace_min')) and now() < starts_at loop
    begin perform _cup_fill(c.id); exception when others then raise warning 'cup_fill %: %', c.id, sqlerrm; end;
  end loop;
  -- start time: draw
  for c in select id from cups where status = 'registration' and now() >= starts_at order by starts_at loop
    begin perform _cup_draw(c.id); exception when others then raise warning 'cup_draw %: %', c.id, sqlerrm; end;
  end loop;
  -- pairings: reminders, readiness, game starts, no-shows
  for m in select cm.* from cup_matches cm join cups cc on cc.id = cm.cup_id where cc.status = 'running' and cm.status in ('pending','ready','live') loop
   begin
    if m.status = 'pending' then
      if not m.reminded and m.p1 is not null and m.p2 is not null and now() >= m.scheduled_at - make_interval(mins => _cupc('remind_min')) then
        update cup_matches set reminded = true where id = m.id;
        perform _notify(u, 'cup_match_soon', '⏰ مسابقه‌ی بعدی‌ات ساعت ' || to_char(greatest(m.scheduled_at, now()) at time zone 'Asia/Tehran', 'HH24:MI'),
                        'آماده باش؛ مسابقه خودکار شروع می‌شود', jsonb_build_object('cup', m.cup_id, 'match', m.id)) from unnest(array[m.p1, m.p2]) u;
      end if;
      perform _cup_check_ready(m.id);
      continue;
    end if;
    perform _cup_try_start(m.id);
    if exists (select 1 from rooms where id = m.room_id and status = 'playing') then continue; end if;
    if m.wait_from is null or now() < m.wait_from + make_interval(mins => _cupc('noshow_min')) then continue; end if;
    p1 := m.room_id is not null and _cup_present(m.room_id, m.p1);
    p2 := m.room_id is not null and _cup_present(m.room_id, m.p2);
    if p1 and p2 then continue; end if;
    if p1 then w := m.p1; l := m.p2;
    elsif p2 then w := m.p2; l := m.p1;
    elsif m.wins2 > m.wins1 or (m.wins2 = m.wins1 and m.goals2 > m.goals1) then w := m.p2; l := m.p1;
    else w := m.p1; l := m.p2; end if;
    perform _cup_advance(m.id, w, l, true);
   exception when others then raise warning 'cup match %: %', m.id, sqlerrm;
   end;
  end loop;
end $$;

-- ------------------------------------------------------------------ grants + schedule
revoke execute on function public._cup_fill(uuid), public._cup_refund(uuid, text), public._cup_check_ready(uuid), public._cup_place(uuid, int, uuid),
  public._cup_third_check(uuid), public._cup_finish(uuid), public._cup_advance(uuid, uuid, uuid, boolean), public._cup_draw(uuid),
  public._cup_present(uuid, uuid), public._cup_try_start(uuid), public.cup_tick() from public, anon, authenticated;
grant execute on function public.cup_create(text, int, int, int, timestamptz, int, int[], boolean), public.cup_join(text), public.cup_leave(uuid),
  public.cup_checkin(uuid), public.cup_cancel(uuid), public.cup_enter(uuid), public.cup_kick(uuid), public.cup_now(), public.cup_cfg() to authenticated;

do $$ begin
  perform cron.unschedule('nexora-cups') where exists (select 1 from cron.job where jobname = 'nexora-cups');
  perform cron.schedule('nexora-cups', '10 seconds', 'select public.cup_tick()');
end $$;
