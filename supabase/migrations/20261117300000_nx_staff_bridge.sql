-- Auth project: push the staff/permission table to the games project mirror (nx_staff_put). Hook: organizers get
-- 'organizer' (not 'tournaments', which means tournament ADMIN on the games project).
alter table public.nx_admin_perms add column if not exists gem_budget integer;

create or replace function public._nx_staff_rows(p_users uuid[] default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', u.id,
           'role', s.role, 'perms', coalesce(to_jsonb(a.perms), '[]'::jsonb),
           'unlimited', coalesce(s.unlimited, false) or coalesce(a.unlimited_gems, false),
           'gem_budget', a.gem_budget,
           'deleted', s.user_id is null and a.user_id is null)), '[]'::jsonb)
    from (select unnest(coalesce(p_users, array(select user_id from nx_staff union select user_id from nx_admin_perms))) id) u
    left join nx_staff s on s.user_id = u.id left join nx_admin_perms a on a.user_id = u.id
$$;

create or replace function public.nx_staff_push(p_users uuid[] default null) returns void
language plpgsql security definer set search_path = public as $$
declare url text := _nx_vault('nx_games_url'); key text := _nx_vault('nx_games_service_key');
begin
  if url is null or key is null then return; end if;
  perform net.http_post(url := url || '/rest/v1/rpc/nx_staff_put',
    headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', key, 'Authorization', 'Bearer ' || key),
    body := jsonb_build_object('p_rows', _nx_staff_rows(p_users), 'p_replace', p_users is null), timeout_milliseconds := 8000);
end $$;
revoke all on function public.nx_staff_push(uuid[]), public._nx_staff_rows(uuid[]) from public, anon, authenticated;

create or replace function public._nx_staff_to_games() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform nx_staff_push(array[coalesce(new.user_id, old.user_id)]);
  return null;
exception when others then return null;
end $$;
drop trigger if exists nx_staff_to_games on public.nx_staff;
create trigger nx_staff_to_games after insert or update or delete on public.nx_staff for each row execute function public._nx_staff_to_games();
drop trigger if exists nx_admin_perms_to_games on public.nx_admin_perms;
create trigger nx_admin_perms_to_games after insert or update or delete on public.nx_admin_perms for each row execute function public._nx_staff_to_games();

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
        if coalesce((select must_change_password from nx_account_flags f where f.user_id = uid), false) then
          perms := perms || 'must_change_password'::text;
        end if;
      end if;
    end if;
    claims := coalesce(event -> 'claims', '{}'::jsonb) || jsonb_build_object('nx_perms', to_jsonb(perms));
    return jsonb_set(event, '{claims}', claims);
  exception when others then
    return event;
  end;
end $$;
grant select on public.nx_account_flags to supabase_auth_admin;
drop policy if exists nx_account_flags_auth_admin on public.nx_account_flags;
create policy nx_account_flags_auth_admin on public.nx_account_flags for select to supabase_auth_admin using (true);
select public.nx_staff_push(null); -- initial full push
