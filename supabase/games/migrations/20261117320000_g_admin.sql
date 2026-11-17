-- Games project · admin: callers that still must change their password get no admin rights here either; rooms moderation
-- (permission 'rooms'), audited in nx_admin_audit.
create or replace function public.nx_is_owner(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null
    and not (u = auth.uid() and coalesce((auth.jwt() -> 'nx_perms') ? 'must_change_password', false))
    and ((u = auth.uid() and nx_perm('owner')) or exists (select 1 from nx_staff where user_id = u and role = 'owner'))
$$;
create or replace function public.nx_has_perm(p text, u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null
    and not (u = auth.uid() and coalesce((auth.jwt() -> 'nx_perms') ? 'must_change_password', false))
    and (nx_is_owner(u) or (u = auth.uid() and nx_perm(p))
         or exists (select 1 from nx_staff where user_id = u and (p = any(perms) or 'all' = any(perms))))
$$;

create table if not exists public.nx_admin_audit (
  id bigserial primary key,
  actor uuid,
  action text not null,
  target text,
  data jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.nx_admin_audit enable row level security;
drop policy if exists nx_admin_audit_read on public.nx_admin_audit;
create policy nx_admin_audit_read on public.nx_admin_audit for select to authenticated using (nx_has_perm('admins'));

create or replace function public.nx_admin_rooms(p_limit integer default 100) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true, 'rooms', coalesce((select jsonb_agg(x order by x.updated_at desc) from (
    select r.id, r.code, r.game, r.status, r.is_private, r.quick, r.seats, r.settings, r.created_at, r.updated_at, r.host,
           p.username as host_name, (select count(*) from nx_room_players rp where rp.room_id = r.id) as players
      from nx_rooms r left join profiles p on p.id = r.host
     where r.status in ('lobby', 'playing')
     order by r.updated_at desc limit greatest(1, least(coalesce(p_limit, 100), 300))) x), '[]'::jsonb));
end $$;

create or replace function public.nx_admin_close_room(p_room uuid, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r nx_rooms;
begin
  if not nx_has_perm('rooms') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.match_id is not null and r.settings ? 'tmatch' then
    return jsonb_build_object('ok', false, 'error', 'tournament_room'); -- use the tournament match tools instead
  end if;
  if r.match_id is not null then
    update nx_matches set status = 'finished', reason = 'admin_closed', winner_seats = '{}', ended_at = now()
     where id = r.match_id and status = 'playing';
  end if;
  update nx_rooms set status = 'closed', updated_at = now() where id = p_room;
  delete from nx_room_players where room_id = p_room;
  insert into nx_admin_audit(actor, action, target, data) values (auth.uid(), 'close_room', p_room::text,
    jsonb_build_object('reason', p_reason, 'code', r.code, 'game', r.game));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.nx_admin_rooms(integer), public.nx_admin_close_room(uuid, text) from public, anon;
grant execute on function public.nx_admin_rooms(integer), public.nx_admin_close_room(uuid, text) to authenticated;
