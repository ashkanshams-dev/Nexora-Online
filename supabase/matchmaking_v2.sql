-- NEXORA · matchmaking v2 (purely additive, idempotent)
-- Ticket queue on top of the existing rooms / room_players / _start_match machinery.
--   * clients enqueue a ticket (mode, kind, region, measured RTT) and keep it alive with mm_poll() every ~2 s
--   * a matcher (run inside every enqueue/poll, serialized with an advisory lock) groups compatible tickets:
--       same mode + kind; rating window widens with wait time (100 + 20/s, max 900);
--       same region is required for the first 8 s, after that any region (ordered by region match, then RTT, then rating gap)
--   * when 2·n tickets fit, one room is created server-side, every player is seated + ready, the match starts immediately
--     (existing _start_match), tickets flip to 'matched' with the room id → clients get it over Realtime and jump in
--   * bot fill: a ticket that has waited >= bot_after seconds (default 25) is matched alone (plus any partial group) and the
--     match starts with bots (existing _start_match(room, true) → matches.bots = true, unranked)
--   * stale tickets (no poll for 12 s) and tickets older than 120 s expire; mm_cancel() cancels
-- Nothing existing is altered: new table, new functions, table added to the realtime publication.

create table if not exists public.mm_tickets (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  mode       text not null check (mode in ('1v1','2v2','3v3')),
  kind       text not null default 'quick' check (kind in ('quick','arena')),
  rating     int  not null default 0,
  region     text not null default 'auto',
  rtt_ms     int,
  bot_after  int  not null default 25 check (bot_after between 8 and 120),
  status     text not null default 'searching' check (status in ('searching','matched','cancelled','expired')),
  room_id    uuid,
  match_id   uuid,
  bots       boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists mm_tickets_search_idx on public.mm_tickets (mode, kind, status, created_at);

alter table public.mm_tickets enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='mm_tickets' and policyname='mm read own') then
    create policy "mm read own" on public.mm_tickets for select to authenticated using (user_id = auth.uid());
  end if;
end $$;
revoke insert, update, delete on public.mm_tickets from authenticated, anon;
grant select on public.mm_tickets to authenticated;

do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='mm_tickets') then
    alter publication supabase_realtime add table public.mm_tickets;
  end if;
end $$;

-- live queue size per mode/kind (for the "N searching" hint in the UI)
create or replace function public.mm_stats()
returns table(mode text, kind text, searching int, avg_wait_s int)
language sql security definer set search_path=public stable as $$
  select t.mode, t.kind, count(*)::int, coalesce(avg(extract(epoch from now()-t.created_at)),0)::int
  from mm_tickets t where t.status='searching' and t.updated_at > now() - interval '12 seconds'
  group by t.mode, t.kind $$;
grant execute on function public.mm_stats() to authenticated;

-- build a started room for a set of tickets (internal)
create or replace function public._mm_launch(p_ids uuid[], p_mode text, p_kind text, p_bots boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid; mid uuid; n int := room_size(p_mode); i int := 0; u uuid; begin
  -- the matched players leave any waiting room they are still sitting in
  delete from room_players rp using rooms ro where ro.id=rp.room_id and ro.status='waiting' and rp.user_id = any(p_ids);
  insert into rooms(code,name,host,mode,is_private,ranked,voice,settings,kind)
  values (_gen_code(), case when p_kind='arena' then 'آرنا '||p_mode else 'مسابقه سریع '||p_mode end, p_ids[1], p_mode, true, true, true,
          jsonb_build_object('goals',3,'time',0,'field',(floor(random()*29))::int,'turn',15,'ball',0,'mm',2), p_kind)
  returning id into rid;
  -- alternate teams so rating-sorted ids are split fairly: 0,1,1,0,0,1
  foreach u in array p_ids loop
    insert into room_players(room_id,user_id,role,team,slot,ready,last_seen)
    values (rid, u, 'player', (case when i % 4 in (0,3) then 0 else 1 end)::smallint, (i / 2)::smallint, true, now())
    on conflict do nothing;
    i := i + 1;
  end loop;
  mid := _start_match(rid, p_bots);
  update mm_tickets set status='matched', room_id=rid, match_id=mid, bots=p_bots, updated_at=now() where user_id = any(p_ids);
  return rid; end $$;

-- one matcher pass for a mode/kind (internal; serialized)
create or replace function public._mm_run(p_mode text, p_kind text)
returns void language plpgsql security definer set search_path=public as $$
declare n int := room_size(p_mode); a mm_tickets; ids uuid[]; waited numeric; win int; begin
  perform pg_advisory_xact_lock(hashtext('nexora-mm2:'||p_mode||':'||p_kind));
  update mm_tickets set status='expired', updated_at=now()
   where status='searching' and (updated_at < now() - interval '12 seconds' or created_at < now() - interval '120 seconds');
  for a in select * from mm_tickets where mode=p_mode and kind=p_kind and status='searching' order by created_at loop
    continue when not exists(select 1 from mm_tickets where user_id=a.user_id and status='searching');
    waited := extract(epoch from now()-a.created_at);
    win := least(900, 100 + (20 * waited)::int);
    select array_agg(x.user_id order by x.rating desc) into ids from (
      select t.user_id, t.rating from mm_tickets t
      where t.mode=p_mode and t.kind=p_kind and t.status='searching' and t.user_id<>a.user_id
        and abs(t.rating - a.rating) <= greatest(win, least(900, 100 + (20 * extract(epoch from now()-t.created_at))::int))
        and (waited >= 8 or t.region = a.region or a.region='auto' or t.region='auto')
      order by (t.region = a.region) desc, coalesce(t.rtt_ms, 999), abs(t.rating - a.rating), t.created_at
      limit 2*n - 1) x;
    if coalesce(array_length(ids,1),0) = 2*n - 1 then
      perform _mm_launch(array[a.user_id] || ids, p_mode, p_kind, false);
    elsif waited >= a.bot_after then
      perform _mm_launch(array[a.user_id] || coalesce(ids, '{}'), p_mode, p_kind, true);
    end if;
  end loop; end $$;

create or replace function public.mm_enqueue(p_mode text, p_kind text default 'quick', p_region text default 'auto', p_rtt int default null, p_bot_after int default 25)
returns public.mm_tickets language plpgsql security definer set search_path=public as $$
declare t mm_tickets; my int; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if p_mode not in ('1v1','2v2','3v3') then raise exception 'bad mode'; end if;
  if p_kind not in ('quick','arena') then raise exception 'bad kind'; end if;
  if exists(select 1 from room_players p join rooms ro on ro.id=p.room_id where p.user_id=auth.uid() and p.role='player' and ro.status='playing'
            and exists(select 1 from matches m where m.id=ro.current_match and m.status='live')) then
    raise exception 'match running'; end if;
  perform leave_all_rooms();
  select case when p_kind='arena' then arena_points else rating end into my from profiles where id=auth.uid();
  insert into mm_tickets(user_id,mode,kind,rating,region,rtt_ms,bot_after,status,room_id,match_id,bots,created_at,updated_at)
  values (auth.uid(), p_mode, p_kind, coalesce(my,0), coalesce(nullif(left(trim(p_region),24),''),'auto'), p_rtt,
          greatest(8, least(120, coalesce(p_bot_after,25))), 'searching', null, null, false, now(), now())
  on conflict (user_id) do update set mode=excluded.mode, kind=excluded.kind, rating=excluded.rating, region=excluded.region,
    rtt_ms=excluded.rtt_ms, bot_after=excluded.bot_after, status='searching', room_id=null, match_id=null, bots=false, created_at=now(), updated_at=now();
  perform _mm_run(p_mode, p_kind);
  select * into t from mm_tickets where user_id=auth.uid();
  return t; end $$;

create or replace function public.mm_poll(p_rtt int default null)
returns public.mm_tickets language plpgsql security definer set search_path=public as $$
declare t mm_tickets; begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  update mm_tickets set updated_at=now(), rtt_ms=coalesce(p_rtt, rtt_ms) where user_id=auth.uid() and status='searching' returning * into t;
  if t.user_id is not null then perform _mm_run(t.mode, t.kind); end if;
  update profiles set online_at=now() where id=auth.uid();
  select * into t from mm_tickets where user_id=auth.uid();
  return t; end $$;

create or replace function public.mm_cancel()
returns void language sql security definer set search_path=public as $$
  update mm_tickets set status='cancelled', updated_at=now() where user_id=auth.uid() and status='searching' $$;

grant execute on function public.mm_enqueue(text,text,text,int,int), public.mm_poll(int), public.mm_cancel() to authenticated;
revoke execute on function public._mm_run(text,text), public._mm_launch(uuid[],text,text,boolean) from public, anon, authenticated;
