-- Custom access token hook (auth project eisstodgncimypdawisy): adds the claim `nx_perms` (text[]) so the games project
-- (which trusts this project's JWTs via Third-Party Auth) can enforce admin permissions without a cross-project query.
-- Owner → ['owner'] (implies everything). Per-permission admins → nx_admin_perms.perms. Tournament staff (nx_staff) →
-- 'tournaments'. Never fails a sign-in: any error returns the event unchanged (this auth is shared with the RN app).
create or replace function public.nx_access_token_hook(event jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid; perms text[] := '{}'; claims jsonb;
begin
  begin
    uid := (event ->> 'user_id')::uuid;
    if uid is not null then
      if nx_is_owner(uid) then
        perms := array['owner'];
      else
        select coalesce(p.perms, '{}') into perms from nx_admin_perms p where p.user_id = uid;
        perms := coalesce(perms, '{}');
        if exists (select 1 from nx_staff s where s.user_id = uid and s.role in ('admin', 'organizer'))
           and not ('tournaments' = any(perms)) then
          perms := perms || 'tournaments';
        end if;
        if exists (select 1 from nx_admin_perms p where p.user_id = uid and p.unlimited_gems) then
          perms := perms || 'unlimited_gems';
        end if;
      end if;
    end if;
    claims := coalesce(event -> 'claims', '{}'::jsonb) || jsonb_build_object('nx_perms', to_jsonb(perms));
    return jsonb_set(event, '{claims}', claims);
  exception when others then
    return event;
  end;
end $$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.nx_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.nx_access_token_hook(jsonb) from public, anon, authenticated;
-- The hook runs as supabase_auth_admin: let it read the tables it needs (RLS policies for that role).
grant select on public.nx_admin_perms, public.nx_staff to supabase_auth_admin;
drop policy if exists nx_admin_perms_auth_admin on public.nx_admin_perms;
create policy nx_admin_perms_auth_admin on public.nx_admin_perms for select to supabase_auth_admin using (true);
drop policy if exists nx_staff_auth_admin on public.nx_staff;
create policy nx_staff_auth_admin on public.nx_staff for select to supabase_auth_admin using (true);
