-- NEXORA GAMES project (eyzafhrefnqlwcjpcdyg) · part 2: rooms, matches, matchmaking, invites, stats, tournaments engine.
-- Generated from the live auth-project catalog (2026-11-17) and adapted: user FKs point at the profiles mirror (auth.users
-- does not exist here), permissions come from the JWT claim nx_perms + the nx_staff mirror pushed by the auth project.

create table if not exists public.nx_rooms (
  id uuid not null default gen_random_uuid(),
  code text not null,
  game text not null,
  host uuid not null,
  seats integer not null default 2,
  status text not null default 'lobby'::text,
  is_private boolean not null default false,
  quick boolean not null default false,
  settings jsonb not null default '{}'::jsonb,
  match_id uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.nx_room_players (
  room_id uuid not null,
  user_id uuid not null,
  seat integer not null,
  ready boolean not null default false,
  joined_at timestamp with time zone not null default now(),
  last_seen timestamp with time zone not null default now()
);
create table if not exists public.nx_matches (
  id uuid not null default gen_random_uuid(),
  room_id uuid,
  game text not null,
  players uuid[] not null,
  names text[] not null default '{}'::text[],
  seed bigint not null,
  settings jsonb not null default '{}'::jsonb,
  status text not null default 'playing'::text,
  winner_seats integer[],
  scores integer[],
  reason text,
  last_seq integer not null default 0,
  state_hash text,
  started_at timestamp with time zone not null default now(),
  ended_at timestamp with time zone
);
create table if not exists public.nx_match_moves (
  match_id uuid not null,
  seq integer not null,
  seat integer not null,
  by_user uuid not null,
  kind text not null default 'move'::text,
  move jsonb not null,
  hash text,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_match_results (
  match_id uuid not null,
  user_id uuid not null,
  game text not null,
  seat integer not null,
  outcome text not null,
  score integer not null default 0,
  rating_delta integer not null default 0,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_match_secrets (
  match_id uuid not null,
  user_id uuid not null,
  slot text not null default 'role'::text,
  data jsonb not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_game_stats (
  user_id uuid not null,
  game text not null,
  played integer not null default 0,
  won integer not null default 0,
  lost integer not null default 0,
  draw integer not null default 0,
  rating integer not null default 1000,
  best integer not null default 0,
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.nx_invites (
  id bigserial not null,
  from_user uuid not null,
  to_user uuid not null,
  kind text not null default 'game'::text,
  room_id uuid,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending'::text,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_xp_events (
  id bigserial not null,
  user_id uuid not null,
  idem_key text not null,
  event text not null,
  xp integer not null default 0,
  coins integer not null default 0,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_tournaments (
  id uuid not null default gen_random_uuid(),
  title text not null,
  description text not null default ''::text,
  rules text not null default ''::text,
  game text not null default 'finger_soccer'::text,
  created_by uuid not null,
  status text not null default 'draft'::text,
  paused boolean not null default false,
  format text not null,
  capacity integer not null,
  min_players integer not null default 2,
  config jsonb not null default '{}'::jsonb,
  reg_mode text not null default 'open'::text,
  min_level integer not null default 0,
  min_xp integer not null default 0,
  min_rating integer not null default 0,
  fee_coins integer not null default 0,
  fee_gems integer not null default 0,
  prize jsonb not null default '{}'::jsonb,
  reg_open_at timestamp with time zone not null,
  reg_close_at timestamp with time zone not null,
  draw_at timestamp with time zone not null,
  start_at timestamp with time zone not null,
  seeding text not null default 'random'::text,
  seed bigint,
  stage text not null default 'main'::text,
  escrow_coins integer not null default 0,
  escrow_gems integer not null default 0,
  paid_out boolean not null default false,
  cancel_reason text,
  winner uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  published_at timestamp with time zone,
  drawn_at timestamp with time zone,
  started_at timestamp with time zone,
  finished_at timestamp with time zone
);
create table if not exists public.nx_t_codes (
  id uuid not null default gen_random_uuid(),
  tournament_id uuid not null,
  code text not null,
  max_uses integer not null default 1,
  uses integer not null default 0,
  expires_at timestamp with time zone,
  revoked boolean not null default false,
  requires_approval boolean not null default false,
  created_by uuid,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_code_attempts (
  id bigserial not null,
  user_id uuid not null,
  code text not null,
  ok boolean not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_entries (
  tournament_id uuid not null,
  user_id uuid not null,
  status text not null,
  seed integer,
  group_no integer,
  rating integer not null default 1000,
  paid_coins integer not null default 0,
  paid_gems integer not null default 0,
  fee_ref bigint,
  code_id uuid,
  note text,
  place integer,
  decided_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_matches (
  id uuid not null default gen_random_uuid(),
  tournament_id uuid not null,
  stage text not null default 'main'::text,
  bracket text not null,
  round integer not null,
  idx integer not null default 0,
  tslot integer not null default 1,
  group_no integer,
  label text,
  p1 uuid,
  p2 uuid,
  p1_set boolean not null default false,
  p2_set boolean not null default false,
  win_to uuid,
  win_slot smallint,
  lose_to uuid,
  lose_slot smallint,
  best_of smallint not null default 1,
  aggregate boolean not null default false,
  status text not null default 'pending'::text,
  scheduled_at timestamp with time zone,
  ready_deadline timestamp with time zone,
  p1_ready boolean not null default false,
  p2_ready boolean not null default false,
  games integer not null default 0,
  w1 integer not null default 0,
  w2 integer not null default 0,
  g1 integer not null default 0,
  g2 integer not null default 0,
  winner uuid,
  loser uuid,
  is_draw boolean not null default false,
  game_match uuid,
  result_note text,
  finished_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_games (
  game_match uuid not null,
  tmatch uuid not null,
  n integer not null,
  home uuid not null,
  away uuid not null,
  golden boolean not null default false,
  ended_at timestamp with time zone,
  srv_winner uuid,
  srv_s_home integer,
  srv_s_away integer,
  accepted boolean not null default false,
  disputed boolean not null default false,
  winner uuid,
  s_home integer,
  s_away integer,
  source text,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_reports (
  game_match uuid not null,
  user_id uuid not null,
  winner uuid,
  s_home integer not null,
  s_away integer not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_jobs (
  id bigserial not null,
  kind text not null,
  tournament_id uuid,
  ref uuid,
  run_at timestamp with time zone not null,
  done_at timestamp with time zone,
  attempts integer not null default 0,
  last_error text,
  idem_key text not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_ledger (
  id bigserial not null,
  tournament_id uuid not null,
  user_id uuid,
  kind text not null,
  currency text not null,
  amount integer not null,
  place integer,
  idem_key text not null,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_notifications (
  id bigserial not null,
  user_id uuid not null,
  tournament_id uuid,
  tmatch uuid,
  kind text not null,
  data jsonb not null default '{}'::jsonb,
  read boolean not null default false,
  dedup text,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_audit (
  id bigserial not null,
  tournament_id uuid,
  actor uuid,
  action text not null,
  data jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default now()
);
create table if not exists public.nx_t_staff (
  tournament_id uuid not null,
  user_id uuid not null,
  added_by uuid,
  created_at timestamp with time zone not null default now()
);
do $$ begin alter table public.nx_game_stats add constraint nx_game_stats_pkey PRIMARY KEY (user_id, game); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_invites add constraint nx_invites_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_moves add constraint nx_match_moves_pkey PRIMARY KEY (match_id, seq); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_results add constraint nx_match_results_pkey PRIMARY KEY (match_id, user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_secrets add constraint nx_match_secrets_pkey PRIMARY KEY (match_id, user_id, slot); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_matches add constraint nx_matches_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_room_players add constraint nx_room_players_pkey PRIMARY KEY (room_id, user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_rooms add constraint nx_rooms_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_audit add constraint nx_t_audit_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_code_attempts add constraint nx_t_code_attempts_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_codes add constraint nx_t_codes_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_entries add constraint nx_t_entries_pkey PRIMARY KEY (tournament_id, user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_games add constraint nx_t_games_pkey PRIMARY KEY (game_match); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_jobs add constraint nx_t_jobs_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_ledger add constraint nx_t_ledger_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_notifications add constraint nx_t_notifications_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_reports add constraint nx_t_reports_pkey PRIMARY KEY (game_match, user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_staff add constraint nx_t_staff_pkey PRIMARY KEY (tournament_id, user_id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_xp_events add constraint nx_xp_events_pkey PRIMARY KEY (id); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_room_players add constraint nx_room_players_room_id_seat_key UNIQUE (room_id, seat); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_rooms add constraint nx_rooms_code_key UNIQUE (code); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_codes add constraint nx_t_codes_code_key UNIQUE (code); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_jobs add constraint nx_t_jobs_idem_key_key UNIQUE (idem_key); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_ledger add constraint nx_t_ledger_idem_key_key UNIQUE (idem_key); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_notifications add constraint nx_t_notifications_user_id_dedup_key UNIQUE (user_id, dedup); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_xp_events add constraint nx_xp_events_user_id_idem_key_key UNIQUE (user_id, idem_key); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_invites add constraint nx_invites_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'declined'::text, 'expired'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_results add constraint nx_match_results_outcome_check CHECK ((outcome = ANY (ARRAY['win'::text, 'loss'::text, 'draw'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_matches add constraint nx_matches_status_check CHECK ((status = ANY (ARRAY['playing'::text, 'finished'::text, 'abandoned'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_rooms add constraint nx_rooms_status_check CHECK ((status = ANY (ARRAY['lobby'::text, 'playing'::text, 'closed'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_rooms add constraint nx_rooms_seats_check CHECK (((seats >= 2) AND (seats <= 12))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_codes add constraint nx_t_codes_max_uses_check CHECK (((max_uses >= 1) AND (max_uses <= 1000))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_codes add constraint nx_t_codes_code_check CHECK ((code ~ '^[A-HJ-NP-Z2-9]{8}$'::text)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_entries add constraint nx_t_entries_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'waitlist'::text, 'withdrawn'::text, 'removed'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_ledger add constraint nx_t_ledger_currency_check CHECK ((currency = ANY (ARRAY['coins'::text, 'gems'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_ledger add constraint nx_t_ledger_kind_check CHECK ((kind = ANY (ARRAY['entry_fee'::text, 'refund'::text, 'payout'::text, 'house_fee'::text, 'entry_fee_unlimited'::text, 'refund_unlimited'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'scheduled'::text, 'ready_check'::text, 'playing'::text, 'done'::text, 'walkover'::text, 'bye'::text, 'disputed'::text, 'void'::text, 'skipped'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_best_of_check CHECK ((best_of = ANY (ARRAY[1, 2, 3, 5]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_bracket_check CHECK ((bracket = ANY (ARRAY['W'::text, 'L'::text, 'GF'::text, 'GF2'::text, 'P3'::text, 'RR'::text, 'G'::text, 'SW'::text, 'C'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'scheduled'::text, 'registering'::text, 'closed'::text, 'drawn'::text, 'live'::text, 'finished'::text, 'cancelled'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_seeding_check CHECK ((seeding = ANY (ARRAY['random'::text, 'rating'::text, 'manual'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_reg_mode_check CHECK ((reg_mode = ANY (ARRAY['open'::text, 'approval'::text, 'code'::text, 'code_approval'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_min_players_check CHECK ((min_players >= 2)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_format_check CHECK ((format = ANY (ARRAY['single_elim'::text, 'double_elim'::text, 'two_legs'::text, 'round_robin'::text, 'groups_ko'::text, 'swiss'::text, 'custom'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_fee_gems_check CHECK (((fee_gems >= 0) AND (fee_gems <= 100000))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_fee_coins_check CHECK (((fee_coins >= 0) AND (fee_coins <= 1000000))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_escrow_gems_check CHECK ((escrow_gems >= 0)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_escrow_coins_check CHECK ((escrow_coins >= 0)); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_capacity_check CHECK (((capacity >= 2) AND (capacity <= 64))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_t_times CHECK (((reg_open_at < reg_close_at) AND (reg_close_at <= draw_at) AND (draw_at <= start_at))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_title_check CHECK (((char_length(title) >= 3) AND (char_length(title) <= 80))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_stage_check CHECK ((stage = ANY (ARRAY['main'::text, 'groups'::text, 'ko'::text]))); exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_game_stats add constraint nx_game_stats_profile_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_invites add constraint nx_invites_room_id_fkey FOREIGN KEY (room_id) REFERENCES nx_rooms(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_moves add constraint nx_match_moves_match_id_fkey FOREIGN KEY (match_id) REFERENCES nx_matches(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_results add constraint nx_match_results_profile_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_results add constraint nx_match_results_match_id_fkey FOREIGN KEY (match_id) REFERENCES nx_matches(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_match_secrets add constraint nx_match_secrets_match_id_fkey FOREIGN KEY (match_id) REFERENCES nx_matches(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_matches add constraint nx_matches_room_id_fkey FOREIGN KEY (room_id) REFERENCES nx_rooms(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_room_players add constraint nx_room_players_room_id_fkey FOREIGN KEY (room_id) REFERENCES nx_rooms(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_room_players add constraint nx_room_players_profile_fk FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_rooms add constraint nx_rooms_host_fkey FOREIGN KEY (host) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_codes add constraint nx_t_codes_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_entries add constraint nx_t_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_entries add constraint nx_t_entries_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_games add constraint nx_t_games_tmatch_fkey FOREIGN KEY (tmatch) REFERENCES nx_t_matches(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_games add constraint nx_t_games_game_match_fkey FOREIGN KEY (game_match) REFERENCES nx_matches(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_jobs add constraint nx_t_jobs_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_ledger add constraint nx_t_ledger_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE RESTRICT; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_lose_to_fkey FOREIGN KEY (lose_to) REFERENCES nx_t_matches(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_win_to_fkey FOREIGN KEY (win_to) REFERENCES nx_t_matches(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_p1_fkey FOREIGN KEY (p1) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_matches add constraint nx_t_matches_p2_fkey FOREIGN KEY (p2) REFERENCES profiles(id) ON DELETE SET NULL; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_notifications add constraint nx_t_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_notifications add constraint nx_t_notifications_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_reports add constraint nx_t_reports_game_match_fkey FOREIGN KEY (game_match) REFERENCES nx_t_games(game_match) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_staff add constraint nx_t_staff_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_t_staff add constraint nx_t_staff_tournament_id_fkey FOREIGN KEY (tournament_id) REFERENCES nx_tournaments(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_tournaments add constraint nx_tournaments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
do $$ begin alter table public.nx_xp_events add constraint nx_xp_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE; exception when duplicate_object or duplicate_table or invalid_table_definition then null; end $$;
CREATE INDEX IF NOT EXISTS nx_rooms_open ON public.nx_rooms USING btree (game, status, quick, created_at);
CREATE INDEX IF NOT EXISTS nx_matches_room ON public.nx_matches USING btree (room_id, started_at DESC);
CREATE INDEX IF NOT EXISTS nx_invites_to ON public.nx_invites USING btree (to_user, status, created_at DESC);
CREATE INDEX IF NOT EXISTS nx_xp_events_user_day ON public.nx_xp_events USING btree (user_id, created_at);
CREATE INDEX IF NOT EXISTS nx_tournaments_status ON public.nx_tournaments USING btree (status, start_at);
CREATE INDEX IF NOT EXISTS nx_t_audit_t ON public.nx_t_audit USING btree (tournament_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nx_t_code_attempts_user ON public.nx_t_code_attempts USING btree (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nx_t_codes_t ON public.nx_t_codes USING btree (tournament_id);
CREATE INDEX IF NOT EXISTS nx_t_entries_user ON public.nx_t_entries USING btree (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nx_t_games_tm ON public.nx_t_games USING btree (tmatch, n);
CREATE INDEX IF NOT EXISTS nx_t_jobs_due ON public.nx_t_jobs USING btree (run_at) WHERE (done_at IS NULL);
CREATE INDEX IF NOT EXISTS nx_t_ledger_t ON public.nx_t_ledger USING btree (tournament_id, created_at);
CREATE INDEX IF NOT EXISTS nx_t_ledger_user ON public.nx_t_ledger USING btree (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS nx_t_matches_t ON public.nx_t_matches USING btree (tournament_id, bracket, round, idx);
CREATE INDEX IF NOT EXISTS nx_t_matches_due ON public.nx_t_matches USING btree (status, scheduled_at);
CREATE INDEX IF NOT EXISTS nx_t_matches_p1 ON public.nx_t_matches USING btree (p1);
CREATE INDEX IF NOT EXISTS nx_t_matches_p2 ON public.nx_t_matches USING btree (p2);
CREATE INDEX IF NOT EXISTS nx_t_notifications_user ON public.nx_t_notifications USING btree (user_id, created_at DESC);
alter table public.nx_rooms enable row level security;
alter table public.nx_room_players enable row level security;
alter table public.nx_matches enable row level security;
alter table public.nx_match_moves enable row level security;
alter table public.nx_match_results enable row level security;
alter table public.nx_match_secrets enable row level security;
alter table public.nx_game_stats enable row level security;
alter table public.nx_invites enable row level security;
alter table public.nx_xp_events enable row level security;
alter table public.nx_tournaments enable row level security;
alter table public.nx_t_codes enable row level security;
alter table public.nx_t_code_attempts enable row level security;
alter table public.nx_t_entries enable row level security;
alter table public.nx_t_matches enable row level security;
alter table public.nx_t_games enable row level security;
alter table public.nx_t_reports enable row level security;
alter table public.nx_t_jobs enable row level security;
alter table public.nx_t_ledger enable row level security;
alter table public.nx_t_notifications enable row level security;
alter table public.nx_t_audit enable row level security;
alter table public.nx_t_staff enable row level security;


-- Permissions on the games project. Source of truth = auth project (nx_staff + nx_admin_perms), pushed here as a
-- read-only mirror (nx_staff_put, service_role only). For the caller, the JWT claim nx_perms (access token hook) is used too,
-- so a fresh grant works on the next token refresh even before the mirror push lands.
create table if not exists public.nx_staff (
  user_id uuid primary key,
  role text,                       -- owner | admin | organizer | null (per-permission admin only)
  perms text[] not null default '{}',
  unlimited boolean not null default false,   -- unlimited gem prizes (appointed by the main admin only)
  gem_budget integer,                          -- per-manager gem prize budget when not unlimited (null = none)
  updated_at timestamptz not null default now()
);
alter table public.nx_staff enable row level security;
drop policy if exists nx_staff_read on public.nx_staff;
create policy nx_staff_read on public.nx_staff for select to authenticated using (true);

create or replace function public.nx_staff_put(p_rows jsonb, p_replace boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare e jsonb; n int := 0;
begin
  if p_replace then delete from nx_staff where user_id not in
    (select (x ->> 'user_id')::uuid from jsonb_array_elements(coalesce(p_rows, '[]')) x); end if;
  for e in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) loop
    if coalesce(e ->> 'deleted', 'false') = 'true' then
      delete from nx_staff where user_id = (e ->> 'user_id')::uuid;
    else
      insert into nx_staff(user_id, role, perms, unlimited, gem_budget, updated_at)
      values ((e ->> 'user_id')::uuid, e ->> 'role',
              coalesce((select array_agg(x) from jsonb_array_elements_text(e -> 'perms') x), '{}'),
              coalesce((e ->> 'unlimited')::boolean, false), (e ->> 'gem_budget')::int, now())
      on conflict (user_id) do update set role = excluded.role, perms = excluded.perms, unlimited = excluded.unlimited,
        gem_budget = excluded.gem_budget, updated_at = now();
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.nx_staff_put(jsonb, boolean) from public, anon, authenticated;
grant execute on function public.nx_staff_put(jsonb, boolean) to service_role;

create or replace function public.nx_is_owner(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and ((u = auth.uid() and nx_perm('owner'))
    or exists (select 1 from nx_staff where user_id = u and role = 'owner'))
$$;
create or replace function public.nx_has_perm(p text, u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_is_owner(u) or (u = auth.uid() and nx_perm(p))
    or exists (select 1 from nx_staff where user_id = u and (p = any(perms) or 'all' = any(perms))))
$$;
-- Tournament admin: owner, 'tournaments' permission, or legacy staff role admin.
create or replace function public.nx_t_is_admin(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_has_perm('tournaments', u)
    or exists (select 1 from nx_staff where user_id = u and role = 'admin'))
$$;
-- Tournament manager (may create tournaments): admins + organizers.
create or replace function public.nx_t_is_organizer(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_t_is_admin(u) or nx_has_perm('organizer', u)
    or exists (select 1 from nx_staff where user_id = u and role = 'organizer'))
$$;
-- Unlimited gem prizes: owner or a manager the owner appointed with that option.
create or replace function public.nx_unlimited(u uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select u is not null and (nx_is_owner(u) or (u = auth.uid() and nx_perm('unlimited_gems'))
    or exists (select 1 from nx_staff where user_id = u and unlimited))
$$;
create or replace function public.is_admin(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$ select nx_t_is_admin(uid) $$;
grant execute on function public.nx_is_owner(uuid), public.nx_has_perm(text, uuid), public.nx_t_is_admin(uuid),
  public.nx_t_is_organizer(uuid), public.nx_unlimited(uuid), public.is_admin(uuid) to authenticated;

create or replace function public._nx_owner_guard() returns text
language sql stable security definer set search_path = public as $$
  select case when auth.uid() is null then 'not_signed_in' when not nx_t_is_admin(auth.uid()) then 'forbidden' else null end
$$;
revoke all on function public._nx_owner_guard() from public, anon, authenticated;


-- ---------------------------------------------------------------- functions (live definitions, ported)
CREATE OR REPLACE FUNCTION public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare i int; uid uuid; oc text; sc int; v_xp int; v_co int; rd int; n int := array_length(m.players, 1);
begin
  for i in 1..n loop
    uid := m.players[i];
    if p_winners is null or array_length(p_winners, 1) is null then oc := 'draw';
    elsif (i - 1) = any(p_winners) then oc := case when array_length(p_winners, 1) = n then 'draw' else 'win' end;
    else oc := 'loss'; end if;
    sc := coalesce(p_scores[i], 0);
    rd := case oc when 'win' then 16 when 'loss' then -12 else 0 end;
    insert into nx_match_results(match_id, user_id, game, seat, outcome, score, rating_delta)
    values (m.id, uid, m.game, i - 1, oc, sc, rd) on conflict do nothing;
    if found then
      insert into nx_game_stats(user_id, game, played, won, lost, draw, rating, best)
      values (uid, m.game, 1, (oc = 'win')::int, (oc = 'loss')::int, (oc = 'draw')::int, greatest(0, 1000 + rd), sc)
      on conflict (user_id, game) do update set
        played = nx_game_stats.played + 1,
        won = nx_game_stats.won + (excluded.won),
        lost = nx_game_stats.lost + (excluded.lost),
        draw = nx_game_stats.draw + (excluded.draw),
        rating = greatest(0, nx_game_stats.rating + rd),
        best = greatest(nx_game_stats.best, excluded.best),
        updated_at = now();
      v_xp := case oc when 'win' then 80 when 'draw' then 40 else 20 end;
      v_co := case oc when 'win' then 50 when 'draw' then 20 else 8 end;
      insert into nx_xp_events(user_id, idem_key, event, xp, coins)
      values (uid, 'match:' || m.id::text, 'online.' || m.game || '.' || oc, v_xp, v_co) on conflict do nothing;
      if found then
        update profiles p set xp = p.xp + v_xp, coins = p.coins + v_co, level = level_for_xp(p.xp + v_xp) where p.id = uid;
      end if;
    end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_leave_all(me uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  for r in select rp.room_id from nx_room_players rp join nx_rooms x on x.id = rp.room_id
            where rp.user_id = me and x.status = 'lobby' loop
    perform nx_leave_room(r.room_id);
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_audit(p_t uuid, p_actor uuid, p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into nx_t_audit(tournament_id, actor, action, data) values (p_t, p_actor, p_action, coalesce(p_data, '{}'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_better_seed(p_t uuid, a uuid, b uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select user_id from nx_t_entries where tournament_id = p_t and user_id in (a, b) order by seed nulls last, user_id limit 1
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_bo(t nx_tournaments, p_kind text)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare v int;
begin
  if t.format = 'two_legs' then
    if p_kind = 'final' and _nx_t_cfg_bool(t.config, 'final_one_leg', false) then return 1; end if;
    return 2;
  end if;
  v := _nx_t_cfg_int(t.config, 'bo_' || p_kind, _nx_t_cfg_int(t.config, 'bo_early', 1));
  if v not in (1, 2, 3, 5) then v := 1; end if;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_cancel(p_t uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status in ('finished', 'cancelled') then return; end if;
  for r in select user_id from nx_t_entries where tournament_id = p_t and (paid_coins > 0 or paid_gems > 0) loop
    perform _nx_t_refund(p_t, r.user_id, 'cancelled');
  end loop;
  update nx_t_matches set status = 'void', result_note = 'cancelled', updated_at = now()
   where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
  update nx_tournaments set status = 'cancelled', cancel_reason = left(p_reason, 200), finished_at = now(), updated_at = now()
   where id = p_t;
  update nx_t_jobs set done_at = now(), last_error = 'cancelled' where tournament_id = p_t and done_at is null;
  perform _nx_t_notify_all(p_t, 'cancelled', jsonb_build_object('reason', p_reason), 'cancelled:' || p_t,
                           array['approved', 'pending', 'waitlist']);
  perform _nx_t_audit(p_t, p_actor, 'cancelled', jsonb_build_object('reason', p_reason));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_cfg_bool(c jsonb, k text, d boolean)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when jsonb_typeof(c -> k) = 'boolean' then (c ->> k)::boolean else d end
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_cfg_int(c jsonb, k text, d integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when jsonb_typeof(c -> k) = 'number' then (c ->> k)::numeric::int
              when jsonb_typeof(c -> k) = 'string' and (c ->> k) ~ '^-?[0-9]+$' then (c ->> k)::int
              else d end
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_charge(p_t uuid, p_user uuid, p_coins integer, p_gems integer)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare lid bigint; ok uuid; unl boolean := nx_unlimited(p_user);
        k text := case when unl then 'ufee:' else 'fee:' end || p_t || ':' || p_user || ':'
                  || floor(extract(epoch from clock_timestamp()) * 1000)::bigint;
        kd text := case when unl then 'entry_fee_unlimited' else 'entry_fee' end;
begin
  if coalesce(p_coins, 0) = 0 and coalesce(p_gems, 0) = 0 then return 0; end if;
  if not unl then
    update profiles set coins = coins - p_coins, gems = coalesce(gems, 0) - p_gems
     where id = p_user and coins >= p_coins and coalesce(gems, 0) >= p_gems returning id into ok;
    if ok is null then return null; end if;
  end if;
  if p_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', -p_coins, k || ':c') returning id into lid;
  end if;
  if p_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', -p_gems, k || ':g') returning id into lid;
  end if;
  update nx_tournaments set escrow_coins = escrow_coins + p_coins, escrow_gems = escrow_gems + p_gems where id = p_t;
  return lid;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_check(p_m uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; t nx_tournaments; at timestamptz;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'pending' or not (m.p1_set and m.p2_set) then return; end if;
  if m.p1 is null or m.p2 is null then
    perform _nx_t_complete(m.id, coalesce(m.p1, m.p2), null, false, 'bye', 'bye');
    return;
  end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  at := greatest(_nx_t_planned(t, m.tslot), now());
  update nx_t_matches set status = 'scheduled', scheduled_at = at, updated_at = now() where id = m.id;
  if at - interval '10 minutes' > now() + interval '1 minute' then
    perform _nx_t_job('remind_match', t.id, m.id, at - interval '10 minutes', 'remind_match:' || m.id);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_check_code(p_user uuid, p_t uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c nx_t_codes; norm text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); bad int; err text;
begin
  select count(*) into bad from nx_t_code_attempts where user_id = p_user and not ok and created_at > now() - interval '15 minutes';
  if bad >= 5 then return jsonb_build_object('ok', false, 'error', 'too_many_attempts'); end if;
  select * into c from nx_t_codes where code = norm and (p_t is null or tournament_id = p_t);
  if c.id is null then err := 'bad_code';
  elsif c.revoked then err := 'code_revoked';
  elsif c.expires_at is not null and c.expires_at < now() then err := 'code_expired';
  elsif c.uses >= c.max_uses then err := 'code_used_up';
  end if;
  insert into nx_t_code_attempts(user_id, code, ok) values (p_user, left(norm, 16), err is null);
  if err is not null then return jsonb_build_object('ok', false, 'error', err); end if;
  return jsonb_build_object('ok', true, 'code_id', c.id, 'tournament_id', c.tournament_id, 'requires_approval', c.requires_approval);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_complete(p_m uuid, p_winner uuid, p_loser uuid, p_draw boolean, p_status text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; elim boolean;
begin
  update nx_t_matches set winner = p_winner, loser = p_loser, is_draw = coalesce(p_draw, false), status = p_status,
         result_note = coalesce(p_note, result_note), finished_at = now(), game_match = null, ready_deadline = null,
         updated_at = now()
   where id = p_m and status not in ('done', 'walkover', 'bye', 'void', 'skipped')
  returning * into m;
  if m.id is null then return; end if;
  if not _nx_t_gen_on() and p_status <> 'bye' then
    elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
    perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'result',
      jsonb_build_object('won', p_winner = m.p1, 'draw', coalesce(p_draw, false), 'w1', m.w1, 'w2', m.w2, 'g1', m.g1, 'g2', m.g2,
                         'note', p_note), 'result:' || m.id);
    perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'result',
      jsonb_build_object('won', p_winner = m.p2, 'draw', coalesce(p_draw, false), 'w1', m.w1, 'w2', m.w2, 'g1', m.g1, 'g2', m.g2,
                         'note', p_note), 'result:' || m.id);
    if elim then
      if p_winner is not null and (m.win_to is not null or m.bracket = 'GF' and p_winner <> m.p1) then
        perform _nx_t_notify(p_winner, m.tournament_id, m.id, 'advanced', '{}'::jsonb, 'adv:' || m.id);
      end if;
      if p_loser is not null and m.lose_to is null and not (m.bracket = 'GF' and p_loser = m.p1) then
        perform _nx_t_notify(p_loser, m.tournament_id, m.id, 'eliminated', '{}'::jsonb, 'elim:' || m.id);
      end if;
    end if;
  elsif p_status = 'bye' and not _nx_t_gen_on() and p_winner is not null then
    perform _nx_t_notify(p_winner, m.tournament_id, m.id, 'bye', '{}'::jsonb, 'bye:' || m.id);
  end if;
  perform _nx_t_audit(m.tournament_id, null, 'match_' || p_status,
                      jsonb_build_object('match', m.id, 'winner', p_winner, 'loser', p_loser, 'draw', p_draw, 'note', p_note));
  perform _nx_t_propagate(m.id);
  perform _nx_t_progress(m.tournament_id);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_dispute(p_m uuid, p_actor uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status in ('done', 'walkover', 'bye', 'void', 'skipped', 'disputed') then return; end if;
  update nx_t_matches set status = 'disputed', result_note = left(p_reason, 120), updated_at = now() where id = p_m;
  if m.game_match is not null then update nx_t_games set disputed = true where game_match = m.game_match; end if;
  perform _nx_t_notify_managers(m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'dispute:' || m.id);
  perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'disputep:' || m.id);
  perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'dispute', jsonb_build_object('reason', p_reason), 'disputep:' || m.id);
  perform _nx_t_audit(m.tournament_id, p_actor, 'dispute', jsonb_build_object('match', m.id, 'reason', p_reason));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_downstream_free(p_m uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select not exists (
    select 1 from nx_t_matches d, nx_t_matches m
     where m.id = p_m and (d.id = m.win_to or d.id = m.lose_to
                           or (m.bracket = 'GF' and d.tournament_id = m.tournament_id and d.bracket = 'GF2'))
       and (d.games > 0 or d.status in ('playing', 'done', 'walkover', 'disputed')))
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_draw(p_t uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int; players uuid[]; g int; a int; i int; grp int; r record; maxr int := 0; rr int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status not in ('registering', 'closed') then return; end if;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  if n < greatest(2, t.min_players) then
    perform _nx_t_cancel(p_t, 'not_enough_players', p_actor);
    return;
  end if;
  -- whoever did not make it (pending approval / waitlist) gets the fee back
  for r in select user_id from nx_t_entries where tournament_id = p_t and status in ('pending', 'waitlist') loop
    perform _nx_t_refund(p_t, r.user_id, 'not_drawn');
    update nx_t_entries set status = 'rejected', note = 'not_drawn', updated_at = now()
     where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'rejected', jsonb_build_object('reason', 'not_drawn'), 'notdrawn:' || p_t);
  end loop;
  if t.seed is null then
    t.seed := floor(random() * 2147483646)::bigint + 1;
    update nx_tournaments set seed = t.seed where id = p_t;
  end if;
  select array_agg(user_id order by
           case when t.seeding = 'manual' then coalesce(seed, 100000) else 0 end,
           case when t.seeding = 'rating' then -rating else 0 end,
           md5(t.seed::text || user_id::text))
    into players from nx_t_entries where tournament_id = p_t and status = 'approved';
  for i in 1..n loop
    update nx_t_entries set seed = i, group_no = null where tournament_id = p_t and user_id = players[i];
  end loop;
  delete from nx_t_matches where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs') then
    perform _nx_t_gen_se(p_t, players, 'main', 0, 0);
  elsif t.format = 'double_elim' then
    perform _nx_t_gen_de(p_t, players);
  elsif t.format = 'round_robin' then
    perform _nx_t_gen_rr(p_t, players, null, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'RR', 'main');
  elsif t.format = 'groups_ko' then
    g := greatest(1, least(_nx_t_cfg_int(t.config, 'groups', 2), n / 2));
    for i in 1..n loop
      -- snake: 1..g, g..1, ...
      grp := case when ((i - 1) / g) % 2 = 0 then ((i - 1) % g) + 1 else g - ((i - 1) % g) end;
      update nx_t_entries set group_no = grp where tournament_id = p_t and user_id = players[i];
    end loop;
    for grp in 1..g loop
      rr := _nx_t_gen_rr(p_t, (select array_agg(user_id order by seed) from nx_t_entries
                                where tournament_id = p_t and status = 'approved' and group_no = grp),
                         grp, _nx_t_cfg_bool(t.config, 'rr_double', false), 0, 0, 'G', 'groups');
    end loop;
    update nx_tournaments set stage = 'groups' where id = p_t;
  elsif t.format = 'swiss' then
    perform _nx_t_swiss_round(p_t, 1);
  end if;
  update nx_tournaments set status = 'drawn', drawn_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'drawn', '{}'::jsonb, 'drawn:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'drawn', jsonb_build_object('seed', t.seed, 'players', n, 'seeding', t.seeding));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_fill_from_waitlist(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int; r record;
begin
  select * into t from nx_tournaments where id = p_t;
  select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
  for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'waitlist' order by created_at loop
    exit when n >= t.capacity;
    update nx_t_entries set status = 'approved', updated_at = now() where tournament_id = p_t and user_id = r.user_id;
    perform _nx_t_notify(r.user_id, p_t, null, 'promoted', '{}'::jsonb, 'promo:' || p_t || ':' || r.user_id);
    n := n + 1;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_finish(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; placed int; r record; i int := 0; champ uuid;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status in ('finished', 'cancelled') then return; end if;
  update nx_t_entries set place = null where tournament_id = p_t;
  if t.format in ('single_elim', 'two_legs', 'double_elim') then
    placed := _nx_t_place_elim(p_t, 'main');
  elsif t.format = 'groups_ko' then
    placed := _nx_t_place_elim(p_t, 'ko');
    update nx_t_entries set place = placed + 1 where tournament_id = p_t and status = 'approved' and place is null;
  else
    for r in select x.user_id from _nx_t_table(p_t, 'main', null) x
              order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed loop
      i := i + 1;
      update nx_t_entries set place = i where tournament_id = p_t and user_id = r.user_id;
    end loop;
  end if;
  select user_id into champ from nx_t_entries where tournament_id = p_t and place = 1 order by seed limit 1;
  update nx_tournaments set status = 'finished', finished_at = now(), winner = champ, updated_at = now() where id = p_t;
  perform _nx_t_payout(p_t);
  perform _nx_t_notify_all(p_t, 'finished', jsonb_build_object('winner', champ,
            'winner_name', (select username from profiles where id = champ)), 'finished:' || p_t);
  perform _nx_t_audit(p_t, null, 'finished', jsonb_build_object('winner', champ));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_game_result(p_gm uuid, p_winner uuid, p_s_home integer, p_s_away integer, p_source text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g nx_t_games; m nx_t_matches; s1 int; s2 int; need int; elim boolean; w uuid; l uuid; draw boolean := false;
        decided boolean := false;
begin
  select * into g from nx_t_games where game_match = p_gm for update;
  if g.game_match is null or g.accepted then return; end if;
  update nx_t_games set accepted = true, disputed = false, winner = p_winner, s_home = p_s_home, s_away = p_s_away,
         source = p_source where game_match = p_gm;
  select * into m from nx_t_matches where id = g.tmatch for update;
  if m.status in ('done', 'walkover', 'bye', 'void', 'skipped') then return; end if;
  if g.home = m.p1 then s1 := coalesce(p_s_home, 0); s2 := coalesce(p_s_away, 0);
  else s1 := coalesce(p_s_away, 0); s2 := coalesce(p_s_home, 0); end if;
  update nx_t_matches set games = games + 1, g1 = g1 + s1, g2 = g2 + s2,
         w1 = w1 + coalesce(p_winner = p1, false)::int, w2 = w2 + coalesce(p_winner = p2, false)::int, game_match = null, updated_at = now()
   where id = m.id returning * into m;
  elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
  need := m.best_of / 2 + 1;
  if m.aggregate then
    if m.games >= 2 then
      if m.games > 2 and p_winner is not null then w := p_winner; decided := true;
      elsif m.g1 > m.g2 then w := m.p1; decided := true;
      elsif m.g2 > m.g1 then w := m.p2; decided := true;
      elsif not elim then draw := true; decided := true;
      end if;
    end if;
  else
    if m.best_of <> 2 and m.w1 >= need then w := m.p1; decided := true;
    elsif m.best_of <> 2 and m.w2 >= need then w := m.p2; decided := true;
    elsif m.games >= m.best_of then
      if m.w1 > m.w2 then w := m.p1; decided := true;
      elsif m.w2 > m.w1 then w := m.p2; decided := true;
      elsif not elim then draw := true; decided := true;
      end if; -- knockout tie → golden-goal decider game
    end if;
  end if;
  if not decided and m.games >= m.best_of + 4 then
    w := _nx_t_better_seed(m.tournament_id, m.p1, m.p2); decided := true;
  end if;
  perform _nx_t_audit(m.tournament_id, null, 'game_accepted',
    jsonb_build_object('match', m.id, 'game_match', p_gm, 'winner', p_winner, 's_home', p_s_home, 's_away', p_s_away, 'source', p_source));
  if decided then
    l := case when w = m.p1 then m.p2 when w = m.p2 then m.p1 end;
    perform _nx_t_complete(m.id, w, l, draw, 'done', p_source);
  else
    update nx_t_matches set status = 'scheduled', updated_at = now() where id = m.id;
    perform _nx_t_open_ready(m.id);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_gen_de(p_t uuid, players uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int := coalesce(array_length(players, 1), 0); k int := 0; p int; ord int[];
        r int; i int; m int; cnt int; mid uuid; gf uuid; gf2 uuid; lrounds int; kind text; a int; b int; j int;
begin
  select * into t from nx_tournaments where id = p_t;
  if n < 2 then return; end if;
  while (1 << k) < n loop k := k + 1; end loop;
  p := 1 << k;
  ord := _nx_t_seed_order(p);
  lrounds := 2 * (k - 1);
  perform set_config('nx.tgen', 'on', true);
  for r in 1..k loop
    kind := case when r = k then 'final' when r = k - 1 then 'semi' else 'early' end;
    for i in 0..(p >> r) - 1 loop
      perform _nx_t_new_match(t, 'main', 'W', r, i, r, null, _nx_t_bo(t, kind));
    end loop;
  end loop;
  for m in 1..lrounds loop
    cnt := _nx_t_lb_count(p, m);
    kind := case when m = lrounds then 'semi' else 'early' end;
    for i in 0..cnt - 1 loop
      perform _nx_t_new_match(t, 'main', 'L', m, i, m + 1, null, _nx_t_bo(t, kind));
    end loop;
  end loop;
  gf := _nx_t_new_match(t, 'main', 'GF', 1, 0, greatest(2 * k, lrounds + 2), null, _nx_t_bo(t, 'final'));
  gf2 := _nx_t_new_match(t, 'main', 'GF2', 1, 0, greatest(2 * k, lrounds + 2) + 1, null, _nx_t_bo(t, 'final'));
  -- winners bracket links
  for r in 1..k loop
    for i in 0..(p >> r) - 1 loop
      mid := _nx_t_mid(p_t, 'main', 'W', r, i);
      if r < k then
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'W', r + 1, i / 2), win_slot = (i % 2) + 1 where id = mid;
      else
        update nx_t_matches set win_to = gf, win_slot = 1 where id = mid;
      end if;
      if k = 1 then
        update nx_t_matches set lose_to = gf, lose_slot = 2 where id = mid;
      elsif r = 1 then
        update nx_t_matches set lose_to = _nx_t_mid(p_t, 'main', 'L', 1, i / 2), lose_slot = (i % 2) + 1 where id = mid;
      else
        cnt := p >> r;
        j := case when r % 2 = 0 then cnt - 1 - i else i end;
        update nx_t_matches set lose_to = _nx_t_mid(p_t, 'main', 'L', 2 * (r - 1), j), lose_slot = 2 where id = mid;
      end if;
    end loop;
  end loop;
  -- losers bracket links
  for m in 1..lrounds loop
    cnt := _nx_t_lb_count(p, m);
    for i in 0..cnt - 1 loop
      mid := _nx_t_mid(p_t, 'main', 'L', m, i);
      if m = lrounds then
        update nx_t_matches set win_to = gf, win_slot = 2 where id = mid;
      elsif m % 2 = 1 then
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'L', m + 1, i), win_slot = 1 where id = mid;
      else
        update nx_t_matches set win_to = _nx_t_mid(p_t, 'main', 'L', m + 1, i / 2), win_slot = (i % 2) + 1 where id = mid;
      end if;
    end loop;
  end loop;
  for i in 0..(p / 2) - 1 loop
    a := ord[2 * i + 1]; b := ord[2 * i + 2];
    mid := _nx_t_mid(p_t, 'main', 'W', 1, i);
    update nx_t_matches set p1 = case when a <= n then players[a] end, p1_set = true,
                            p2 = case when b <= n then players[b] end, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end loop;
  perform set_config('nx.tgen', 'off', true);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_gen_on()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(current_setting('nx.tgen', true), '') = 'on'
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_gen_rr(p_t uuid, players uuid[], p_group integer, p_double boolean, r_off integer, s_off integer, p_bracket text, p_stage text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; arr uuid[] := players; m int; rounds int; cyc int; r int; i int; a uuid; b uuid; tmp uuid;
        rr int; mid uuid; idx int;
begin
  select * into t from nx_tournaments where id = p_t;
  if coalesce(array_length(arr, 1), 0) < 2 then return 0; end if;
  if array_length(arr, 1) % 2 = 1 then arr := arr || null::uuid; end if;
  m := array_length(arr, 1);
  rounds := m - 1;
  perform set_config('nx.tgen', 'on', true);
  for cyc in 0..(case when p_double then 1 else 0 end) loop
    arr := players;
    if array_length(arr, 1) % 2 = 1 then arr := arr || null::uuid; end if;
    for r in 0..rounds - 1 loop
      rr := cyc * rounds + r + 1;
      idx := 0;
      for i in 0..(m / 2) - 1 loop
        a := arr[i + 1]; b := arr[m - i];
        if a is not null and b is not null then
          if (r % 2 = 1 and i = 0) <> (cyc = 1) then tmp := a; a := b; b := tmp; end if;
          mid := _nx_t_new_match(t, p_stage, p_bracket, r_off + rr, idx, s_off + rr, p_group, _nx_t_bo(t, 'early'));
          update nx_t_matches set p1 = a, p1_set = true, p2 = b, p2_set = true where id = mid;
          perform _nx_t_check(mid);
          idx := idx + 1;
        end if;
      end loop;
      -- rotate all but the first
      arr := array[arr[1], arr[m]] || arr[2:m - 1];
    end loop;
  end loop;
  perform set_config('nx.tgen', 'off', true);
  return rounds * (case when p_double then 2 else 1 end);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_gen_se(p_t uuid, players uuid[], p_stage text, r_off integer, s_off integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; n int := coalesce(array_length(players, 1), 0); k int := 0; p int; ord int[];
        r int; i int; cnt int; mid uuid; final_id uuid; p3 uuid; kind text; a int; b int; nxt uuid;
begin
  select * into t from nx_tournaments where id = p_t;
  if n < 2 then return null; end if;
  while (1 << k) < n loop k := k + 1; end loop;
  p := 1 << k;
  ord := _nx_t_seed_order(p);
  perform set_config('nx.tgen', 'on', true);
  for r in 1..k loop
    cnt := p >> r;
    kind := case when r = k then 'final' when r = k - 1 then 'semi' else 'early' end;
    for i in 0..cnt - 1 loop
      mid := _nx_t_new_match(t, p_stage, 'W', r_off + r, i, s_off + r, null, _nx_t_bo(t, kind));
      if r = k then final_id := mid; end if;
    end loop;
  end loop;
  for r in 1..k - 1 loop
    for i in 0..(p >> r) - 1 loop
      nxt := _nx_t_mid(p_t, p_stage, 'W', r_off + r + 1, i / 2);
      update nx_t_matches set win_to = nxt, win_slot = (i % 2) + 1
       where id = _nx_t_mid(p_t, p_stage, 'W', r_off + r, i);
    end loop;
  end loop;
  if k >= 2 and _nx_t_cfg_bool(t.config, 'third_place', false) then
    p3 := _nx_t_new_match(t, p_stage, 'P3', r_off + k, 0, s_off + k, null, _nx_t_bo(t, 'final'));
    update nx_t_matches set lose_to = p3, lose_slot = 1 where id = _nx_t_mid(p_t, p_stage, 'W', r_off + k - 1, 0);
    update nx_t_matches set lose_to = p3, lose_slot = 2 where id = _nx_t_mid(p_t, p_stage, 'W', r_off + k - 1, 1);
  end if;
  for i in 0..(p / 2) - 1 loop
    a := ord[2 * i + 1]; b := ord[2 * i + 2];
    mid := _nx_t_mid(p_t, p_stage, 'W', r_off + 1, i);
    update nx_t_matches set p1 = case when a <= n then players[a] end, p1_set = true,
                            p2 = case when b <= n then players[b] end, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end loop;
  perform set_config('nx.tgen', 'off', true);
  return final_id;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_job(p_kind text, p_t uuid, p_ref uuid, p_run timestamp with time zone, p_key text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into nx_t_jobs(kind, tournament_id, ref, run_at, idem_key) values (p_kind, p_t, p_ref, p_run, p_key)
  on conflict (idem_key) do update set run_at = excluded.run_at, last_error = null
   where nx_t_jobs.done_at is null;
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_launch(p_m uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; t nx_tournaments; home uuid; away uuid; rid uuid; mid uuid; sd bigint; c text; golden boolean;
        st jsonb;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'ready_check' then return null; end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  if m.games % 2 = 0 then home := m.p1; away := m.p2; else home := m.p2; away := m.p1; end if;
  golden := m.games >= m.best_of;
  st := jsonb_build_object('tmatch', m.id, 'tournament', t.id, 'game_no', m.games + 1, 'golden_goal', golden,
                           'grace_sec', 60, 'best_of', m.best_of, 'aggregate', m.aggregate);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, status, is_private, quick, settings)
  values (c, t.game, home, 2, 'playing', true, false, st) returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, home, 0, true), (rid, away, 1, true);
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings)
  values (rid, t.game, array[home, away],
          array[coalesce((select username from profiles where id = home), 'Pilot'),
                coalesce((select username from profiles where id = away), 'Pilot')], sd, st)
  returning id into mid;
  update nx_rooms set match_id = mid where id = rid;
  insert into nx_t_games(game_match, tmatch, n, home, away, golden) values (mid, m.id, m.games + 1, home, away, golden);
  update nx_t_matches set status = 'playing', game_match = mid, ready_deadline = null, updated_at = now() where id = m.id;
  perform _nx_t_audit(t.id, null, 'game_started', jsonb_build_object('match', m.id, 'game_match', mid, 'n', m.games + 1));
  return mid;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_lb_count(p integer, m integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when m = 1 then p >> 2 when m % 2 = 0 then p >> (m / 2 + 1) else p >> ((m - 1) / 2 + 2) end
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_mid(p_t uuid, p_stage text, p_bracket text, p_round integer, p_idx integer)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = p_bracket
     and round = p_round and idx = p_idx limit 1
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_new_code()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare c text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    c := '';
    for i in 1..8 loop c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from nx_t_codes where code = c);
  end loop;
  return c;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_new_match(t nx_tournaments, p_stage text, p_bracket text, p_round integer, p_idx integer, p_slot integer, p_group integer, p_bo integer, p_label text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare mid uuid;
begin
  insert into nx_t_matches(tournament_id, stage, bracket, round, idx, tslot, group_no, best_of, aggregate, label)
  values (t.id, p_stage, p_bracket, p_round, p_idx, p_slot, p_group, p_bo,
          t.format = 'two_legs' and p_bo = 2, p_label)
  returning id into mid;
  return mid;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_no_show(p_m uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; elim boolean; w uuid;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status <> 'ready_check' or m.ready_deadline > now() then return; end if;
  elim := m.bracket in ('W', 'L', 'GF', 'GF2', 'P3');
  if m.p1_ready and not m.p2_ready then
    perform _nx_t_complete(m.id, m.p1, m.p2, false, 'walkover', 'no_show');
    perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'walkover', jsonb_build_object('lost', true), 'wo:' || m.id);
  elsif m.p2_ready and not m.p1_ready then
    perform _nx_t_complete(m.id, m.p2, m.p1, false, 'walkover', 'no_show');
    perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'walkover', jsonb_build_object('lost', true), 'wo:' || m.id);
  elsif elim then
    -- nobody showed up: the better seed advances (a knockout needs a winner)
    w := _nx_t_better_seed(m.tournament_id, m.p1, m.p2);
    perform _nx_t_complete(m.id, w, case when w = m.p1 then m.p2 else m.p1 end, false, 'walkover', 'double_no_show');
  else
    perform _nx_t_complete(m.id, null, null, false, 'void', 'double_no_show');
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_notify(p_user uuid, p_t uuid, p_tm uuid, p_kind text, p_data jsonb DEFAULT '{}'::jsonb, p_dedup text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ttl text;
begin
  if p_user is null then return; end if;
  select title into ttl from nx_tournaments where id = p_t;
  insert into nx_t_notifications(user_id, tournament_id, tmatch, kind, data, dedup)
  values (p_user, p_t, p_tm, p_kind, coalesce(p_data, '{}'::jsonb) || jsonb_build_object('title', ttl), p_dedup)
  on conflict (user_id, dedup) do nothing;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_notify_all(p_t uuid, p_kind text, p_data jsonb, p_dedup text, p_statuses text[] DEFAULT ARRAY['approved'::text])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record;
begin
  for r in select user_id from nx_t_entries where tournament_id = p_t and status = any(p_statuses) loop
    perform _nx_t_notify(r.user_id, p_t, null, p_kind, p_data, case when p_dedup is null then null else p_dedup end);
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_notify_managers(p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare u uuid;
begin
  for u in
    select created_by from nx_tournaments where id = p_t
    union select user_id from nx_t_staff where tournament_id = p_t
    union select user_id from nx_staff where role = 'admin'
  loop
    perform _nx_t_notify(u, p_t, p_tm, p_kind, p_data, p_dedup);
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_on_match_end()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare w uuid;
begin
  if not (new.settings ? 'tmatch') or old.status <> 'playing' or new.status = 'playing' then return new; end if;
  begin
    update nx_rooms set status = 'closed', updated_at = now() where id = new.room_id;
    if array_length(new.winner_seats, 1) = 1 then w := new.players[new.winner_seats[1] + 1]; end if;
    update nx_t_games set ended_at = now(), srv_winner = w, srv_s_home = coalesce(new.scores[1], 0),
           srv_s_away = coalesce(new.scores[2], 0) where game_match = new.id;
    if coalesce(new.reason, '') like 'forfeit%' or new.status = 'abandoned' then
      perform _nx_t_game_result(new.id, w, coalesce(new.scores[1], 0), coalesce(new.scores[2], 0), 'forfeit');
    else
      perform _nx_t_try_accept(new.id, false);
    end if;
  exception when others then
    insert into nx_t_audit(tournament_id, action, data)
    values ((new.settings ->> 'tournament')::uuid, 'error_match_end', jsonb_build_object('match', new.id, 'error', sqlerrm));
  end;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_open_ready(p_m uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; t nx_tournaments; secs int;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or m.status not in ('scheduled', 'playing') then return; end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  secs := greatest(30, least(_nx_t_cfg_int(t.config, 'ready_seconds', 300), 3600));
  update nx_t_matches set status = 'ready_check', ready_deadline = now() + make_interval(secs => secs),
         p1_ready = false, p2_ready = false, game_match = null, updated_at = now() where id = p_m;
  perform _nx_t_notify(m.p1, m.tournament_id, m.id, 'match_ready', jsonb_build_object('game', m.games + 1, 'seconds', secs),
                       'ready:' || m.id || ':' || m.games);
  perform _nx_t_notify(m.p2, m.tournament_id, m.id, 'match_ready', jsonb_build_object('game', m.games + 1, 'seconds', secs),
                       'ready:' || m.id || ':' || m.games);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_payout(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; dist int[]; tc int; tg int; r record; pool int;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.paid_out then return; end if;
  select coalesce(array_agg(v::numeric::int order by o), array[60, 30, 10]) into dist
    from jsonb_array_elements_text(case when jsonb_typeof(t.prize -> 'dist') = 'array' then t.prize -> 'dist' else '[60,30,10]'::jsonb end)
         with ordinality as x(v, o);
  tc := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_coins', 0), t.escrow_coins, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  tg := _nx_t_prize_total(_nx_t_cfg_int(t.prize, 'fixed_gems', 0), t.escrow_gems, _nx_t_cfg_int(t.prize, 'pool_pct', 0),
                          _nx_t_cfg_int(t.prize, 'fee_pct', 0));
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tc, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'coins', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':coins')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set coins = coins + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('coins', r.amount, 'place', r.place),
                           'prize:coins:' || p_t);
    end if;
  end loop;
  for r in select s.user_id, min(s.place) as place, sum(s.amount)::int as amount from _nx_t_split(p_t, tg, dist) s group by s.user_id loop
    continue when r.amount <= 0;
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, place, idem_key)
    values (p_t, r.user_id, 'payout', 'gems', r.amount, r.place, 'payout:' || p_t || ':' || r.user_id || ':gems')
    on conflict (idem_key) do nothing;
    if found then
      update profiles set gems = coalesce(gems, 0) + r.amount where id = r.user_id;
      perform _nx_t_notify(r.user_id, p_t, null, 'prize', jsonb_build_object('gems', r.amount, 'place', r.place),
                           'prize:gems:' || p_t);
    end if;
  end loop;
  -- the rest of the escrow (house fee + the part not in the pool) is released to the house in the ledger
  pool := t.escrow_coins;
  if pool > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'coins', pool - least(pool, greatest(0, tc - _nx_t_cfg_int(t.prize, 'fixed_coins', 0))),
            'house:' || p_t || ':coins') on conflict (idem_key) do nothing;
  end if;
  if t.escrow_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, null, 'house_fee', 'gems',
            t.escrow_gems - least(t.escrow_gems, greatest(0, tg - _nx_t_cfg_int(t.prize, 'fixed_gems', 0))),
            'house:' || p_t || ':gems') on conflict (idem_key) do nothing;
  end if;
  update nx_tournaments set paid_out = true, escrow_coins = 0, escrow_gems = 0, updated_at = now() where id = p_t;
  perform _nx_t_audit(p_t, null, 'payout', jsonb_build_object('coins', tc, 'gems', tg, 'dist', to_jsonb(dist)));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_place_elim(p_t uuid, p_stage text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; minr int; maxr int; k int; m record; champ uuid; second uuid; lmax int; placed int := 0;
        r record; cnt int;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.format = 'double_elim' then
    select * into m from nx_t_matches where tournament_id = p_t and bracket = 'GF2' and status in ('done', 'walkover');
    if m.id is null then
      select * into m from nx_t_matches where tournament_id = p_t and bracket = 'GF';
    end if;
    champ := m.winner; second := case when m.winner = m.p1 then m.p2 else m.p1 end;
    update nx_t_entries set place = 1 where tournament_id = p_t and user_id = champ;
    update nx_t_entries set place = 2 where tournament_id = p_t and user_id = second;
    placed := 2;
    select max(round) into lmax from nx_t_matches where tournament_id = p_t and bracket = 'L';
    for r in select round as rd, array_agg(loser) as us from nx_t_matches
              where tournament_id = p_t and bracket = 'L' and loser is not null group by round order by round desc loop
      update nx_t_entries set place = placed + 1 where tournament_id = p_t and user_id = any(r.us) and place is null;
      placed := placed + array_length(r.us, 1);
    end loop;
    return placed;
  end if;
  select min(round), max(round) into minr, maxr from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'W';
  if minr is null then return 0; end if;
  k := maxr - minr + 1;
  select * into m from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'W' and round = maxr;
  update nx_t_entries set place = 1 where tournament_id = p_t and user_id = m.winner;
  for r in select round as rd, loser from nx_t_matches
            where tournament_id = p_t and stage = p_stage and bracket = 'W' and loser is not null loop
    update nx_t_entries set place = (1 << (k - (r.rd - minr + 1))) + 1 where tournament_id = p_t and user_id = r.loser;
  end loop;
  select * into m from nx_t_matches where tournament_id = p_t and stage = p_stage and bracket = 'P3' and status in ('done', 'walkover', 'bye');
  if m.id is not null and m.winner is not null then
    update nx_t_entries set place = 3 where tournament_id = p_t and user_id = m.winner;
    if m.loser is not null then update nx_t_entries set place = 4 where tournament_id = p_t and user_id = m.loser; end if;
  end if;
  select count(*) into cnt from nx_t_entries where tournament_id = p_t and status = 'approved' and place is not null;
  return cnt;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_planned(t nx_tournaments, p_slot integer)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
AS $function$
declare a jsonb := t.config -> 'round_starts'; v text;
begin
  if jsonb_typeof(a) = 'array' and jsonb_array_length(a) >= p_slot and p_slot >= 1 then
    v := a ->> (p_slot - 1);
    if v is not null and v <> '' then
      begin return v::timestamptz; exception when others then null; end;
    end if;
  end if;
  return t.start_at + make_interval(mins => greatest(0, p_slot - 1) * greatest(1, _nx_t_cfg_int(t.config, 'round_minutes', 20)));
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_prize_total(p_fixed integer, p_escrow integer, p_pool_pct integer, p_fee_pct integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select greatest(0, coalesce(p_fixed, 0))
       + (greatest(0, coalesce(p_escrow, 0)) * least(100, greatest(0, coalesce(p_pool_pct, 0))) / 100)
       - ((greatest(0, coalesce(p_escrow, 0)) * least(100, greatest(0, coalesce(p_pool_pct, 0))) / 100)
          * least(100, greatest(0, coalesce(p_fee_pct, 0))) / 100)
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_progress(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; open_n int; g int; a int; rk int; grp int; adv uuid[] := '{}'; r record; maxr int; maxs int;
        rounds int; pick uuid; k int;
begin
  if _nx_t_gen_on() then return; end if;
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or t.status <> 'live' then return; end if;
  select count(*) into open_n from nx_t_matches
   where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
  if open_n > 0 then return; end if;
  if t.format = 'groups_ko' and t.stage = 'groups' then
    g := coalesce((select max(group_no) from nx_t_entries where tournament_id = p_t and status = 'approved'), 1);
    a := greatest(1, least(_nx_t_cfg_int(t.config, 'advance', 2), 8));
    for rk in 1..a loop
      for grp in 1..g loop
        -- A1, B1, C1 ..., A2, B2 ...: the standard bracket order then pairs A1–(last group)2, B1–…, never two of one group
        pick := null;
        select y.user_id into pick from (
          select x.user_id, row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed) as pos
            from _nx_t_table(p_t, 'groups', grp) x) y where y.pos = rk;
        if pick is not null then adv := adv || pick; end if;
      end loop;
    end loop;
    select max(round), max(tslot) into maxr, maxs from nx_t_matches where tournament_id = p_t;
    update nx_tournaments set stage = 'ko', updated_at = now() where id = p_t;
    for r in select user_id from nx_t_entries where tournament_id = p_t and status = 'approved' and not (user_id = any(adv)) loop
      perform _nx_t_notify(r.user_id, p_t, null, 'eliminated', jsonb_build_object('stage', 'groups'), 'elimg:' || p_t);
    end loop;
    if coalesce(array_length(adv, 1), 0) >= 2 then
      for r in select unnest(adv) as u loop
        perform _nx_t_notify(r.u, p_t, null, 'advanced', jsonb_build_object('stage', 'groups'), 'advg:' || p_t);
      end loop;
      perform _nx_t_gen_se(p_t, adv, 'ko', coalesce(maxr, 0), coalesce(maxs, 0));
      perform _nx_t_progress(p_t);
      return;
    end if;
  elsif t.format = 'swiss' then
    select max(round) into maxr from nx_t_matches where tournament_id = p_t and bracket = 'SW';
    select count(*) into rounds from nx_t_entries where tournament_id = p_t and status = 'approved';
    k := 0;
    while (1 << k) < rounds loop k := k + 1; end loop;
    rounds := least(greatest(1, _nx_t_cfg_int(t.config, 'swiss_rounds', greatest(k, 1))), greatest(1, rounds - 1));
    if coalesce(maxr, 0) < rounds then
      perform _nx_t_swiss_round(p_t, coalesce(maxr, 0) + 1);
      perform _nx_t_progress(p_t);
      return;
    end if;
  elsif t.format = 'custom' then
    return; -- custom brackets are finished by the organizer
  end if;
  perform _nx_t_finish(p_t);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_propagate(p_m uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_t_matches; gf2 uuid;
begin
  select * into m from nx_t_matches where id = p_m;
  if m.bracket = 'GF' then
    select id into gf2 from nx_t_matches where tournament_id = m.tournament_id and bracket = 'GF2' and status = 'pending';
    if gf2 is null then return; end if;
    if m.winner is not distinct from m.p1 or m.p2 is null or m.p1 is null then
      update nx_t_matches set status = 'skipped', result_note = 'winners_bracket_champion', updated_at = now() where id = gf2;
    else
      perform _nx_t_put(gf2, 1, m.p1);
      perform _nx_t_put(gf2, 2, m.p2);
    end if;
    return;
  end if;
  if m.win_to is not null then perform _nx_t_put(m.win_to, m.win_slot, m.winner); end if;
  if m.lose_to is not null then perform _nx_t_put(m.lose_to, m.lose_slot, m.loser); end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_put(p_m uuid, p_slot integer, p_player uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_m is null then return; end if;
  if p_slot = 1 then
    update nx_t_matches set p1 = p_player, p1_set = true, updated_at = now() where id = p_m;
  else
    update nx_t_matches set p2 = p_player, p2_set = true, updated_at = now() where id = p_m;
  end if;
  perform _nx_t_check(p_m);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_refund(p_t uuid, p_user uuid, p_reason text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e nx_t_entries; got boolean := false; unl boolean; kd text;
begin
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or (e.paid_coins = 0 and e.paid_gems = 0) then return false; end if;
  unl := coalesce((select kind = 'entry_fee_unlimited' from nx_t_ledger where id = e.fee_ref), false);
  kd := case when unl then 'refund_unlimited' else 'refund' end;
  if e.paid_coins > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'coins', e.paid_coins, 'refund:coins:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then update profiles set coins = coins + e.paid_coins where id = p_user; end if;
      update nx_tournaments set escrow_coins = greatest(0, escrow_coins - e.paid_coins) where id = p_t;
      got := true;
    end if;
  end if;
  if e.paid_gems > 0 then
    insert into nx_t_ledger(tournament_id, user_id, kind, currency, amount, idem_key)
    values (p_t, p_user, kd, 'gems', e.paid_gems, 'refund:gems:' || coalesce(e.fee_ref::text, p_t || ':' || p_user))
    on conflict (idem_key) do nothing;
    if found then
      if not unl then update profiles set gems = gems + e.paid_gems where id = p_user; end if;
      update nx_tournaments set escrow_gems = greatest(0, escrow_gems - e.paid_gems) where id = p_t;
      got := true;
    end if;
  end if;
  update nx_t_entries set paid_coins = 0, paid_gems = 0, updated_at = now() where tournament_id = p_t and user_id = p_user;
  if got then
    perform _nx_t_notify(p_user, p_t, null, 'refund', jsonb_build_object('coins', e.paid_coins, 'gems', e.paid_gems,
                         'reason', p_reason, 'unlimited', unl), 'refund:' || coalesce(e.fee_ref::text, p_user::text));
  end if;
  return got;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_reschedule(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; r record; at timestamptz;
begin
  select * into t from nx_tournaments where id = p_t;
  for r in select id, tslot from nx_t_matches where tournament_id = p_t and status = 'scheduled' loop
    at := greatest(_nx_t_planned(t, r.tslot), now());
    update nx_t_matches set scheduled_at = at, updated_at = now() where id = r.id;
    if at - interval '10 minutes' > now() + interval '1 minute' then
      perform _nx_t_job('remind_match', p_t, r.id, at - interval '10 minutes', 'remind_match:' || r.id);
    end if;
  end loop;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_run_job(j nx_t_jobs)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; m nx_t_matches;
begin
  select * into t from nx_tournaments where id = j.tournament_id;
  if t.id is null or t.status in ('finished', 'cancelled', 'draft') then return; end if;
  case j.kind
    when 'open_reg' then
      update nx_tournaments set status = 'registering', updated_at = now() where id = t.id and status = 'scheduled';
    when 'close_reg' then
      update nx_tournaments set status = 'closed', updated_at = now() where id = t.id and status = 'registering';
    when 'draw' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_draw(t.id);
    when 'start' then
      if t.status = 'scheduled' then update nx_tournaments set status = 'closed' where id = t.id; end if;
      perform _nx_t_start(t.id);
    when 'remind_start' then
      if t.status in ('registering', 'closed', 'drawn') then
        perform _nx_t_notify_all(t.id, 'starting_soon', jsonb_build_object('start_at', t.start_at), 'soon:' || t.id);
      end if;
    when 'remind_match' then
      select * into m from nx_t_matches where id = j.ref;
      if m.id is not null and m.status = 'scheduled' and m.p1 is not null and m.p2 is not null then
        perform _nx_t_notify(m.p1, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
        perform _nx_t_notify(m.p2, t.id, m.id, 'match_soon', jsonb_build_object('at', m.scheduled_at), 'msoon:' || m.id);
      end if;
    else
      null;
  end case;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_seed_order(p integer)
 RETURNS integer[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare a int[] := array[1]; b int[]; n int := 1; x int;
begin
  while n < p loop
    n := n * 2; b := '{}';
    foreach x in array a loop b := b || x || (n + 1 - x); end loop;
    a := b;
  end loop;
  return a;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_split(p_t uuid, p_total integer, p_dist integer[])
 RETURNS TABLE(user_id uuid, place integer, amount integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; k int; share int; i int; paid int := 0; top uuid; dsum int := 0; first_place int;
begin
  if p_total <= 0 or p_dist is null then return; end if;
  for i in 1..coalesce(array_length(p_dist, 1), 0) loop dsum := dsum + greatest(0, p_dist[i]); end loop;
  select min(e.place) into first_place from nx_t_entries e where e.tournament_id = p_t and e.status = 'approved' and e.place is not null;
  for r in select e.place as pl, array_agg(e.user_id order by e.seed nulls last, e.user_id) as us
             from nx_t_entries e where e.tournament_id = p_t and e.status = 'approved' and e.place is not null
            group by e.place order by e.place loop
    k := array_length(r.us, 1);
    share := 0;
    for i in r.pl..r.pl + k - 1 loop
      if i <= coalesce(array_length(p_dist, 1), 0) then share := share + greatest(0, p_dist[i]); end if;
    end loop;
    if share > 0 then
      for i in 1..k loop
        user_id := r.us[i]; place := r.pl; amount := (p_total::bigint * share / 100 / k)::int;
        paid := paid + amount;
        if top is null and r.pl = first_place then top := r.us[i]; end if;
        return next;
      end loop;
    end if;
  end loop;
  if top is not null and (p_total::bigint * least(100, dsum) / 100)::int - paid > 0 then
    user_id := top; place := first_place; amount := (p_total::bigint * least(100, dsum) / 100)::int - paid;
    return next;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_start(p_t uuid, p_actor uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return; end if;
  if t.status in ('registering', 'closed') then
    perform _nx_t_draw(p_t, p_actor);
    select * into t from nx_tournaments where id = p_t;
  end if;
  if t.status <> 'drawn' then return; end if;
  update nx_tournaments set status = 'live', started_at = now(), updated_at = now() where id = p_t;
  perform _nx_t_notify_all(p_t, 'started', '{}'::jsonb, 'started:' || p_t);
  perform _nx_t_audit(p_t, p_actor, 'started', '{}'::jsonb);
  perform _nx_t_progress(p_t);
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_swiss_round(p_t uuid, p_r integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; ord uuid[]; n int; h int; i int; j int; used boolean[]; bye uuid; mid uuid; idx int := 0;
        partner int;
begin
  select * into t from nx_tournaments where id = p_t;
  if p_r = 1 then
    select array_agg(user_id order by seed) into ord from nx_t_entries where tournament_id = p_t and status = 'approved';
  else
    select array_agg(x.user_id order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.seed) into ord
      from _nx_t_table(p_t, 'main', null) x;
  end if;
  n := coalesce(array_length(ord, 1), 0);
  if n < 2 then return; end if;
  perform set_config('nx.tgen', 'on', true);
  if n % 2 = 1 then
    for i in reverse n..1 loop
      if not exists (select 1 from nx_t_matches where tournament_id = p_t and bracket = 'SW' and status = 'bye'
                      and p1 = ord[i]) then
        bye := ord[i]; exit;
      end if;
    end loop;
    if bye is null then bye := ord[n]; end if;
    ord := array_remove(ord, bye);
    n := n - 1;
  end if;
  if p_r = 1 then
    h := n / 2;
    for i in 1..h loop
      mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, _nx_t_bo(t, 'early'));
      update nx_t_matches set p1 = ord[i], p1_set = true, p2 = ord[i + h], p2_set = true where id = mid;
      perform _nx_t_check(mid); idx := idx + 1;
    end loop;
  else
    used := array_fill(false, array[n]);
    for i in 1..n loop
      continue when used[i];
      partner := null;
      for j in i + 1..n loop
        continue when used[j];
        if not exists (select 1 from nx_t_matches where tournament_id = p_t and bracket = 'SW'
                        and ((p1 = ord[i] and p2 = ord[j]) or (p1 = ord[j] and p2 = ord[i]))) then
          partner := j; exit;
        end if;
      end loop;
      if partner is null then
        for j in i + 1..n loop
          if not used[j] then partner := j; exit; end if;
        end loop;
      end if;
      exit when partner is null;
      used[i] := true; used[partner] := true;
      mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, _nx_t_bo(t, 'early'));
      update nx_t_matches set p1 = ord[i], p1_set = true, p2 = ord[partner], p2_set = true where id = mid;
      perform _nx_t_check(mid); idx := idx + 1;
    end loop;
  end if;
  if bye is not null then
    mid := _nx_t_new_match(t, 'main', 'SW', p_r, idx, p_r, null, 1);
    update nx_t_matches set p1 = bye, p1_set = true, p2 = null, p2_set = true where id = mid;
    perform _nx_t_check(mid);
  end if;
  perform set_config('nx.tgen', 'off', true);
  update nx_tournaments set updated_at = now() where id = p_t;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_sync_jobs(p_t uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or t.status in ('draft', 'finished', 'cancelled') then return; end if;
  perform _nx_t_job('open_reg', t.id, null, t.reg_open_at, 'open_reg:' || t.id);
  perform _nx_t_job('close_reg', t.id, null, t.reg_close_at, 'close_reg:' || t.id);
  perform _nx_t_job('draw', t.id, null, t.draw_at, 'draw:' || t.id);
  perform _nx_t_job('start', t.id, null, t.start_at, 'start:' || t.id);
  if t.start_at - interval '10 minutes' > now() then
    perform _nx_t_job('remind_start', t.id, null, t.start_at - interval '10 minutes', 'remind_start:' || t.id);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_table(p_t uuid, p_stage text, p_group integer)
 RETURNS TABLE(user_id uuid, seed integer, played integer, won integer, drawn integer, lost integer, gf integer, ga integer, pts integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with t as (select * from nx_tournaments where id = p_t),
  rows as (
    select m.p1 as u, m.p2 as o, m.winner, m.is_draw, m.g1 as f, m.g2 as a, m.status from nx_t_matches m
     where m.tournament_id = p_t and m.stage = p_stage and m.bracket in ('RR', 'G', 'SW', 'C') and m.p1 is not null
       and (p_group is null or m.group_no = p_group) and m.status in ('done', 'walkover', 'bye')
    union all
    select m.p2, m.p1, m.winner, m.is_draw, m.g2, m.g1, m.status from nx_t_matches m
     where m.tournament_id = p_t and m.stage = p_stage and m.bracket in ('RR', 'G', 'SW', 'C') and m.p2 is not null
       and (p_group is null or m.group_no = p_group) and m.status in ('done', 'walkover', 'bye')
  )
  select e.user_id, e.seed,
         count(r.u)::int,
         count(r.u) filter (where r.winner = e.user_id)::int,
         count(r.u) filter (where r.is_draw)::int,
         count(r.u) filter (where r.winner is distinct from e.user_id and not r.is_draw)::int,
         coalesce(sum(r.f), 0)::int, coalesce(sum(r.a), 0)::int,
         (count(r.u) filter (where r.winner = e.user_id) * _nx_t_cfg_int((select config from t), 'points_win', 3)
          + count(r.u) filter (where r.is_draw) * _nx_t_cfg_int((select config from t), 'points_draw', 1))::int
    from nx_t_entries e left join rows r on r.u = e.user_id
   where e.tournament_id = p_t and e.status = 'approved' and (p_group is null or e.group_no = p_group)
   group by e.user_id, e.seed
$function$;

CREATE OR REPLACE FUNCTION public._nx_t_try_accept(p_gm uuid, p_from_tick boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g nx_t_games; rh nx_t_reports; ra nx_t_reports; one nx_t_reports; n int;
begin
  select * into g from nx_t_games where game_match = p_gm;
  if g.game_match is null or g.accepted or g.disputed then return; end if;
  select * into rh from nx_t_reports where game_match = p_gm and user_id = g.home;
  select * into ra from nx_t_reports where game_match = p_gm and user_id = g.away;
  if rh.user_id is not null and ra.user_id is not null then
    if rh.winner is not distinct from ra.winner and rh.s_home = ra.s_home and rh.s_away = ra.s_away then
      perform _nx_t_game_result(p_gm, rh.winner, rh.s_home, rh.s_away, 'both_reports');
    else
      perform _nx_t_dispute(g.tmatch, null, 'reports_disagree');
    end if;
    return;
  end if;
  one := coalesce(rh, ra);
  if one.user_id is not null then
    if g.ended_at is not null and (one.winner is distinct from g.srv_winner) then
      perform _nx_t_dispute(g.tmatch, null, 'report_vs_server');
      return;
    end if;
    if p_from_tick and g.ended_at is not null and greatest(g.ended_at, one.created_at) < now() - interval '90 seconds' then
      perform _nx_t_game_result(p_gm, one.winner, one.s_home, one.s_away, 'single_report');
    end if;
    return;
  end if;
  if p_from_tick and g.ended_at is not null and g.ended_at < now() - interval '3 minutes' then
    perform _nx_t_game_result(p_gm, g.srv_winner, coalesce(g.srv_s_home, 0), coalesce(g.srv_s_away, 0), 'server_only');
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_validate_cfg(c jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
declare o jsonb := coalesce(c, '{}'::jsonb); k text;
begin
  foreach k in array array['bo_early', 'bo_semi', 'bo_final'] loop
    if _nx_t_cfg_int(o, k, 1) not in (1, 2, 3, 5) then o := o || jsonb_build_object(k, 1); end if;
  end loop;
  o := o || jsonb_build_object(
    'groups', greatest(1, least(_nx_t_cfg_int(o, 'groups', 2), 16)),
    'advance', greatest(1, least(_nx_t_cfg_int(o, 'advance', 2), 8)),
    'swiss_rounds', greatest(0, least(_nx_t_cfg_int(o, 'swiss_rounds', 0), 12)),
    'points_win', greatest(0, least(_nx_t_cfg_int(o, 'points_win', 3), 10)),
    'points_draw', greatest(0, least(_nx_t_cfg_int(o, 'points_draw', 1), 10)),
    'ready_seconds', greatest(30, least(_nx_t_cfg_int(o, 'ready_seconds', 300), 3600)),
    'round_minutes', greatest(1, least(_nx_t_cfg_int(o, 'round_minutes', 20), 10080)),
    'max_game_minutes', greatest(5, least(_nx_t_cfg_int(o, 'max_game_minutes', 30), 240)));
  return o;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean DEFAULT false, p_settings jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); b record; s int; rid uuid; c text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into b from nx_game_bounds(p_game);
  if p_game not in ('finger_soccer','carrom','billiards','backgammon','ludo','snakes_ladders','uno','quiz','mafia') then
    raise exception 'unknown game'; end if;
  s := greatest(b.min_seats, least(coalesce(p_seats, b.min_seats), b.max_seats));
  perform _nx_leave_all(me);
  c := nx_gen_code();
  insert into nx_rooms(code, game, host, seats, is_private, quick, settings)
  values (c, p_game, me, s, coalesce(p_private, false), coalesce(p_quick, false), coalesce(p_settings, '{}'::jsonb))
  returning id into rid;
  insert into nx_room_players(room_id, user_id, seat, ready) values (rid, me, 0, true);
  return jsonb_build_object('room_id', rid, 'code', c, 'seats', s);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text DEFAULT NULL::text, p_reason text DEFAULT 'finished'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_matches;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  if not (me = any(m.players)) then raise exception 'not a player'; end if;
  if m.status <> 'playing' then
    return jsonb_build_object('ok', true, 'already', true, 'winners', m.winner_seats);
  end if;
  update nx_matches set status = 'finished', winner_seats = p_winners, scores = p_scores, reason = left(p_reason, 40),
         state_hash = coalesce(p_hash, state_hash), ended_at = now() where id = p_match returning * into m;
  perform _nx_apply_result(m, p_winners, p_scores);
  update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
  update nx_room_players set ready = false where room_id = m.room_id and seat > 0;
  return jsonb_build_object('ok', true, 'winners', p_winners);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_finish_match_as(p_match uuid, p_winners integer[], p_loser integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_matches;
begin
  update nx_matches set status = 'finished', winner_seats = p_winners, reason = 'forfeit:' || p_loser, ended_at = now()
   where id = p_match and status = 'playing' returning * into m;
  if m.id is null then return jsonb_build_object('ok', false); end if;
  perform _nx_apply_result(m, p_winners, null);
  update nx_rooms set status = 'lobby', updated_at = now() where id = m.room_id and match_id = m.id;
  return jsonb_build_object('ok', true, 'winners', p_winners, 'forfeit', p_loser);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_forfeit(p_match uuid, p_seat integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_matches; s int; others int[];
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null or m.status <> 'playing' then return jsonb_build_object('ok', false); end if;
  s := array_position(m.players, me) - 1;
  if s is null then raise exception 'not a player'; end if;
  if p_seat is not null and p_seat <> s then
    if s <> 0 then raise exception 'authority only'; end if;  -- host may forfeit an absent seat
    s := p_seat;
  end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move)
  values (p_match, m.last_seq + 1, s, me, 'forfeit', jsonb_build_object('seat', s));
  update nx_matches set last_seq = m.last_seq + 1 where id = p_match;
  if array_length(m.players, 1) = 2 then
    select array_agg(g) into others from generate_series(0, 1) g where g <> s;
    return nx_finish_match_as(p_match, others, s);
  end if;
  return jsonb_build_object('ok', true, 'seat', s);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_game_bounds(p_game text, OUT min_seats integer, OUT max_seats integer)
 RETURNS record
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_game when 'ludo' then 2 when 'snakes_ladders' then 2 when 'uno' then 2 when 'quiz' then 2
                     when 'mafia' then 6 else 2 end,
         case p_game when 'ludo' then 4 when 'snakes_ladders' then 4 when 'uno' then 4 when 'quiz' then 2
                     when 'mafia' then 10 else 2 end
$function$;

CREATE OR REPLACE FUNCTION public.nx_gen_code()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
declare c text; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; i int;
begin
  loop
    c := '';
    for i in 1..6 loop c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1); end loop;
    exit when not exists (select 1 from nx_rooms where code = c);
  end loop;
  return c;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_in_match(m uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from nx_matches where id = m and auth.uid() = any(players))
$function$;

CREATE OR REPLACE FUNCTION public.nx_in_room(r uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from nx_room_players where room_id = r and user_id = auth.uid())
$function$;

CREATE OR REPLACE FUNCTION public.nx_invite(p_room uuid, p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); r nx_rooms;
begin
  select * into r from nx_rooms where id = p_room;
  if r.id is null or not nx_in_room(p_room) then raise exception 'not in room'; end if;
  if exists (select 1 from user_blocks where blocker = p_user and blocked = me) then raise exception 'blocked'; end if;
  insert into nx_invites(from_user, to_user, kind, room_id, payload)
  values (me, p_user, 'game', p_room, jsonb_build_object('code', r.code, 'game', r.game,
          'from_name', (select username from profiles where id = me)));
end $function$;

CREATE OR REPLACE FUNCTION public.nx_join_room(p_code text DEFAULT NULL::text, p_room uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); r nx_rooms; s int;
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_room is not null then select * into r from nx_rooms where id = p_room for update;
  else select * into r from nx_rooms where code = upper(trim(p_code)) for update; end if;
  if r.id is null then raise exception 'room not found'; end if;
  if exists (select 1 from nx_room_players where room_id = r.id and user_id = me) then
    update nx_room_players set last_seen = now() where room_id = r.id and user_id = me;
    return jsonb_build_object('room_id', r.id, 'code', r.code, 'rejoined', true, 'status', r.status, 'match_id', r.match_id);
  end if;
  if r.status <> 'lobby' then raise exception 'room already started'; end if;
  perform _nx_leave_all(me);
  select min(g) into s from generate_series(0, r.seats - 1) g
   where not exists (select 1 from nx_room_players where room_id = r.id and seat = g);
  if s is null then raise exception 'room full'; end if;
  insert into nx_room_players(room_id, user_id, seat) values (r.id, me, s);
  update nx_rooms set updated_at = now() where id = r.id;
  return jsonb_build_object('room_id', r.id, 'code', r.code, 'seat', s, 'status', r.status);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_leave_room(p_room uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); r nx_rooms; nh uuid;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then return; end if;
  if r.status = 'playing' and r.match_id is not null then
    perform nx_forfeit(r.match_id);
  end if;
  delete from nx_room_players where room_id = p_room and user_id = me;
  if not exists (select 1 from nx_room_players where room_id = p_room) then
    update nx_rooms set status = 'closed', updated_at = now() where id = p_room;
  elsif r.host = me then
    select user_id into nh from nx_room_players where room_id = p_room order by seat limit 1;
    update nx_rooms set host = nh, updated_at = now() where id = p_room;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_my_active_match()
 RETURNS TABLE(match_id uuid, game text, room_id uuid, started_at timestamp with time zone, seats integer, tournament boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.id, m.game, m.room_id, m.started_at, array_length(m.players, 1),
         (m.settings ? 'tmatch')
    from nx_matches m
   where m.status = 'playing' and auth.uid() = any(m.players)
     and m.started_at > now() - interval '3 hours'
     and not exists (select 1 from nx_match_moves x
                      where x.match_id = m.id and x.kind = 'forfeit'
                        and (x.move->>'seat')::int = array_position(m.players, auth.uid()) - 1)
   order by m.started_at desc
   limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.nx_owner_tournaments(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g text := _nx_owner_guard(); res jsonb;
begin
  if g is not null then return jsonb_build_object('ok', false, 'error', g); end if;
  select coalesce(jsonb_agg(x order by x.created_at desc), '[]'::jsonb) into res from (
    select t.id, t.title, t.game, t.format, t.status, t.capacity, t.start_at, t.created_at, t.created_by, p.username as creator,
           (select count(*) from nx_t_entries e where e.tournament_id = t.id and e.status = 'approved') as players,
           (select count(*) from nx_t_matches m where m.tournament_id = t.id and m.status = 'disputed') as disputes,
           t.fee_coins, t.fee_gems, t.prize
      from nx_tournaments t left join profiles p on p.id = t.created_by
     order by t.created_at desc limit greatest(1, least(coalesce(p_limit, 100), 500))) x;
  return jsonb_build_object('ok', true, 'tournaments', res);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_push_move(p_match uuid, p_seq integer, p_kind text, p_move jsonb, p_hash text, p_seat integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_matches; s int;
begin
  select * into m from nx_matches where id = p_match for update;
  if m.id is null then raise exception 'match not found'; end if;
  s := array_position(m.players, me) - 1;
  if s is null then raise exception 'not a player'; end if;
  if m.status <> 'playing' then return jsonb_build_object('ok', false, 'reason', 'over', 'last_seq', m.last_seq); end if;
  if p_seq <> m.last_seq + 1 then return jsonb_build_object('ok', false, 'reason', 'seq', 'last_seq', m.last_seq); end if;
  -- the authority (host side) may post on behalf of a disconnected seat (timeouts/forfeits) and snapshots
  if p_seat is not null and p_seat <> s and p_kind not in ('snap', 'timeout', 'forfeit', 'system') then
    raise exception 'seat mismatch'; end if;
  insert into nx_match_moves(match_id, seq, seat, by_user, kind, move, hash)
  values (p_match, p_seq, coalesce(p_seat, s), me, left(coalesce(p_kind, 'move'), 16), coalesce(p_move, '{}'::jsonb), p_hash);
  update nx_matches set last_seq = p_seq, state_hash = coalesce(p_hash, state_hash) where id = p_match;
  return jsonb_build_object('ok', true, 'seq', p_seq);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_put_secret(p_match uuid, p_user uuid, p_slot text, p_data jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m nx_matches;
begin
  select * into m from nx_matches where id = p_match;
  if m.id is null or m.players[1] <> auth.uid() then raise exception 'authority only'; end if;
  if not (p_user = any(m.players)) then raise exception 'not a player'; end if;
  insert into nx_match_secrets(match_id, user_id, slot, data) values (p_match, p_user, p_slot, p_data)
  on conflict (match_id, user_id, slot) do update set data = excluded.data, created_at = now();
end $function$;

CREATE OR REPLACE FUNCTION public.nx_quick(p_game text, p_seats integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); rid uuid; res jsonb; n int; s int; r nx_rooms;
begin
  if me is null then raise exception 'not signed in'; end if;
  update nx_rooms set status = 'closed' where status = 'lobby' and quick and updated_at < now() - interval '10 minutes';
  select x.id into rid from nx_rooms x
   where x.game = p_game and x.status = 'lobby' and x.quick and not x.is_private and x.seats = p_seats
     and not exists (select 1 from nx_room_players rp where rp.room_id = x.id and rp.user_id = me)
     and (select count(*) from nx_room_players rp where rp.room_id = x.id) < x.seats
   order by x.created_at limit 1 for update skip locked;
  if rid is null then
    res := nx_create_room(p_game, p_seats, false, true, '{}'::jsonb);
    return res || jsonb_build_object('created', true);
  end if;
  res := nx_join_room(null, rid);
  select * into r from nx_rooms where id = rid;
  select count(*) into n from nx_room_players where room_id = rid;
  if n >= r.seats then
    res := res || nx_start_match_quick(rid);
  end if;
  return res;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_set_ready(p_room uuid, p_ready boolean)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update nx_room_players set ready = p_ready, last_seen = now() where room_id = p_room and user_id = auth.uid();
  update nx_rooms set updated_at = now() where id = p_room;
$function$;

CREATE OR REPLACE FUNCTION public.nx_start_match(p_room uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); r nx_rooms; b record; ids uuid[]; nm text[]; mid uuid; sd bigint; n int;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.id is null then raise exception 'room not found'; end if;
  if r.host <> me and not r.quick then raise exception 'host only'; end if;
  if r.status = 'playing' and r.match_id is not null then
    return jsonb_build_object('match_id', r.match_id, 'already', true);
  end if;
  select * into b from nx_game_bounds(r.game);
  select array_agg(rp.user_id order by rp.seat), array_agg(coalesce(p.username, 'Pilot') order by rp.seat), count(*)
    into ids, nm, n
    from nx_room_players rp left join profiles p on p.id = rp.user_id where rp.room_id = p_room;
  if n < b.min_seats then raise exception 'need % players', b.min_seats; end if;
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings) values (p_room, r.game, ids, nm, sd, r.settings)
  returning id into mid;
  update nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', sd);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_start_match_quick(p_room uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r nx_rooms; ids uuid[]; nm text[]; mid uuid; sd bigint;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.status <> 'lobby' then return jsonb_build_object('match_id', r.match_id); end if;
  select array_agg(rp.user_id order by rp.seat), array_agg(coalesce(p.username, 'Pilot') order by rp.seat)
    into ids, nm from nx_room_players rp left join profiles p on p.id = rp.user_id where rp.room_id = p_room;
  sd := floor(random() * 2147483646)::bigint + 1;
  insert into nx_matches(room_id, game, players, names, seed, settings) values (p_room, r.game, ids, nm, sd, r.settings)
  returning id into mid;
  update nx_rooms set status = 'playing', match_id = mid, updated_at = now() where id = p_room;
  return jsonb_build_object('match_id', mid, 'seed', sd);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_admin(p_t uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; r record;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  case p_action
    when 'publish' then
      if t.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
      update nx_tournaments set status = case when reg_open_at <= now() then 'registering' else 'scheduled' end,
             published_at = now(), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'open_reg' then
      if t.status <> 'scheduled' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'registering', reg_open_at = least(reg_open_at, now()), updated_at = now() where id = p_t;
      perform _nx_t_sync_jobs(p_t);
    when 'close_reg' then
      if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set status = 'closed', reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             updated_at = now() where id = p_t;
      update nx_t_jobs set done_at = now() where idem_key = 'close_reg:' || p_t and done_at is null;
    when 'draw', 'redraw' then
      if p_action = 'redraw' then
        if t.status <> 'drawn' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
        delete from nx_t_matches where tournament_id = p_t;
        update nx_tournaments set status = 'closed', seed = null, stage = 'main' where id = p_t;
      elsif t.status not in ('registering', 'closed') then
        return jsonb_build_object('ok', false, 'error', 'bad_status');
      end if;
      update nx_tournaments set reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())) where id = p_t;
      perform _nx_t_draw(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t) and done_at is null;
    when 'start' then
      if t.status not in ('registering', 'closed', 'drawn') then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_tournaments set
             reg_close_at = greatest(reg_open_at + interval '1 second', least(reg_close_at, now())),
             draw_at = greatest(reg_open_at + interval '1 second', least(draw_at, now())),
             start_at = greatest(reg_open_at + interval '1 second', least(start_at, now())) where id = p_t;
      perform _nx_t_start(p_t, me);
      update nx_t_jobs set done_at = now() where idem_key in ('close_reg:' || p_t, 'draw:' || p_t, 'start:' || p_t, 'remind_start:' || p_t)
         and done_at is null;
      perform _nx_t_reschedule(p_t);
    when 'pause' then
      update nx_tournaments set paused = true, updated_at = now() where id = p_t;
    when 'resume' then
      update nx_tournaments set paused = false, updated_at = now() where id = p_t;
      for r in select id from nx_t_matches where tournament_id = p_t and status = 'ready_check' loop
        update nx_t_matches set ready_deadline = now() + make_interval(secs => _nx_t_cfg_int(t.config, 'ready_seconds', 300))
         where id = r.id;
      end loop;
    when 'cancel' then
      perform _nx_t_cancel(p_t, coalesce(nullif(p_reason, ''), 'cancelled_by_organizer'), me);
    when 'finish' then
      if t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      update nx_t_matches set status = 'void', result_note = 'closed_by_organizer', updated_at = now()
       where tournament_id = p_t and status not in ('done', 'walkover', 'bye', 'void', 'skipped');
      perform _nx_t_finish(p_t);
    when 'delete' then
      if t.status <> 'draft' or exists (select 1 from nx_t_ledger where tournament_id = p_t) then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_tournaments where id = p_t;
      return jsonb_build_object('ok', true, 'deleted', true);
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(p_t, me, 'admin_' || p_action, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'status', (select status from nx_tournaments where id = p_t));
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_admin_match(p_m uuid, p_action text, p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_t_matches; t nx_tournaments; w uuid; l uuid; dr boolean; d record; mid uuid;
        np1 uuid; np2 uuid;
begin
  if p_action = 'add' then
    select * into t from nx_tournaments where id = (p ->> 'tournament_id')::uuid for update;
  else
    select * into m from nx_t_matches where id = p_m for update;
    select * into t from nx_tournaments where id = m.tournament_id for update;
  end if;
  if t.id is null or not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  case p_action
    when 'result' then
      w := nullif(p ->> 'winner', '')::uuid;
      dr := coalesce((p ->> 'draw')::boolean, false);
      if not dr and (w is null or not (w = m.p1 or w = m.p2)) then return jsonb_build_object('ok', false, 'error', 'bad_winner'); end if;
      if dr and m.bracket in ('W', 'L', 'GF', 'GF2', 'P3') then return jsonb_build_object('ok', false, 'error', 'knockout_needs_winner'); end if;
      l := case when w = m.p1 then m.p2 when w = m.p2 then m.p1 end;
      if m.status in ('done', 'walkover') then
        if not _nx_t_downstream_free(m.id) then return jsonb_build_object('ok', false, 'error', 'downstream_started'); end if;
        update nx_t_matches set winner = w, loser = l, is_draw = dr, status = 'done',
               w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2),
               result_note = 'admin:' || coalesce(p ->> 'note', ''), updated_at = now() where id = m.id;
        if w is distinct from m.winner then
          -- re-seat the corrected players downstream
          for d in select id, status from nx_t_matches where id in (m.win_to, m.lose_to) loop
            update nx_t_matches set status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false where id = d.id;
          end loop;
          if m.win_to is not null then perform _nx_t_put(m.win_to, m.win_slot, w); end if;
          if m.lose_to is not null then perform _nx_t_put(m.lose_to, m.lose_slot, l); end if;
          if m.bracket = 'GF' then
            update nx_t_matches set status = 'pending', p1 = null, p2 = null, p1_set = false, p2_set = false
             where tournament_id = t.id and bracket = 'GF2';
            perform _nx_t_propagate(m.id);
          end if;
        end if;
        perform _nx_t_notify(m.p1, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
        perform _nx_t_notify(m.p2, t.id, m.id, 'result_corrected', jsonb_build_object('winner', w), 'fix:' || m.id || ':' || clock_timestamp());
      else
        if m.p1 is null or m.p2 is null then return jsonb_build_object('ok', false, 'error', 'players_unknown'); end if;
        update nx_t_matches set w1 = coalesce((p ->> 'w1')::int, w1), w2 = coalesce((p ->> 'w2')::int, w2),
               g1 = coalesce((p ->> 'g1')::int, g1), g2 = coalesce((p ->> 'g2')::int, g2) where id = m.id;
        if m.game_match is not null then
          update nx_t_games set accepted = true, winner = w, source = 'admin' where game_match = m.game_match;
          update nx_matches set status = 'abandoned', reason = 'admin', ended_at = now() where id = m.game_match and status = 'playing';
        end if;
        perform _nx_t_complete(m.id, w, l, dr, 'done', 'admin:' || coalesce(p ->> 'note', ''));
      end if;
    when 'replay' then
      if m.status not in ('disputed', 'playing', 'ready_check', 'scheduled') or m.p1 is null or m.p2 is null then
        return jsonb_build_object('ok', false, 'error', 'bad_status'); end if;
      if m.game_match is not null then
        update nx_t_games set accepted = true, source = 'void_replay' where game_match = m.game_match;
        update nx_matches set status = 'abandoned', reason = 'replay', ended_at = now() where id = m.game_match and status = 'playing';
      end if;
      update nx_t_matches set status = 'scheduled', game_match = null, updated_at = now() where id = m.id;
      if t.status = 'live' then perform _nx_t_open_ready(m.id); end if;
    when 'edit' then
      if m.status not in ('pending', 'scheduled', 'ready_check') or m.games > 0 then
        return jsonb_build_object('ok', false, 'error', 'already_started'); end if;
      np1 := case when p ? 'p1' then nullif(p ->> 'p1', '')::uuid else m.p1 end;
      np2 := case when p ? 'p2' then nullif(p ->> 'p2', '')::uuid else m.p2 end;
      if (np1 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved'))
         or (np2 is not null and not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved'))
         or (np1 = np2) then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      update nx_t_matches set p1 = np1, p2 = np2,
             p1_set = p1_set or p ? 'p1', p2_set = p2_set or p ? 'p2',
             best_of = case when (p ->> 'best_of')::int in (1, 2, 3, 5) then (p ->> 'best_of')::int else best_of end,
             status = 'pending', ready_deadline = null, p1_ready = false, p2_ready = false, updated_at = now()
       where id = m.id;
      perform _nx_t_check(m.id);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = m.id and status = 'scheduled';
      end if;
    when 'add' then
      if t.format <> 'custom' then return jsonb_build_object('ok', false, 'error', 'custom_only'); end if;
      if t.status not in ('drawn', 'live') then return jsonb_build_object('ok', false, 'error', 'draw_first'); end if;
      np1 := nullif(p ->> 'p1', '')::uuid; np2 := nullif(p ->> 'p2', '')::uuid;
      if np1 is null or np2 is null or np1 = np2
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np1 and status = 'approved')
         or not exists (select 1 from nx_t_entries where tournament_id = t.id and user_id = np2 and status = 'approved') then
        return jsonb_build_object('ok', false, 'error', 'bad_players'); end if;
      mid := _nx_t_new_match(t, 'main', 'C', greatest(1, coalesce((p ->> 'round')::int, 1)),
                             coalesce((select count(*) from nx_t_matches where tournament_id = t.id and bracket = 'C'
                                        and round = greatest(1, coalesce((p ->> 'round')::int, 1))), 0)::int,
                             greatest(1, coalesce((p ->> 'round')::int, 1)), null,
                             case when (p ->> 'best_of')::int in (1, 2, 3, 5) then (p ->> 'best_of')::int else 1 end,
                             left(p ->> 'label', 40));
      update nx_t_matches set p1 = np1, p2 = np2, p1_set = true, p2_set = true where id = mid;
      perform _nx_t_check(mid);
      if p ? 'scheduled_at' then
        update nx_t_matches set scheduled_at = greatest((p ->> 'scheduled_at')::timestamptz, now()) where id = mid and status = 'scheduled';
      end if;
      perform _nx_t_audit(t.id, me, 'match_add', jsonb_build_object('match', mid, 'p', p));
      return jsonb_build_object('ok', true, 'id', mid);
    when 'delete' then
      if t.format <> 'custom' or m.games > 0 or m.status not in ('pending', 'scheduled', 'ready_check') then
        return jsonb_build_object('ok', false, 'error', 'not_deletable'); end if;
      delete from nx_t_matches where id = m.id;
    else
      return jsonb_build_object('ok', false, 'error', 'bad_action');
  end case;
  perform _nx_t_audit(t.id, me, 'match_' || p_action, jsonb_build_object('match', p_m, 'p', p));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_can_manage(t uuid, u uuid DEFAULT auth.uid())
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u is not null and (
    nx_t_is_admin(u)
    or exists (select 1 from nx_tournaments x where x.id = t and x.created_by = u and nx_t_is_organizer(u))
    or exists (select 1 from nx_t_staff s where s.tournament_id = t and s.user_id = u)
  )
$function$;

CREATE OR REPLACE FUNCTION public.nx_t_code_create(p_t uuid, p_max_uses integer DEFAULT 1, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_requires_approval boolean DEFAULT false, p_count integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); out_codes jsonb := '[]'::jsonb; c text; i int;
begin
  if not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  for i in 1..greatest(1, least(coalesce(p_count, 1), 50)) loop
    c := _nx_t_new_code();
    insert into nx_t_codes(tournament_id, code, max_uses, expires_at, requires_approval, created_by)
    values (p_t, c, greatest(1, least(coalesce(p_max_uses, 1), 1000)), p_expires_at, coalesce(p_requires_approval, false), me);
    out_codes := out_codes || to_jsonb(c);
  end loop;
  perform _nx_t_audit(p_t, me, 'codes_created', jsonb_build_object('count', jsonb_array_length(out_codes)));
  return jsonb_build_object('ok', true, 'codes', out_codes);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_code_revoke(p_code uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t uuid;
begin
  select tournament_id into t from nx_t_codes where id = p_code;
  if t is null or not nx_t_can_manage(t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  update nx_t_codes set revoked = true where id = p_code;
  perform _nx_t_audit(t, me, 'code_revoked', jsonb_build_object('code', p_code));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_decide(p_t uuid, p_user uuid, p_approve boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; n int; st text;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or e.status not in ('pending', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  if p_approve then
    select count(*) into n from nx_t_entries where tournament_id = p_t and status = 'approved';
    st := case when n >= t.capacity then 'waitlist' else 'approved' end;
    update nx_t_entries set status = st, decided_by = me, note = p_note, updated_at = now() where tournament_id = p_t and user_id = p_user;
    perform _nx_t_notify(p_user, p_t, null, case st when 'approved' then 'approved' else 'waitlisted' end,
                         jsonb_build_object('note', p_note), 'dec:' || p_t || ':' || p_user || ':' || st);
  else
    st := 'rejected';
    perform _nx_t_refund(p_t, p_user, 'rejected');
    update nx_t_entries set status = st, decided_by = me, note = p_note, updated_at = now() where tournament_id = p_t and user_id = p_user;
    perform _nx_t_notify(p_user, p_t, null, 'rejected', jsonb_build_object('note', p_note), 'dec:' || p_t || ':' || p_user || ':rejected');
  end if;
  perform _nx_t_audit(p_t, me, 'decided', jsonb_build_object('user', p_user, 'status', st, 'note', p_note));
  return jsonb_build_object('ok', true, 'status', st);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_dispute(p_m uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_t_matches;
begin
  select * into m from nx_t_matches where id = p_m;
  if m.id is null or not (me = m.p1 or me = m.p2) then return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if m.status in ('done', 'walkover', 'bye', 'void', 'skipped') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  perform _nx_t_dispute(p_m, me, coalesce(nullif(left(p_reason, 120), ''), 'player_dispute'));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_logs(p_t uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not nx_t_can_manage(p_t) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  return jsonb_build_object('ok', true,
    'audit', coalesce((select jsonb_agg(to_jsonb(a) || jsonb_build_object('actor_name', p.username) order by a.created_at desc)
                         from (select * from nx_t_audit where tournament_id = p_t order by created_at desc limit 300) a
                         left join profiles p on p.id = a.actor), '[]'::jsonb),
    'jobs', coalesce((select jsonb_agg(to_jsonb(j) order by j.run_at) from nx_t_jobs j where j.tournament_id = p_t), '[]'::jsonb),
    'ledger', coalesce((select jsonb_agg(to_jsonb(l) order by l.id) from nx_t_ledger l where l.tournament_id = p_t), '[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_mark_read()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update nx_t_notifications set read = true where user_id = auth.uid() and not read;
$function$;

CREATE OR REPLACE FUNCTION public.nx_t_ready(p_m uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); m nx_t_matches; t nx_tournaments; gm uuid;
begin
  select * into m from nx_t_matches where id = p_m for update;
  if m.id is null or me is null or not (me = m.p1 or me = m.p2) then return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if m.status = 'playing' then return jsonb_build_object('ok', true, 'status', 'playing', 'game_match', m.game_match); end if;
  if m.status <> 'ready_check' then return jsonb_build_object('ok', false, 'error', 'not_ready_time', 'status', m.status); end if;
  select * into t from nx_tournaments where id = m.tournament_id;
  if t.paused or t.status <> 'live' then return jsonb_build_object('ok', false, 'error', 'paused'); end if;
  if me = m.p1 then update nx_t_matches set p1_ready = true, updated_at = now() where id = p_m returning * into m;
  else update nx_t_matches set p2_ready = true, updated_at = now() where id = p_m returning * into m; end if;
  if m.p1_ready and m.p2_ready then
    gm := _nx_t_launch(p_m);
    return jsonb_build_object('ok', true, 'status', 'playing', 'game_match', gm);
  end if;
  return jsonb_build_object('ok', true, 'status', 'ready_check', 'p1_ready', m.p1_ready, 'p2_ready', m.p2_ready);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_register(p_t uuid, p_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; pr record; rating int; chk jsonb := null; approval boolean;
        lid bigint; st text; n_appr int; code_id uuid;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or t.status = 'draft' then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if t.status <> 'registering' then return jsonb_build_object('ok', false, 'error', 'registration_closed'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is not null and e.status in ('pending', 'approved', 'waitlist') then
    return jsonb_build_object('ok', true, 'status', e.status, 'already', true);
  end if;
  if e.user_id is not null and e.status in ('removed', 'rejected') then
    return jsonb_build_object('ok', false, 'error', 'not_allowed');
  end if;
  select level, xp, coins, coalesce(gems, 0) as gems into pr from profiles where id = me;
  if pr is null then return jsonb_build_object('ok', false, 'error', 'no_profile'); end if;
  select coalesce((select s.rating from nx_game_stats s where s.user_id = me and s.game = t.game), 1000) into rating;
  if coalesce(pr.level, 1) < t.min_level then return jsonb_build_object('ok', false, 'error', 'min_level', 'need', t.min_level); end if;
  if coalesce(pr.xp, 0) < t.min_xp then return jsonb_build_object('ok', false, 'error', 'min_xp', 'need', t.min_xp); end if;
  if rating < t.min_rating then return jsonb_build_object('ok', false, 'error', 'min_rating', 'need', t.min_rating); end if;
  if coalesce(p_code, '') <> '' then
    chk := _nx_t_check_code(me, p_t, p_code);
    if not (chk ->> 'ok')::boolean then return chk; end if;
    code_id := (chk ->> 'code_id')::uuid;
  elsif t.reg_mode in ('code', 'code_approval') then
    return jsonb_build_object('ok', false, 'error', 'code_required');
  end if;
  approval := t.reg_mode in ('approval', 'code_approval') or coalesce((chk ->> 'requires_approval')::boolean, false);
  lid := _nx_t_charge(p_t, me, t.fee_coins, t.fee_gems);
  if lid is null then return jsonb_build_object('ok', false, 'error', 'insufficient_funds',
                                                'fee_coins', t.fee_coins, 'fee_gems', t.fee_gems); end if;
  select count(*) into n_appr from nx_t_entries where tournament_id = p_t and status = 'approved';
  st := case when approval then 'pending' when n_appr >= t.capacity then 'waitlist' else 'approved' end;
  insert into nx_t_entries(tournament_id, user_id, status, rating, paid_coins, paid_gems, fee_ref, code_id)
  values (p_t, me, st, rating, t.fee_coins, t.fee_gems, nullif(lid, 0), code_id)
  on conflict (tournament_id, user_id) do update set status = excluded.status, rating = excluded.rating,
     paid_coins = excluded.paid_coins, paid_gems = excluded.paid_gems, fee_ref = excluded.fee_ref, code_id = excluded.code_id,
     note = null, place = null, seed = null, group_no = null, decided_by = null, created_at = now(), updated_at = now();
  if code_id is not null then update nx_t_codes set uses = uses + 1 where id = code_id; end if;
  perform _nx_t_notify(me, p_t, null, case st when 'approved' then 'approved' when 'waitlist' then 'waitlisted' else 'registered' end,
                       '{}'::jsonb, 'reg:' || p_t || ':' || coalesce(lid, 0));
  if st = 'pending' then
    perform _nx_t_notify_managers(p_t, null, 'approval_needed', jsonb_build_object('user', me), 'appr:' || p_t || ':' || me || ':' || coalesce(lid, 0));
  end if;
  perform _nx_t_audit(p_t, me, 'registered', jsonb_build_object('status', st, 'code', code_id, 'fee_coins', t.fee_coins, 'fee_gems', t.fee_gems));
  return jsonb_build_object('ok', true, 'status', st);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries;
begin
  select * into t from nx_tournaments where id = p_t for update;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = p_user for update;
  if e.user_id is null or e.status not in ('pending', 'approved', 'waitlist') then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform _nx_t_refund(p_t, p_user, 'removed');
  update nx_t_entries set status = 'removed', note = p_note, decided_by = me, updated_at = now() where tournament_id = p_t and user_id = p_user;
  perform _nx_t_notify(p_user, p_t, null, 'rejected', jsonb_build_object('note', p_note, 'removed', true), 'rm:' || p_t || ':' || p_user);
  if e.status = 'approved' then perform _nx_t_fill_from_waitlist(p_t); end if;
  perform _nx_t_audit(p_t, me, 'removed', jsonb_build_object('user', p_user, 'note', p_note));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_report(p_game uuid, p_winner_seat integer, p_s0 integer, p_s1 integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); g nx_t_games; w uuid;
begin
  select * into g from nx_t_games where game_match = p_game;
  if g.game_match is null or me is null or not (me = g.home or me = g.away) then
    return jsonb_build_object('ok', false, 'error', 'not_a_player'); end if;
  if p_winner_seat not in (-1, 0, 1) or p_s0 is null or p_s1 is null or p_s0 not between 0 and 99 or p_s1 not between 0 and 99 then
    return jsonb_build_object('ok', false, 'error', 'bad_report'); end if;
  if (p_winner_seat = 0 and p_s0 < p_s1) or (p_winner_seat = 1 and p_s1 < p_s0) or (p_winner_seat = -1 and p_s0 <> p_s1) then
    return jsonb_build_object('ok', false, 'error', 'inconsistent_report'); end if;
  w := case p_winner_seat when 0 then g.home when 1 then g.away end;
  insert into nx_t_reports(game_match, user_id, winner, s_home, s_away) values (p_game, me, w, p_s0, p_s1)
  on conflict (game_match, user_id) do nothing;
  perform _nx_t_try_accept(p_game, false);
  return jsonb_build_object('ok', true, 'accepted', (select accepted from nx_t_games where game_match = p_game),
                            'disputed', (select disputed from nx_t_games where game_match = p_game));
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_save(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; old nx_tournaments; isnew boolean; adm boolean; paid boolean;
        n_appr int; times_changed boolean := false; prize jsonb; dsum int := 0; v jsonb;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  adm := nx_t_is_admin(me);
  isnew := (p ->> 'id') is null;
  if isnew then
    if not nx_t_is_organizer(me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    t.id := gen_random_uuid(); t.status := 'draft'; t.created_by := me; t.config := '{}'; t.prize := '{}';
    t.game := 'finger_soccer'; t.format := 'single_elim'; t.capacity := 16; t.min_players := 2; t.reg_mode := 'open';
    t.min_level := 0; t.min_xp := 0; t.min_rating := 0; t.fee_coins := 0; t.fee_gems := 0; t.seeding := 'random';
    t.description := ''; t.rules := ''; t.paused := false; t.stage := 'main'; t.escrow_coins := 0; t.escrow_gems := 0;
    t.paid_out := false; t.created_at := now();
  else
    select * into t from nx_tournaments where id = (p ->> 'id')::uuid for update;
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if not nx_t_can_manage(t.id, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
    if t.status in ('finished', 'cancelled') then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  end if;
  old := t;
  -- always editable
  if p ? 'title' then t.title := left(trim(p ->> 'title'), 80); end if;
  if p ? 'description' then t.description := left(coalesce(p ->> 'description', ''), 4000); end if;
  if p ? 'rules' then t.rules := left(coalesce(p ->> 'rules', ''), 4000); end if;
  if p ? 'reg_open_at' and t.status in ('draft', 'scheduled') then t.reg_open_at := (p ->> 'reg_open_at')::timestamptz; end if;
  if p ? 'reg_close_at' and t.status in ('draft', 'scheduled', 'registering') then t.reg_close_at := (p ->> 'reg_close_at')::timestamptz; end if;
  if p ? 'draw_at' and t.status in ('draft', 'scheduled', 'registering', 'closed') then t.draw_at := (p ->> 'draw_at')::timestamptz; end if;
  if p ? 'start_at' and t.status in ('draft', 'scheduled', 'registering', 'closed', 'drawn') then t.start_at := (p ->> 'start_at')::timestamptz; end if;
  if p ? 'config' then
    if t.status in ('draft', 'scheduled', 'registering', 'closed') then
      t.config := _nx_t_validate_cfg(p -> 'config');
    else
      -- after the draw only timing settings may change
      v := p -> 'config';
      t.config := _nx_t_validate_cfg(t.config || jsonb_strip_nulls(jsonb_build_object(
        'round_starts', v -> 'round_starts', 'round_minutes', v -> 'round_minutes', 'ready_seconds', v -> 'ready_seconds',
        'max_game_minutes', v -> 'max_game_minutes')));
    end if;
  end if;
  if t.status in ('draft', 'scheduled', 'registering', 'closed') then
    select count(*) into n_appr from nx_t_entries where tournament_id = t.id and status = 'approved';
    select exists (select 1 from nx_t_entries where tournament_id = t.id and (paid_coins > 0 or paid_gems > 0)) into paid;
    if p ? 'game' then t.game := p ->> 'game'; end if;
    if p ? 'format' then t.format := p ->> 'format'; end if;
    if p ? 'capacity' then t.capacity := greatest(n_appr, (p ->> 'capacity')::int); end if;
    if p ? 'min_players' then t.min_players := greatest(2, least((p ->> 'min_players')::int, t.capacity)); end if;
    if p ? 'reg_mode' then t.reg_mode := p ->> 'reg_mode'; end if;
    if p ? 'min_level' then t.min_level := greatest(0, (p ->> 'min_level')::int); end if;
    if p ? 'min_xp' then t.min_xp := greatest(0, (p ->> 'min_xp')::int); end if;
    if p ? 'min_rating' then t.min_rating := greatest(0, (p ->> 'min_rating')::int); end if;
    if p ? 'seeding' then t.seeding := p ->> 'seeding'; end if;
    if not paid then
      if p ? 'fee_coins' then t.fee_coins := greatest(0, (p ->> 'fee_coins')::int); end if;
      if p ? 'fee_gems' then t.fee_gems := greatest(0, (p ->> 'fee_gems')::int); end if;
    elsif (p ? 'fee_coins' and (p ->> 'fee_coins')::int <> t.fee_coins) or (p ? 'fee_gems' and (p ->> 'fee_gems')::int <> t.fee_gems) then
      return jsonb_build_object('ok', false, 'error', 'fee_locked');
    end if;
    if p ? 'prize' then
      prize := coalesce(p -> 'prize', '{}'::jsonb);
      prize := jsonb_build_object(
        'fixed_coins', greatest(0, _nx_t_cfg_int(prize, 'fixed_coins', 0)),
        'fixed_gems', greatest(0, _nx_t_cfg_int(prize, 'fixed_gems', 0)),
        'pool_pct', greatest(0, least(_nx_t_cfg_int(prize, 'pool_pct', 0), 100)),
        'fee_pct', greatest(0, least(_nx_t_cfg_int(prize, 'fee_pct', 0), 50)),
        'dist', case when jsonb_typeof(prize -> 'dist') = 'array' then prize -> 'dist' else '[60,30,10]'::jsonb end);
      select coalesce(sum(greatest(0, x::numeric::int)), 0) into dsum from jsonb_array_elements_text(prize -> 'dist') x;
      if dsum > 100 or jsonb_array_length(prize -> 'dist') > 64 then
        return jsonb_build_object('ok', false, 'error', 'bad_distribution'); end if;
      -- minting coins/gems out of nothing is an admin decision
      -- (admins, the owner and tournament admins with the 'unlimited' perk; nothing is deducted from their balance,
      --  every payout is still written to nx_t_ledger)
      if (_nx_t_cfg_int(prize, 'fixed_coins', 0) > _nx_t_cfg_int(old.prize, 'fixed_coins', 0)
          or _nx_t_cfg_int(prize, 'fixed_gems', 0) > _nx_t_cfg_int(old.prize, 'fixed_gems', 0)) then
        if not (adm or nx_unlimited(me)) then
          return jsonb_build_object('ok', false, 'error', 'fixed_prize_admin_only'); end if;
        perform _nx_t_audit(t.id, me, 'fixed_prize_minted', jsonb_build_object(
          'fixed_coins', _nx_t_cfg_int(prize, 'fixed_coins', 0), 'fixed_gems', _nx_t_cfg_int(prize, 'fixed_gems', 0),
          'by', case when adm then 'admin' else 'tournament_admin_unlimited' end));
      end if;
      t.prize := prize;
    end if;
  end if;
  if t.title is null or char_length(t.title) < 3 then return jsonb_build_object('ok', false, 'error', 'bad_title'); end if;
  if t.format not in ('single_elim', 'double_elim', 'two_legs', 'round_robin', 'groups_ko', 'swiss', 'custom') then
    return jsonb_build_object('ok', false, 'error', 'bad_format'); end if;
  if t.capacity is null or t.capacity < 2 or t.capacity > 64 then return jsonb_build_object('ok', false, 'error', 'bad_capacity'); end if;
  if t.game not in ('finger_soccer', 'carrom', 'billiards', 'backgammon', 'quiz') then
    return jsonb_build_object('ok', false, 'error', 'bad_game'); end if;
  if t.reg_open_at is null or t.reg_close_at is null or t.draw_at is null or t.start_at is null
     or not (t.reg_open_at < t.reg_close_at and t.reg_close_at <= t.draw_at and t.draw_at <= t.start_at) then
    return jsonb_build_object('ok', false, 'error', 'bad_times'); end if;
  if t.format = 'groups_ko' and t.capacity < 4 then return jsonb_build_object('ok', false, 'error', 'groups_need_4'); end if;
  times_changed := not isnew and old.status <> 'draft' and (old.reg_open_at, old.reg_close_at, old.draw_at, old.start_at, old.config -> 'round_starts', old.config -> 'round_minutes')
                   is distinct from (t.reg_open_at, t.reg_close_at, t.draw_at, t.start_at, t.config -> 'round_starts', t.config -> 'round_minutes');
  t.updated_at := now();
  if isnew then
    insert into nx_tournaments select t.*;
    perform _nx_t_audit(t.id, me, 'created', jsonb_build_object('title', t.title, 'format', t.format));
  else
    update nx_tournaments set title = t.title, description = t.description, rules = t.rules, game = t.game, format = t.format,
           capacity = t.capacity, min_players = t.min_players, config = t.config, reg_mode = t.reg_mode, min_level = t.min_level,
           min_xp = t.min_xp, min_rating = t.min_rating, fee_coins = t.fee_coins, fee_gems = t.fee_gems, prize = t.prize,
           reg_open_at = t.reg_open_at, reg_close_at = t.reg_close_at, draw_at = t.draw_at, start_at = t.start_at,
           seeding = t.seeding, updated_at = now()
     where id = t.id;
    perform _nx_t_audit(t.id, me, 'edited', jsonb_build_object('times_changed', times_changed));
  end if;
  if times_changed then
    perform _nx_t_sync_jobs(t.id);
    perform _nx_t_reschedule(t.id);
    perform _nx_t_notify_all(t.id, 'time_changed', jsonb_build_object('start_at', t.start_at, 'reg_close_at', t.reg_close_at,
              'draw_at', t.draw_at), 'time:' || t.id || ':' || floor(extract(epoch from clock_timestamp()))::bigint,
              array['approved', 'pending', 'waitlist']);
  end if;
  return jsonb_build_object('ok', true, 'id', t.id);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_set_runner(p_t uuid, p_user uuid, p_add boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid();
begin
  if not (nx_t_is_admin(me) or exists (select 1 from nx_tournaments where id = p_t and created_by = me)) then
    return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if p_add then
    insert into nx_t_staff(tournament_id, user_id, added_by) values (p_t, p_user, me) on conflict do nothing;
  else
    delete from nx_t_staff where tournament_id = p_t and user_id = p_user;
  end if;
  perform _nx_t_audit(p_t, me, 'set_runner', jsonb_build_object('user', p_user, 'add', p_add));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_set_seed(p_t uuid, p_user uuid, p_seed integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or not nx_t_can_manage(p_t, me) then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if t.status not in ('draft', 'scheduled', 'registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  update nx_t_entries set seed = greatest(1, least(p_seed, 64)), updated_at = now() where tournament_id = p_t and user_id = p_user;
  perform _nx_t_audit(p_t, me, 'seed', jsonb_build_object('user', p_user, 'seed', p_seed));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_standings(p_t uuid)
 RETURNS TABLE(group_no integer, user_id uuid, username text, seed integer, played integer, won integer, drawn integer, lost integer, gf integer, ga integer, pts integer, rank integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t nx_tournaments; g int;
begin
  select * into t from nx_tournaments where id = p_t;
  if t.id is null or not nx_t_visible(p_t) then return; end if;
  if t.format = 'groups_ko' then
    for g in select distinct e.group_no from nx_t_entries e where e.tournament_id = p_t and e.group_no is not null order by 1 loop
      return query
        select g, x.user_id, p.username, x.seed, x.played, x.won, x.drawn, x.lost, x.gf, x.ga, x.pts,
               (row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed))::int
          from _nx_t_table(p_t, 'groups', g) x left join profiles p on p.id = x.user_id;
    end loop;
  else
    return query
      select null::int, x.user_id, p.username, x.seed, x.played, x.won, x.drawn, x.lost, x.gf, x.ga, x.pts,
             (row_number() over (order by x.pts desc, (x.gf - x.ga) desc, x.gf desc, x.won desc, x.seed))::int
        from _nx_t_table(p_t, 'main', null) x left join profiles p on p.id = x.user_id;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j nx_t_jobs; r record; nj int := 0; nr int := 0; nn int := 0; na int := 0;
begin
  if not pg_try_advisory_xact_lock(74230011) then return jsonb_build_object('skipped', true); end if;
  for j in select jb.* from nx_t_jobs jb left join nx_tournaments t on t.id = jb.tournament_id
            where jb.done_at is null and jb.run_at <= now()
              and not (coalesce(t.paused, false) and jb.kind in ('draw', 'start'))
            order by jb.run_at limit 200 loop
    begin
      perform _nx_t_run_job(j);
      update nx_t_jobs set done_at = now(), attempts = attempts + 1, last_error = null where id = j.id;
      nj := nj + 1;
    exception when others then
      update nx_t_jobs set attempts = attempts + 1, last_error = left(sqlerrm, 300),
             run_at = now() + make_interval(mins => least(attempts + 1, 15)),
             done_at = case when attempts + 1 >= 60 then now() end
       where id = j.id;
    end;
  end loop;
  -- due matches → ready check
  for r in select m.id from nx_t_matches m join nx_tournaments t on t.id = m.tournament_id
            where m.status = 'scheduled' and m.scheduled_at <= now() and t.status = 'live' and not t.paused
            order by m.scheduled_at limit 500 loop
    begin perform _nx_t_open_ready(r.id); nr := nr + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_ready', jsonb_build_object('match', r.id, 'error', sqlerrm)); end;
  end loop;
  -- ready deadlines → walkovers
  for r in select m.id from nx_t_matches m join nx_tournaments t on t.id = m.tournament_id
            where m.status = 'ready_check' and m.ready_deadline < now() and not t.paused limit 500 loop
    begin perform _nx_t_no_show(r.id); nn := nn + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_no_show', jsonb_build_object('match', r.id, 'error', sqlerrm)); end;
  end loop;
  -- results waiting for the second report
  for r in select g.game_match from nx_t_games g where not g.accepted and not g.disputed and g.ended_at is not null limit 500 loop
    begin perform _nx_t_try_accept(r.game_match, true); na := na + 1;
    exception when others then perform _nx_t_audit(null, null, 'error_accept', jsonb_build_object('game', r.game_match, 'error', sqlerrm)); end;
  end loop;
  -- games that never ended (both phones gone) → dispute for an organizer
  for r in select g.tmatch from nx_t_games g join nx_t_matches m on m.id = g.tmatch join nx_tournaments t on t.id = m.tournament_id
            where not g.accepted and not g.disputed and g.ended_at is null and m.status = 'playing'
              and g.created_at < now() - make_interval(mins => greatest(5, _nx_t_cfg_int(t.config, 'max_game_minutes', 30)))
            limit 100 loop
    begin perform _nx_t_dispute(r.tmatch, null, 'game_timeout');
    exception when others then null; end;
  end loop;
  return jsonb_build_object('jobs', nj, 'ready', nr, 'no_show', nn, 'accept', na);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_visible(t uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from nx_tournaments x where x.id = t and x.status <> 'draft') or nx_t_can_manage(t)
$function$;

CREATE OR REPLACE FUNCTION public.nx_t_withdraw(p_t uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); t nx_tournaments; e nx_t_entries; refunded boolean := false;
begin
  select * into t from nx_tournaments where id = p_t for update;
  select * into e from nx_t_entries where tournament_id = p_t and user_id = me for update;
  if e.user_id is null or e.status not in ('pending', 'approved', 'waitlist') then
    return jsonb_build_object('ok', false, 'error', 'not_registered'); end if;
  if t.status not in ('registering', 'closed') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  if t.status = 'registering' then refunded := _nx_t_refund(p_t, me, 'withdrawn'); end if;
  update nx_t_entries set status = 'withdrawn', updated_at = now() where tournament_id = p_t and user_id = me;
  if e.status = 'approved' then perform _nx_t_fill_from_waitlist(p_t); end if;
  perform _nx_t_audit(p_t, me, 'withdrawn', jsonb_build_object('refunded', refunded));
  return jsonb_build_object('ok', true, 'refunded', refunded);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_update_room(p_room uuid, p_seats integer, p_settings jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r nx_rooms; b record; n int;
begin
  select * into r from nx_rooms where id = p_room for update;
  if r.host <> auth.uid() then raise exception 'host only'; end if;
  if r.status <> 'lobby' then raise exception 'already started'; end if;
  select * into b from nx_game_bounds(r.game);
  select count(*) into n from nx_room_players where room_id = p_room;
  update nx_rooms set seats = greatest(n, greatest(b.min_seats, least(coalesce(p_seats, r.seats), b.max_seats))),
         settings = coalesce(p_settings, settings), updated_at = now() where id = p_room;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_ledger_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  raise exception '% is append-only', tg_table_name;
end $function$;

CREATE OR REPLACE FUNCTION public._nx_t_notif_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.user_id := old.user_id; new.tournament_id := old.tournament_id; new.tmatch := old.tmatch; new.kind := old.kind;
  new.data := old.data; new.dedup := old.dedup; new.created_at := old.created_at;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_join_code(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); chk jsonb; res jsonb; t uuid;
begin
  if me is null then return jsonb_build_object('ok', false, 'error', 'not_signed_in'); end if;
  chk := _nx_t_check_code(me, null, p_code);
  if not (chk ->> 'ok')::boolean then return chk; end if;
  t := (chk ->> 'tournament_id')::uuid;
  -- the check above logged a successful attempt; nx_t_register validates (and logs) once more on purpose
  res := nx_t_register(t, p_code);
  return res || jsonb_build_object('tournament_id', t);
end $function$;

CREATE OR REPLACE FUNCTION public.nx_t_my_role()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('admin', nx_t_is_admin(auth.uid()), 'organizer', nx_t_is_organizer(auth.uid()), 'uid', auth.uid(),
                            'owner', nx_is_owner(auth.uid()), 'unlimited', nx_unlimited(auth.uid()))
$function$;

drop policy if exists nx_rooms_read on public.nx_rooms;
create policy nx_rooms_read on public.nx_rooms for SELECT to authenticated using (((NOT is_private) OR (host = auth.uid()) OR nx_in_room(id)));
drop policy if exists nx_room_players_read on public.nx_room_players;
create policy nx_room_players_read on public.nx_room_players for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM nx_rooms r
  WHERE ((r.id = nx_room_players.room_id) AND ((NOT r.is_private) OR nx_in_room(r.id))))));
drop policy if exists nx_matches_read on public.nx_matches;
create policy nx_matches_read on public.nx_matches for SELECT to authenticated using (true);
drop policy if exists nx_match_moves_read on public.nx_match_moves;
create policy nx_match_moves_read on public.nx_match_moves for SELECT to authenticated using (nx_in_match(match_id));
drop policy if exists nx_match_results_read on public.nx_match_results;
create policy nx_match_results_read on public.nx_match_results for SELECT to authenticated using (true);
drop policy if exists nx_match_secrets_read on public.nx_match_secrets;
create policy nx_match_secrets_read on public.nx_match_secrets for SELECT to authenticated using ((user_id = auth.uid()));
drop policy if exists nx_game_stats_read on public.nx_game_stats;
create policy nx_game_stats_read on public.nx_game_stats for SELECT to public using (true);
drop policy if exists nx_invites_read on public.nx_invites;
create policy nx_invites_read on public.nx_invites for SELECT to authenticated using (((to_user = auth.uid()) OR (from_user = auth.uid())));
drop policy if exists nx_invites_upd on public.nx_invites;
create policy nx_invites_upd on public.nx_invites for UPDATE to authenticated using ((to_user = auth.uid())) with check ((to_user = auth.uid()));
drop policy if exists nx_xp_events_read on public.nx_xp_events;
create policy nx_xp_events_read on public.nx_xp_events for SELECT to authenticated using ((user_id = auth.uid()));
drop policy if exists nx_tournaments_read on public.nx_tournaments;
create policy nx_tournaments_read on public.nx_tournaments for SELECT to authenticated using (((status <> 'draft'::text) OR nx_t_can_manage(id)));
drop policy if exists nx_t_audit_read on public.nx_t_audit;
create policy nx_t_audit_read on public.nx_t_audit for SELECT to authenticated using (nx_t_can_manage(tournament_id));
drop policy if exists nx_t_codes_read on public.nx_t_codes;
create policy nx_t_codes_read on public.nx_t_codes for SELECT to authenticated using (nx_t_can_manage(tournament_id));
drop policy if exists nx_t_entries_read on public.nx_t_entries;
create policy nx_t_entries_read on public.nx_t_entries for SELECT to authenticated using (((user_id = auth.uid()) OR ((status = ANY (ARRAY['approved'::text, 'waitlist'::text])) AND nx_t_visible(tournament_id)) OR nx_t_can_manage(tournament_id)));
drop policy if exists nx_t_games_read on public.nx_t_games;
create policy nx_t_games_read on public.nx_t_games for SELECT to authenticated using ((EXISTS ( SELECT 1
   FROM nx_t_matches m
  WHERE ((m.id = nx_t_games.tmatch) AND nx_t_visible(m.tournament_id)))));
drop policy if exists nx_t_ledger_read on public.nx_t_ledger;
create policy nx_t_ledger_read on public.nx_t_ledger for SELECT to authenticated using (((user_id = auth.uid()) OR nx_t_can_manage(tournament_id)));
drop policy if exists nx_t_matches_read on public.nx_t_matches;
create policy nx_t_matches_read on public.nx_t_matches for SELECT to authenticated using (nx_t_visible(tournament_id));
drop policy if exists nx_t_notif_del on public.nx_t_notifications;
create policy nx_t_notif_del on public.nx_t_notifications for DELETE to authenticated using ((user_id = auth.uid()));
drop policy if exists nx_t_notif_read on public.nx_t_notifications;
create policy nx_t_notif_read on public.nx_t_notifications for SELECT to authenticated using ((user_id = auth.uid()));
drop policy if exists nx_t_notif_upd on public.nx_t_notifications;
create policy nx_t_notif_upd on public.nx_t_notifications for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
drop policy if exists nx_t_reports_read on public.nx_t_reports;
create policy nx_t_reports_read on public.nx_t_reports for SELECT to authenticated using (((user_id = auth.uid()) OR (EXISTS ( SELECT 1
   FROM (nx_t_games g
     JOIN nx_t_matches m ON ((m.id = g.tmatch)))
  WHERE ((g.game_match = nx_t_reports.game_match) AND nx_t_can_manage(m.tournament_id))))));
drop policy if exists nx_t_staff_read on public.nx_t_staff;
create policy nx_t_staff_read on public.nx_t_staff for SELECT to authenticated using (nx_t_visible(tournament_id));


drop trigger if exists nx_t_on_match_end on public.nx_matches;
CREATE TRIGGER nx_t_on_match_end AFTER UPDATE OF status ON public.nx_matches FOR EACH ROW EXECUTE FUNCTION _nx_t_on_match_end();

drop trigger if exists nx_t_audit_immutable on public.nx_t_audit;
CREATE TRIGGER nx_t_audit_immutable BEFORE DELETE OR UPDATE ON public.nx_t_audit FOR EACH ROW EXECUTE FUNCTION _nx_t_ledger_immutable();

drop trigger if exists nx_t_ledger_immutable on public.nx_t_ledger;
CREATE TRIGGER nx_t_ledger_immutable BEFORE DELETE OR UPDATE ON public.nx_t_ledger FOR EACH ROW EXECUTE FUNCTION _nx_t_ledger_immutable();

drop trigger if exists nx_t_notif_guard on public.nx_t_notifications;
CREATE TRIGGER nx_t_notif_guard BEFORE UPDATE ON public.nx_t_notifications FOR EACH ROW EXECUTE FUNCTION _nx_t_notif_guard();

create or replace view public.nx_leaderboard as SELECT s.game,
    s.user_id,
    p.username,
    p.avatar,
    s.rating,
    s.played,
    s.won,
    s.lost,
    s.draw,
    s.best
   FROM nx_game_stats s
     JOIN profiles p ON p.id = s.user_id;

create or replace view public.nx_leaderboard_global as  SELECT p.id AS user_id,
    p.username,
    p.avatar,
    p.xp,
    p.level,
    COALESCE(sum(s.won), 0::bigint)::integer AS won,
    COALESCE(sum(s.played), 0::bigint)::integer AS played
   FROM profiles p
          LEFT JOIN nx_game_stats s ON s.user_id = p.id
  GROUP BY p.id, p.username, p.avatar, p.xp, p.level;

do $$ begin alter publication supabase_realtime add table public.nx_rooms; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_room_players; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_matches; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_match_moves; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_invites; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_tournaments; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_t_entries; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_t_matches; exception when duplicate_object then null; end $$;

do $$ begin alter publication supabase_realtime add table public.nx_t_notifications; exception when duplicate_object then null; end $$;


alter view public.nx_leaderboard set (security_invoker = true);
alter view public.nx_leaderboard_global set (security_invoker = true);


do $$ begin perform cron.unschedule(jobid) from cron.job where jobname = 'nx_t_tick'; exception when others then null; end $$;
select cron.schedule('nx_t_tick', '* * * * *', 'select public.nx_t_tick()');


revoke all on function public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[]) from public, anon, authenticated;
grant execute on function public._nx_apply_result(m nx_matches, p_winners integer[], p_scores integer[]) to service_role;
revoke all on function public._nx_leave_all(me uuid) from public, anon, authenticated;
grant execute on function public._nx_leave_all(me uuid) to service_role;
revoke all on function public._nx_t_audit(p_t uuid, p_actor uuid, p_action text, p_data jsonb) from public, anon, authenticated;
grant execute on function public._nx_t_audit(p_t uuid, p_actor uuid, p_action text, p_data jsonb) to service_role;
revoke all on function public._nx_t_better_seed(p_t uuid, a uuid, b uuid) from public, anon, authenticated;
grant execute on function public._nx_t_better_seed(p_t uuid, a uuid, b uuid) to service_role;
revoke all on function public._nx_t_bo(t nx_tournaments, p_kind text) from public, anon, authenticated;
grant execute on function public._nx_t_bo(t nx_tournaments, p_kind text) to service_role;
revoke all on function public._nx_t_cancel(p_t uuid, p_reason text, p_actor uuid) from public, anon, authenticated;
grant execute on function public._nx_t_cancel(p_t uuid, p_reason text, p_actor uuid) to service_role;
revoke all on function public._nx_t_cfg_bool(c jsonb, k text, d boolean) from public, anon, authenticated;
grant execute on function public._nx_t_cfg_bool(c jsonb, k text, d boolean) to service_role;
revoke all on function public._nx_t_cfg_int(c jsonb, k text, d integer) from public, anon, authenticated;
grant execute on function public._nx_t_cfg_int(c jsonb, k text, d integer) to service_role;
revoke all on function public._nx_t_charge(p_t uuid, p_user uuid, p_coins integer, p_gems integer) from public, anon, authenticated;
grant execute on function public._nx_t_charge(p_t uuid, p_user uuid, p_coins integer, p_gems integer) to service_role;
revoke all on function public._nx_t_check(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_check(p_m uuid) to service_role;
revoke all on function public._nx_t_check_code(p_user uuid, p_t uuid, p_code text) from public, anon, authenticated;
grant execute on function public._nx_t_check_code(p_user uuid, p_t uuid, p_code text) to service_role;
revoke all on function public._nx_t_complete(p_m uuid, p_winner uuid, p_loser uuid, p_draw boolean, p_status text, p_note text) from public, anon, authenticated;
grant execute on function public._nx_t_complete(p_m uuid, p_winner uuid, p_loser uuid, p_draw boolean, p_status text, p_note text) to service_role;
revoke all on function public._nx_t_dispute(p_m uuid, p_actor uuid, p_reason text) from public, anon, authenticated;
grant execute on function public._nx_t_dispute(p_m uuid, p_actor uuid, p_reason text) to service_role;
revoke all on function public._nx_t_downstream_free(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_downstream_free(p_m uuid) to service_role;
revoke all on function public._nx_t_draw(p_t uuid, p_actor uuid) from public, anon, authenticated;
grant execute on function public._nx_t_draw(p_t uuid, p_actor uuid) to service_role;
revoke all on function public._nx_t_fill_from_waitlist(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_fill_from_waitlist(p_t uuid) to service_role;
revoke all on function public._nx_t_finish(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_finish(p_t uuid) to service_role;
revoke all on function public._nx_t_game_result(p_gm uuid, p_winner uuid, p_s_home integer, p_s_away integer, p_source text) from public, anon, authenticated;
grant execute on function public._nx_t_game_result(p_gm uuid, p_winner uuid, p_s_home integer, p_s_away integer, p_source text) to service_role;
revoke all on function public._nx_t_gen_de(p_t uuid, players uuid[]) from public, anon, authenticated;
grant execute on function public._nx_t_gen_de(p_t uuid, players uuid[]) to service_role;
revoke all on function public._nx_t_gen_on() from public, anon, authenticated;
grant execute on function public._nx_t_gen_on() to service_role;
revoke all on function public._nx_t_gen_rr(p_t uuid, players uuid[], p_group integer, p_double boolean, r_off integer, s_off integer, p_bracket text, p_stage text) from public, anon, authenticated;
grant execute on function public._nx_t_gen_rr(p_t uuid, players uuid[], p_group integer, p_double boolean, r_off integer, s_off integer, p_bracket text, p_stage text) to service_role;
revoke all on function public._nx_t_gen_se(p_t uuid, players uuid[], p_stage text, r_off integer, s_off integer) from public, anon, authenticated;
grant execute on function public._nx_t_gen_se(p_t uuid, players uuid[], p_stage text, r_off integer, s_off integer) to service_role;
revoke all on function public._nx_t_job(p_kind text, p_t uuid, p_ref uuid, p_run timestamp with time zone, p_key text) from public, anon, authenticated;
grant execute on function public._nx_t_job(p_kind text, p_t uuid, p_ref uuid, p_run timestamp with time zone, p_key text) to service_role;
revoke all on function public._nx_t_launch(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_launch(p_m uuid) to service_role;
revoke all on function public._nx_t_lb_count(p integer, m integer) from public, anon, authenticated;
grant execute on function public._nx_t_lb_count(p integer, m integer) to service_role;
revoke all on function public._nx_t_mid(p_t uuid, p_stage text, p_bracket text, p_round integer, p_idx integer) from public, anon, authenticated;
grant execute on function public._nx_t_mid(p_t uuid, p_stage text, p_bracket text, p_round integer, p_idx integer) to service_role;
revoke all on function public._nx_t_new_code() from public, anon, authenticated;
grant execute on function public._nx_t_new_code() to service_role;
revoke all on function public._nx_t_new_match(t nx_tournaments, p_stage text, p_bracket text, p_round integer, p_idx integer, p_slot integer, p_group integer, p_bo integer, p_label text) from public, anon, authenticated;
grant execute on function public._nx_t_new_match(t nx_tournaments, p_stage text, p_bracket text, p_round integer, p_idx integer, p_slot integer, p_group integer, p_bo integer, p_label text) to service_role;
revoke all on function public._nx_t_no_show(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_no_show(p_m uuid) to service_role;
revoke all on function public._nx_t_notify(p_user uuid, p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text) from public, anon, authenticated;
grant execute on function public._nx_t_notify(p_user uuid, p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text) to service_role;
revoke all on function public._nx_t_notify_all(p_t uuid, p_kind text, p_data jsonb, p_dedup text, p_statuses text[]) from public, anon, authenticated;
grant execute on function public._nx_t_notify_all(p_t uuid, p_kind text, p_data jsonb, p_dedup text, p_statuses text[]) to service_role;
revoke all on function public._nx_t_notify_managers(p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text) from public, anon, authenticated;
grant execute on function public._nx_t_notify_managers(p_t uuid, p_tm uuid, p_kind text, p_data jsonb, p_dedup text) to service_role;
revoke all on function public._nx_t_on_match_end() from public, anon, authenticated;
grant execute on function public._nx_t_on_match_end() to service_role;
revoke all on function public._nx_t_open_ready(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_open_ready(p_m uuid) to service_role;
revoke all on function public._nx_t_payout(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_payout(p_t uuid) to service_role;
revoke all on function public._nx_t_place_elim(p_t uuid, p_stage text) from public, anon, authenticated;
grant execute on function public._nx_t_place_elim(p_t uuid, p_stage text) to service_role;
revoke all on function public._nx_t_planned(t nx_tournaments, p_slot integer) from public, anon, authenticated;
grant execute on function public._nx_t_planned(t nx_tournaments, p_slot integer) to service_role;
revoke all on function public._nx_t_prize_total(p_fixed integer, p_escrow integer, p_pool_pct integer, p_fee_pct integer) from public, anon, authenticated;
grant execute on function public._nx_t_prize_total(p_fixed integer, p_escrow integer, p_pool_pct integer, p_fee_pct integer) to service_role;
revoke all on function public._nx_t_progress(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_progress(p_t uuid) to service_role;
revoke all on function public._nx_t_propagate(p_m uuid) from public, anon, authenticated;
grant execute on function public._nx_t_propagate(p_m uuid) to service_role;
revoke all on function public._nx_t_put(p_m uuid, p_slot integer, p_player uuid) from public, anon, authenticated;
grant execute on function public._nx_t_put(p_m uuid, p_slot integer, p_player uuid) to service_role;
revoke all on function public._nx_t_refund(p_t uuid, p_user uuid, p_reason text) from public, anon, authenticated;
grant execute on function public._nx_t_refund(p_t uuid, p_user uuid, p_reason text) to service_role;
revoke all on function public._nx_t_reschedule(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_reschedule(p_t uuid) to service_role;
revoke all on function public._nx_t_run_job(j nx_t_jobs) from public, anon, authenticated;
grant execute on function public._nx_t_run_job(j nx_t_jobs) to service_role;
revoke all on function public._nx_t_seed_order(p integer) from public, anon, authenticated;
grant execute on function public._nx_t_seed_order(p integer) to service_role;
revoke all on function public._nx_t_split(p_t uuid, p_total integer, p_dist integer[]) from public, anon, authenticated;
grant execute on function public._nx_t_split(p_t uuid, p_total integer, p_dist integer[]) to service_role;
revoke all on function public._nx_t_start(p_t uuid, p_actor uuid) from public, anon, authenticated;
grant execute on function public._nx_t_start(p_t uuid, p_actor uuid) to service_role;
revoke all on function public._nx_t_swiss_round(p_t uuid, p_r integer) from public, anon, authenticated;
grant execute on function public._nx_t_swiss_round(p_t uuid, p_r integer) to service_role;
revoke all on function public._nx_t_sync_jobs(p_t uuid) from public, anon, authenticated;
grant execute on function public._nx_t_sync_jobs(p_t uuid) to service_role;
revoke all on function public._nx_t_table(p_t uuid, p_stage text, p_group integer) from public, anon, authenticated;
grant execute on function public._nx_t_table(p_t uuid, p_stage text, p_group integer) to service_role;
revoke all on function public._nx_t_try_accept(p_gm uuid, p_from_tick boolean) from public, anon, authenticated;
grant execute on function public._nx_t_try_accept(p_gm uuid, p_from_tick boolean) to service_role;
revoke all on function public._nx_t_validate_cfg(c jsonb) from public, anon, authenticated;
grant execute on function public._nx_t_validate_cfg(c jsonb) to service_role;
revoke all on function public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean, p_settings jsonb) from public, anon, authenticated;
grant execute on function public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean, p_settings jsonb) to anon, authenticated;
grant execute on function public.nx_create_room(p_game text, p_seats integer, p_private boolean, p_quick boolean, p_settings jsonb) to service_role;
revoke all on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) from public, anon, authenticated;
grant execute on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) to anon, authenticated;
grant execute on function public.nx_finish_match(p_match uuid, p_winners integer[], p_scores integer[], p_hash text, p_reason text) to service_role;
revoke all on function public.nx_finish_match_as(p_match uuid, p_winners integer[], p_loser integer) from public, anon, authenticated;
grant execute on function public.nx_finish_match_as(p_match uuid, p_winners integer[], p_loser integer) to service_role;
revoke all on function public.nx_forfeit(p_match uuid, p_seat integer) from public, anon, authenticated;
grant execute on function public.nx_forfeit(p_match uuid, p_seat integer) to anon, authenticated;
grant execute on function public.nx_forfeit(p_match uuid, p_seat integer) to service_role;
revoke all on function public.nx_game_bounds(p_game text, OUT min_seats integer, OUT max_seats integer) from public, anon, authenticated;
grant execute on function public.nx_game_bounds(p_game text, OUT min_seats integer, OUT max_seats integer) to anon, authenticated;
grant execute on function public.nx_game_bounds(p_game text, OUT min_seats integer, OUT max_seats integer) to service_role;
revoke all on function public.nx_gen_code() from public, anon, authenticated;
grant execute on function public.nx_gen_code() to anon, authenticated;
grant execute on function public.nx_gen_code() to service_role;
revoke all on function public.nx_in_match(m uuid) from public, anon, authenticated;
grant execute on function public.nx_in_match(m uuid) to anon, authenticated;
grant execute on function public.nx_in_match(m uuid) to service_role;
revoke all on function public.nx_in_room(r uuid) from public, anon, authenticated;
grant execute on function public.nx_in_room(r uuid) to anon, authenticated;
grant execute on function public.nx_in_room(r uuid) to service_role;
revoke all on function public.nx_invite(p_room uuid, p_user uuid) from public, anon, authenticated;
grant execute on function public.nx_invite(p_room uuid, p_user uuid) to anon, authenticated;
grant execute on function public.nx_invite(p_room uuid, p_user uuid) to service_role;
revoke all on function public.nx_join_room(p_code text, p_room uuid) from public, anon, authenticated;
grant execute on function public.nx_join_room(p_code text, p_room uuid) to anon, authenticated;
grant execute on function public.nx_join_room(p_code text, p_room uuid) to service_role;
revoke all on function public.nx_leave_room(p_room uuid) from public, anon, authenticated;
grant execute on function public.nx_leave_room(p_room uuid) to anon, authenticated;
grant execute on function public.nx_leave_room(p_room uuid) to service_role;
revoke all on function public.nx_my_active_match() from public, anon, authenticated;
grant execute on function public.nx_my_active_match() to authenticated;
grant execute on function public.nx_my_active_match() to service_role;
revoke all on function public.nx_owner_tournaments(p_limit integer) from public, anon, authenticated;
grant execute on function public.nx_owner_tournaments(p_limit integer) to authenticated;
grant execute on function public.nx_owner_tournaments(p_limit integer) to service_role;
revoke all on function public.nx_push_move(p_match uuid, p_seq integer, p_kind text, p_move jsonb, p_hash text, p_seat integer) from public, anon, authenticated;
grant execute on function public.nx_push_move(p_match uuid, p_seq integer, p_kind text, p_move jsonb, p_hash text, p_seat integer) to anon, authenticated;
grant execute on function public.nx_push_move(p_match uuid, p_seq integer, p_kind text, p_move jsonb, p_hash text, p_seat integer) to service_role;
revoke all on function public.nx_put_secret(p_match uuid, p_user uuid, p_slot text, p_data jsonb) from public, anon, authenticated;
grant execute on function public.nx_put_secret(p_match uuid, p_user uuid, p_slot text, p_data jsonb) to anon, authenticated;
grant execute on function public.nx_put_secret(p_match uuid, p_user uuid, p_slot text, p_data jsonb) to service_role;
revoke all on function public.nx_quick(p_game text, p_seats integer) from public, anon, authenticated;
grant execute on function public.nx_quick(p_game text, p_seats integer) to anon, authenticated;
grant execute on function public.nx_quick(p_game text, p_seats integer) to service_role;
revoke all on function public.nx_set_ready(p_room uuid, p_ready boolean) from public, anon, authenticated;
grant execute on function public.nx_set_ready(p_room uuid, p_ready boolean) to anon, authenticated;
grant execute on function public.nx_set_ready(p_room uuid, p_ready boolean) to service_role;
revoke all on function public.nx_start_match(p_room uuid) from public, anon, authenticated;
grant execute on function public.nx_start_match(p_room uuid) to anon, authenticated;
grant execute on function public.nx_start_match(p_room uuid) to service_role;
revoke all on function public.nx_start_match_quick(p_room uuid) from public, anon, authenticated;
grant execute on function public.nx_start_match_quick(p_room uuid) to service_role;
revoke all on function public.nx_t_admin(p_t uuid, p_action text, p_reason text) from public, anon, authenticated;
grant execute on function public.nx_t_admin(p_t uuid, p_action text, p_reason text) to authenticated;
grant execute on function public.nx_t_admin(p_t uuid, p_action text, p_reason text) to service_role;
revoke all on function public.nx_t_admin_match(p_m uuid, p_action text, p jsonb) from public, anon, authenticated;
grant execute on function public.nx_t_admin_match(p_m uuid, p_action text, p jsonb) to authenticated;
grant execute on function public.nx_t_admin_match(p_m uuid, p_action text, p jsonb) to service_role;
revoke all on function public.nx_t_can_manage(t uuid, u uuid) from public, anon, authenticated;
grant execute on function public.nx_t_can_manage(t uuid, u uuid) to anon, authenticated;
grant execute on function public.nx_t_can_manage(t uuid, u uuid) to service_role;
revoke all on function public.nx_t_code_create(p_t uuid, p_max_uses integer, p_expires_at timestamp with time zone, p_requires_approval boolean, p_count integer) from public, anon, authenticated;
grant execute on function public.nx_t_code_create(p_t uuid, p_max_uses integer, p_expires_at timestamp with time zone, p_requires_approval boolean, p_count integer) to authenticated;
grant execute on function public.nx_t_code_create(p_t uuid, p_max_uses integer, p_expires_at timestamp with time zone, p_requires_approval boolean, p_count integer) to service_role;
revoke all on function public.nx_t_code_revoke(p_code uuid) from public, anon, authenticated;
grant execute on function public.nx_t_code_revoke(p_code uuid) to authenticated;
grant execute on function public.nx_t_code_revoke(p_code uuid) to service_role;
revoke all on function public.nx_t_decide(p_t uuid, p_user uuid, p_approve boolean, p_note text) from public, anon, authenticated;
grant execute on function public.nx_t_decide(p_t uuid, p_user uuid, p_approve boolean, p_note text) to authenticated;
grant execute on function public.nx_t_decide(p_t uuid, p_user uuid, p_approve boolean, p_note text) to service_role;
revoke all on function public.nx_t_dispute(p_m uuid, p_reason text) from public, anon, authenticated;
grant execute on function public.nx_t_dispute(p_m uuid, p_reason text) to authenticated;
grant execute on function public.nx_t_dispute(p_m uuid, p_reason text) to service_role;
revoke all on function public.nx_t_logs(p_t uuid) from public, anon, authenticated;
grant execute on function public.nx_t_logs(p_t uuid) to authenticated;
grant execute on function public.nx_t_logs(p_t uuid) to service_role;
revoke all on function public.nx_t_mark_read() from public, anon, authenticated;
grant execute on function public.nx_t_mark_read() to authenticated;
grant execute on function public.nx_t_mark_read() to service_role;
revoke all on function public.nx_t_ready(p_m uuid) from public, anon, authenticated;
grant execute on function public.nx_t_ready(p_m uuid) to authenticated;
grant execute on function public.nx_t_ready(p_m uuid) to service_role;
revoke all on function public.nx_t_register(p_t uuid, p_code text) from public, anon, authenticated;
grant execute on function public.nx_t_register(p_t uuid, p_code text) to authenticated;
grant execute on function public.nx_t_register(p_t uuid, p_code text) to service_role;
revoke all on function public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text) from public, anon, authenticated;
grant execute on function public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text) to authenticated;
grant execute on function public.nx_t_remove_entry(p_t uuid, p_user uuid, p_note text) to service_role;
revoke all on function public.nx_t_report(p_game uuid, p_winner_seat integer, p_s0 integer, p_s1 integer) from public, anon, authenticated;
grant execute on function public.nx_t_report(p_game uuid, p_winner_seat integer, p_s0 integer, p_s1 integer) to authenticated;
grant execute on function public.nx_t_report(p_game uuid, p_winner_seat integer, p_s0 integer, p_s1 integer) to service_role;
revoke all on function public.nx_t_save(p jsonb) from public, anon, authenticated;
grant execute on function public.nx_t_save(p jsonb) to authenticated;
grant execute on function public.nx_t_save(p jsonb) to service_role;
revoke all on function public.nx_t_set_runner(p_t uuid, p_user uuid, p_add boolean) from public, anon, authenticated;
grant execute on function public.nx_t_set_runner(p_t uuid, p_user uuid, p_add boolean) to authenticated;
grant execute on function public.nx_t_set_runner(p_t uuid, p_user uuid, p_add boolean) to service_role;
revoke all on function public.nx_t_set_seed(p_t uuid, p_user uuid, p_seed integer) from public, anon, authenticated;
grant execute on function public.nx_t_set_seed(p_t uuid, p_user uuid, p_seed integer) to authenticated;
grant execute on function public.nx_t_set_seed(p_t uuid, p_user uuid, p_seed integer) to service_role;
revoke all on function public.nx_t_standings(p_t uuid) from public, anon, authenticated;
grant execute on function public.nx_t_standings(p_t uuid) to authenticated;
grant execute on function public.nx_t_standings(p_t uuid) to service_role;
revoke all on function public.nx_t_tick() from public, anon, authenticated;
grant execute on function public.nx_t_tick() to service_role;
revoke all on function public.nx_t_visible(t uuid) from public, anon, authenticated;
grant execute on function public.nx_t_visible(t uuid) to anon, authenticated;
grant execute on function public.nx_t_visible(t uuid) to service_role;
revoke all on function public.nx_t_withdraw(p_t uuid) from public, anon, authenticated;
grant execute on function public.nx_t_withdraw(p_t uuid) to authenticated;
grant execute on function public.nx_t_withdraw(p_t uuid) to service_role;
revoke all on function public.nx_update_room(p_room uuid, p_seats integer, p_settings jsonb) from public, anon, authenticated;
grant execute on function public.nx_update_room(p_room uuid, p_seats integer, p_settings jsonb) to anon, authenticated;
grant execute on function public.nx_update_room(p_room uuid, p_seats integer, p_settings jsonb) to service_role;
revoke all on function public._nx_t_ledger_immutable() from public, anon, authenticated;
grant execute on function public._nx_t_ledger_immutable() to service_role;
revoke all on function public._nx_t_notif_guard() from public, anon, authenticated;
grant execute on function public._nx_t_notif_guard() to service_role;
revoke all on function public.nx_t_join_code(p_code text) from public, anon, authenticated;
grant execute on function public.nx_t_join_code(p_code text) to authenticated;
grant execute on function public.nx_t_join_code(p_code text) to service_role;
revoke all on function public.nx_t_my_role() from public, anon, authenticated;
grant execute on function public.nx_t_my_role() to authenticated;
grant execute on function public.nx_t_my_role() to service_role;
