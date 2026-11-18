-- Reference-tuning contract: compact presentation, heavier discs and softer ball spin.
update public.nx_physics_contracts
set version = 'physics-2026-11-18-v2',
    contract = '{"BR":35,"PR":58.5,"field_width_scale":1.1,"field_length_scale":1.16,"goal_half_width":170,"ball_mass":2.6,"player_mass":4.5,"HV":10,"PCAP":520,"ball_player_restitution":0.78,"player_player_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"PF1":430,"PF2":4,"PV0":820,"shot_power_coefficient":2.5,"LMAX":175,"ball_wall_restitution":0.93,"fast_ball_drop":0.22,"player_wall_restitution":0.93,"post_restitution":1.9,"formation":"1-2-2","scene_speed":1.03,"turn_seconds":10,"ball_spin_transfer":0.24}'::jsonb,
    updated_at = now()
where game = 'finger_soccer';
update public.nx_physics_contracts
set version = 'physics-2026-11-18-v2',
    contract = '{"BR":35,"PR":58.5,"ball_mass":2.6,"object_mass":4,"HV":10,"PCAP":520,"max_shot_speed":520,"ball_object_restitution":0.78,"object_object_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"shot_power_coefficient":2.5,"LMAX":175,"cushion_restitution":0.93}'::jsonb,
    updated_at = now()
where game = 'billiards';
update public.nx_physics_contracts
set version = 'physics-2026-11-18-v2',
    contract = '{"BR":35,"PR":58.5,"coin_mass":4,"striker_mass":2.6,"HV":10,"PCAP":520,"striker_coin_restitution":0.78,"coin_coin_restitution":0.72,"ball_friction":510,"ball_traction":0.175,"shot_power_coefficient":2.5,"LMAX":175,"wall_restitution":0.93,"turn_seconds":10}'::jsonb,
    updated_at = now()
where game = 'carrom';
