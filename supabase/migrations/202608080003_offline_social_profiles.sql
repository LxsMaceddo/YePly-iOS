-- YePly iOS 1.2: social profile fields and private avatar storage.
-- Offline music files remain only on the iPhone and require no database table.

alter table public.profiles
  add column if not exists bio text,
  add column if not exists tastes text[] not null default '{}'::text[];

alter table public.profiles drop constraint if exists profiles_bio_length;
alter table public.profiles add constraint profiles_bio_length
  check (bio is null or char_length(bio) <= 280);

alter table public.profiles drop constraint if exists profiles_tastes_limit;
alter table public.profiles add constraint profiles_tastes_limit
  check (cardinality(tastes) <= 12 and char_length(array_to_string(tastes, '')) <= 360);

-- Username is permanent. Users may edit only their presentation fields.
create or replace function public.protect_profile_security_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_user not in ('postgres', 'supabase_admin') and not public.is_admin() then
    new.role := old.role;
  end if;
  new.id := old.id;
  new.username := old.username;
  new.created_at := old.created_at;
  new.updated_at := now();
  if new.avatar_path is not null and new.avatar_path not like lower(new.id::text) || '/%' then
    raise exception 'invalid_avatar_path' using errcode = '22023';
  end if;
  return new;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatars_read_authenticated on storage.objects;
create policy avatars_read_authenticated on storage.objects
for select to authenticated
using (bucket_id = 'avatars');

drop policy if exists avatars_insert_self on storage.objects;
create policy avatars_insert_self on storage.objects
for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

drop policy if exists avatars_update_self on storage.objects;
create policy avatars_update_self on storage.objects
for update to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(storage.extension(name)) in ('jpg', 'jpeg', 'png', 'webp')
);

drop policy if exists avatars_delete_self on storage.objects;
create policy avatars_delete_self on storage.objects
for delete to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

comment on column public.profiles.bio is 'Public profile biography, limited to 280 characters.';
comment on column public.profiles.tastes is 'Up to twelve musical tastes shown on the social profile.';
comment on function public.protect_profile_security_fields() is 'Keeps profile identity and role fields immutable while allowing presentation updates.';
