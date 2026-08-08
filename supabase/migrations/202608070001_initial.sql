-- YePly: schema, authorization and private storage policies
create extension if not exists pgcrypto;

create type public.user_role as enum ('listener', 'creator', 'admin');
create type public.playlist_visibility as enum ('public', 'unlisted', 'private');
create type public.playlist_member_role as enum ('viewer', 'editor');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  username text not null unique check (username ~ '^[a-z0-9_]{3,30}$'),
  avatar_path text,
  role public.user_role not null default 'listener',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.playlists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  artist_name text not null check (char_length(artist_name) between 1 and 120),
  summary text check (char_length(summary) <= 1000),
  cover_path text,
  visibility public.playlist_visibility not null default 'unlisted',
  share_token uuid not null unique default gen_random_uuid(),
  is_featured boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.playlist_members (
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.playlist_member_role not null default 'viewer',
  added_at timestamptz not null default now(),
  primary key (playlist_id, user_id)
);

create table public.tracks (
  id uuid primary key default gen_random_uuid(),
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete restrict,
  title text not null check (char_length(title) between 1 and 180),
  artist_name text not null check (char_length(artist_name) between 1 and 180),
  album_name text check (char_length(album_name) <= 180),
  duration_seconds double precision not null default 0 check (duration_seconds >= 0 and duration_seconds <= 86400),
  audio_path text not null unique,
  artwork_path text,
  position integer not null default 0 check (position >= 0),
  file_size_bytes bigint check (file_size_bytes > 0 and file_size_bytes <= 209715200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (playlist_id, position)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index playlists_owner_idx on public.playlists(owner_id);
create index playlists_updated_idx on public.playlists(updated_at desc);
create index playlist_members_user_idx on public.playlist_members(user_id);
create index tracks_playlist_position_idx on public.tracks(playlist_id, position);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false) $$;

create or replace function public.can_manage_playlist(p_playlist_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.playlists p
    where p.id = p_playlist_id and (
      p.owner_id = auth.uid() or exists (
        select 1 from public.playlist_members m
        where m.playlist_id = p.id and m.user_id = auth.uid() and m.role = 'editor'
      )
    )
  )
$$;

create or replace function public.can_read_playlist(p_playlist_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_admin() or exists (
    select 1 from public.playlists p
    where p.id = p_playlist_id and (
      p.visibility = 'public' or p.owner_id = auth.uid() or exists (
        select 1 from public.playlist_members m where m.playlist_id = p.id and m.user_id = auth.uid()
      )
    )
  )
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  base_username text;
  final_username text;
begin
  base_username := lower(regexp_replace(coalesce(new.raw_user_meta_data ->> 'username', split_part(new.email, '@', 1)), '[^a-z0-9_]', '', 'g'));
  if char_length(base_username) < 3 then base_username := 'user'; end if;
  final_username := left(base_username, 30);
  if exists(select 1 from public.profiles where username = final_username) then
    final_username := left(base_username, 22) || '_' || substr(replace(new.id::text, '-', ''), 1, 7);
  end if;
  insert into public.profiles (id, display_name, username, role) values (
    new.id, left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1), 'Usuário'), 80), final_username,
    case when new.raw_app_meta_data ->> 'role' = 'admin' then 'admin'::public.user_role else 'listener'::public.user_role end);
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.protect_profile_security_fields()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if session_user not in ('postgres', 'supabase_admin') and not public.is_admin() then new.role := old.role; end if;
  new.id := old.id;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;
create trigger profiles_protect before update on public.profiles for each row execute procedure public.protect_profile_security_fields();

create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end; $$;
create trigger playlists_touch before update on public.playlists for each row execute procedure public.touch_updated_at();
create trigger tracks_touch before update on public.tracks for each row execute procedure public.touch_updated_at();

create or replace function public.prevent_playlist_security_changes()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_admin() then
    new.id := old.id; new.owner_id := old.owner_id; new.share_token := old.share_token;
    new.is_featured := old.is_featured; new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
create trigger playlists_protect before update on public.playlists for each row execute procedure public.prevent_playlist_security_changes();

create or replace function public.accept_playlist_share(p_token uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare target public.playlists;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into target from public.playlists where share_token = p_token limit 1;
  if target.id is null then raise exception 'invalid_share_token' using errcode = 'P0002'; end if;
  if target.visibility = 'private' and target.owner_id <> auth.uid() and not public.is_admin() then
    raise exception 'private_playlist' using errcode = '42501';
  end if;
  if target.owner_id <> auth.uid() then
    insert into public.playlist_members (playlist_id, user_id, role)
    values (target.id, auth.uid(), 'viewer') on conflict (playlist_id, user_id) do nothing;
  end if;
  insert into public.audit_log(actor_id, action, entity_type, entity_id)
  values(auth.uid(), 'share_opened', 'playlist', target.id);
  return target.id;
end;
$$;

create or replace function public.library_playlists(p_scope text default 'all')
returns table (
  id uuid, owner_id uuid, title text, artist_name text, summary text, cover_path text,
  visibility public.playlist_visibility, share_token uuid, is_featured boolean,
  created_at timestamptz, updated_at timestamptz, track_count bigint
)
language sql stable security invoker set search_path = ''
as $$
  select p.id, p.owner_id, p.title, p.artist_name, p.summary, p.cover_path,
         p.visibility, p.share_token, p.is_featured, p.created_at, p.updated_at,
         count(t.id) as track_count
  from public.playlists p
  left join public.tracks t on t.playlist_id = p.id
  where
    (p_scope = 'all') or
    (p_scope = 'mine' and p.owner_id = auth.uid()) or
    (p_scope = 'shared' and p.owner_id <> auth.uid() and exists (
      select 1 from public.playlist_members m where m.playlist_id = p.id and m.user_id = auth.uid()
    ))
  group by p.id
  order by p.is_featured desc, p.updated_at desc
$$;

-- Row-level authorization
alter table public.profiles enable row level security;
alter table public.playlists enable row level security;
alter table public.playlist_members enable row level security;
alter table public.tracks enable row level security;
alter table public.audit_log enable row level security;

create policy profiles_read_authenticated on public.profiles for select to authenticated using (true);
create policy profiles_update_self on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy playlists_read_allowed on public.playlists for select to authenticated using (public.can_read_playlist(id));
create policy playlists_create_self on public.playlists for insert to authenticated with check (owner_id = auth.uid());
create policy playlists_update_managers on public.playlists for update to authenticated using (public.can_manage_playlist(id)) with check (public.can_manage_playlist(id));
create policy playlists_delete_managers on public.playlists for delete to authenticated using (public.can_manage_playlist(id));

create policy members_read_related on public.playlist_members for select to authenticated using (user_id = auth.uid() or public.can_manage_playlist(playlist_id));
create policy members_delete_self_or_manager on public.playlist_members for delete to authenticated using (user_id = auth.uid() or public.can_manage_playlist(playlist_id));

create policy tracks_read_allowed on public.tracks for select to authenticated using (public.can_read_playlist(playlist_id));
create policy tracks_create_manager on public.tracks for insert to authenticated with check (
  uploader_id = auth.uid() and public.can_manage_playlist(playlist_id) and
  audio_path like lower(playlist_id::text) || '/%'
);
create policy tracks_update_manager on public.tracks for update to authenticated using (public.can_manage_playlist(playlist_id)) with check (public.can_manage_playlist(playlist_id));
create policy tracks_delete_manager on public.tracks for delete to authenticated using (public.can_manage_playlist(playlist_id));
create policy audit_admin_read on public.audit_log for select to authenticated using (public.is_admin());

-- Private object storage. Object names start with playlist UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('audio', 'audio', false, 209715200, array['audio/mpeg', 'audio/mp3'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('covers', 'covers', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy audio_read_allowed on storage.objects for select to authenticated using (
  bucket_id = 'audio' and public.can_read_playlist(((storage.foldername(name))[1])::uuid)
);
create policy audio_insert_manager on storage.objects for insert to authenticated with check (
  bucket_id = 'audio' and storage.extension(name) = 'mp3' and public.can_manage_playlist(((storage.foldername(name))[1])::uuid)
);
create policy audio_delete_manager on storage.objects for delete to authenticated using (
  bucket_id = 'audio' and public.can_manage_playlist(((storage.foldername(name))[1])::uuid)
);

create policy covers_read_allowed on storage.objects for select to authenticated using (
  bucket_id = 'covers' and public.can_read_playlist(((storage.foldername(name))[1])::uuid)
);
create policy covers_insert_manager on storage.objects for insert to authenticated with check (
  bucket_id = 'covers' and lower(storage.extension(name)) in ('jpg','jpeg','png','webp') and public.can_manage_playlist(((storage.foldername(name))[1])::uuid)
);
create policy covers_update_manager on storage.objects for update to authenticated using (
  bucket_id = 'covers' and public.can_manage_playlist(((storage.foldername(name))[1])::uuid)
) with check (bucket_id = 'covers' and public.can_manage_playlist(((storage.foldername(name))[1])::uuid));
create policy covers_delete_manager on storage.objects for delete to authenticated using (
  bucket_id = 'covers' and public.can_manage_playlist(((storage.foldername(name))[1])::uuid)
);

-- Least privilege grants. The service role is only for trusted server-side operations.
revoke all on all tables in schema public from anon;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.playlists, public.playlist_members, public.tracks to authenticated;
grant select on public.audit_log to authenticated;
revoke all on function public.accept_playlist_share(uuid) from public;
revoke all on function public.library_playlists(text) from public;
revoke all on function public.is_admin() from public;
revoke all on function public.can_manage_playlist(uuid) from public;
revoke all on function public.can_read_playlist(uuid) from public;
revoke all on function public.handle_new_user() from public;
revoke all on function public.protect_profile_security_fields() from public;
revoke all on function public.touch_updated_at() from public;
revoke all on function public.prevent_playlist_security_changes() from public;
grant execute on function public.accept_playlist_share(uuid) to authenticated;
grant execute on function public.library_playlists(text) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_manage_playlist(uuid) to authenticated;
grant execute on function public.can_read_playlist(uuid) to authenticated;

comment on table public.tracks is 'Metadata only. Audio objects stay private in the audio storage bucket.';
comment on function public.accept_playlist_share(uuid) is 'Validates an unlisted/public share token and grants membership to the authenticated user.';
