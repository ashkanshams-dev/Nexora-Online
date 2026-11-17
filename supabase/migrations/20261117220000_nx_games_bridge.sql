-- Auth/social project (eisstodgncimypdawisy) side of the games bridge. The wallet (xp, coins, gems) stays in
-- public.profiles here (shared with the RN app). The games project (eyzafhrefnqlwcjpcdyg) keeps a mirror and sends
-- balance deltas, applied once each (idempotent by its tx id); fresh snapshots are pushed back with pg_net.
-- Server-to-server only: service_role keys live in Vault on both sides.
create extension if not exists pg_net;

create table if not exists public.nx_bridge_applied (
  tx_id bigint primary key,
  user_id uuid not null,
  xp int not null, coins int not null, gems int not null,
  reason text,
  applied_at timestamptz not null default now()
);
alter table public.nx_bridge_applied enable row level security;
drop policy if exists nx_bridge_applied_own on public.nx_bridge_applied;
create policy nx_bridge_applied_own on public.nx_bridge_applied for select to authenticated using (user_id = auth.uid());

create or replace function public._nx_vault(n text) returns text
language sql stable security definer set search_path = public, vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = n limit 1
$$;
revoke all on function public._nx_vault(text) from public, anon, authenticated;

-- Push snapshots of the given users to the games mirror (fire-and-forget, after commit).
create or replace function public.nx_bridge_push(p_users uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare url text := _nx_vault('nx_games_url'); key text := _nx_vault('nx_games_service_key'); rows jsonb;
begin
  if url is null or key is null or coalesce(array_length(p_users, 1), 0) = 0 then return; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'username', p.username, 'avatar', coalesce(p.avatar_url, p.avatar),
           'xp', p.xp, 'level', p.level, 'coins', p.coins, 'gems', p.gems, 'role', p.role)), '[]'::jsonb)
    into rows from profiles p where p.id = any(p_users);
  if jsonb_array_length(rows) = 0 then return; end if;
  perform net.http_post(url := url || '/rest/v1/rpc/nx_mirror_put',
                        headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', key, 'Authorization', 'Bearer ' || key),
                        body := jsonb_build_object('p_rows', rows), timeout_milliseconds := 8000);
end $$;

-- Deltas from the games project (service_role only).
create or replace function public.nx_bridge_apply_batch(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e jsonb; n int := 0; users uuid[] := '{}'; u uuid;
begin
  perform set_config('nx.bridge', '1', true);
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    u := (e ->> 'user_id')::uuid;
    insert into nx_bridge_applied(tx_id, user_id, xp, coins, gems, reason)
    values ((e ->> 'id')::bigint, u, coalesce((e ->> 'xp')::int, 0), coalesce((e ->> 'coins')::int, 0),
            coalesce((e ->> 'gems')::int, 0), left(e ->> 'reason', 80))
    on conflict (tx_id) do nothing;
    if found then
      update profiles set xp = greatest(0, xp + coalesce((e ->> 'xp')::int, 0)),
                          coins = greatest(0, coins + coalesce((e ->> 'coins')::int, 0)),
                          gems = greatest(0, gems + coalesce((e ->> 'gems')::int, 0))
       where id = u;
      update profiles set level = level_for_xp(xp) where id = u;
      n := n + 1;
    end if;
    if not (u = any(users)) then users := users || u; end if;
  end loop;
  perform nx_bridge_push(users);
  return jsonb_build_object('applied', n);
end $$;

create or replace function public.nx_bridge_push_profile(p_user uuid) returns void
language sql security definer set search_path = public as $$ select nx_bridge_push(array[p_user]) $$;

revoke all on function public.nx_bridge_push(uuid[]), public.nx_bridge_apply_batch(jsonb), public.nx_bridge_push_profile(uuid)
  from public, anon, authenticated;
grant execute on function public.nx_bridge_apply_batch(jsonb), public.nx_bridge_push_profile(uuid) to service_role;

-- Any wallet/identity change made here (awards, purchases, the RN app, owner grants) → snapshot to the games mirror,
-- for NEXORA-Flutter players only (they have an nx_profiles row).
create or replace function public._nx_profiles_to_games() returns trigger
language plpgsql security definer set search_path = public as $$
declare ids uuid[];
begin
  if coalesce(current_setting('nx.bridge', true), '') = '1' then return null; end if;
  select coalesce(array_agg(distinct nw.id), '{}') into ids
    from new_rows nw join old_rows o on o.id = nw.id join nx_profiles n on n.id = nw.id
   where (nw.xp, nw.coins, nw.gems, nw.username, nw.avatar, nw.avatar_url, nw.role)
         is distinct from (o.xp, o.coins, o.gems, o.username, o.avatar, o.avatar_url, o.role);
  perform nx_bridge_push(ids);
  return null;
exception when others then
  return null; -- never break a profile update because of the bridge
end $$;
drop trigger if exists nx_profiles_to_games on public.profiles;
create trigger nx_profiles_to_games after update on public.profiles
  referencing old table as old_rows new table as new_rows for each statement execute function public._nx_profiles_to_games();
