-- NEXORA physics contract v1: client replay and server moves must use the same coefficients.
create table if not exists public.nx_physics_contracts (
  game text primary key,
  version text not null,
  contract jsonb not null,
  updated_at timestamptz not null default now()
);

insert into public.nx_physics_contracts(game, version, contract) values
('finger_soccer', 'physics-2026-11-18-v1', '{"BR":35,"PR":58.5,"field_width_scale":1.1,"field_length_scale":1.16,"goal_half_width":170,"ball_mass":2.6,"player_mass":4,"HV":10,"PCAP":520,"ball_player_restitution":0.78,"player_player_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"PF1":430,"PF2":4,"PV0":820,"shot_power_coefficient":2.5,"LMAX":175,"ball_wall_restitution":0.93,"fast_ball_drop":0.22,"player_wall_restitution":0.93,"post_restitution":1.9,"formation":"1-2-2","scene_speed":1.03,"turn_seconds":10}'::jsonb),
('billiards', 'physics-2026-11-18-v1', '{"BR":35,"PR":58.5,"ball_mass":2.6,"object_mass":4,"HV":10,"PCAP":520,"ball_object_restitution":0.78,"object_object_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"shot_power_coefficient":2.5,"LMAX":175,"cushion_restitution":0.93}'::jsonb),
('carrom', 'physics-2026-11-18-v1', '{"BR":35,"PR":58.5,"coin_mass":4,"striker_mass":2.6,"HV":10,"PCAP":520,"striker_coin_restitution":0.78,"coin_coin_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"shot_power_coefficient":2.5,"LMAX":175,"wall_restitution":0.93,"turn_seconds":10}'::jsonb)
on conflict (game) do update set version = excluded.version, contract = excluded.contract, updated_at = now();

alter table public.nx_matches
  add column if not exists physics_version text not null default 'physics-2026-11-18-v1',
  add column if not exists physics_contract jsonb not null default '{}'::jsonb;

create or replace function public.nx_apply_physics_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare c nx_physics_contracts;
begin
  select * into c from public.nx_physics_contracts where game = new.game;
  if found then
    new.physics_version := c.version;
    new.physics_contract := c.contract;
  end if;
  return new;
end;
$$;

drop trigger if exists nx_matches_physics_contract on public.nx_matches;
create trigger nx_matches_physics_contract
before insert on public.nx_matches
for each row execute function public.nx_apply_physics_contract();

update public.nx_matches m
set physics_version = c.version, physics_contract = c.contract
from public.nx_physics_contracts c
where c.game = m.game;

alter table public.nx_physics_contracts enable row level security;
revoke all on public.nx_physics_contracts from anon, authenticated;
revoke all on function public.nx_apply_physics_contract() from public, anon, authenticated;
