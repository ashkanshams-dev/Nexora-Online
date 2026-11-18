-- Durable direct-message notifications, server-side read state and privacy.
-- Auth/social Supabase project: eisstodgncimypdawisy

create or replace function public.nx_social_message_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare recipient uuid;
begin
  for recipient in select cm.user_id from public.nx_chat_members cm where cm.chat_id = new.chat_id and cm.user_id <> new.author loop
    insert into public.nx_social_notifications(user_id, actor, kind, entity_id)
    values (recipient, new.author, 'message', new.id);
  end loop;
  return new;
end $$;

drop trigger if exists nx_social_message_notification_trigger on public.nx_messages;
create trigger nx_social_message_notification_trigger after insert on public.nx_messages for each row execute function public.nx_social_message_notification();

create or replace function public.nx_social_mark_chat_read(p_chat uuid)
returns void language sql security definer set search_path = public as $$
  update public.nx_chat_members set last_read_at = now() where chat_id = p_chat and user_id = auth.uid();
$$;
grant execute on function public.nx_social_mark_chat_read(uuid) to authenticated;

create or replace function public.nx_social_set_privacy(p_private boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in'; end if;
  update public.profiles set is_private = coalesce(p_private, false), updated_at = now() where id = me;
  return public.nx_social_profile(me);
end $$;
grant execute on function public.nx_social_set_privacy(boolean) to authenticated;
