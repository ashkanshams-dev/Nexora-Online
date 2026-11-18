-- Shared Auth database: invalid user metadata must never make Auth signup fail.
-- Keep profiles_username_check unchanged; substitute a valid username only when metadata is absent/invalid.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  n text;
begin
  n := nullif(btrim(new.raw_user_meta_data->>'username'), '');

  if n is null or char_length(n) < 3 or char_length(n) > 20 then
    -- Stable per-user fallback avoids short-name constraint failures while preserving valid names.
    n := 'Pilot' || substr(replace(new.id::text, '-', ''), 1, 15);
  end if;

  -- Preserve the existing unique-name fallback behavior.
  while exists(select 1 from public.profiles where username = n) loop
    n := 'Pilot' || lpad((floor(random() * 99999))::bigint::text, 5, '0');
  end loop;

  insert into public.profiles(id, username, is_guest)
  values (new.id, n, coalesce(new.is_anonymous, false));
  return new;
end
$function$;
