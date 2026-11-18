-- NEXORA conversation-first rooms: 30 speakers + 20 spectators, with a
-- separate six-player game selection layer. Existing nx_room_players remains
-- the legacy active-seat projection for compatibility with older match flows.

alter table public.nx_rooms
  add column if not exists speaker_capacity int not null default 30,
  add column if not exists spectator_capacity int not null default 20,
  add column if not exists selected_game text,
  add column if not exists selected_seats int[] not null default '{}';

update public.nx_rooms
   set speaker_capacity = 30,
       spectator_capacity = 20,
       selected_game = coalesce(selected_game, game)
 where speaker_capacity is null or spectator_capacity is null or selected_game is null;

create table if not exists public.nx_room_members (
  room_id uuid not null references public.nx_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('manager','speaker','spectator')),
  joined_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  muted boolean not null default false,
  primary key (room_id, user_id)
);
create index if not exists nx_room_members_room_role
  on public.nx_room_members(room_id, role, joined_at);
create index if not exists nx_room_members_user
  on public.nx_room_members(user_id, last_seen desc);

create table if not exists public.nx_room_game_players (
  room_id uuid not null references public.nx_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seat int not null check (seat between 0 and 5),
  team int not null default 0 check (team between 0 and 2),
  ready boolean not null default false,
  selected_at timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, seat)
);
create index if not exists nx_room_game_players_room
  on public.nx_room_game_players(room_id, seat);

create table if not exists public.nx_room_messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.nx_rooms(id) on delete cascade,
  author uuid not null references auth.users(id) on delete cascade,
  text text not null check (char_length(btrim(text)) between 1 and 4000),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted boolean not null default false
);
create index if not exists nx_room_messages_room_time
  on public.nx_room_messages(room_id, created_at desc);

alter table public.nx_room_members enable row level security;
alter table public.nx_room_game_players enable row level security;
alter table public.nx_room_messages enable row level security;

drop policy if exists nx_room_members_read on public.nx_room_members;
create policy nx_room_members_read on public.nx_room_members for select
using (exists (select 1 from public.nx_room_members me
               where me.room_id = nx_room_members.room_id and me.user_id = auth.uid()));
drop policy if exists nx_room_players_read on public.nx_room_game_players;
create policy nx_room_players_read on public.nx_room_game_players for select
using (exists (select 1 from public.nx_room_members me
               where me.room_id = nx_room_game_players.room_id and me.user_id = auth.uid()));
drop policy if exists nx_room_messages_read on public.nx_room_messages;
create policy nx_room_messages_read on public.nx_room_messages for select
using (exists (select 1 from public.nx_room_members me
               where me.room_id = nx_room_messages.room_id and me.user_id = auth.uid()));

create or replace function public.nx_room_member_role(p_room uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.nx_room_members
   where room_id = p_room and user_id = auth.uid()
$$;

create or replace function public.nx_room_join(p_room uuid, p_role text default 'speaker')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid(); r public.nx_rooms; role_to_use text; total int; speakers int; spectators int;
  seat_no int; game_limit int;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into r from public.nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status = 'closed' then raise exception 'room closed'; end if;
  if exists (select 1 from public.nx_room_members where room_id=p_room and user_id=me) then
    update public.nx_room_members set last_seen=now() where room_id=p_room and user_id=me;
    return jsonb_build_object('room_id',p_room,'role',public.nx_room_member_role(p_room),'rejoined',true);
  end if;
  select count(*) into total from public.nx_room_members where room_id=p_room;
  if total >= coalesce(r.speaker_capacity,30)+coalesce(r.spectator_capacity,20) then raise exception 'room full'; end if;
  select count(*) into speakers from public.nx_room_members where room_id=p_room and role in ('manager','speaker');
  select count(*) into spectators from public.nx_room_members where room_id=p_room and role='spectator';
  if p_role = 'spectator' and spectators < coalesce(r.spectator_capacity,20) then role_to_use := 'spectator';
  elsif speakers < coalesce(r.speaker_capacity,30) then role_to_use := case when p_role='spectator' then 'speaker' else 'speaker' end;
  elsif spectators < coalesce(r.spectator_capacity,20) then role_to_use := 'spectator';
  else raise exception 'room full'; end if;
  insert into public.nx_room_members(room_id,user_id,role) values (p_room,me,role_to_use);
  -- Preserve the old active-seat projection while there is a free game seat.
  game_limit := least(coalesce(r.seats, 6), 6);
  select min(g) into seat_no from generate_series(0, least(game_limit,6)-1) g
    where not exists (select 1 from public.nx_room_game_players where room_id=p_room and seat=g)
      and not exists (select 1 from public.nx_room_players where room_id=p_room and seat=g);
  if role_to_use='speaker' and seat_no is not null and seat_no < 6 then
    insert into public.nx_room_game_players(room_id,user_id,seat,team)
      values (p_room,me,seat_no,seat_no/2);
  end if;
  update public.nx_rooms set updated_at=now() where id=p_room;
  return jsonb_build_object('room_id',p_room,'role',role_to_use,'seat',seat_no,'status',r.status);
end $$;

create or replace function public.nx_room_leave(p_room uuid)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  delete from public.nx_room_game_players where room_id=p_room and user_id=me;
  delete from public.nx_room_players where room_id=p_room and user_id=me;
  delete from public.nx_room_members where room_id=p_room and user_id=me;
  update public.nx_rooms set updated_at=now() where id=p_room;
end $$;

create or replace function public.nx_room_set_role(p_room uuid, p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); speakers int; spectators int;
begin
  if public.nx_room_member_role(p_room) <> 'manager' then raise exception 'manager only'; end if;
  if p_role not in ('speaker','spectator') then raise exception 'bad role'; end if;
  select count(*) into speakers from public.nx_room_members where room_id=p_room and role in ('manager','speaker');
  select count(*) into spectators from public.nx_room_members where room_id=p_room and role='spectator';
  if p_role='speaker' and speakers >= 30 then raise exception 'speaker capacity reached'; end if;
  if p_role='spectator' and spectators >= 20 then raise exception 'spectator capacity reached'; end if;
  update public.nx_room_members set role=p_role,last_seen=now()
   where room_id=p_room and user_id=p_user and p_user <> me;
  if not found then raise exception 'member not found'; end if;
end $$;

create or replace function public.nx_room_change_game(p_room uuid, p_game text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.nx_room_member_role(p_room) <> 'manager' then raise exception 'manager only'; end if;
  if p_game not in ('finger_soccer','carrom','billiards','backgammon','ludo','snakes_ladders','uno','quiz','mafia') then raise exception 'unknown game'; end if;
  update public.nx_rooms set game=p_game, selected_game=p_game, selected_seats='{}', updated_at=now()
   where id=p_room and status='lobby';
  if not found then raise exception 'room already started'; end if;
  delete from public.nx_room_game_players where room_id=p_room;
end $$;

create or replace function public.nx_room_select_players(p_room uuid, p_users uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n int; i int; uid uuid; g public.nx_rooms;
begin
  if public.nx_room_member_role(p_room) <> 'manager' then raise exception 'manager only'; end if;
  select * into g from public.nx_rooms where id=p_room for update;
  if g.id is null then raise exception 'room not found'; end if;
  if g.game not in ('finger_soccer','carrom') and cardinality(coalesce(p_users,'{}')) > 2 then raise exception 'game supports at most 2 players'; end if;
  if cardinality(coalesce(p_users,'{}')) > 6 then raise exception 'at most six players'; end if;
  if exists (select 1 from unnest(coalesce(p_users,'{}')) u where not exists (select 1 from public.nx_room_members m where m.room_id=p_room and m.user_id=u)) then raise exception 'all players must be room members'; end if;
  delete from public.nx_room_game_players where room_id=p_room;
  i := 0;
  foreach uid in array coalesce(p_users,'{}') loop
    insert into public.nx_room_game_players(room_id,user_id,seat,team) values(p_room,uid,i,i/2);
    i := i+1;
  end loop;
  update public.nx_rooms set selected_seats=coalesce((select array_agg(seat order by seat) from public.nx_room_game_players where room_id=p_room),'{}'), updated_at=now() where id=p_room;
  return jsonb_build_object('selected',i);
end $$;

create or replace function public.nx_room_send_message(p_room uuid, p_text text)
returns public.nx_room_messages language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); out_msg public.nx_room_messages;
begin
  if me is null or public.nx_room_member_role(p_room) is null then raise exception 'not a room member'; end if;
  insert into public.nx_room_messages(room_id,author,text) values(p_room,me,btrim(p_text)) returning * into out_msg;
  update public.nx_room_members set last_seen=now() where room_id=p_room and user_id=me;
  update public.nx_rooms set updated_at=now() where id=p_room;
  return out_msg;
end $$;

grant execute on function public.nx_room_member_role(uuid), public.nx_room_join(uuid,text), public.nx_room_leave(uuid), public.nx_room_set_role(uuid,uuid,text), public.nx_room_change_game(uuid,text), public.nx_room_select_players(uuid,uuid[]), public.nx_room_send_message(uuid,text) to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.nx_room_members; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_room_game_players; exception when others then null; end;
  begin alter publication supabase_realtime add table public.nx_room_messages; exception when others then null; end;
end $$;

-- Existing host rows become manager members, without duplicating users.
insert into public.nx_room_members(room_id,user_id,role)
select r.id,r.host,'manager' from public.nx_rooms r
 where exists (select 1 from auth.users u where u.id=r.host)
on conflict (room_id,user_id) do update set role='manager';
