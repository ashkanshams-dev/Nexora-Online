-- NEXORA · social v2 + notifications + push + client error log (purely additive, idempotent)
--  * friend requests (friends = mutual follows, so every existing follow keeps working)
--  * notification triggers: new follower, friend request / accept, DM, club invite / join request, room (match) invite
--  * presence ping (profiles.online_at) and room invites
--  * device_tokens (FCM) + AFTER INSERT trigger on notifications → pg_net → edge function push-send
--    (the function skips silently while FCM_SERVICE_ACCOUNT is not set)
--  * client_errors: crash / error reports from the app (insert-only for clients)
-- Nothing existing is dropped or rewritten; only new tables, functions, triggers and policies.

create extension if not exists pg_net;

-- ============ friend requests ============
create table if not exists public.friend_requests (
  from_user  uuid not null references public.profiles(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  status     text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);
create index if not exists friend_requests_to_idx on public.friend_requests (to_user, status);
alter table public.friend_requests enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='friend_requests' and policyname='fr read own') then
    create policy "fr read own" on public.friend_requests for select to authenticated using (from_user = auth.uid() or to_user = auth.uid());
  end if;
end $$;
revoke insert, update, delete on public.friend_requests from authenticated, anon;
grant select on public.friend_requests to authenticated;

-- friends = mutual follows
create or replace view public.friends with (security_invoker=on) as
select a.follower as user_id, a.followee as friend_id, greatest(a.created_at, b.created_at) as since
from public.follows a join public.follows b on b.follower = a.followee and b.followee = a.follower;
grant select on public.friends to authenticated;

create or replace function public.send_friend_request(p_user uuid)
returns text language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); begin
  if me is null then raise exception 'not signed in'; end if;
  if p_user = me then raise exception 'not allowed'; end if;
  if exists(select 1 from user_blocks where blocker = p_user and blocked = me) then raise exception 'blocked'; end if;
  if exists(select 1 from follows where follower=me and followee=p_user) and exists(select 1 from follows where follower=p_user and followee=me) then
    return 'friends'; end if;
  -- they already asked me → accept straight away
  if exists(select 1 from friend_requests where from_user=p_user and to_user=me and status='pending') then
    perform respond_friend_request(p_user, true); return 'friends'; end if;
  insert into friend_requests(from_user,to_user,status) values (me,p_user,'pending')
    on conflict (from_user,to_user) do update set status='pending', updated_at=now();
  insert into follows(follower,followee) values (me,p_user) on conflict do nothing;
  return 'sent'; end $$;

create or replace function public.respond_friend_request(p_from uuid, p_accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare me uuid := auth.uid(); begin
  if me is null then raise exception 'not signed in'; end if;
  update friend_requests set status = case when p_accept then 'accepted' else 'declined' end, updated_at=now()
   where from_user=p_from and to_user=me and status='pending';
  if not found then raise exception 'request not found'; end if;
  if p_accept then
    insert into follows(follower,followee) values (me,p_from) on conflict do nothing;
    insert into follows(follower,followee) values (p_from,me) on conflict do nothing;
  end if; end $$;

create or replace function public.cancel_friend_request(p_user uuid)
returns void language sql security definer set search_path=public as $$
  delete from friend_requests where from_user=auth.uid() and to_user=p_user and status='pending' $$;

-- unfriend: both directions of the follow go (only rows that involve the caller)
create or replace function public.remove_friend(p_user uuid)
returns void language sql security definer set search_path=public as $$
  delete from follows where (follower=auth.uid() and followee=p_user) or (follower=p_user and followee=auth.uid());
  update friend_requests set status='declined', updated_at=now()
   where (from_user=auth.uid() and to_user=p_user) or (from_user=p_user and to_user=auth.uid()) $$;

grant execute on function public.send_friend_request(uuid), public.respond_friend_request(uuid,boolean), public.cancel_friend_request(uuid), public.remove_friend(uuid) to authenticated;

-- ============ presence + room invites ============
create or replace function public.touch_presence()
returns void language sql security definer set search_path=public as $$
  update profiles set online_at=now() where id=auth.uid() $$;
grant execute on function public.touch_presence() to authenticated;

create or replace function public.invite_to_room(p_room uuid, p_user uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; nm text; begin
  select * into r from rooms where id=p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if not exists(select 1 from room_players where room_id=p_room and user_id=auth.uid()) then raise exception 'not allowed'; end if;
  if exists(select 1 from user_blocks where blocker=p_user and blocked=auth.uid()) then raise exception 'blocked'; end if;
  select username into nm from profiles where id=auth.uid();
  perform _notify(p_user, 'room_invite', coalesce(nm,'یک بازیکن')||' تو را به بازی دعوت کرد',
    r.mode||' · کد '||r.code, jsonb_build_object('room', r.id, 'code', r.code, 'from', auth.uid()));
end $$;
grant execute on function public.invite_to_room(uuid,uuid) to authenticated;

-- ============ notification triggers (social) ============
create or replace function public._nt_follow() returns trigger language plpgsql security definer set search_path=public as $$
declare nm text; begin
  -- a follow that is part of a friend request is announced by the request trigger instead
  if exists(select 1 from friend_requests where from_user=new.follower and to_user=new.followee and status='pending' and updated_at > now() - interval '5 seconds') then return new; end if;
  if exists(select 1 from friend_requests where from_user=new.followee and to_user=new.follower and status='accepted' and updated_at > now() - interval '5 seconds') then return new; end if;
  select username into nm from profiles where id=new.follower;
  perform _notify(new.followee, 'follow', coalesce(nm,'یک بازیکن')||' دنبالت کرد', null, jsonb_build_object('user', new.follower));
  return new; end $$;
drop trigger if exists nt_follow on public.follows;
create trigger nt_follow after insert on public.follows for each row execute function public._nt_follow();

create or replace function public._nt_friend() returns trigger language plpgsql security definer set search_path=public as $$
declare nm text; begin
  if new.status='pending' and (tg_op='INSERT' or old.status is distinct from 'pending') then
    select username into nm from profiles where id=new.from_user;
    perform _notify(new.to_user, 'friend_request', coalesce(nm,'یک بازیکن')||' درخواست دوستی فرستاد', null, jsonb_build_object('user', new.from_user));
  elsif new.status='accepted' and tg_op='UPDATE' and old.status='pending' then
    select username into nm from profiles where id=new.to_user;
    perform _notify(new.from_user, 'friend_accept', coalesce(nm,'یک بازیکن')||' درخواست دوستی‌ات را پذیرفت', null, jsonb_build_object('user', new.to_user));
  end if;
  return new; end $$;
drop trigger if exists nt_friend on public.friend_requests;
create trigger nt_friend after insert or update on public.friend_requests for each row execute function public._nt_friend();

create or replace function public._nt_message() returns trigger language plpgsql security definer set search_path=public as $$
declare c conversations; nm text; u uuid; begin
  if new.sender is null then return new; end if;
  select * into c from conversations where id=new.conversation_id;
  if c.kind <> 'dm' then return new; end if;   -- groups / channels / clubs: in-app badges only (no push spam)
  select username into nm from profiles where id=new.sender;
  for u in select user_id from conversation_members where conversation_id=new.conversation_id and user_id<>new.sender and not coalesce(muted,false) loop
    if exists(select 1 from user_blocks where blocker=u and blocked=new.sender) then continue; end if;
    perform _notify(u, 'dm', coalesce(nm,'پیام جدید'), case when new.body is null and new.image_url is not null then '📷 عکس' else left(coalesce(new.body,''),140) end,
      jsonb_build_object('conversation', new.conversation_id, 'user', new.sender));
  end loop;
  return new; end $$;
drop trigger if exists nt_message on public.messages;
create trigger nt_message after insert on public.messages for each row execute function public._nt_message();

create or replace function public._nt_club_request() returns trigger language plpgsql security definer set search_path=public as $$
declare cl clubs; nm text; u uuid; begin
  select * into cl from clubs where id=new.club_id;
  if new.kind='invite' then
    perform _notify(new.user_id, 'club_invite', 'دعوت به باشگاه '||coalesce(cl.name,''), null, jsonb_build_object('club', new.club_id));
  elsif new.kind='request' then
    select username into nm from profiles where id=new.user_id;
    for u in select user_id from club_members where club_id=new.club_id and role in ('leader','officer') loop
      perform _notify(u, 'club_request', coalesce(nm,'یک بازیکن')||' می‌خواهد به '||coalesce(cl.name,'باشگاه')||' بپیوندد', new.message, jsonb_build_object('club', new.club_id, 'user', new.user_id));
    end loop;
  end if;
  return new; end $$;
drop trigger if exists nt_club_request on public.club_requests;
create trigger nt_club_request after insert or update of kind on public.club_requests for each row execute function public._nt_club_request();

-- ============ device tokens + push dispatch ============
create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null default 'android',
  locale     text,
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='device_tokens' and policyname='dt read own') then
    create policy "dt read own" on public.device_tokens for select to authenticated using (user_id = auth.uid());
  end if;
end $$;
revoke insert, update, delete on public.device_tokens from authenticated, anon;

create or replace function public.register_device(p_token text, p_platform text default 'android', p_locale text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or length(coalesce(p_token,'')) < 20 then return; end if;
  insert into device_tokens(token,user_id,platform,locale,updated_at) values (p_token, auth.uid(), left(coalesce(p_platform,'android'),16), left(p_locale,8), now())
  on conflict (token) do update set user_id=auth.uid(), platform=excluded.platform, locale=excluded.locale, updated_at=now();
end $$;
create or replace function public.unregister_device(p_token text)
returns void language sql security definer set search_path=public as $$ delete from device_tokens where token=p_token and user_id=auth.uid() $$;
grant execute on function public.register_device(text,text,text), public.unregister_device(text) to authenticated;

-- shared secret between this trigger and the push-send function (kept in Vault, never readable by clients)
do $$ begin
  if not exists (select 1 from vault.secrets where name='push_webhook_secret') then
    perform vault.create_secret(encode(gen_random_bytes(24),'hex'), 'push_webhook_secret', 'NEXORA notifications → push-send');
  end if;
end $$;

create or replace function public._push_dispatch() returns trigger language plpgsql security definer set search_path=public, extensions as $$
declare sec text; begin
  if not exists(select 1 from device_tokens where user_id=new.user_id) then return new; end if;
  select decrypted_secret into sec from vault.decrypted_secrets where name='push_webhook_secret';
  perform net.http_post(
    url := 'https://eisstodgncimypdawisy.supabase.co/functions/v1/push-send',
    body := jsonb_build_object('id', new.id, 'user_id', new.user_id, 'kind', new.kind, 'title', new.title, 'body', new.body, 'data', new.data),
    headers := jsonb_build_object('Content-Type','application/json','x-push-secret', coalesce(sec,'')),
    timeout_milliseconds := 4000);
  return new;
exception when others then return new;   -- push must never break the insert
end $$;
drop trigger if exists push_dispatch on public.notifications;
create trigger push_dispatch after insert on public.notifications for each row execute function public._push_dispatch();

-- ============ client error log ============
create table if not exists public.client_errors (
  id         bigint generated always as identity primary key,
  user_id    uuid,
  kind       text not null default 'error',
  message    text not null,
  stack      text,
  context    jsonb not null default '{}',
  app_version text,
  platform   text,
  created_at timestamptz not null default now()
);
create index if not exists client_errors_created_idx on public.client_errors (created_at desc);
alter table public.client_errors enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='client_errors' and policyname='ce insert') then
    create policy "ce insert" on public.client_errors for insert to anon, authenticated
      with check (length(message) <= 2000 and length(coalesce(stack,'')) <= 8000 and (user_id is null or user_id = auth.uid()));
  end if;
end $$;
grant insert on public.client_errors to anon, authenticated;
revoke select, update, delete on public.client_errors from anon, authenticated;

-- realtime for the new tables the app listens to
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='friend_requests') then
    alter publication supabase_realtime add table public.friend_requests;
  end if;
end $$;
