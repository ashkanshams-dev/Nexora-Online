-- NEXORA online backend schema (v1)
create extension if not exists pgcrypto;

-- ============ LEAGUES / LEVEL ============
create table public.leagues (
  id text primary key, name_fa text not null, min_rating int not null, color text not null, sort int not null
);
insert into public.leagues values
 ('bronze','برنز',0,'#c07a43',1),('silver','نقره',1100,'#b9c3cf',2),('gold','طلا',1250,'#f4c542',3),
 ('platinum','پلاتین',1400,'#5ee0d6',4),('diamond','الماس',1600,'#6fa8ff',5),('master','استاد',1800,'#b06bff',6),
 ('legend','افسانه',2050,'#ff4d7d',7);

create or replace function public.level_for_xp(x int) returns int language sql immutable as
$$ select greatest(1, floor(sqrt(greatest(x,0)/100.0))::int + 1) $$;
create or replace function public.xp_for_level(l int) returns int language sql immutable as
$$ select ((greatest(l,1)-1)*(greatest(l,1)-1)*100) $$;
create or replace function public.league_for_rating(r int) returns text language sql stable as
$$ select id from public.leagues where min_rating <= r order by min_rating desc limit 1 $$;

-- ============ PROFILES ============
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 20),
  avatar text not null default 'elite00',
  xp int not null default 0,
  level int not null default 1,
  coins int not null default 500,
  gems int not null default 20,
  rating int not null default 1000,
  league text not null default 'bronze' references public.leagues(id),
  wins int not null default 0, losses int not null default 0, draws int not null default 0,
  goals int not null default 0, trophies int not null default 0,
  is_guest boolean not null default true,
  online_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare n text; begin
  n := coalesce(nullif(new.raw_user_meta_data->>'username',''), 'Pilot' || lpad((floor(random()*99999))::text,5,'0'));
  while exists(select 1 from profiles where username = n) loop n := 'Pilot' || lpad((floor(random()*99999))::text,5,'0'); end loop;
  insert into profiles(id, username, is_guest) values (new.id, n, coalesce(new.is_anonymous, false));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.handle_user_upgrade() returns trigger language plpgsql security definer set search_path = public as $$
begin update profiles set is_guest = coalesce(new.is_anonymous,false) where id = new.id; return new; end $$;
create trigger on_auth_user_updated after update of is_anonymous on auth.users for each row execute function public.handle_user_upgrade();

-- ============ ROOMS ============
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null default 'اتاق',
  host uuid not null references public.profiles(id) on delete cascade,
  mode text not null check (mode in ('1v1','2v2','3v3')),
  status text not null default 'waiting' check (status in ('waiting','playing','finished')),
  is_private boolean not null default false,
  ranked boolean not null default true,
  voice boolean not null default true,
  settings jsonb not null default '{"goals":3,"time":180,"field":0}'::jsonb,
  tournament_match_id uuid,
  current_match uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.room_players (
  room_id uuid references public.rooms(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'player' check (role in ('player','spectator')),
  team smallint check (team in (0,1)),
  slot smallint,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);
create index on public.room_players(user_id);

create or replace function public.room_size(m text) returns int language sql immutable as
$$ select case m when '1v1' then 1 when '2v2' then 2 else 3 end $$;

-- ============ MATCHES ============
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms(id) on delete set null,
  mode text not null,
  team_a uuid[] not null, team_b uuid[] not null,
  score_a int, score_b int,
  winner smallint, -- 0 team A, 1 team B, -1 draw
  ranked boolean not null default true,
  tournament_id uuid,
  tournament_match_id uuid,
  status text not null default 'live' check (status in ('live','done','abandoned')),
  duration_s int,
  started_at timestamptz not null default now(),
  ended_at timestamptz
);
create index on public.matches using gin(team_a);
create index on public.matches using gin(team_b);

create table public.xp_events (
  id bigserial primary key, user_id uuid references public.profiles(id) on delete cascade,
  amount int not null, reason text not null, ref uuid, created_at timestamptz not null default now()
);

-- ============ TOURNAMENTS ============
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  format text not null check (format in ('single_elim','double_elim','round_robin','swiss','league')),
  mode text not null default '1v1' check (mode in ('1v1','2v2','3v3')),
  max_entries int not null default 8 check (max_entries between 2 and 64),
  rounds int, -- swiss rounds / league legs
  status text not null default 'registration' check (status in ('registration','running','finished')),
  created_by uuid references public.profiles(id) on delete set null,
  prize_xp int not null default 500, prize_coins int not null default 1000,
  min_level int not null default 1,
  winner_entry uuid,
  current_round int not null default 0,
  starts_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.tournament_entries (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  captain uuid not null references public.profiles(id) on delete cascade,
  team_name text not null,
  members uuid[] not null,
  seed int,
  points int not null default 0, played int not null default 0,
  wins int not null default 0, draws int not null default 0, losses int not null default 0,
  gf int not null default 0, ga int not null default 0,
  lb_losses int not null default 0,
  eliminated boolean not null default false,
  final_rank int,
  unique (tournament_id, captain)
);
create table public.tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  bracket text not null default 'main' check (bracket in ('main','winners','losers','final')),
  round int not null, idx int not null,
  entry_a uuid references public.tournament_entries(id) on delete set null,
  entry_b uuid references public.tournament_entries(id) on delete set null,
  score_a int, score_b int,
  winner_entry uuid,
  status text not null default 'pending' check (status in ('pending','ready','live','done','bye')),
  room_id uuid,
  next_match uuid, next_slot smallint,
  loser_next uuid, loser_slot smallint,
  unique (tournament_id, bracket, round, idx)
);

-- ============ RLS ============
alter table public.leagues enable row level security;
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.matches enable row level security;
alter table public.xp_events enable row level security;
alter table public.tournaments enable row level security;
alter table public.tournament_entries enable row level security;
alter table public.tournament_matches enable row level security;

create policy "read" on public.leagues for select using (true);
create policy "read" on public.profiles for select to authenticated using (true);
create policy "update self" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "read" on public.rooms for select to authenticated using (not is_private or exists(select 1 from public.room_players p where p.room_id = id and p.user_id = auth.uid()) or host = auth.uid());
create policy "read" on public.room_players for select to authenticated using (true);
create policy "read" on public.matches for select to authenticated using (true);
create policy "read own" on public.xp_events for select to authenticated using (user_id = auth.uid());
create policy "read" on public.tournaments for select to authenticated using (true);
create policy "read" on public.tournament_entries for select to authenticated using (true);
create policy "read" on public.tournament_matches for select to authenticated using (true);

-- profiles: users may only change cosmetic columns
revoke update on public.profiles from authenticated, anon;
grant update (username, avatar, online_at) on public.profiles to authenticated;
revoke insert, update, delete on public.rooms, public.room_players, public.matches, public.xp_events,
  public.tournaments, public.tournament_entries, public.tournament_matches, public.leagues from authenticated, anon;

-- ============ ROOM RPCs ============
create or replace function public._gen_code() returns text language plpgsql as $$
declare c text; begin
  loop c := upper(substr(translate(encode(extensions.gen_random_bytes(6),'base64'),'+/=0OIl1','XYZ23456'),1,6));
    exit when not exists(select 1 from public.rooms where code = c); end loop; return c; end $$;

create or replace function public._autoseat(r public.rooms, uid uuid) returns void language plpgsql security definer set search_path=public as $$
declare n int := room_size(r.mode); t smallint; s smallint; begin
  for t in 0..1 loop
    for s in 0..n-1 loop
      if not exists(select 1 from room_players where room_id=r.id and role='player' and team=t and slot=s) then
        update room_players set role='player', team=t, slot=s, ready=false where room_id=r.id and user_id=uid; return; end if;
    end loop;
  end loop;
  update room_players set role='spectator', team=null, slot=null, ready=false where room_id=r.id and user_id=uid;
end $$;

create or replace function public.leave_all_rooms() returns void language plpgsql security definer set search_path=public as $$
declare r record; begin
  for r in select rp.room_id from room_players rp where rp.user_id = auth.uid() loop
    perform public.leave_room(r.room_id);
  end loop; end $$;

create or replace function public.create_room(p_mode text, p_name text default null, p_private boolean default false,
  p_ranked boolean default true, p_voice boolean default true, p_settings jsonb default null)
returns public.rooms language plpgsql security definer set search_path=public as $$
declare r rooms; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  perform leave_all_rooms();
  insert into rooms(code,name,host,mode,is_private,ranked,voice,settings)
  values (_gen_code(), coalesce(nullif(trim(p_name),''),'اتاق '||p_mode), auth.uid(), p_mode, p_private, p_ranked, p_voice,
          coalesce(p_settings,'{"goals":3,"time":180,"field":0}'::jsonb)) returning * into r;
  insert into room_players(room_id,user_id,role,team,slot) values (r.id, auth.uid(),'player',0,0);
  return r; end $$;

create or replace function public.join_room(p_code text default null, p_room uuid default null, p_spectate boolean default false)
returns public.rooms language plpgsql security definer set search_path=public as $$
declare r rooms; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select * into r from rooms where (p_room is not null and id=p_room) or (p_code is not null and code=upper(trim(p_code))) limit 1;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status='finished' then raise exception 'room closed'; end if;
  if exists(select 1 from room_players where room_id=r.id and user_id=auth.uid()) then return r; end if;
  perform leave_all_rooms();
  insert into room_players(room_id,user_id,role) values (r.id, auth.uid(),'spectator');
  if not p_spectate and r.status='waiting' then perform _autoseat(r, auth.uid()); end if;
  update rooms set updated_at=now() where id=r.id;
  return r; end $$;

create or replace function public.quick_match(p_mode text) returns public.rooms language plpgsql security definer set search_path=public as $$
declare rid uuid; r rooms; begin
  select ro.id into rid from rooms ro where ro.mode=p_mode and ro.status='waiting' and not ro.is_private and ro.ranked
    and ro.tournament_match_id is null
    and (select count(*) from room_players p where p.room_id=ro.id and p.role='player') < room_size(ro.mode)*2
    and ro.updated_at > now() - interval '15 minutes'
  order by (select count(*) from room_players p where p.room_id=ro.id and p.role='player') desc, ro.created_at limit 1;
  if rid is null then return create_room(p_mode, null, false, true, true, null); end if;
  return join_room(null, rid, false); end $$;

create or replace function public.leave_room(p_room uuid) returns void language plpgsql security definer set search_path=public as $$
declare r rooms; nh uuid; begin
  delete from room_players where room_id=p_room and user_id=auth.uid();
  select * into r from rooms where id=p_room; if r.id is null then return; end if;
  if not exists(select 1 from room_players where room_id=p_room) then delete from rooms where id=p_room; return; end if;
  if r.host = auth.uid() then
    select user_id into nh from room_players where room_id=p_room order by (role='player') desc, joined_at limit 1;
    update rooms set host=nh, updated_at=now() where id=p_room;
  else update rooms set updated_at=now() where id=p_room; end if;
end $$;

create or replace function public.take_seat(p_room uuid, p_team smallint, p_slot smallint) returns void language plpgsql security definer set search_path=public as $$
declare r rooms; begin
  select * into r from rooms where id=p_room;
  if r.status<>'waiting' then raise exception 'match running'; end if;
  if p_slot<0 or p_slot>=room_size(r.mode) then raise exception 'bad slot'; end if;
  if exists(select 1 from room_players where room_id=p_room and team=p_team and slot=p_slot and role='player' and user_id<>auth.uid()) then raise exception 'seat taken'; end if;
  update room_players set role='player', team=p_team, slot=p_slot, ready=false where room_id=p_room and user_id=auth.uid();
  update rooms set updated_at=now() where id=p_room; end $$;

create or replace function public.spectate(p_room uuid) returns void language plpgsql security definer set search_path=public as $$
begin update room_players set role='spectator', team=null, slot=null, ready=false where room_id=p_room and user_id=auth.uid(); end $$;

create or replace function public.set_ready(p_room uuid, p_ready boolean) returns void language plpgsql security definer set search_path=public as $$
begin update room_players set ready=p_ready where room_id=p_room and user_id=auth.uid() and role='player';
  update rooms set updated_at=now() where id=p_room; end $$;

create or replace function public.update_room(p_room uuid, p_settings jsonb, p_name text default null) returns void language plpgsql security definer set search_path=public as $$
begin update rooms set settings=coalesce(p_settings,settings), name=coalesce(nullif(trim(p_name),''),name), updated_at=now()
  where id=p_room and host=auth.uid() and status='waiting'; end $$;

create or replace function public.kick(p_room uuid, p_user uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not exists(select 1 from rooms where id=p_room and host=auth.uid()) then raise exception 'host only'; end if;
  delete from room_players where room_id=p_room and user_id=p_user and p_user<>auth.uid(); end $$;

create or replace function public.start_match(p_room uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare r rooms; n int; a uuid[]; b uuid[]; mid uuid; tm tournament_matches; begin
  select * into r from rooms where id=p_room for update;
  if r.host<>auth.uid() then raise exception 'host only'; end if;
  if r.status<>'waiting' then raise exception 'already started'; end if;
  n := room_size(r.mode);
  select array_agg(user_id order by slot) into a from room_players where room_id=p_room and role='player' and team=0;
  select array_agg(user_id order by slot) into b from room_players where room_id=p_room and role='player' and team=1;
  if coalesce(array_length(a,1),0)<>n or coalesce(array_length(b,1),0)<>n then raise exception 'teams not full'; end if;
  if exists(select 1 from room_players where room_id=p_room and role='player' and not ready and user_id<>r.host) then raise exception 'not all ready'; end if;
  if r.tournament_match_id is not null then select * into tm from tournament_matches where id=r.tournament_match_id; end if;
  insert into matches(room_id,mode,team_a,team_b,ranked,tournament_id,tournament_match_id)
    values (p_room,r.mode,a,b,r.ranked,tm.tournament_id,r.tournament_match_id) returning id into mid;
  update rooms set status='playing', current_match=mid, updated_at=now() where id=p_room;
  if tm.id is not null then update tournament_matches set status='live' where id=tm.id; end if;
  return mid; end $$;

-- ============ XP / RESULTS ============
create or replace function public._grant(uid uuid, p_xp int, p_coins int, p_rating int, p_result int, p_goals int, p_reason text, p_ref uuid)
returns void language plpgsql security definer set search_path=public as $$
declare nx int; begin
  update profiles set xp = xp + p_xp, coins = coins + p_coins, rating = greatest(0, rating + p_rating),
    wins = wins + (p_result=1)::int, losses = losses + (p_result=-1)::int, draws = draws + (p_result=0 and p_reason like 'match%')::int,
    goals = goals + p_goals
  where id = uid returning xp into nx;
  update profiles set level = level_for_xp(nx), league = league_for_rating(rating) where id = uid;
  if p_xp<>0 then insert into xp_events(user_id,amount,reason,ref) values (uid,p_xp,p_reason,p_ref); end if;
end $$;

create or replace function public.report_match(p_match uuid, p_score_a int, p_score_b int, p_duration int default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m matches; r rooms; w smallint; u uuid; ra int; rb int; ex numeric; k int := 32; d int; res int; i int; begin
  select * into m from matches where id=p_match for update;
  if m.id is null or m.status<>'live' then raise exception 'match not live'; end if;
  select * into r from rooms where id=m.room_id;
  if r.host<>auth.uid() then raise exception 'host only'; end if;
  w := case when p_score_a>p_score_b then 0 when p_score_b>p_score_a then 1 else -1 end;
  select avg(rating)::int into ra from profiles where id = any(m.team_a);
  select avg(rating)::int into rb from profiles where id = any(m.team_b);
  ex := 1/(1+power(10,(rb-ra)/400.0));
  d := round(k*((case w when 0 then 1 when 1 then 0 else 0.5 end) - ex));
  update matches set score_a=p_score_a, score_b=p_score_b, winner=w, status='done', ended_at=now(),
    duration_s=coalesce(p_duration, extract(epoch from now()-started_at)::int) where id=p_match;
  foreach u in array m.team_a loop
    res := case w when 0 then 1 when 1 then -1 else 0 end;
    perform _grant(u, 40 + res*30 + 10 + p_score_a*5, 50 + (res=1)::int*100, case when m.ranked then d else 0 end, res, 0, 'match', p_match);
  end loop;
  foreach u in array m.team_b loop
    res := case w when 1 then 1 when 0 then -1 else 0 end;
    perform _grant(u, 40 + res*30 + 10 + p_score_b*5, 50 + (res=1)::int*100, case when m.ranked then -d else 0 end, res, 0, 'match', p_match);
  end loop;
  if m.tournament_match_id is not null then perform _tm_result(m.tournament_match_id, p_score_a, p_score_b); end if;
  update rooms set status='waiting', current_match=null, updated_at=now() where id=m.room_id;
  update room_players set ready=false where room_id=m.room_id;
  return jsonb_build_object('winner',w,'rating_delta',d); end $$;

create or replace function public.abandon_match(p_match uuid) returns void language plpgsql security definer set search_path=public as $$
declare m matches; begin select * into m from matches where id=p_match;
  if not exists(select 1 from rooms where id=m.room_id and host=auth.uid()) then raise exception 'host only'; end if;
  update matches set status='abandoned', ended_at=now() where id=p_match and status='live';
  update rooms set status='waiting', current_match=null, updated_at=now() where id=m.room_id; end $$;

-- ============ TOURNAMENT ENGINE ============
create or replace function public.create_tournament(p_name text, p_format text, p_mode text default '1v1', p_max int default 8,
  p_rounds int default null, p_prize_xp int default 500, p_prize_coins int default 1000, p_starts timestamptz default null)
returns public.tournaments language plpgsql security definer set search_path=public as $$
declare t tournaments; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  insert into tournaments(name,format,mode,max_entries,rounds,created_by,prize_xp,prize_coins,starts_at)
  values (p_name,p_format,p_mode,p_max,p_rounds,auth.uid(),least(p_prize_xp,2000),least(p_prize_coins,5000),p_starts) returning * into t;
  return t; end $$;

create or replace function public.join_tournament(p_tid uuid, p_team_name text default null, p_members uuid[] default null)
returns public.tournament_entries language plpgsql security definer set search_path=public as $$
declare t tournaments; e tournament_entries; nm text; begin
  select * into t from tournaments where id=p_tid;
  if t.status<>'registration' then raise exception 'registration closed'; end if;
  if (select count(*) from tournament_entries where tournament_id=p_tid) >= t.max_entries then raise exception 'full'; end if;
  select username into nm from profiles where id=auth.uid();
  insert into tournament_entries(tournament_id,captain,team_name,members)
  values (p_tid, auth.uid(), coalesce(nullif(trim(p_team_name),''), nm), coalesce(p_members, array[auth.uid()])) returning * into e;
  return e; end $$;

create or replace function public.leave_tournament(p_tid uuid) returns void language plpgsql security definer set search_path=public as $$
begin delete from tournament_entries where tournament_id=p_tid and captain=auth.uid()
  and exists(select 1 from tournaments where id=p_tid and status='registration'); end $$;

-- place an entry into a slot of a match; resolves byes
create or replace function public._tm_place(p_match uuid, p_slot smallint, p_entry uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if p_match is null then return; end if;
  if p_slot=0 then update tournament_matches set entry_a=p_entry where id=p_match;
  else update tournament_matches set entry_b=p_entry where id=p_match; end if;
  update tournament_matches set status='ready' where id=p_match and entry_a is not null and entry_b is not null and status='pending';
end $$;


create or replace function public._resolve_byes(p_tid uuid) returns void language plpgsql security definer set search_path=public as $$
declare m record; changed boolean := true; feeders int; fin int; e uuid; guard int := 0; begin
  while changed and guard < 200 loop
    changed := false; guard := guard+1;
    for m in select * from tournament_matches where tournament_id=p_tid and status='pending' loop
      select count(*), count(*) filter (where status in ('done','bye')) into feeders, fin
        from tournament_matches where next_match=m.id or loser_next=m.id;
      if feeders>0 and feeders=fin and (m.entry_a is null or m.entry_b is null) then
        e := coalesce(m.entry_a, m.entry_b);
        update tournament_matches set status='bye', winner_entry=e where id=m.id;
        if e is not null then perform _tm_place(m.next_match, m.next_slot, e);
          if m.next_match is null then perform _finish_tournament(p_tid, e); end if; end if;
        changed := true;
      end if;
    end loop;
  end loop; end $$;

create or replace function public._rr_schedule(p_tid uuid, ids uuid[], legs int) returns void language plpgsql security definer set search_path=public as $$
declare n int; arr uuid[]; rnd int; i int; a uuid; b uuid; leg int; idx int; total_r int; begin
  arr := ids; if array_length(arr,1) % 2 = 1 then arr := arr || array[null::uuid]; end if;
  n := array_length(arr,1); total_r := n-1;
  for leg in 0..legs-1 loop
    for rnd in 0..total_r-1 loop
      idx := 0;
      for i in 0..(n/2)-1 loop
        a := arr[i+1]; b := arr[n-i];
        if a is not null and b is not null then
          if leg % 2 = 1 then insert into tournament_matches(tournament_id,bracket,round,idx,entry_a,entry_b,status) values (p_tid,'main',leg*total_r+rnd+1,idx,b,a,'ready');
          else insert into tournament_matches(tournament_id,bracket,round,idx,entry_a,entry_b,status) values (p_tid,'main',leg*total_r+rnd+1,idx,a,b,'ready'); end if;
          idx := idx+1;
        end if;
      end loop;
      arr := array[arr[1]] || array[arr[n]] || arr[2:n-1];
    end loop;
  end loop; end $$;

create or replace function public._swiss_round(p_tid uuid, p_round int) returns void language plpgsql security definer set search_path=public as $$
declare ids uuid[]; i int := 1; idx int := 0; a uuid; b uuid; used uuid[] := '{}'; j int; begin
  select array_agg(id order by points desc, (gf-ga) desc, seed) into ids from tournament_entries where tournament_id=p_tid;
  while i <= array_length(ids,1) loop
    a := ids[i];
    if a = any(used) then i := i+1; continue; end if;
    b := null;
    for j in i+1..array_length(ids,1) loop
      if not ids[j] = any(used) and not exists(select 1 from tournament_matches where tournament_id=p_tid and
         ((entry_a=a and entry_b=ids[j]) or (entry_a=ids[j] and entry_b=a))) then b := ids[j]; exit; end if;
    end loop;
    if b is null then for j in i+1..array_length(ids,1) loop if not ids[j] = any(used) then b := ids[j]; exit; end if; end loop; end if;
    used := used || a;
    if b is null then
      insert into tournament_matches(tournament_id,bracket,round,idx,entry_a,status,winner_entry) values (p_tid,'main',p_round,idx,a,'bye',a);
      update tournament_entries set points=points+3, wins=wins+1, played=played+1 where id=a;
    else used := used || b;
      insert into tournament_matches(tournament_id,bracket,round,idx,entry_a,entry_b,status) values (p_tid,'main',p_round,idx,a,b,'ready'); end if;
    idx := idx+1; i := i+1;
  end loop;
  update tournaments set current_round=p_round where id=p_tid; end $$;

create or replace function public.start_tournament(p_tid uuid) returns void language plpgsql security definer set search_path=public as $$
declare t tournaments; ids uuid[]; n int; size int := 2; rounds int; r int; i int; mid uuid; nxt uuid; m record; begin
  select * into t from tournaments where id=p_tid for update;
  if t.created_by<>auth.uid() then raise exception 'organizer only'; end if;
  if t.status<>'registration' then raise exception 'already started'; end if;
  select array_agg(id order by random()) into ids from tournament_entries where tournament_id=p_tid;
  n := coalesce(array_length(ids,1),0);
  if n < 2 then raise exception 'need at least 2 entries'; end if;
  if t.format='double_elim' and n<=2 then update tournaments set format='single_elim' where id=p_tid; t.format:='single_elim'; end if;
  for i in 1..n loop update tournament_entries set seed=i where id=ids[i]; end loop;
  update tournaments set status='running', starts_at=coalesce(starts_at,now()) where id=p_tid;

  if t.format in ('round_robin','league') then
    perform _rr_schedule(p_tid, ids, case when t.format='league' then greatest(coalesce(t.rounds,2),1) else 1 end);
    update tournaments set current_round=1 where id=p_tid; return;
  elsif t.format='swiss' then
    update tournaments set rounds=coalesce(t.rounds, ceil(ln(n)/ln(2))::int) where id=p_tid;
    perform _swiss_round(p_tid, 1); return;
  end if;

  -- elimination brackets
  while size < n loop size := size*2; end loop;
  rounds := round(ln(size)/ln(2));
  for r in 1..rounds loop
    for i in 0..(size / (2^r)::int)-1 loop
      insert into tournament_matches(tournament_id,bracket,round,idx) values (p_tid, case when t.format='double_elim' then 'winners' else 'main' end, r, i);
    end loop;
  end loop;
  for m in select * from tournament_matches where tournament_id=p_tid and round<rounds loop
    select id into nxt from tournament_matches where tournament_id=p_tid and bracket=m.bracket and round=m.round+1 and idx=m.idx/2;
    update tournament_matches set next_match=nxt, next_slot=(m.idx%2) where id=m.id;
  end loop;
  if t.format='double_elim' then
    -- losers bracket: 2*(rounds-1) rounds, then grand final
    for r in 1..greatest(2*(rounds-1),0) loop
      for i in 0..greatest((size/(2^(((r+1)/2)+1))::int)-1,0) loop
        insert into tournament_matches(tournament_id,bracket,round,idx) values (p_tid,'losers',r,i);
      end loop;
    end loop;
    insert into tournament_matches(tournament_id,bracket,round,idx) values (p_tid,'final',1,0);
    -- wire losers bracket forward
    for m in select * from tournament_matches where tournament_id=p_tid and bracket='losers' loop
      if m.round = 2*(rounds-1) then select id into nxt from tournament_matches where tournament_id=p_tid and bracket='final';
        update tournament_matches set next_match=nxt, next_slot=1 where id=m.id;
      elsif m.round % 2 = 1 then select id into nxt from tournament_matches where tournament_id=p_tid and bracket='losers' and round=m.round+1 and idx=m.idx;
        update tournament_matches set next_match=nxt, next_slot=0 where id=m.id;
      else select id into nxt from tournament_matches where tournament_id=p_tid and bracket='losers' and round=m.round+1 and idx=m.idx/2;
        update tournament_matches set next_match=nxt, next_slot=(m.idx%2) where id=m.id; end if;
    end loop;
    -- winners bracket losers drop
    for m in select * from tournament_matches where tournament_id=p_tid and bracket='winners' loop
      if m.round=1 then select id into nxt from tournament_matches where tournament_id=p_tid and bracket='losers' and round=1 and idx=m.idx/2;
        update tournament_matches set loser_next=nxt, loser_slot=(m.idx%2) where id=m.id;
      elsif m.round=rounds then select id into nxt from tournament_matches where tournament_id=p_tid and bracket='final';
        update tournament_matches set next_match=nxt, next_slot=0 where id=m.id;
        select id into nxt from tournament_matches where tournament_id=p_tid and bracket='losers' and round=2*(rounds-1);
        update tournament_matches set loser_next=nxt, loser_slot=1 where id=m.id;
      else select id into nxt from tournament_matches where tournament_id=p_tid and bracket='losers' and round=2*(m.round-1) and idx=m.idx;
        update tournament_matches set loser_next=nxt, loser_slot=1 where id=m.id; end if;
    end loop;
  end if;
  -- seed round 1 (standard: entries 1..n, byes to top seeds)
  for i in 0..size/2-1 loop
    select id into mid from tournament_matches where tournament_id=p_tid and bracket in ('main','winners') and round=1 and idx=i;
    update tournament_matches set entry_a = ids[i*2+1], entry_b = case when i*2+2<=n then ids[i*2+2] end where id=mid;
  end loop;
  -- spread byes: if entry_b null -> auto-advance
  for m in select * from tournament_matches where tournament_id=p_tid and round=1 and bracket in ('main','winners') loop
    if m.entry_a is not null and m.entry_b is null then
      update tournament_matches set status='bye', winner_entry=m.entry_a where id=m.id;
      perform _tm_place(m.next_match, m.next_slot, m.entry_a);
    elsif m.entry_a is not null and m.entry_b is not null then update tournament_matches set status='ready' where id=m.id;
    elsif m.entry_a is null and m.entry_b is null then update tournament_matches set status='bye' where id=m.id;
    end if;
  end loop;
  perform _resolve_byes(p_tid);
  update tournaments set current_round=1 where id=p_tid;
end $$;

create or replace function public._finish_tournament(p_tid uuid, p_winner uuid) returns void language plpgsql security definer set search_path=public as $$
declare t tournaments; e record; rk int := 0; u uuid; begin
  select * into t from tournaments where id=p_tid;
  if p_winner is null then
    select id into p_winner from tournament_entries where tournament_id=p_tid order by points desc, (gf-ga) desc, gf desc limit 1;
    for e in select id from tournament_entries where tournament_id=p_tid order by points desc,(gf-ga) desc, gf desc loop
      rk := rk+1; update tournament_entries set final_rank=rk where id=e.id; end loop;
  else update tournament_entries set final_rank=1 where id=p_winner; end if;
  update tournaments set status='finished', winner_entry=p_winner where id=p_tid;
  foreach u in array (select members from tournament_entries where id=p_winner) loop
    perform _grant(u, t.prize_xp, t.prize_coins, 25, 2, 0, 'tournament', p_tid);
    update profiles set trophies=trophies+1 where id=u;
  end loop;
end $$;

create or replace function public._tm_result(p_tm uuid, sa int, sb int) returns void language plpgsql security definer set search_path=public as $$
declare tm tournament_matches; t tournaments; win uuid; los uuid; pending int; begin
  select * into tm from tournament_matches where id=p_tm for update;
  select * into t from tournaments where id=tm.tournament_id;
  update tournament_matches set score_a=sa, score_b=sb, status='done' where id=p_tm;
  update tournament_entries set played=played+1, gf=gf+sa, ga=ga+sb, wins=wins+(sa>sb)::int, draws=draws+(sa=sb)::int, losses=losses+(sa<sb)::int,
    points=points+case when sa>sb then 3 when sa=sb then 1 else 0 end where id=tm.entry_a;
  update tournament_entries set played=played+1, gf=gf+sb, ga=ga+sa, wins=wins+(sb>sa)::int, draws=draws+(sa=sb)::int, losses=losses+(sb<sa)::int,
    points=points+case when sb>sa then 3 when sa=sb then 1 else 0 end where id=tm.entry_b;

  if t.format in ('round_robin','league','swiss') then
    if not exists(select 1 from tournament_matches where tournament_id=t.id and status in ('pending','ready','live')) then
      if t.format='swiss' and t.current_round < t.rounds then perform _swiss_round(t.id, t.current_round+1);
      else perform _finish_tournament(t.id, null); end if;
    end if; return;
  end if;

  -- knockout: draw → team A advances on tiebreak (higher seed); clients should use golden goal
  if sa>=sb then win:=tm.entry_a; los:=tm.entry_b; else win:=tm.entry_b; los:=tm.entry_a; end if;
  update tournament_matches set winner_entry=win where id=p_tm;
  if tm.bracket='final' then
    perform _finish_tournament(t.id, win); return; end if;
  if tm.loser_next is not null then perform _tm_place(tm.loser_next, tm.loser_slot, los); perform _resolve_byes(t.id);
  else update tournament_entries set eliminated=true where id=los; end if;
  if tm.next_match is null then perform _finish_tournament(t.id, win); return; end if;
  perform _tm_place(tm.next_match, tm.next_slot, win);
  perform _resolve_byes(t.id);
  update tournaments set current_round=greatest(current_round, tm.round+1) where id=t.id;
end $$;

-- organizer can force a result (e.g. no-show)
create or replace function public.set_tournament_result(p_tm uuid, p_sa int, p_sb int) returns void language plpgsql security definer set search_path=public as $$
declare tm tournament_matches; begin select * into tm from tournament_matches where id=p_tm;
  if not exists(select 1 from tournaments where id=tm.tournament_id and created_by=auth.uid()) then raise exception 'organizer only'; end if;
  if tm.status not in ('ready','live') then raise exception 'not playable'; end if;
  perform _tm_result(p_tm, p_sa, p_sb); end $$;

-- open a room for a tournament match (either side's captain)
create or replace function public.open_tournament_room(p_tm uuid) returns public.rooms language plpgsql security definer set search_path=public as $$
declare tm tournament_matches; t tournaments; r rooms; ea tournament_entries; eb tournament_entries; side smallint; begin
  select * into tm from tournament_matches where id=p_tm;
  select * into t from tournaments where id=tm.tournament_id;
  select * into ea from tournament_entries where id=tm.entry_a; select * into eb from tournament_entries where id=tm.entry_b;
  if auth.uid() = any(ea.members) then side:=0; elsif auth.uid() = any(eb.members) then side:=1; else raise exception 'not in this match'; end if;
  if tm.status not in ('ready','live') then raise exception 'match not ready'; end if;
  if tm.room_id is not null and exists(select 1 from rooms where id=tm.room_id) then
    r := join_room(null, tm.room_id, false); return r; end if;
  r := create_room(t.mode, t.name||' · '||ea.team_name||' vs '||eb.team_name, true, true, true, null);
  update rooms set tournament_match_id=p_tm where id=r.id;
  update tournament_matches set room_id=r.id where id=p_tm;
  if side=1 then update room_players set team=1 where room_id=r.id and user_id=auth.uid(); end if;
  select * into r from rooms where id=r.id; return r; end $$;

-- ============ VIEWS ============
create or replace view public.room_list with (security_invoker=on) as
select r.id, r.code, r.name, r.mode, r.status, r.is_private, r.ranked, r.voice, r.settings, r.created_at, r.host,
  h.username as host_name, h.avatar as host_avatar, h.level as host_level, h.league as host_league,
  (select count(*) from public.room_players p where p.room_id=r.id and p.role='player')::int as players,
  (select count(*) from public.room_players p where p.room_id=r.id and p.role='spectator')::int as spectators,
  public.room_size(r.mode)*2 as capacity
from public.rooms r join public.profiles h on h.id=r.host
where not r.is_private and r.updated_at > now() - interval '2 hours';

create or replace view public.leaderboard with (security_invoker=on) as
select id, username, avatar, level, xp, rating, league, wins, losses, draws, trophies,
  rank() over (order by rating desc, xp desc) as rank from public.profiles;

create or replace view public.standings with (security_invoker=on) as
select e.*, rank() over (partition by e.tournament_id order by e.points desc, (e.gf-e.ga) desc, e.gf desc) as pos
from public.tournament_entries e;

grant select on public.room_list, public.leaderboard, public.standings to authenticated;
grant execute on all functions in schema public to authenticated;
revoke execute on function public._grant, public._tm_result, public._tm_place, public._finish_tournament, public._rr_schedule,
  public._swiss_round, public._autoseat, public._gen_code, public._resolve_byes from authenticated, anon, public;

-- ============ REALTIME ============
alter publication supabase_realtime add table public.rooms, public.room_players, public.matches,
  public.tournaments, public.tournament_entries, public.tournament_matches, public.profiles;
