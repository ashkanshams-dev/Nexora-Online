-- NEXORA social: tap-a-player profile, follow, direct messages, block, moderation.
-- Builds on the existing tables (profiles, follows, user_blocks, conversations, conversation_members, messages),
-- all of which already have RLS enabled. Idempotent: safe to run more than once.

-- ---------------------------------------------------------------- moderation constants
create or replace function public.nx_dm_max_len() returns int language sql immutable as $$ select 500 $$;

-- ---------------------------------------------------------------- blocks
-- Blocking removes follows in both directions (also when user_blocks is written directly under its RLS policy).
create or replace function public._blk_cleanup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from follows where (follower = new.blocker and followee = new.blocked) or (follower = new.blocked and followee = new.blocker);
  return new;
end $$;
drop trigger if exists blk_cleanup on public.user_blocks;
create trigger blk_cleanup after insert on public.user_blocks for each row execute function public._blk_cleanup();

-- No follow across a block, whichever way it was set and however the row is written.
create or replace function public._follow_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists(select 1 from user_blocks where (blocker = new.followee and blocked = new.follower) or (blocker = new.follower and blocked = new.followee)) then
    raise exception 'blocked';
  end if;
  return new;
end $$;
drop trigger if exists follow_guard on public.follows;
create trigger follow_guard before insert on public.follows for each row execute function public._follow_guard();

-- ---------------------------------------------------------------- DM moderation (applies to RPC and direct inserts)
create or replace function public._dm_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; n int;
begin
  select kind into k from conversations where id = new.conversation_id;
  if k is distinct from 'dm' or new.sender is null then return new; end if;
  new.body := nullif(btrim(new.body), '');
  if new.body is null and new.image_url is null then raise exception 'empty message'; end if;
  if char_length(coalesce(new.body, '')) > nx_dm_max_len() then raise exception 'message too long'; end if;
  if exists(select 1 from conversation_members o join user_blocks b
              on (b.blocker = o.user_id and b.blocked = new.sender) or (b.blocker = new.sender and b.blocked = o.user_id)
            where o.conversation_id = new.conversation_id and o.user_id <> new.sender) then
    raise exception 'blocked';
  end if;
  select count(*) into n from messages m join conversations c on c.id = m.conversation_id
   where m.sender = new.sender and c.kind = 'dm' and m.created_at > now() - interval '10 seconds';
  if n >= 6 then raise exception 'slow down'; end if;
  return new;
end $$;
drop trigger if exists dm_guard on public.messages;
create trigger dm_guard before insert on public.messages for each row execute function public._dm_guard();

-- open_dm: also refuse when *I* blocked them (they must be unblocked first)
create or replace function public.open_dm(p_user uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare k text; cid uuid; me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_user = me then raise exception 'cannot dm yourself'; end if;
  if not exists(select 1 from profiles where id = p_user) then raise exception 'player not found'; end if;
  if exists(select 1 from user_blocks where blocker = p_user and blocked = me) then raise exception 'blocked'; end if;
  if exists(select 1 from user_blocks where blocker = me and blocked = p_user) then raise exception 'unblock first'; end if;
  k := least(me::text, p_user::text) || ':' || greatest(me::text, p_user::text);
  select id into cid from conversations where dm_key = k;
  if cid is null then
    insert into conversations(kind, dm_key, owner) values ('dm', k, me) returning id into cid;
    insert into conversation_members(conversation_id, user_id, role) values (cid, me, 'member'), (cid, p_user, 'member')
      on conflict do nothing;
  end if;
  return cid;
end $$;

-- ---------------------------------------------------------------- RPCs
create or replace function public.follow_user(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_user = me then raise exception 'cannot follow yourself'; end if;
  insert into follows(follower, followee) values (me, p_user) on conflict do nothing;
  return jsonb_build_object('following', true,
    'followers', (select count(*) from follows where followee = p_user),
    'following_n', (select count(*) from follows where follower = p_user));
end $$;

create or replace function public.unfollow_user(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  delete from follows where follower = me and followee = p_user;
  return jsonb_build_object('following', false,
    'followers', (select count(*) from follows where followee = p_user),
    'following_n', (select count(*) from follows where follower = p_user));
end $$;

create or replace function public.block_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if p_user = me then raise exception 'not allowed'; end if;
  insert into user_blocks(blocker, blocked) values (me, p_user) on conflict do nothing;
end $$;

create or replace function public.unblock_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  delete from user_blocks where blocker = auth.uid() and blocked = p_user;
end $$;

-- Send a direct message to a player (opens the conversation if needed). Moderation runs in _dm_guard.
create or replace function public.send_dm(p_user uuid, p_body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare cid uuid; mid bigint; me uuid := auth.uid();
begin
  cid := open_dm(p_user);
  insert into messages(conversation_id, sender, body) values (cid, me, p_body) returning id into mid;
  update conversation_members set last_read_at = now() where conversation_id = cid and user_id = me;
  return jsonb_build_object('conversation', cid, 'id', mid);
end $$;

-- Unread direct messages for the badge (ignores muted chats and people I blocked).
create or replace function public.dm_unread_total() returns int
language sql stable security definer set search_path = public as $$
  select coalesce(count(*), 0)::int
  from conversation_members me
  join conversations c on c.id = me.conversation_id and c.kind = 'dm'
  join messages m on m.conversation_id = c.id
  where me.user_id = auth.uid() and not coalesce(me.muted, false)
    and m.sender is not null and m.sender <> auth.uid() and not m.deleted
    and m.created_at > coalesce(me.last_read_at, 'epoch'::timestamptz)
    and not exists(select 1 from user_blocks b where b.blocker = auth.uid() and b.blocked = m.sender)
$$;

create or replace function public.mark_conversation_read(p_conv uuid) returns void
language sql security definer set search_path = public as $$
  update conversation_members set last_read_at = now() where conversation_id = p_conv and user_id = auth.uid()
$$;

-- Achievements, derived on the server from the player's real stats (nothing client-written).
create or replace function public.player_achievements(p_user uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with p as (
    select coalesce(wins,0) w, coalesce(losses,0) l, coalesce(draws,0) d, coalesce(goals,0) g, coalesce(level,1) lv,
           coalesce(best_streak,0) bs, coalesce(arena_points,0) ap, coalesce(trophies,0) tr
    from profiles where id = p_user),
  x as (select (select count(*) from follows where followee = p_user)::int fl,
               (select count(*) from tournament_prizes where user_id = p_user and place = 1)::int champ),
  a(sort, id, title, descr, v, target) as (
    select 1, 'first_win', 'اولین برد', 'اولین بازی آنلاین را ببر', w, 1 from p union all
    select 2, 'wins_10', 'ده برد', '۱۰ بازی ببر', w, 10 from p union all
    select 3, 'wins_50', 'کهنه‌کار', '۵۰ بازی ببر', w, 50 from p union all
    select 4, 'played_100', 'صدتایی', '۱۰۰ بازی انجام بده', w + l + d, 100 from p union all
    select 5, 'goals_50', 'گلزن', '۵۰ گل بزن', g, 50 from p union all
    select 6, 'goals_200', 'آقای گل', '۲۰۰ گل بزن', g, 200 from p union all
    select 7, 'streak_5', 'برد پیاپی', '۵ برد پشت سر هم', bs, 5 from p union all
    select 8, 'level_10', 'سطح ۱۰', 'به سطح ۱۰ برس', lv, 10 from p union all
    select 9, 'level_25', 'سطح ۲۵', 'به سطح ۲۵ برس', lv, 25 from p union all
    select 10, 'arena_100', 'گلادیاتور', '۱۰۰ امتیاز آرنا', ap, 100 from p union all
    select 11, 'champion', 'قهرمان', 'قهرمان یک تورنمنت شو', greatest(tr, (select champ from x)), 1 from p union all
    select 12, 'followers_10', 'محبوب', '۱۰ دنبال‌کننده', (select fl from x), 10 from p)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'desc', descr,
           'progress', least(v, target), 'target', target, 'done', v >= target) order by sort), '[]'::jsonb)
  from a
$$;

-- Everything the profile sheet needs in one call.
create or replace function public.player_card(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); r jsonb;
begin
  select jsonb_build_object(
    'id', p.id, 'username', p.username, 'avatar', p.avatar, 'avatar_url', p.avatar_url, 'equipped_disc', p.equipped_disc,
    'bio', p.bio, 'level', p.level, 'xp', p.xp, 'rating', p.rating, 'league', p.league, 'wins', p.wins, 'losses', p.losses,
    'draws', p.draws, 'goals', p.goals, 'trophies', p.trophies, 'arena_points', p.arena_points, 'best_streak', p.best_streak,
    'online_at', p.online_at, 'is_guest', p.is_guest, 'club_id', p.club_id,
    'followers', (select count(*) from follows where followee = p.id),
    'following_n', (select count(*) from follows where follower = p.id),
    'is_following', me is not null and exists(select 1 from follows where follower = me and followee = p.id),
    'follows_me', me is not null and exists(select 1 from follows where follower = p.id and followee = me),
    'blocked_by_me', me is not null and exists(select 1 from user_blocks where blocker = me and blocked = p.id),
    'blocked_me', me is not null and exists(select 1 from user_blocks where blocker = p.id and blocked = me),
    'achievements', player_achievements(p.id))
  into r from profiles p where p.id = p_user;
  if r is null then raise exception 'player not found'; end if;
  return r;
end $$;

revoke all on function public.follow_user(uuid), public.unfollow_user(uuid), public.block_user(uuid), public.unblock_user(uuid),
  public.send_dm(uuid, text), public.dm_unread_total(), public.mark_conversation_read(uuid), public.player_card(uuid),
  public.player_achievements(uuid), public.open_dm(uuid) from public, anon;
grant execute on function public.follow_user(uuid), public.unfollow_user(uuid), public.block_user(uuid), public.unblock_user(uuid),
  public.send_dm(uuid, text), public.dm_unread_total(), public.mark_conversation_read(uuid), public.player_card(uuid),
  public.player_achievements(uuid), public.open_dm(uuid) to authenticated;
revoke all on function public._dm_guard(), public._follow_guard(), public._blk_cleanup() from public, anon, authenticated;

-- realtime for messages is already in the supabase_realtime publication (used by the app's inbox / chat).
