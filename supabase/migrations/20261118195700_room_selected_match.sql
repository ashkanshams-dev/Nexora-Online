create or replace function public.nx_start_room_match(p_room uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.nx_rooms; ids uuid[]; names text[]; mid uuid; seed_value bigint; n int;
begin
  if public.nx_room_member_role(p_room) <> 'manager' then raise exception 'manager only'; end if;
  select * into r from public.nx_rooms where id=p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.status='playing' and r.match_id is not null then return jsonb_build_object('match_id',r.match_id,'already',true); end if;
  select array_agg(g.user_id order by g.seat), array_agg(coalesce(p.username,'Pilot') order by g.seat), count(*)
    into ids,names,n
    from public.nx_room_game_players g left join public.profiles p on p.id=g.user_id where g.room_id=p_room;
  if n is null or n < 2 then raise exception 'need at least two selected players'; end if;
  if n > 6 then raise exception 'at most six players'; end if;
  seed_value := floor(random()*2147483646)::bigint+1;
  insert into public.nx_matches(room_id,game,players,names,seed,settings)
    values(p_room,coalesce(r.selected_game,r.game),ids,names,seed_value,r.settings) returning id into mid;
  update public.nx_rooms set status='playing',match_id=mid,updated_at=now() where id=p_room;
  return jsonb_build_object('match_id',mid,'seed',seed_value,'players',n);
end $$;
grant execute on function public.nx_start_room_match(uuid) to authenticated;
