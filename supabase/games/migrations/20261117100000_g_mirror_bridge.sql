-- NEXORA GAMES project (eyzafhrefnqlwcjpcdyg) · foundation: identity, player mirror, wallet bridge.
--
-- Split (owner decision): this project = games, rooms, matchmaking, matches, tournaments, realtime match state.
-- The social/auth project (eisstodgncimypdawisy) = Supabase Auth, profiles, posts, stories, likes, follows, chat, calls, ORACLE.
--
-- Identity: this project trusts the auth project's JWTs (Supabase Third-Party Auth, custom JWKS =
--   https://eisstodgncimypdawisy.supabase.co/auth/v1/.well-known/jwks.json). auth.uid() here = the same user id.
--   Admin permissions travel in the JWT claim `nx_perms` (custom access token hook on the auth project).
--
-- Wallet: the real balances live in the auth project's public.profiles (shared with the other NEXORA app).
--   public.profiles HERE is a mirror (id, username, avatar, xp, level, coins, gems, role) so the game SQL can check and move
--   balances atomically. Every balance change made here is captured as a delta in nx_wallet_tx and pushed (pg_net) to the
--   auth project's nx_bridge_apply_batch (idempotent by tx id); the auth project pushes fresh snapshots back
--   (nx_mirror_put). Retries + acks run every minute (pg_cron). Server-to-server only, keys in Vault, no extra server.
create extension if not exists pg_net;
create extension if not exists pg_cron;
create extension if not exists supabase_vault;

create table if not exists public.profiles (
  id uuid primary key,
  username text,
  avatar text,
  xp int not null default 0,
  level int not null default 1,
  coins int not null default 0,
  gems int not null default 0,
  role text,
  synced_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles for select to authenticated using (true);

create or replace function public.level_for_xp(x integer) returns integer
language sql immutable as $$ select greatest(1, floor(sqrt(greatest(x,0)/100.0))::int + 1) $$;

-- Permissions from the auth project's token (claim nx_perms: text[]; 'owner' implies everything).
create or replace function public.nx_perm(p text) returns boolean
language sql stable as $$
  select coalesce((auth.jwt() -> 'nx_perms') ? 'owner' or (auth.jwt() -> 'nx_perms') ? p, false)
$$;
create or replace function public.is_owner(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select (uid = auth.uid() and nx_perm('owner')) or exists (select 1 from profiles where id = uid and role = 'owner')
$$;
create or replace function public.is_admin(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select is_owner(uid) or (uid = auth.uid() and nx_perm('tournaments'))
$$;

-- --------------------------------------------------------------------------- wallet outbox
create table if not exists public.nx_wallet_tx (
  id bigserial primary key,
  user_id uuid not null,
  xp int not null default 0,
  coins int not null default 0,
  gems int not null default 0,
  reason text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  request_id bigint,
  acked_at timestamptz,
  tries int not null default 0
);
create index if not exists nx_wallet_tx_pending on public.nx_wallet_tx(acked_at, created_at) where acked_at is null;
alter table public.nx_wallet_tx enable row level security;
drop policy if exists nx_wallet_tx_own on public.nx_wallet_tx;
create policy nx_wallet_tx_own on public.nx_wallet_tx for select to authenticated using (user_id = auth.uid());

-- Capture every local balance change (not the ones written by the sync itself).
create or replace function public._nx_profiles_delta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('nx.sync', true), '') = '1' then return new; end if;
  if tg_op = 'UPDATE' and (new.xp <> old.xp or new.coins <> old.coins or new.gems <> old.gems) then
    insert into nx_wallet_tx(user_id, xp, coins, gems, reason)
    values (new.id, new.xp - old.xp, new.coins - old.coins, new.gems - old.gems,
            left(coalesce(current_setting('nx.reason', true), 'games'), 80));
    new.level := level_for_xp(new.xp);
    new.updated_at := now();
  end if;
  return new;
end $$;
drop trigger if exists nx_profiles_delta on public.profiles;
create trigger nx_profiles_delta before update on public.profiles for each row execute function public._nx_profiles_delta();

create or replace function public._nx_secret(n text) returns text
language sql stable security definer set search_path = public, vault as $$
  select decrypted_secret from vault.decrypted_secrets where name = n limit 1
$$;

-- Push pending deltas to the auth project (batch, idempotent by id there).
create or replace function public.nx_wallet_push() returns int
language plpgsql security definer set search_path = public as $$
declare url text := _nx_secret('nx_social_url'); key text := _nx_secret('nx_social_service_key'); rows jsonb; rid bigint; n int;
begin
  if url is null or key is null then return 0; end if;
  -- ack what the other side answered with 2xx
  update nx_wallet_tx t set acked_at = now()
    from net._http_response r
   where t.acked_at is null and t.request_id = r.id and r.status_code between 200 and 299;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'user_id', user_id, 'xp', xp, 'coins', coins, 'gems', gems,
                                               'reason', reason) order by id), '[]'::jsonb), count(*)
    into rows, n
    from (select * from nx_wallet_tx
           where acked_at is null and (sent_at is null or sent_at < now() - interval '50 seconds') and tries < 200
           order by id limit 200) x;
  if n = 0 then return 0; end if;
  select net.http_post(url := url || '/rest/v1/rpc/nx_bridge_apply_batch',
                       headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', key,
                                                     'Authorization', 'Bearer ' || key),
                       body := jsonb_build_object('p_rows', rows), timeout_milliseconds := 8000) into rid;
  update nx_wallet_tx set sent_at = now(), request_id = rid, tries = tries + 1
   where id in (select (e ->> 'id')::bigint from jsonb_array_elements(rows) e);
  return n;
end $$;

-- Push right after the transaction that created deltas commits (pg_net sends after commit).
create or replace function public._nx_wallet_tx_kick() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform nx_wallet_push();
  return null;
end $$;
drop trigger if exists nx_wallet_tx_kick on public.nx_wallet_tx;
create trigger nx_wallet_tx_kick after insert on public.nx_wallet_tx for each statement execute function public._nx_wallet_tx_kick();

-- Snapshots from the auth project (service_role only). Balances are not overwritten while local deltas are still in flight
-- (the auth project re-sends a snapshot after applying them).
create or replace function public.nx_mirror_put(p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare e jsonb; n int := 0; pend boolean;
begin
  perform set_config('nx.sync', '1', true);
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    select exists (select 1 from nx_wallet_tx where user_id = (e ->> 'id')::uuid and acked_at is null) into pend;
    insert into profiles(id, username, avatar, xp, level, coins, gems, role, synced_at)
    values ((e ->> 'id')::uuid, e ->> 'username', e ->> 'avatar', coalesce((e ->> 'xp')::int, 0), coalesce((e ->> 'level')::int, 1),
            coalesce((e ->> 'coins')::int, 0), coalesce((e ->> 'gems')::int, 0), e ->> 'role', now())
    on conflict (id) do update set
      username = excluded.username, avatar = excluded.avatar, role = excluded.role, synced_at = now(),
      xp = case when pend then profiles.xp else excluded.xp end,
      level = case when pend then profiles.level else excluded.level end,
      coins = case when pend then profiles.coins else excluded.coins end,
      gems = case when pend then profiles.gems else excluded.gems end;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Ask the auth project to push my snapshot (first visit / after login). Creates a placeholder row so FKs work at once.
create or replace function public.nx_g_hello() returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); url text := _nx_secret('nx_social_url'); key text := _nx_secret('nx_social_service_key'); r profiles;
begin
  if me is null then raise exception 'not signed in'; end if;
  perform set_config('nx.sync', '1', true);
  insert into profiles(id, username) values (me, coalesce(auth.jwt() -> 'user_metadata' ->> 'username', 'Pilot'))
  on conflict (id) do nothing;
  select * into r from profiles where id = me;
  if (r.synced_at is null or r.synced_at < now() - interval '2 minutes') and url is not null then
    perform net.http_post(url := url || '/rest/v1/rpc/nx_bridge_push_profile',
                          headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', key, 'Authorization', 'Bearer ' || key),
                          body := jsonb_build_object('p_user', me), timeout_milliseconds := 8000);
  end if;
  return jsonb_build_object('id', r.id, 'username', r.username, 'xp', r.xp, 'coins', r.coins, 'gems', r.gems, 'level', r.level,
                            'synced_at', r.synced_at);
end $$;

revoke all on function public.nx_mirror_put(jsonb), public.nx_wallet_push(), public._nx_secret(text) from public, anon, authenticated;
grant execute on function public.nx_mirror_put(jsonb), public.nx_wallet_push() to service_role;
grant execute on function public.nx_g_hello(), public.nx_perm(text) to authenticated;

do $$ begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'nx_wallet_push';
exception when others then null; end $$;
select cron.schedule('nx_wallet_push', '* * * * *', 'select public.nx_wallet_push()');
