-- NEXORA backend v2: disc catalog & gem economy, arena/quick matchmaking fixes, social (follow, DM, groups, channels),
-- avatars, clubs, daily challenges, seasons with gem rewards (<=30), tournaments 4..64.

-- ============ PROFILE EXTRAS ============
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists bio text check (char_length(bio) <= 160);
alter table public.profiles add column if not exists club_id uuid;
alter table public.profiles add column if not exists equipped_disc text not null default 'club0';
alter table public.profiles add column if not exists arena_points int not null default 0;
alter table public.profiles add column if not exists win_streak int not null default 0;
alter table public.profiles add column if not exists best_streak int not null default 0;
alter table public.profiles alter column gems set default 150;
alter table public.profiles alter column avatar set default 'club0';
grant update (username, avatar, avatar_url, bio, online_at) on public.profiles to authenticated;

-- ============ DISC CATALOG / INVENTORY ============
create table if not exists public.discs (
  id text primary key, cat text not null, name text not null,
  price_gems int not null check (price_gems = 0 or price_gems between 130 and 300),
  power smallint not null check (power between 1 and 10),
  accuracy smallint not null check (accuracy between 1 and 10)
);
create table if not exists public.inventory (
  user_id uuid references public.profiles(id) on delete cascade,
  disc_id text references public.discs(id) on delete cascade,
  acquired_at timestamptz not null default now(),
  primary key (user_id, disc_id)
);
alter table public.discs enable row level security;
alter table public.inventory enable row level security;
create policy "read" on public.discs for select using (true);
create policy "read" on public.inventory for select to authenticated using (true);
revoke insert, update, delete on public.discs, public.inventory from authenticated, anon;

create or replace function public.buy_disc(p_disc text) returns int language plpgsql security definer set search_path=public as $$
declare d discs; g int; begin
  select * into d from discs where id=p_disc; if d.id is null then raise exception 'disc not found'; end if;
  if exists(select 1 from inventory where user_id=auth.uid() and disc_id=p_disc) then raise exception 'already owned'; end if;
  update profiles set gems = gems - d.price_gems where id=auth.uid() and gems >= d.price_gems returning gems into g;
  if g is null then raise exception 'not enough gems'; end if;
  insert into inventory(user_id,disc_id) values (auth.uid(), p_disc);
  return g; end $$;

create or replace function public.equip_disc(p_disc text) returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from discs where id=p_disc and price_gems=0) and not exists(select 1 from inventory where user_id=auth.uid() and disc_id=p_disc)
    then raise exception 'not owned'; end if;
  update profiles set equipped_disc=p_disc, avatar=p_disc where id=auth.uid(); end $$;

-- ============ ROOMS: kinds, heartbeat, matchmaking ============
alter table public.rooms add column if not exists kind text not null default 'casual';
alter table public.rooms drop constraint if exists rooms_kind_check;
alter table public.rooms add constraint rooms_kind_check check (kind in ('casual','quick','arena','tournament'));
alter table public.room_players add column if not exists last_seen timestamptz not null default now();
alter table public.room_players add column if not exists disc_id text;

create or replace function public.heartbeat(p_room uuid) returns void language plpgsql security definer set search_path=public as $$
begin update room_players set last_seen=now() where room_id=p_room and user_id=auth.uid();
  update profiles set online_at=now() where id=auth.uid(); end $$;

-- remove players silent > 45s from waiting rooms; drop empty rooms
create or replace function public._sweep_rooms() returns void language plpgsql security definer set search_path=public as $$
declare r record; nh uuid; begin
  delete from room_players rp using rooms ro where ro.id=rp.room_id and ro.status='waiting' and rp.last_seen < now() - interval '45 seconds';
  delete from rooms ro where not exists(select 1 from room_players p where p.room_id=ro.id);
  for r in select ro.id from rooms ro where not exists(select 1 from room_players p where p.room_id=ro.id and p.user_id=ro.host) loop
    select user_id into nh from room_players where room_id=r.id order by (role='player') desc, joined_at limit 1;
    update rooms set host=nh where id=r.id;
  end loop;
end $$;

create or replace function public.quick_match(p_mode text, p_kind text default 'quick') returns public.rooms language plpgsql security definer set search_path=public as $$
declare rid uuid; r rooms; my int; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_kind not in ('quick','arena') then raise exception 'bad kind'; end if;
  perform _sweep_rooms();
  select case when p_kind='arena' then arena_points else rating end into my from profiles where id=auth.uid();
  select ro.id into rid from rooms ro
  where ro.mode=p_mode and ro.kind=p_kind and ro.status='waiting' and not ro.is_private
    and (select count(*) from room_players p where p.room_id=ro.id and p.role='player') < room_size(ro.mode)*2
    and not exists(select 1 from room_players p where p.room_id=ro.id and p.user_id=auth.uid())
  order by abs(coalesce((select avg(case when p_kind='arena' then pr.arena_points else pr.rating end) from room_players p join profiles pr on pr.id=p.user_id where p.room_id=ro.id and p.role='player'),my) - my),
           (select count(*) from room_players p where p.room_id=ro.id and p.role='player') desc, ro.created_at
  limit 1 for update skip locked;
  if rid is null then
    r := create_room(p_mode, case when p_kind='arena' then 'آرنا '||p_mode else 'مسابقه سریع '||p_mode end, false, true, true, null);
    update rooms set kind=p_kind where id=r.id returning * into r;
  else
    r := join_room(null, rid, false);
  end if;
  update room_players set ready=true where room_id=r.id and user_id=auth.uid();
  return r; end $$;

-- the server tells clients when a quick/arena room is full and everyone ready (host client auto-starts)
drop view if exists public.room_list;
create view public.room_list with (security_invoker=on) as
select r.id, r.code, r.name, r.mode, r.kind, r.status, r.is_private, r.ranked, r.voice, r.settings, r.created_at, r.host,
  h.username as host_name, h.avatar as host_avatar, h.avatar_url as host_avatar_url, h.level as host_level, h.league as host_league,
  (select count(*) from public.room_players p where p.room_id=r.id and p.role='player')::int as players,
  (select count(*) from public.room_players p where p.room_id=r.id and p.role='spectator')::int as spectators,
  public.room_size(r.mode)*2 as capacity
from public.rooms r join public.profiles h on h.id=r.host
where not r.is_private and r.updated_at > now() - interval '2 hours';
grant select on public.room_list to authenticated;

-- ============ DAILY CHALLENGES ============
create table if not exists public.challenge_defs (
  id text primary key, title_fa text not null, kind text not null, target int not null,
  reward_gems int not null check (reward_gems between 0 and 5), reward_xp int not null default 50
);
create table if not exists public.user_challenges (
  user_id uuid references public.profiles(id) on delete cascade, day date not null, def_id text references public.challenge_defs(id),
  progress int not null default 0, claimed boolean not null default false,
  primary key (user_id, day, def_id)
);
alter table public.challenge_defs enable row level security;
alter table public.user_challenges enable row level security;
create policy "read" on public.challenge_defs for select using (true);
create policy "read own" on public.user_challenges for select to authenticated using (user_id=auth.uid());
revoke insert, update, delete on public.challenge_defs, public.user_challenges from authenticated, anon;

insert into public.challenge_defs values
 ('win1','یک بازی آنلاین ببر','win_online',1,2,60),
 ('win3','سه بازی آنلاین ببر','win_online',3,4,150),
 ('play3','سه بازی آنلاین انجام بده','play_online',3,2,80),
 ('goals5','پنج گل در بازی‌های آنلاین بزن','goals',5,3,100),
 ('goals10','ده گل بزن','goals',10,5,180),
 ('team2v2','یک بازی ۲ به ۲ انجام بده','play_2v2',1,2,70),
 ('team3v3','یک بازی ۳ به ۳ انجام بده','play_3v3',1,2,70),
 ('arena1','یک بازی آرنا ببر','win_arena',1,3,120),
 ('clean1','یک بازی بدون گل خورده ببر','clean_sheet',1,4,140),
 ('bot3','سه بار ربات را شکست بده','win_bot',3,1,60),
 ('chat','در لابی پیام بفرست و بازی کن','play_online',1,1,30),
 ('tour1','یک مسابقه‌ی تورنمنت انجام بده','play_tournament',1,3,120),
 ('streak3','سه برد پشت سر هم بگیر','streak',3,5,200)
on conflict (id) do nothing;

create or replace function public.get_daily_challenges() returns setof public.user_challenges language plpgsql security definer set search_path=public as $$
declare d date := (now() at time zone 'Asia/Tehran')::date; begin
  if not exists(select 1 from user_challenges where user_id=auth.uid() and day=d) then
    insert into user_challenges(user_id,day,def_id)
    select auth.uid(), d, id from challenge_defs order by md5(id || d::text || auth.uid()::text) limit 4;
  end if;
  return query select * from user_challenges where user_id=auth.uid() and day=d order by def_id; end $$;

create or replace function public._progress(uid uuid, p_kind text, amt int) returns void language plpgsql security definer set search_path=public as $$
declare d date := (now() at time zone 'Asia/Tehran')::date; begin
  if amt <= 0 then return; end if;
  update user_challenges uc set progress = case when p_kind='streak' then greatest(progress, amt) else least(progress + amt, cd.target) end
  from challenge_defs cd where uc.def_id=cd.id and uc.user_id=uid and uc.day=d and cd.kind=p_kind and not uc.claimed;
  update user_challenges uc set progress = least(progress, cd.target) from challenge_defs cd where uc.def_id=cd.id and uc.user_id=uid and uc.day=d;
end $$;

create or replace function public.claim_challenge(p_def text) returns jsonb language plpgsql security definer set search_path=public as $$
declare d date := (now() at time zone 'Asia/Tehran')::date; uc user_challenges; cd challenge_defs; begin
  select * into uc from user_challenges where user_id=auth.uid() and day=d and def_id=p_def for update;
  select * into cd from challenge_defs where id=p_def;
  if uc.user_id is null then raise exception 'challenge not found'; end if;
  if uc.claimed then raise exception 'already claimed'; end if;
  if uc.progress < cd.target then raise exception 'not completed'; end if;
  update user_challenges set claimed=true where user_id=auth.uid() and day=d and def_id=p_def;
  update profiles set gems=gems+cd.reward_gems where id=auth.uid();
  perform _grant(auth.uid(), cd.reward_xp, 0, 0, 2, 0, 'challenge', null);
  return jsonb_build_object('gems',cd.reward_gems,'xp',cd.reward_xp); end $$;

-- offline bot wins count for the bot challenge only (no gems/xp directly; rate-limited)
create or replace function public.report_offline(p_won boolean) returns void language plpgsql security definer set search_path=public as $$
begin
  if p_won and (select count(*) from xp_events where user_id=auth.uid() and reason='offline' and created_at > now()-interval '2 minutes') = 0 then
    insert into xp_events(user_id,amount,reason) values (auth.uid(),10,'offline');
    update profiles set xp=xp+10, level=level_for_xp(xp+10) where id=auth.uid();
    perform _progress(auth.uid(),'win_bot',1);
  end if; end $$;

-- ============ RESULTS v2 (streaks, arena, challenges) ============
create or replace function public.report_match(p_match uuid, p_score_a int, p_score_b int, p_duration int default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare m matches; r rooms; w smallint; u uuid; ra int; rb int; ex numeric; k int := 32; d int; res int; my int; opp int; begin
  select * into m from matches where id=p_match for update;
  if m.id is null or m.status<>'live' then raise exception 'match not live'; end if;
  select * into r from rooms where id=m.room_id;
  if r.host<>auth.uid() then raise exception 'host only'; end if;
  if p_score_a<0 or p_score_b<0 or p_score_a>30 or p_score_b>30 then raise exception 'bad score'; end if;
  w := case when p_score_a>p_score_b then 0 when p_score_b>p_score_a then 1 else -1 end;
  select avg(rating)::int into ra from profiles where id = any(m.team_a);
  select avg(rating)::int into rb from profiles where id = any(m.team_b);
  ex := 1/(1+power(10,(rb-ra)/400.0));
  d := round(k*((case w when 0 then 1 when 1 then 0 else 0.5 end) - ex));
  update matches set score_a=p_score_a, score_b=p_score_b, winner=w, status='done', ended_at=now(),
    duration_s=coalesce(p_duration, extract(epoch from now()-started_at)::int) where id=p_match;
  for u, res, my, opp in
    select x, case w when 0 then 1 when 1 then -1 else 0 end, p_score_a, p_score_b from unnest(m.team_a) x
    union all select x, case w when 1 then 1 when 0 then -1 else 0 end, p_score_b, p_score_a from unnest(m.team_b) x
  loop
    perform _grant(u, 40 + res*30 + 10 + my*5, 50 + (res=1)::int*100,
      case when m.ranked then (case when u = any(m.team_a) then d else -d end) else 0 end, res, my, 'match', p_match);
    update profiles set win_streak = case when res=1 then win_streak+1 else 0 end,
      best_streak = greatest(best_streak, case when res=1 then win_streak+1 else 0 end),
      arena_points = case when r.kind='arena' then greatest(0, arena_points + case res when 1 then 30 + least(win_streak,5)*5 when 0 then 5 else -20 end) else arena_points end
    where id=u;
    perform _progress(u,'play_online',1);
    perform _progress(u,'goals',my);
    if res=1 then perform _progress(u,'win_online',1); end if;
    if res=1 and r.kind='arena' then perform _progress(u,'win_arena',1); end if;
    if res=1 and opp=0 then perform _progress(u,'clean_sheet',1); end if;
    if m.mode='2v2' then perform _progress(u,'play_2v2',1); elsif m.mode='3v3' then perform _progress(u,'play_3v3',1); end if;
    if m.tournament_match_id is not null then perform _progress(u,'play_tournament',1); end if;
    perform _progress(u,'streak',(select win_streak from profiles where id=u));
  end loop;
  if m.tournament_match_id is not null then perform _tm_result(m.tournament_match_id, p_score_a, p_score_b); end if;
  update rooms set status='waiting', current_match=null, updated_at=now() where id=m.room_id;
  update room_players set ready=(r.kind in ('quick','arena')) where room_id=m.room_id;
  return jsonb_build_object('winner',w,'rating_delta',d); end $$;

-- ============ TOURNAMENTS v2: sizes up to 64, gem prizes (<=30) ============
alter table public.tournaments add column if not exists prize_gems int not null default 20;
alter table public.tournaments drop constraint if exists tournaments_prize_gems_check;
alter table public.tournaments add constraint tournaments_prize_gems_check check (prize_gems between 0 and 30);
alter table public.tournaments alter column prize_coins set default 0;
update public.tournaments set prize_coins=0;
alter table public.tournaments add column if not exists club_id uuid;

drop function if exists public.create_tournament(text,text,text,int,int,int,int,timestamptz);
create or replace function public.create_tournament(p_name text, p_format text, p_mode text default '1v1', p_max int default 16,
  p_rounds int default null, p_prize_gems int default 20, p_starts timestamptz default null, p_min_level int default 1)
returns public.tournaments language plpgsql security definer set search_path=public as $$
declare t tournaments; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_max not in (4,8,16,32,64) then raise exception 'bad size'; end if;
  insert into tournaments(name,format,mode,max_entries,rounds,created_by,prize_xp,prize_coins,prize_gems,starts_at,min_level)
  values (p_name,p_format,p_mode,p_max,p_rounds,auth.uid(),300,0,least(greatest(coalesce(p_prize_gems,20),0),30),p_starts,greatest(p_min_level,1)) returning * into t;
  return t; end $$;

create or replace function public.join_tournament(p_tid uuid, p_team_name text default null, p_members uuid[] default null)
returns public.tournament_entries language plpgsql security definer set search_path=public as $$
declare t tournaments; e tournament_entries; nm text; lvl int; begin
  select * into t from tournaments where id=p_tid;
  if t.status<>'registration' then raise exception 'registration closed'; end if;
  if (select count(*) from tournament_entries where tournament_id=p_tid) >= t.max_entries then raise exception 'full'; end if;
  select username, level into nm, lvl from profiles where id=auth.uid();
  if lvl < t.min_level then raise exception 'level too low'; end if;
  if exists(select 1 from tournament_entries where tournament_id=p_tid and auth.uid() = any(members)) then raise exception 'already joined'; end if;
  insert into tournament_entries(tournament_id,captain,team_name,members)
  values (p_tid, auth.uid(), coalesce(nullif(trim(p_team_name),''), nm),
          case when p_members is null then array[auth.uid()] else array(select distinct x from unnest(array[auth.uid()] || p_members) x) end) returning * into e;
  return e; end $$;

create or replace function public._finish_tournament(p_tid uuid, p_winner uuid) returns void language plpgsql security definer set search_path=public as $$
declare t tournaments; e record; rk int := 0; u uuid; runner uuid; begin
  select * into t from tournaments where id=p_tid;
  if t.status='finished' then return; end if;
  if p_winner is null then
    select id into p_winner from tournament_entries where tournament_id=p_tid order by points desc, (gf-ga) desc, gf desc limit 1;
    for e in select id from tournament_entries where tournament_id=p_tid order by points desc,(gf-ga) desc, gf desc loop
      rk := rk+1; update tournament_entries set final_rank=rk where id=e.id; end loop;
  else update tournament_entries set final_rank=1 where id=p_winner; end if;
  update tournaments set status='finished', winner_entry=p_winner where id=p_tid;
  foreach u in array (select members from tournament_entries where id=p_winner) loop
    perform _grant(u, t.prize_xp, 0, 25, 2, 0, 'tournament', p_tid);
    update profiles set trophies=trophies+1, gems=gems+least(t.prize_gems,30) where id=u;
  end loop;
  -- runner-up gets a third of the gems
  select id into runner from tournament_entries where tournament_id=p_tid and id<>p_winner order by coalesce(final_rank,99), points desc, (gf-ga) desc limit 1;
  if runner is not null then
    update profiles set gems=gems+(least(t.prize_gems,30)/3) where id in (select unnest(members) from tournament_entries where id=runner);
  end if;
end $$;

-- ============ SEASONS (league ladder) ============
create table if not exists public.seasons (
  id serial primary key, name text not null, starts_at timestamptz not null, ends_at timestamptz not null, active boolean not null default true
);
create table if not exists public.season_rewards (league text primary key references public.leagues(id), gems int not null check (gems between 0 and 30));
create table if not exists public.season_claims (
  season_id int references public.seasons(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade,
  league text, gems int, claimed_at timestamptz not null default now(), primary key (season_id,user_id)
);
alter table public.seasons enable row level security; alter table public.season_rewards enable row level security; alter table public.season_claims enable row level security;
create policy "read" on public.seasons for select using (true);
create policy "read" on public.season_rewards for select using (true);
create policy "read own" on public.season_claims for select to authenticated using (user_id=auth.uid());
revoke insert, update, delete on public.seasons, public.season_rewards, public.season_claims from authenticated, anon;
insert into public.season_rewards values ('bronze',3),('silver',6),('gold',10),('platinum',14),('diamond',18),('master',24),('legend',30) on conflict do nothing;
insert into public.seasons(name,starts_at,ends_at) select 'فصل ۱', now(), now() + interval '28 days' where not exists(select 1 from public.seasons);

-- claim reward for the most recent ended season (based on current league), then roll a new season if needed
create or replace function public.claim_season_reward() returns jsonb language plpgsql security definer set search_path=public as $$
declare s seasons; lg text; g int; begin
  select * into s from seasons where ends_at < now() order by ends_at desc limit 1;
  if s.id is null then raise exception 'season running'; end if;
  if exists(select 1 from season_claims where season_id=s.id and user_id=auth.uid()) then raise exception 'already claimed'; end if;
  select league into lg from profiles where id=auth.uid();
  select gems into g from season_rewards where league=lg;
  insert into season_claims values (s.id, auth.uid(), lg, g);
  update profiles set gems=gems+g where id=auth.uid();
  return jsonb_build_object('league',lg,'gems',g); end $$;

create or replace function public.current_season() returns public.seasons language plpgsql security definer set search_path=public as $$
declare s seasons; n int; begin
  select * into s from seasons where active order by id desc limit 1;
  if s.ends_at < now() then
    update seasons set active=false where id=s.id;
    select count(*)+1 into n from seasons;
    insert into seasons(name,starts_at,ends_at) values ('فصل '||n, now(), now()+interval '28 days') returning * into s;
  end if;
  return s; end $$;

-- ============ SOCIAL: follows ============
create table if not exists public.follows (
  follower uuid references public.profiles(id) on delete cascade, followee uuid references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (follower, followee), check (follower<>followee)
);
alter table public.follows enable row level security;
create policy "read" on public.follows for select to authenticated using (true);
create policy "follow" on public.follows for insert to authenticated with check (follower=auth.uid());
create policy "unfollow" on public.follows for delete to authenticated using (follower=auth.uid());
grant insert, delete on public.follows to authenticated;

create or replace view public.profile_stats with (security_invoker=on) as
select p.id, (select count(*) from public.follows f where f.followee=p.id)::int as followers,
  (select count(*) from public.follows f where f.follower=p.id)::int as following from public.profiles p;
grant select on public.profile_stats to authenticated;

-- ============ SOCIAL: conversations (dm / group / channel / club) ============
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('dm','group','channel','club')),
  title text, about text, avatar_url text,
  owner uuid references public.profiles(id) on delete set null,
  is_public boolean not null default false,
  dm_key text unique,
  club_id uuid,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  muted boolean not null default false,
  last_read_at timestamptz not null default now(),
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create index if not exists cm_user on public.conversation_members(user_id);
create table if not exists public.messages (
  id bigserial primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender uuid references public.profiles(id) on delete set null,
  body text check (char_length(body) <= 2000),
  image_url text,
  reply_to bigint,
  deleted boolean not null default false,
  created_at timestamptz not null default now(),
  check (body is not null or image_url is not null)
);
create index if not exists msg_conv on public.messages(conversation_id, created_at desc);

create table if not exists public.user_blocks (
  blocker uuid references public.profiles(id) on delete cascade, blocked uuid references public.profiles(id) on delete cascade,
  primary key (blocker, blocked)
);

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.user_blocks enable row level security;

create or replace function public.is_member(c uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from conversation_members where conversation_id=c and user_id=auth.uid()) $$;
create or replace function public.can_post(c uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from conversation_members m join conversations v on v.id=m.conversation_id
   where m.conversation_id=c and m.user_id=auth.uid() and (v.kind<>'channel' or m.role in ('owner','admin'))
   and not (v.kind='dm' and exists(select 1 from conversation_members o join user_blocks b on (b.blocker=o.user_id and b.blocked=auth.uid())
     where o.conversation_id=c and o.user_id<>auth.uid()))) $$;

create policy "read" on public.conversations for select to authenticated using (is_public or public.is_member(id));
create policy "read" on public.conversation_members for select to authenticated using (public.is_member(conversation_id)
  or exists(select 1 from public.conversations v where v.id=conversation_id and v.is_public));
create policy "update self" on public.conversation_members for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
grant update (muted, last_read_at) on public.conversation_members to authenticated;
create policy "read" on public.messages for select to authenticated using (public.is_member(conversation_id)
  or exists(select 1 from public.conversations v where v.id=conversation_id and v.is_public and v.kind='channel'));
create policy "send" on public.messages for insert to authenticated with check (sender=auth.uid() and public.can_post(conversation_id));
create policy "delete own" on public.messages for update to authenticated using (sender=auth.uid()) with check (sender=auth.uid());
grant insert on public.messages to authenticated; grant usage on sequence public.messages_id_seq to authenticated;
grant update (deleted, body) on public.messages to authenticated;
create policy "own" on public.user_blocks for all to authenticated using (blocker=auth.uid()) with check (blocker=auth.uid());
grant select, insert, delete on public.user_blocks to authenticated;

create or replace function public._touch_conv() returns trigger language plpgsql security definer set search_path=public as $$
begin update conversations set last_message_at=new.created_at where id=new.conversation_id; return new; end $$;
drop trigger if exists msg_touch on public.messages;
create trigger msg_touch after insert on public.messages for each row execute function public._touch_conv();

create or replace function public.open_dm(p_user uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare k text; cid uuid; begin
  if p_user = auth.uid() then raise exception 'cannot dm yourself'; end if;
  if exists(select 1 from user_blocks where blocker=p_user and blocked=auth.uid()) then raise exception 'blocked'; end if;
  k := least(auth.uid()::text, p_user::text) || ':' || greatest(auth.uid()::text, p_user::text);
  select id into cid from conversations where dm_key=k;
  if cid is null then
    insert into conversations(kind, dm_key, owner) values ('dm', k, auth.uid()) returning id into cid;
    insert into conversation_members(conversation_id,user_id,role) values (cid,auth.uid(),'member'),(cid,p_user,'member');
  end if;
  return cid; end $$;

create or replace function public.create_conversation(p_kind text, p_title text, p_about text default null, p_public boolean default true, p_members uuid[] default '{}')
returns uuid language plpgsql security definer set search_path=public as $$
declare cid uuid; u uuid; begin
  if p_kind not in ('group','channel') then raise exception 'bad kind'; end if;
  if char_length(coalesce(trim(p_title),'')) < 2 then raise exception 'title required'; end if;
  insert into conversations(kind,title,about,owner,is_public) values (p_kind,trim(p_title),p_about,auth.uid(),p_public) returning id into cid;
  insert into conversation_members(conversation_id,user_id,role) values (cid,auth.uid(),'owner');
  foreach u in array coalesce(p_members,'{}') loop
    insert into conversation_members(conversation_id,user_id) values (cid,u) on conflict do nothing; end loop;
  return cid; end $$;

create or replace function public.join_conversation(p_conv uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from conversations where id=p_conv and is_public and kind in ('group','channel')) then raise exception 'not public'; end if;
  insert into conversation_members(conversation_id,user_id) values (p_conv,auth.uid()) on conflict do nothing; end $$;

create or replace function public.leave_conversation(p_conv uuid) returns void language plpgsql security definer set search_path=public as $$
declare nxt uuid; begin
  delete from conversation_members where conversation_id=p_conv and user_id=auth.uid();
  if not exists(select 1 from conversation_members where conversation_id=p_conv) then delete from conversations where id=p_conv and kind<>'club'; return; end if;
  if not exists(select 1 from conversation_members where conversation_id=p_conv and role='owner') then
    select user_id into nxt from conversation_members where conversation_id=p_conv order by (role='admin') desc, joined_at limit 1;
    update conversation_members set role='owner' where conversation_id=p_conv and user_id=nxt;
    update conversations set owner=nxt where id=p_conv;
  end if; end $$;

create or replace function public.manage_member(p_conv uuid, p_user uuid, p_action text) returns void language plpgsql security definer set search_path=public as $$
declare myrole text; begin
  select role into myrole from conversation_members where conversation_id=p_conv and user_id=auth.uid();
  if myrole not in ('owner','admin') then raise exception 'admin only'; end if;
  if p_action='add' then insert into conversation_members(conversation_id,user_id) values (p_conv,p_user) on conflict do nothing;
  elsif p_action='remove' then delete from conversation_members where conversation_id=p_conv and user_id=p_user and role<>'owner';
  elsif p_action='promote' and myrole='owner' then update conversation_members set role='admin' where conversation_id=p_conv and user_id=p_user;
  elsif p_action='demote' and myrole='owner' then update conversation_members set role='member' where conversation_id=p_conv and user_id=p_user and role='admin';
  else raise exception 'bad action'; end if; end $$;

create or replace function public.update_conversation(p_conv uuid, p_title text, p_about text, p_avatar_url text) returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from conversation_members where conversation_id=p_conv and user_id=auth.uid() and role in ('owner','admin')) then raise exception 'admin only'; end if;
  update conversations set title=coalesce(nullif(trim(p_title),''),title), about=coalesce(p_about,about), avatar_url=coalesce(p_avatar_url,avatar_url) where id=p_conv; end $$;

-- inbox: my conversations with last message + unread count + the other user for DMs
create or replace view public.inbox with (security_invoker=on) as
select c.id, c.kind, c.title, c.avatar_url, c.club_id, c.last_message_at, m.role, m.muted,
  (select row_to_json(x) from (select ms.body, ms.image_url, ms.sender, ms.created_at from public.messages ms where ms.conversation_id=c.id and not ms.deleted order by ms.created_at desc limit 1) x) as last_message,
  (select count(*) from public.messages ms where ms.conversation_id=c.id and ms.created_at > m.last_read_at and ms.sender<>auth.uid())::int as unread,
  (select row_to_json(o) from (select p.id, p.username, p.avatar, p.avatar_url, p.online_at from public.conversation_members om join public.profiles p on p.id=om.user_id
      where om.conversation_id=c.id and om.user_id<>auth.uid() limit 1) o) as peer,
  (select count(*) from public.conversation_members cm where cm.conversation_id=c.id)::int as members
from public.conversations c join public.conversation_members m on m.conversation_id=c.id and m.user_id=auth.uid();
grant select on public.inbox to authenticated;

create or replace view public.public_conversations with (security_invoker=on) as
select c.id, c.kind, c.title, c.about, c.avatar_url, c.last_message_at,
  (select count(*) from public.conversation_members cm where cm.conversation_id=c.id)::int as members
from public.conversations c where c.is_public and c.kind in ('group','channel');
grant select on public.public_conversations to authenticated;

-- ============ CLUBS ============
create table if not exists public.clubs (
  id uuid primary key default gen_random_uuid(),
  name text unique not null check (char_length(name) between 3 and 24),
  tag text unique not null check (tag ~ '^[A-Z0-9]{2,5}$'),
  emblem text not null default 'emb0',
  description text check (char_length(description) <= 300),
  owner uuid references public.profiles(id) on delete set null,
  join_policy text not null default 'open' check (join_policy in ('open','request','invite')),
  min_level int not null default 1,
  max_members int not null default 30 check (max_members between 5 and 50),
  conversation_id uuid references public.conversations(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.club_members (
  club_id uuid references public.clubs(id) on delete cascade,
  user_id uuid unique references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('leader','officer','member')),
  joined_at timestamptz not null default now(),
  primary key (club_id, user_id)
);
create table if not exists public.club_requests (
  club_id uuid references public.clubs(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade,
  kind text not null default 'request' check (kind in ('request','invite')), message text,
  created_at timestamptz not null default now(), primary key (club_id, user_id)
);
alter table public.clubs enable row level security; alter table public.club_members enable row level security; alter table public.club_requests enable row level security;
create policy "read" on public.clubs for select to authenticated using (true);
create policy "read" on public.club_members for select to authenticated using (true);
create policy "read" on public.club_requests for select to authenticated using (user_id=auth.uid()
  or exists(select 1 from public.club_members cm where cm.club_id=club_requests.club_id and cm.user_id=auth.uid() and cm.role in ('leader','officer')));
revoke insert, update, delete on public.clubs, public.club_members, public.club_requests from authenticated, anon;

create or replace view public.club_list with (security_invoker=on) as
select c.*, (select count(*) from public.club_members m where m.club_id=c.id)::int as members,
  coalesce((select sum(p.trophies*100 + p.rating) from public.club_members m join public.profiles p on p.id=m.user_id where m.club_id=c.id),0)::int as power
from public.clubs c;
grant select on public.club_list to authenticated;

create or replace function public._club_add(p_club uuid, p_user uuid, p_role text) returns void language plpgsql security definer set search_path=public as $$
declare cv uuid; begin
  if (select count(*) from club_members where club_id=p_club) >= (select max_members from clubs where id=p_club) then raise exception 'club full'; end if;
  insert into club_members(club_id,user_id,role) values (p_club,p_user,p_role);
  update profiles set club_id=p_club where id=p_user;
  delete from club_requests where user_id=p_user;
  select conversation_id into cv from clubs where id=p_club;
  if cv is not null then insert into conversation_members(conversation_id,user_id,role) values (cv,p_user,case when p_role='leader' then 'owner' else 'member' end) on conflict do nothing; end if;
end $$;

create or replace function public.create_club(p_name text, p_tag text, p_emblem text default 'emb0', p_desc text default null, p_policy text default 'open', p_min_level int default 1)
returns uuid language plpgsql security definer set search_path=public as $$
declare cid uuid; cv uuid; begin
  if exists(select 1 from club_members where user_id=auth.uid()) then raise exception 'already in club'; end if;
  update profiles set gems=gems-50 where id=auth.uid() and gems>=50;
  if not found then raise exception 'not enough gems'; end if;
  insert into clubs(name,tag,emblem,description,owner,join_policy,min_level) values (trim(p_name), upper(trim(p_tag)), p_emblem, p_desc, auth.uid(), p_policy, greatest(p_min_level,1)) returning id into cid;
  insert into conversations(kind,title,owner,club_id) values ('club', trim(p_name), auth.uid(), cid) returning id into cv;
  update clubs set conversation_id=cv where id=cid;
  perform _club_add(cid, auth.uid(), 'leader');
  return cid; end $$;

create or replace function public.join_club(p_club uuid, p_message text default null) returns text language plpgsql security definer set search_path=public as $$
declare c clubs; lvl int; begin
  select * into c from clubs where id=p_club; if c.id is null then raise exception 'club not found'; end if;
  if exists(select 1 from club_members where user_id=auth.uid()) then raise exception 'already in club'; end if;
  select level into lvl from profiles where id=auth.uid(); if lvl < c.min_level then raise exception 'level too low'; end if;
  if exists(select 1 from club_requests where club_id=p_club and user_id=auth.uid() and kind='invite') or c.join_policy='open' then
    perform _club_add(p_club, auth.uid(), 'member'); return 'joined'; end if;
  if c.join_policy='invite' then raise exception 'invite only'; end if;
  insert into club_requests(club_id,user_id,kind,message) values (p_club,auth.uid(),'request',p_message) on conflict (club_id,user_id) do update set message=excluded.message, created_at=now();
  return 'requested'; end $$;

create or replace function public._club_role(p_club uuid) returns text language sql stable security definer set search_path=public as
$$ select role from club_members where club_id=p_club and user_id=auth.uid() $$;

create or replace function public.club_decide(p_club uuid, p_user uuid, p_accept boolean) returns void language plpgsql security definer set search_path=public as $$
begin
  if coalesce(_club_role(p_club),'member') not in ('leader','officer') then raise exception 'officer only'; end if;
  if not exists(select 1 from club_requests where club_id=p_club and user_id=p_user and kind='request') then raise exception 'request not found'; end if;
  if p_accept then perform _club_add(p_club,p_user,'member'); else delete from club_requests where club_id=p_club and user_id=p_user; end if; end $$;

create or replace function public.club_invite(p_club uuid, p_user uuid) returns void language plpgsql security definer set search_path=public as $$
begin
  if coalesce(_club_role(p_club),'member') not in ('leader','officer') then raise exception 'officer only'; end if;
  insert into club_requests(club_id,user_id,kind) values (p_club,p_user,'invite') on conflict (club_id,user_id) do update set kind='invite'; end $$;

create or replace function public.club_member_action(p_club uuid, p_user uuid, p_action text) returns void language plpgsql security definer set search_path=public as $$
declare me text := _club_role(p_club); them text; cv uuid; begin
  select role into them from club_members where club_id=p_club and user_id=p_user;
  select conversation_id into cv from clubs where id=p_club;
  if p_action='kick' and me in ('leader','officer') and them='member' or (p_action='kick' and me='leader' and them='officer') then
    delete from club_members where club_id=p_club and user_id=p_user; update profiles set club_id=null where id=p_user;
    delete from conversation_members where conversation_id=cv and user_id=p_user;
  elsif p_action='promote' and me='leader' then update club_members set role='officer' where club_id=p_club and user_id=p_user;
    update conversation_members set role='admin' where conversation_id=cv and user_id=p_user;
  elsif p_action='demote' and me='leader' then update club_members set role='member' where club_id=p_club and user_id=p_user;
    update conversation_members set role='member' where conversation_id=cv and user_id=p_user;
  elsif p_action='transfer' and me='leader' and them is not null then
    update club_members set role='officer' where club_id=p_club and user_id=auth.uid();
    update club_members set role='leader' where club_id=p_club and user_id=p_user; update clubs set owner=p_user where id=p_club;
  else raise exception 'not allowed'; end if; end $$;

create or replace function public.update_club(p_club uuid, p_desc text, p_policy text, p_emblem text, p_min_level int) returns void language plpgsql security definer set search_path=public as $$
begin if _club_role(p_club) <> 'leader' then raise exception 'leader only'; end if;
  update clubs set description=coalesce(p_desc,description), join_policy=coalesce(p_policy,join_policy), emblem=coalesce(p_emblem,emblem),
    min_level=coalesce(p_min_level,min_level) where id=p_club; end $$;

create or replace function public.leave_club() returns void language plpgsql security definer set search_path=public as $$
declare cm club_members; nxt uuid; cv uuid; begin
  select * into cm from club_members where user_id=auth.uid(); if cm.club_id is null then return; end if;
  select conversation_id into cv from clubs where id=cm.club_id;
  delete from club_members where user_id=auth.uid(); update profiles set club_id=null where id=auth.uid();
  delete from conversation_members where conversation_id=cv and user_id=auth.uid();
  if not exists(select 1 from club_members where club_id=cm.club_id) then delete from conversations where id=cv; delete from clubs where id=cm.club_id; return; end if;
  if cm.role='leader' then
    select user_id into nxt from club_members where club_id=cm.club_id order by (role='officer') desc, joined_at limit 1;
    update club_members set role='leader' where club_id=cm.club_id and user_id=nxt; update clubs set owner=nxt where id=cm.club_id;
  end if; end $$;

-- ============ STORAGE: avatars & chat images ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars','avatars',true, 2097152, array['image/jpeg','image/png','image/webp']),
       ('chat','chat',true, 5242880, array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do nothing;
drop policy if exists "avatars read" on storage.objects;
drop policy if exists "avatars write own" on storage.objects;
drop policy if exists "avatars update own" on storage.objects;
drop policy if exists "avatars delete own" on storage.objects;
drop policy if exists "chat read" on storage.objects;
drop policy if exists "chat write own" on storage.objects;
create policy "avatars read" on storage.objects for select using (bucket_id='avatars');
create policy "avatars write own" on storage.objects for insert to authenticated with check (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars update own" on storage.objects for update to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars delete own" on storage.objects for delete to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "chat read" on storage.objects for select using (bucket_id='chat');
create policy "chat write own" on storage.objects for insert to authenticated with check (bucket_id='chat' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ GRANTS / REALTIME ============
grant execute on all functions in schema public to authenticated;
revoke execute on function public._grant, public._tm_result, public._tm_place, public._finish_tournament, public._rr_schedule,
  public._swiss_round, public._autoseat, public._gen_code, public._resolve_byes, public._progress, public._sweep_rooms,
  public._club_add from authenticated, anon, public;
grant select on public.leaderboard, public.standings to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
  begin alter publication supabase_realtime add table public.conversation_members; exception when others then null; end;
  begin alter publication supabase_realtime add table public.follows; exception when others then null; end;
  begin alter publication supabase_realtime add table public.club_members; exception when others then null; end;
  begin alter publication supabase_realtime add table public.club_requests; exception when others then null; end;
  begin alter publication supabase_realtime add table public.user_challenges; exception when others then null; end;
  begin alter publication supabase_realtime add table public.inventory; exception when others then null; end;
end $$;
