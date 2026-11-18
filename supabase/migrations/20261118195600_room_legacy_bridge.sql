-- Keep the shipped Flutter lobby compatible while routing membership through the
-- conversation-first room tables.
create or replace function public.nx_create_room(p_game text, p_seats int, p_private boolean, p_quick boolean default false, p_settings jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); b record; s int; rid uuid; c text;
begin
 if me is null then raise exception 'not signed in'; end if;
 if p_game not in('finger_soccer','carrom','billiards','backgammon','ludo','snakes_ladders','uno','quiz','mafia') then raise exception 'unknown game'; end if;
 select * into b from nx_game_bounds(p_game); s:=greatest(b.min_seats,least(coalesce(p_seats,b.min_seats),case when p_game in('finger_soccer','carrom') then 6 else b.max_seats end));
 perform _nx_leave_all(me); c:=nx_gen_code();
 insert into nx_rooms(code,game,host,seats,is_private,quick,settings,selected_game) values(c,p_game,me,s,coalesce(p_private,false),coalesce(p_quick,false),coalesce(p_settings,'{}'::jsonb),p_game) returning id into rid;
 insert into nx_room_players(room_id,user_id,seat,ready) values(rid,me,0,true);
 insert into nx_room_members(room_id,user_id,role) values(rid,me,'manager') on conflict(room_id,user_id) do update set role='manager',last_seen=now();
 insert into nx_room_game_players(room_id,user_id,seat,team,ready) values(rid,me,0,0,true) on conflict(room_id,user_id) do update set ready=true;
 return jsonb_build_object('room_id',rid,'code',c,'seats',s,'speaker_capacity',30,'spectator_capacity',20);
end $$;

create or replace function public.nx_join_room(p_code text default null,p_room uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare me uuid:=auth.uid(); rid uuid; r nx_rooms; joined jsonb; seat_no int;
begin
 if me is null then raise exception 'not signed in'; end if;
 if p_room is not null then rid:=p_room; else select id into rid from nx_rooms where code=upper(trim(p_code)); end if;
 if rid is null then raise exception 'room not found'; end if;
 select * into r from nx_rooms where id=rid for update;
 joined:=nx_room_join(rid,'speaker');
 seat_no:=nullif(joined->>'seat','')::int;
 if seat_no is not null and not exists(select 1 from nx_room_players where room_id=rid and user_id=me) then
   insert into nx_room_players(room_id,user_id,seat,ready) values(rid,me,seat_no,false) on conflict(room_id,user_id) do update set last_seen=now();
 end if;
 update nx_room_members set last_seen=now() where room_id=rid and user_id=me;
 return jsonb_build_object('room_id',rid,'code',r.code,'seat',seat_no,'role',joined->>'role','status',r.status,'match_id',r.match_id,'rejoined',coalesce((joined->>'rejoined')::boolean,false));
end $$;

grant execute on function public.nx_create_room(text,int,boolean,boolean,jsonb),public.nx_join_room(text,uuid) to authenticated;
