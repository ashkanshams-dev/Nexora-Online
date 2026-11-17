-- ORACLE AI (Flutter app): provider keys in Supabase Vault, per-user daily usage log. Social/auth project (eisstodgncimypdawisy).
create extension if not exists supabase_vault;

create table if not exists public.nx_oracle_usage (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null,
  model text not null,
  at timestamptz not null default now()
);
create index if not exists nx_oracle_usage_user_at on public.nx_oracle_usage(user_id, at desc);
alter table public.nx_oracle_usage enable row level security;
drop policy if exists nx_oracle_usage_own on public.nx_oracle_usage;
create policy nx_oracle_usage_own on public.nx_oracle_usage for select to authenticated using (user_id = auth.uid());

create or replace function public.nx_oracle_count(p_user uuid) returns int
language sql security definer set search_path = public as $$
  select count(*)::int from nx_oracle_usage where user_id = p_user and at > now() - interval '1 day';
$$;
create or replace function public.nx_oracle_log(p_user uuid, p_provider text, p_model text) returns void
language sql security definer set search_path = public as $$
  insert into nx_oracle_usage(user_id, provider, model) values (p_user, p_provider, p_model);
$$;

-- Keys: vault secrets named nx_ai_<provider>_<slot>. Only service_role may call these.
create or replace function public.nx_ai_keys() returns table(provider text, slot text, key text)
language sql security definer set search_path = public, vault as $$
  select split_part(substr(name, 7), '_', 1), split_part(substr(name, 7), '_', 2), decrypted_secret
    from vault.decrypted_secrets where name like 'nx\_ai\_%';
$$;
create or replace function public.nx_ai_key_list() returns table(provider text, slot text, updated_at timestamptz)
language sql security definer set search_path = public, vault as $$
  select split_part(substr(name, 7), '_', 1), split_part(substr(name, 7), '_', 2), updated_at
    from vault.secrets where name like 'nx\_ai\_%' order by 1, 2;
$$;
create or replace function public.nx_ai_key_put(p_provider text, p_slot text, p_key text) returns void
language plpgsql security definer set search_path = public, vault as $$
declare n text := 'nx_ai_' || p_provider || '_' || p_slot; sid uuid;
begin
  select id into sid from vault.secrets where name = n;
  if sid is null then perform vault.create_secret(p_key, n, 'NEXORA ORACLE provider key');
  else perform vault.update_secret(sid, p_key, n, 'NEXORA ORACLE provider key'); end if;
end $$;
create or replace function public.nx_ai_key_delete(p_provider text, p_slot text) returns void
language sql security definer set search_path = public, vault as $$
  delete from vault.secrets where name = 'nx_ai_' || p_provider || '_' || p_slot;
$$;
do $$ declare f text; begin
  foreach f in array array['nx_oracle_count(uuid)','nx_oracle_log(uuid,text,text)','nx_ai_keys()','nx_ai_key_list()',
                           'nx_ai_key_put(text,text,text)','nx_ai_key_delete(text,text)'] loop
    execute format('revoke all on function public.%s from public, anon, authenticated', f);
    execute format('grant execute on function public.%s to service_role', f);
  end loop;
end $$;
