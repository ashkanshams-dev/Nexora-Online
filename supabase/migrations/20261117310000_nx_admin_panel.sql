-- Admin panel (auth project): per-permission admins, server-enforced + audited. The main admin (owner) has everything;
-- other admins get a subset of: users (search, ban/unban), currency (grant coins/gems), tournaments, moderation (posts/
-- comments/stories), rooms, announcements, oracle (ORACLE persona config), admins (manage other admins; only the owner may
-- hand out 'admins' or unlimited gem prizes). Every admin RPC refuses while the caller must still change their password.
create or replace function public.nx_admin_perm_list() returns text[] language sql immutable as $$
  select array['users', 'currency', 'tournaments', 'moderation', 'rooms', 'announcements', 'oracle', 'admins']
$$;

create or replace function public._nx_admin_guard(p text default null) returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then return 'not_signed_in'; end if;
  if nx_is_banned(auth.uid()) then return 'banned'; end if;
  if p = 'owner' then
    if not nx_is_owner(auth.uid()) then return 'forbidden'; end if;
  elsif p is null then
    if not (nx_is_owner(auth.uid()) or exists (select 1 from nx_admin_perms where user_id = auth.uid() and cardinality(perms) > 0)) then
      return 'forbidden'; end if;
  elsif not nx_has_perm(p, auth.uid()) then
    return 'forbidden';
  end if;
  if coalesce((select must_change_password from nx_account_flags where user_id = auth.uid()), false) then
    return 'password_change_required'; end if;
  return null;
end $$;
revoke all on function public._nx_admin_guard(text) from public, anon, authenticated;


CREATE OR REPLACE FUNCTION public.nx_owner_users(p_q text DEFAULT ''::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('users'); q text := lower(trim(coalesce(p_q, ''))); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select u.id, p.username, u.email, coalesce(u.is_anonymous, false) as guest, u.created_at, u.last_sign_in_at,
           coalesce(p.coins, 0) as coins, coalesce(p.gems, 0) as gems, coalesce(p.xp, 0) as xp, coalesce(p.level, 1) as level,
           case when nx_is_owner(u.id) then 'owner' else coalesce(s.role, 'player') end as role,
           coalesce(s.unlimited, false) as unlimited,
           coalesce(f.banned, false) as banned, f.ban_reason
      from auth.users u
      left join profiles p on p.id = u.id
      left join nx_staff s on s.user_id = u.id
      left join nx_account_flags f on f.user_id = u.id
     where q = '' or lower(coalesce(p.username, '')) like '%' || q || '%' or lower(coalesce(u.email, '')) like '%' || q || '%'
           or u.id::text like q || '%'
     order by u.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200)) offset greatest(0, coalesce(p_offset, 0))) x;
  return jsonb_build_object('ok', true, 'users', res);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_ban(p_user uuid, p_ban boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare g text := _nx_admin_guard('users');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_user = auth.uid() or nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_owner'); end if;
  if nx_is_admin_any(p_user) and not nx_is_owner(auth.uid()) then return jsonb_build_object('ok', false, 'error', 'cannot_ban_admin'); end if;
  if p_ban then
    insert into nx_account_flags(user_id, banned, ban_reason, banned_at, banned_by) values (p_user, true, left(p_reason, 300), now(), auth.uid())
    on conflict (user_id) do update set banned = true, ban_reason = excluded.ban_reason, banned_at = now(), banned_by = auth.uid(),
       updated_at = now();
    update auth.users set banned_until = 'infinity'::timestamptz where id = p_user;
    delete from auth.sessions where user_id = p_user;
    delete from auth.refresh_tokens where user_id = p_user::text;
  else
    update nx_account_flags set banned = false, ban_reason = null, banned_at = null, banned_by = null, updated_at = now() where user_id = p_user;
    update auth.users set banned_until = null where id = p_user;
  end if;
  perform _nx_owner_log(case when p_ban then 'ban' else 'unban' end, p_user, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'banned', p_ban);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_grant(p_user uuid, p_coins integer, p_gems integer, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('currency'); c int := coalesce(p_coins, 0); gm int := coalesce(p_gems, 0); r record;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if abs(c) > 10000000 or abs(gm) > 10000000 then return jsonb_build_object('ok', false, 'error', 'amount_too_large'); end if;
  if c = 0 and gm = 0 then return jsonb_build_object('ok', false, 'error', 'zero_amount'); end if;
  update profiles set coins = coins + c, gems = coalesce(gems, 0) + gm
   where id = p_user and coins + c >= 0 and coalesce(gems, 0) + gm >= 0 returning coins, gems into r;
  if not found then
    if not exists (select 1 from profiles where id = p_user) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance');
  end if;
  perform _nx_owner_log('grant', p_user, jsonb_build_object('coins', c, 'gems', gm, 'reason', p_reason,
                                                             'balance_coins', r.coins, 'balance_gems', r.gems));
  return jsonb_build_object('ok', true, 'coins', r.coins, 'gems', r.gems);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_set_role(p_user uuid, p_role text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('admins'); cur nx_staff;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  select * into cur from nx_staff where user_id = p_user for update;
  if p_role is null or p_role in ('', 'player') then
    delete from nx_staff where user_id = p_user;
  elsif p_role = 'admin' then
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'admin', auth.uid(), false)
    on conflict (user_id) do update set role = 'admin', unlimited = false, via_code = null, granted_by = auth.uid(), granted_at = now();
  elsif p_role = 'organizer' then
    if not coalesce(cur.role = 'organizer' and cur.unlimited, false) and _nx_tadmin_count() >= _nx_tadmin_cap() then
      return jsonb_build_object('ok', false, 'error', 'cap_reached', 'cap', _nx_tadmin_cap()); end if;
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'organizer', auth.uid(), true)
    on conflict (user_id) do update set role = 'organizer', unlimited = true, granted_by = auth.uid(), granted_at = now();
  else
    return jsonb_build_object('ok', false, 'error', 'bad_role');
  end if;
  perform _nx_owner_log('set_role', p_user, jsonb_build_object('role', coalesce(nullif(p_role, ''), 'player'), 'previous', cur.role));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_audit_list(p_limit integer DEFAULT 100, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('admins'); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select * from (
      select 'owner' as source, a.created_at, a.action, a.actor, pa.username as actor_name, a.target, pt.username as target_name,
             null::uuid as tournament_id, a.data
        from nx_owner_audit a left join profiles pa on pa.id = a.actor left join profiles pt on pt.id = a.target
       where p_before is null or a.created_at < p_before
      union all
      select 'tournament', a.created_at, a.action, a.actor, pa.username, null, null, a.tournament_id, a.data
        from nx_t_audit a left join profiles pa on pa.id = a.actor
       where p_before is null or a.created_at < p_before) u
    order by created_at desc limit greatest(1, least(coalesce(p_limit, 100), 500))) x;
  return jsonb_build_object('ok', true, 'entries', res);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard(null);
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true,
    'users', (select count(*) from auth.users),
    'guests', (select count(*) from auth.users where coalesce(is_anonymous, false)),
    'banned', (select count(*) from nx_account_flags where banned),
    'admins', (select count(*) from nx_staff where role = 'admin'),
    'organizers', (select count(*) from nx_staff where role = 'organizer'),
    'tournament_admins', _nx_tadmin_count(),
    'tadmin_cap', _nx_tadmin_cap(),
    'tournaments_live', (select count(*) from nx_tournaments where status in ('registering', 'closed', 'drawn', 'live')),
    'tournaments_total', (select count(*) from nx_tournaments));
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_codes(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('admins'); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select c.id, c.hint, c.label, c.created_at, c.expires_at, c.revoked_at, c.used_at, c.used_by, p.username as used_by_name,
           case when c.revoked_at is not null then 'revoked' when c.used_at is not null then 'used'
                when c.expires_at is not null and c.expires_at < now() then 'expired' else 'active' end as status,
           (c.used_by is not null and exists (select 1 from nx_staff s where s.user_id = c.used_by and s.role = 'organizer'
                                              and s.unlimited and s.via_code = c.id)) as holder_active
      from nx_admin_codes c left join profiles p on p.id = c.used_by
     order by c.created_at desc limit greatest(1, least(coalesce(p_limit, 200), 1000))) x;
  return jsonb_build_object('ok', true, 'codes', res, 'cap', _nx_tadmin_cap(), 'active', _nx_tadmin_count());
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_code_create(p_label text DEFAULT ''::text, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare g text := _nx_admin_guard('admins'); alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; raw text; i int; k int;
        b bytea; out jsonb := '[]'::jsonb; cid uuid;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_expires_at is not null and p_expires_at <= now() then return jsonb_build_object('ok', false, 'error', 'bad_expiry'); end if;
  for k in 1..greatest(1, least(coalesce(p_count, 1), 20)) loop
    loop
      b := extensions.gen_random_bytes(12); raw := '';
      for i in 0..11 loop raw := raw || substr(alphabet, (get_byte(b, i) % 32) + 1, 1); end loop;
      exit when not exists (select 1 from nx_admin_codes where code_hash = _nx_admin_code_hash(raw));
    end loop;
    insert into nx_admin_codes(code_hash, hint, label, created_by, expires_at)
    values (_nx_admin_code_hash(raw), right(raw, 4), left(coalesce(p_label, ''), 60), auth.uid(), p_expires_at) returning id into cid;
    out := out || jsonb_build_object('id', cid, 'code', substr(raw, 1, 4) || '-' || substr(raw, 5, 4) || '-' || substr(raw, 9, 4));
  end loop;
  perform _nx_owner_log('admin_code_create', null, jsonb_build_object('count', jsonb_array_length(out), 'label', p_label,
                        'expires_at', p_expires_at, 'ids', (select jsonb_agg(x -> 'id') from jsonb_array_elements(out) x)));
  return jsonb_build_object('ok', true, 'codes', out);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_code_revoke(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('admins');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  update nx_admin_codes set revoked_at = now(), revoked_by = auth.uid() where id = p_id and revoked_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('admin_code_revoke', null, jsonb_build_object('code', p_id));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_owner_set_cap(p_cap integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_admin_guard('owner');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_cap is null or p_cap < 1 or p_cap > 1000 then return jsonb_build_object('ok', false, 'error', 'bad_cap'); end if;
  insert into nx_settings(key, value, updated_by, updated_at) values ('tadmin_cap', to_jsonb(p_cap), auth.uid(), now())
  on conflict (key) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now();
  perform _nx_owner_log('set_tadmin_cap', null, jsonb_build_object('cap', p_cap));
  return jsonb_build_object('ok', true, 'cap', p_cap, 'active', _nx_tadmin_count());
end $function$;


create or replace function public.nx_is_admin_any(u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select nx_is_owner(u) or exists (select 1 from nx_admin_perms where user_id = u and cardinality(perms) > 0)
$$;
-- Admin management (permission 'admins'; only the owner may grant 'admins' itself or unlimited gem prizes).
create or replace function public.nx_admin_set_perms(p_user uuid, p_perms text[], p_unlimited_gems boolean default false,
                                                     p_gem_budget integer default null) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare g text := _nx_admin_guard('admins'); me uuid := auth.uid(); own boolean := nx_is_owner(auth.uid());
        clean text[]; cur nx_admin_perms;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user and not coalesce(is_anonymous, false)) then
    return jsonb_build_object('ok', false, 'error', 'account_required'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  if p_user = me and not own then return jsonb_build_object('ok', false, 'error', 'cannot_change_self'); end if;
  select coalesce(array_agg(distinct x order by x), '{}') into clean
    from unnest(coalesce(p_perms, '{}')) x where x = any(nx_admin_perm_list());
  select * into cur from nx_admin_perms where user_id = p_user;
  if not own then
    -- a non-owner admin manager can neither hand out nor take away 'admins', nor touch unlimited gems
    if ('admins' = any(clean)) <> coalesce('admins' = any(cur.perms), false) then
      return jsonb_build_object('ok', false, 'error', 'owner_only_admins'); end if;
    if coalesce(p_unlimited_gems, false) <> coalesce(cur.unlimited_gems, false) then
      return jsonb_build_object('ok', false, 'error', 'owner_only_unlimited'); end if;
  end if;
  if p_gem_budget is not null and (p_gem_budget < 0 or p_gem_budget > 10000000) then
    return jsonb_build_object('ok', false, 'error', 'bad_budget'); end if;
  if cardinality(clean) = 0 and not coalesce(p_unlimited_gems, false) and p_gem_budget is null then
    delete from nx_admin_perms where user_id = p_user;
  else
    insert into nx_admin_perms(user_id, perms, unlimited_gems, gem_budget, granted_by, updated_at)
    values (p_user, clean, coalesce(p_unlimited_gems, false), p_gem_budget, me, now())
    on conflict (user_id) do update set perms = excluded.perms, unlimited_gems = excluded.unlimited_gems,
      gem_budget = excluded.gem_budget, granted_by = me, updated_at = now();
  end if;
  -- tournament managers (may create tournaments) = nx_staff organizer; keep it in step with the 'tournaments' perm
  if 'tournaments' = any(clean) then
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'organizer', me, coalesce(p_unlimited_gems, false))
    on conflict (user_id) do update set unlimited = coalesce(p_unlimited_gems, false), granted_by = me, granted_at = now()
      where nx_staff.role = 'organizer';
  end if;
  perform _nx_owner_log('set_perms', p_user, jsonb_build_object('perms', clean, 'unlimited_gems', coalesce(p_unlimited_gems, false),
    'gem_budget', p_gem_budget, 'previous', to_jsonb(cur.perms)));
  return jsonb_build_object('ok', true, 'perms', clean);
end $$;

-- Tournament manager (organizer) with a gem prize budget; unlimited only from the owner.
create or replace function public.nx_admin_set_manager(p_user uuid, p_manager boolean, p_unlimited boolean default false,
                                                       p_gem_budget integer default 0) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare g text := _nx_admin_guard('tournaments'); me uuid := auth.uid(); cur nx_admin_perms;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_user is null or not exists (select 1 from auth.users where id = p_user and not coalesce(is_anonymous, false)) then
    return jsonb_build_object('ok', false, 'error', 'account_required'); end if;
  if nx_is_owner(p_user) then return jsonb_build_object('ok', false, 'error', 'cannot_change_owner'); end if;
  if coalesce(p_unlimited, false) and not nx_is_owner(me) then
    return jsonb_build_object('ok', false, 'error', 'owner_only_unlimited'); end if;
  if coalesce(p_gem_budget, 0) < 0 or coalesce(p_gem_budget, 0) > 10000000 then
    return jsonb_build_object('ok', false, 'error', 'bad_budget'); end if;
  select * into cur from nx_admin_perms where user_id = p_user;
  if not p_manager then
    delete from nx_staff where user_id = p_user and role = 'organizer';
    update nx_admin_perms set gem_budget = null, unlimited_gems = case when nx_is_owner(me) then false else unlimited_gems end,
           updated_at = now() where user_id = p_user;
  else
    insert into nx_staff(user_id, role, granted_by, unlimited) values (p_user, 'organizer', me, coalesce(p_unlimited, false))
    on conflict (user_id) do update set role = case when nx_staff.role = 'admin' then 'admin' else 'organizer' end,
      unlimited = coalesce(p_unlimited, false), granted_by = me, granted_at = now();
    insert into nx_admin_perms(user_id, perms, unlimited_gems, gem_budget, granted_by, updated_at)
    values (p_user, '{}', coalesce(p_unlimited, false), coalesce(p_gem_budget, 0), me, now())
    on conflict (user_id) do update set unlimited_gems = coalesce(p_unlimited, false), gem_budget = coalesce(p_gem_budget, 0),
      granted_by = me, updated_at = now();
  end if;
  perform _nx_owner_log('set_manager', p_user, jsonb_build_object('manager', p_manager, 'unlimited', coalesce(p_unlimited, false),
    'gem_budget', p_gem_budget));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.nx_admin_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard(null); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.owner desc, x.username), '[]'::jsonb) into res from (
    select u.id, p.username, nx_is_owner(u.id) as owner, coalesce(a.perms, '{}') as perms,
           coalesce(a.unlimited_gems, false) or coalesce(s.unlimited, false) as unlimited_gems, a.gem_budget, s.role as staff_role,
           a.updated_at
      from (select user_id as id from nx_admin_perms union select user_id from nx_staff) u
      left join profiles p on p.id = u.id left join nx_admin_perms a on a.user_id = u.id left join nx_staff s on s.user_id = u.id) x;
  return jsonb_build_object('ok', true, 'admins', res, 'perm_list', to_jsonb(nx_admin_perm_list()));
end $$;

-- What the signed-in user may do (drives the admin panel UI; the server re-checks on every call).
create or replace function public.nx_my_access() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'uid', auth.uid(),
    'owner', nx_is_owner(auth.uid()),
    'perms', case when nx_is_owner(auth.uid()) then to_jsonb(nx_admin_perm_list())
                  else coalesce((select to_jsonb(perms) from nx_admin_perms where user_id = auth.uid()), '[]'::jsonb) end,
    'admin', nx_t_is_admin(auth.uid()),
    'organizer', nx_t_is_organizer(auth.uid()),
    'tournament_admin', exists (select 1 from nx_staff where user_id = auth.uid() and role = 'organizer' and unlimited),
    'unlimited', nx_unlimited(auth.uid()),
    'gem_budget', (select gem_budget from nx_admin_perms where user_id = auth.uid()),
    'banned', nx_is_banned(auth.uid()),
    'must_change_password', coalesce((select must_change_password from nx_account_flags where user_id = auth.uid()), false))
$$;

-- ------------------------------------------------------------------ announcements
create table if not exists public.nx_announcements (
  id bigserial primary key,
  title text not null check (char_length(title) between 1 and 120),
  body text not null default '' check (char_length(body) <= 2000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz,
  active boolean not null default true
);
alter table public.nx_announcements enable row level security;
drop policy if exists nx_announcements_read on public.nx_announcements;
create policy nx_announcements_read on public.nx_announcements for select to anon, authenticated
  using (active and (expires_at is null or expires_at > now()));
do $$ begin alter publication supabase_realtime add table public.nx_announcements; exception when duplicate_object then null; end $$;

create or replace function public.nx_admin_announce(p_title text, p_body text, p_hours integer default 72) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('announcements'); nid bigint;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if coalesce(trim(p_title), '') = '' then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  insert into nx_announcements(title, body, created_by, expires_at)
  values (left(trim(p_title), 120), left(coalesce(p_body, ''), 2000), auth.uid(),
          case when coalesce(p_hours, 0) > 0 then now() + make_interval(hours => least(p_hours, 24 * 365)) end)
  returning id into nid;
  perform _nx_owner_log('announce', null, jsonb_build_object('id', nid, 'title', p_title));
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function public.nx_admin_announce_end(p_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('announcements');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  update nx_announcements set active = false where id = p_id;
  perform _nx_owner_log('announce_end', null, jsonb_build_object('id', p_id));
  return jsonb_build_object('ok', found);
end $$;

create or replace function public.nx_admin_announcements() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('announcements');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true, 'items', coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc)
    from (select * from nx_announcements order by created_at desc limit 100) a), '[]'::jsonb));
end $$;

-- ------------------------------------------------------------------ moderation
create or replace function public.nx_admin_recent_content(p_limit integer default 60) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare g text := _nx_admin_guard('moderation');
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  return jsonb_build_object('ok', true,
    'posts', coalesce((select jsonb_agg(x order by x.created_at desc) from (
       select p.id, p.kind, p.text, p.created_at, p.author, pr.username from nx_posts p left join profiles pr on pr.id = p.author
        order by p.created_at desc limit greatest(1, least(coalesce(p_limit, 60), 200))) x), '[]'::jsonb),
    'comments', coalesce((select jsonb_agg(x order by x.created_at desc) from (
       select c.id, c.post_id, c.text, c.created_at, c.author, pr.username from nx_post_comments c left join profiles pr on pr.id = c.author
        order by c.created_at desc limit greatest(1, least(coalesce(p_limit, 60), 200))) x), '[]'::jsonb));
end $$;

create or replace function public.nx_admin_remove(p_kind text, p_id text, p_reason text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare g text := _nx_admin_guard('moderation'); who uuid;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  if p_kind = 'post' then
    delete from nx_posts where id::text = p_id returning author into who;
  elsif p_kind = 'comment' then
    delete from nx_post_comments where id::text = p_id returning author into who;
  else
    return jsonb_build_object('ok', false, 'error', 'bad_kind');
  end if;
  if who is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_owner_log('remove_' || p_kind, who, jsonb_build_object('id', p_id, 'reason', p_reason));
  return jsonb_build_object('ok', true);
end $$;

-- ------------------------------------------------------------------ forced password change
-- Clears the flag server-side after the client changed the password (the auth.users trigger does the same).
create or replace function public.nx_password_changed_ack() returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare changed timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select updated_at into changed from auth.users where id = auth.uid();
  return jsonb_build_object('ok', true, 'must_change_password',
    coalesce((select must_change_password from nx_account_flags where user_id = auth.uid()), false));
end $$;

do $$ declare f text; begin
  foreach f in array array['nx_admin_set_perms(uuid,text[],boolean,integer)', 'nx_admin_set_manager(uuid,boolean,boolean,integer)',
    'nx_admin_list()', 'nx_my_access()', 'nx_admin_announce(text,text,integer)', 'nx_admin_announce_end(bigint)',
    'nx_admin_announcements()', 'nx_admin_recent_content(integer)', 'nx_admin_remove(text,text,text)', 'nx_password_changed_ack()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.nx_is_admin_any(uuid) from public, anon;
grant execute on function public.nx_is_admin_any(uuid) to authenticated;

-- ------------------------------------------------------------------ default main-admin login
-- Account `admin` (internal e-mail admin@users.nexora.invalid, created with the GoTrue admin API) is a main admin (owner)
-- and must change its password on first login.
do $$ declare a uuid; begin
  select id into a from auth.users where email = 'admin@users.nexora.invalid';
  if a is not null then
    insert into nx_staff(user_id, role, unlimited) values (a, 'owner', true)
    on conflict (user_id) do update set role = 'owner', unlimited = true;
    insert into nx_account_flags(user_id, must_change_password) values (a, true)
    on conflict (user_id) do update set must_change_password = true;
    insert into nx_profiles(id) values (a) on conflict (id) do nothing;
  end if;
end $$;
create or replace function public.nx_access_token_hook(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid; perms text[] := '{}'; claims jsonb; r text;
begin
  begin
    uid := (event ->> 'user_id')::uuid;
    if uid is not null then
      if nx_is_owner(uid) then
        perms := array['owner'];
      else
        select coalesce(p.perms, '{}') into perms from nx_admin_perms p where p.user_id = uid;
        perms := coalesce(perms, '{}');
        select s.role into r from nx_staff s where s.user_id = uid;
        if r = 'admin' and not ('tournaments' = any(perms)) then perms := perms || 'tournaments'::text; end if;
        if r = 'organizer' and not ('organizer' = any(perms)) then perms := perms || 'organizer'::text; end if;
        if exists (select 1 from nx_admin_perms p where p.user_id = uid and p.unlimited_gems)
           or exists (select 1 from nx_staff s where s.user_id = uid and s.unlimited) then
          perms := perms || 'unlimited_gems'::text;
        end if;
      end if;
      if coalesce((select must_change_password from nx_account_flags f where f.user_id = uid), false) then
        perms := perms || 'must_change_password'::text;
      end if;
    end if;
    claims := coalesce(event -> 'claims', '{}'::jsonb) || jsonb_build_object('nx_perms', to_jsonb(perms));
    return jsonb_set(event, '{claims}', claims);
  exception when others then
    return event;
  end;
end $$;
