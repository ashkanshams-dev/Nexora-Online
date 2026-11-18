-- Social audit fixes: incoming follow-request list and private-profile post access.
create or replace function public.nx_social_pending_follow_requests()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'requester', q.requester,
    'username', coalesce(p.username,''),
    'display_name', coalesce(p.display_name,''),
    'avatar_url', coalesce(p.avatar_url,p.avatar),
    'created_at', q.created_at
  ) order by q.created_at desc), '[]'::jsonb)
  from public.nx_follow_requests q
  join public.profiles p on p.id=q.requester
  where q.target=auth.uid() and q.status='pending';
$$;

create or replace function public.nx_social_posts(p_user uuid)
returns table(id uuid, author uuid, text text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select x.id, x.author, x.text, x.created_at
  from public.nx_posts x
  where x.author=p_user
    and (x.expires_at is null or x.expires_at > now())
    and (p_user=auth.uid()
         or not exists(select 1 from public.profiles p where p.id=p_user and p.is_private)
         or exists(select 1 from public.follows f where f.follower=auth.uid() and f.followee=p_user))
  order by x.created_at desc
  limit 50;
$$;

grant execute on function public.nx_social_pending_follow_requests(), public.nx_social_posts(uuid) to authenticated;
