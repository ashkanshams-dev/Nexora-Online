-- NEXORA Social Media v1: durable profile fields, follow requests and server-side follow operations.
-- Applied to the auth/social Supabase project (eisstodgncimypdawisy).

alter table public.profiles
  add column if not exists display_name text not null default '',
  add column if not exists website text not null default '',
  add column if not exists location text not null default '',
  add column if not exists is_private boolean not null default false;

create index if not exists profiles_username_lower_idx on public.profiles (lower(username));

create table if not exists public.nx_follow_requests (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null references auth.users(id) on delete cascade,
  target uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (requester, target),
  check (requester <> target)
);
create index if not exists nx_follow_requests_target_status_idx on public.nx_follow_requests(target, status, created_at desc);
create index if not exists nx_follow_requests_requester_status_idx on public.nx_follow_requests(requester, status, created_at desc);

alter table public.nx_follow_requests enable row level security;
drop policy if exists nx_follow_requests_read on public.nx_follow_requests;
create policy nx_follow_requests_read on public.nx_follow_requests for select to authenticated
  using (requester = auth.uid() or target = auth.uid());

create table if not exists public.nx_social_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('follow','follow_request','follow_accepted','message')),
  entity_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists nx_social_notifications_user_idx on public.nx_social_notifications(user_id, created_at desc);
alter table public.nx_social_notifications enable row level security;
drop policy if exists nx_social_notifications_read on public.nx_social_notifications;
create policy nx_social_notifications_read on public.nx_social_notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists nx_social_notifications_update on public.nx_social_notifications;
create policy nx_social_notifications_update on public.nx_social_notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create or replace function public.nx_social_profile(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r record; me uuid := auth.uid();
begin
  if p_user is null then raise exception 'bad_user'; end if;
  select p.id, p.username, p.avatar_url, p.avatar, p.display_name, p.bio, p.website, p.location,
         p.is_private,
         (select count(*)::int from follows f where f.followee = p.id) as followers,
         (select count(*)::int from follows f where f.follower = p.id) as following,
         exists(select 1 from follows f where f.follower = me and f.followee = p.id) as is_following,
         exists(select 1 from nx_follow_requests q where q.requester = me and q.target = p.id and q.status = 'pending') as is_pending,
         (select count(*)::int from nx_posts x where x.author = p.id and (x.expires_at is null or x.expires_at > now())) as posts
    into r from profiles p where p.id = p_user;
  if not found then raise exception 'profile_not_found'; end if;
  return jsonb_build_object('id',r.id,'username',coalesce(r.username,''),'avatar_url',coalesce(r.avatar_url,r.avatar),
    'display_name',coalesce(r.display_name,''),'bio',coalesce(r.bio,''),'website',coalesce(r.website,''),'location',coalesce(r.location,''),
    'is_private',r.is_private,'followers',r.followers,'following',r.following,'posts',r.posts,
    'is_following',coalesce(r.is_following,false),'is_pending',coalesce(r.is_pending,false));
end $$;

create or replace function public.nx_social_update_profile(p_display_name text, p_username text, p_bio text, p_website text, p_location text, p_avatar_url text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text := lower(trim(coalesce(p_username,'')));
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if char_length(n) < 2 or char_length(n) > 24 or n !~ '^[a-z0-9_.]+$' then raise exception 'bad_username'; end if;
  if exists(select 1 from profiles where lower(username) = n and id <> me) then raise exception 'username_taken'; end if;
  update profiles set username=n, display_name=left(trim(coalesce(p_display_name,'')),80), bio=left(trim(coalesce(p_bio,'')),500),
    website=left(trim(coalesce(p_website,'')),200), location=left(trim(coalesce(p_location,'')),120), avatar_url=nullif(trim(coalesce(p_avatar_url,'')),''), updated_at=now()
    where id=me;
  return public.nx_social_profile(me);
end $$;

create or replace function public.nx_social_toggle_follow(p_target uuid, p_follow boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); target_private boolean; already boolean;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if p_target is null or p_target = me then raise exception 'bad_target'; end if;
  if not exists(select 1 from profiles where id=p_target) then raise exception 'profile_not_found'; end if;
  select is_private into target_private from profiles where id=p_target;
  if not p_follow then
    delete from follows where follower=me and followee=p_target;
    update nx_follow_requests set status='cancelled', updated_at=now() where requester=me and target=p_target and status='pending';
  elsif target_private then
    insert into nx_follow_requests(requester,target,status) values(me,p_target,'pending')
      on conflict(requester,target) do update set status='pending', updated_at=now();
    insert into nx_social_notifications(user_id,actor,kind) values(p_target,me,'follow_request');
  else
    insert into follows(follower,followee) values(me,p_target) on conflict(follower,followee) do nothing;
    insert into nx_social_notifications(user_id,actor,kind) values(p_target,me,'follow');
  end if;
  return public.nx_social_profile(p_target);
end $$;

create or replace function public.nx_social_respond_follow_request(p_requester uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null or p_requester is null or p_requester = me then raise exception 'bad_request'; end if;
  if not exists(select 1 from nx_follow_requests where requester=p_requester and target=me and status='pending') then raise exception 'request_not_found'; end if;
  update nx_follow_requests set status=case when p_accept then 'accepted' else 'rejected' end, updated_at=now()
    where requester=p_requester and target=me and status='pending';
  if p_accept then
    insert into follows(follower,followee) values(p_requester,me) on conflict(follower,followee) do nothing;
    insert into nx_social_notifications(user_id,actor,kind) values(p_requester,me,'follow_accepted');
  end if;
  return public.nx_social_profile(me);
end $$;

create or replace function public.nx_social_mark_notification(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update nx_social_notifications set read_at=now() where id=p_id and user_id=auth.uid();
$$;

grant execute on function public.nx_social_profile(uuid), public.nx_social_update_profile(text,text,text,text,text,text), public.nx_social_toggle_follow(uuid,boolean), public.nx_social_respond_follow_request(uuid,boolean), public.nx_social_mark_notification(uuid) to authenticated;
