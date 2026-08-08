-- YePly iOS 1.3: social graph, discovery, track reactions and playlist views.

begin;

create table if not exists public.user_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_user_id),
  check (follower_id <> followed_user_id)
);

create table if not exists public.playlist_follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, playlist_id)
);

create table if not exists public.artist_follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  artist_key text not null,
  artist_name text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, artist_key),
  check (char_length(artist_key) between 1 and 180),
  check (char_length(artist_name) between 1 and 180)
);

create table if not exists public.track_likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, track_id)
);

create table if not exists public.track_comments (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.comment_likes (
  user_id uuid not null references public.profiles(id) on delete cascade,
  comment_id uuid not null references public.track_comments(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, comment_id)
);

create table if not exists public.playlist_views (
  playlist_id uuid not null references public.playlists(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  view_count integer not null default 1 check (view_count > 0),
  primary key (playlist_id, user_id)
);

create index if not exists user_follows_followed_idx on public.user_follows(followed_user_id);
create index if not exists playlist_follows_playlist_idx on public.playlist_follows(playlist_id);
create index if not exists artist_follows_key_idx on public.artist_follows(artist_key);
create index if not exists track_likes_track_idx on public.track_likes(track_id);
create index if not exists track_comments_track_created_idx on public.track_comments(track_id, created_at desc);
create index if not exists comment_likes_comment_idx on public.comment_likes(comment_id);
create index if not exists playlist_views_playlist_idx on public.playlist_views(playlist_id);

drop trigger if exists track_comments_touch on public.track_comments;
create trigger track_comments_touch before update on public.track_comments
for each row execute procedure public.touch_updated_at();

alter table public.user_follows enable row level security;
alter table public.playlist_follows enable row level security;
alter table public.artist_follows enable row level security;
alter table public.track_likes enable row level security;
alter table public.track_comments enable row level security;
alter table public.comment_likes enable row level security;
alter table public.playlist_views enable row level security;

drop policy if exists user_follows_read on public.user_follows;
create policy user_follows_read on public.user_follows for select to authenticated using (true);
drop policy if exists user_follows_insert_self on public.user_follows;
create policy user_follows_insert_self on public.user_follows for insert to authenticated
with check (follower_id = auth.uid() and followed_user_id <> auth.uid());
drop policy if exists user_follows_delete_self on public.user_follows;
create policy user_follows_delete_self on public.user_follows for delete to authenticated using (follower_id = auth.uid());

drop policy if exists playlist_follows_read on public.playlist_follows;
create policy playlist_follows_read on public.playlist_follows for select to authenticated using (true);
drop policy if exists playlist_follows_insert_self on public.playlist_follows;
create policy playlist_follows_insert_self on public.playlist_follows for insert to authenticated
with check (user_id = auth.uid() and public.can_read_playlist(playlist_id));
drop policy if exists playlist_follows_delete_self on public.playlist_follows;
create policy playlist_follows_delete_self on public.playlist_follows for delete to authenticated using (user_id = auth.uid());

drop policy if exists artist_follows_read on public.artist_follows;
create policy artist_follows_read on public.artist_follows for select to authenticated using (true);
drop policy if exists artist_follows_insert_self on public.artist_follows;
create policy artist_follows_insert_self on public.artist_follows for insert to authenticated with check (user_id = auth.uid());
drop policy if exists artist_follows_delete_self on public.artist_follows;
create policy artist_follows_delete_self on public.artist_follows for delete to authenticated using (user_id = auth.uid());

drop policy if exists track_likes_read_allowed on public.track_likes;
create policy track_likes_read_allowed on public.track_likes for select to authenticated using (
  public.can_read_playlist((select t.playlist_id from public.tracks t where t.id = track_id))
);
drop policy if exists track_likes_insert_self on public.track_likes;
create policy track_likes_insert_self on public.track_likes for insert to authenticated with check (
  user_id = auth.uid() and public.can_read_playlist((select t.playlist_id from public.tracks t where t.id = track_id))
);
drop policy if exists track_likes_delete_self on public.track_likes;
create policy track_likes_delete_self on public.track_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists track_comments_read_allowed on public.track_comments;
create policy track_comments_read_allowed on public.track_comments for select to authenticated using (
  public.can_read_playlist((select t.playlist_id from public.tracks t where t.id = track_id))
);
drop policy if exists track_comments_insert_self on public.track_comments;
create policy track_comments_insert_self on public.track_comments for insert to authenticated with check (
  user_id = auth.uid() and public.can_read_playlist((select t.playlist_id from public.tracks t where t.id = track_id))
);
drop policy if exists track_comments_update_owner on public.track_comments;
create policy track_comments_update_owner on public.track_comments for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists track_comments_delete_owner_or_manager on public.track_comments;
create policy track_comments_delete_owner_or_manager on public.track_comments for delete to authenticated using (
  user_id = auth.uid() or public.is_admin() or public.can_manage_playlist((select t.playlist_id from public.tracks t where t.id = track_id))
);

drop policy if exists comment_likes_read_allowed on public.comment_likes;
create policy comment_likes_read_allowed on public.comment_likes for select to authenticated using (
  public.can_read_playlist((select t.playlist_id from public.track_comments c join public.tracks t on t.id = c.track_id where c.id = comment_id))
);
drop policy if exists comment_likes_insert_self on public.comment_likes;
create policy comment_likes_insert_self on public.comment_likes for insert to authenticated with check (
  user_id = auth.uid() and public.can_read_playlist((select t.playlist_id from public.track_comments c join public.tracks t on t.id = c.track_id where c.id = comment_id))
);
drop policy if exists comment_likes_delete_self on public.comment_likes;
create policy comment_likes_delete_self on public.comment_likes for delete to authenticated using (user_id = auth.uid());

drop policy if exists playlist_views_read_related on public.playlist_views;
create policy playlist_views_read_related on public.playlist_views for select to authenticated using (
  user_id = auth.uid() or public.can_manage_playlist(playlist_id)
);

create or replace function public.toggle_user_follow(p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or p_user_id = auth.uid() or not exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'invalid_follow_target' using errcode = '22023';
  end if;
  if exists (select 1 from public.user_follows f where f.follower_id = auth.uid() and f.followed_user_id = p_user_id) then
    delete from public.user_follows where follower_id = auth.uid() and followed_user_id = p_user_id;
    return false;
  end if;
  insert into public.user_follows(follower_id, followed_user_id) values (auth.uid(), p_user_id);
  return true;
end; $$;

create or replace function public.toggle_playlist_follow(p_playlist_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.can_read_playlist(p_playlist_id) then raise exception 'playlist_access_denied' using errcode = '42501'; end if;
  if exists (select 1 from public.playlist_follows f where f.user_id = auth.uid() and f.playlist_id = p_playlist_id) then
    delete from public.playlist_follows where user_id = auth.uid() and playlist_id = p_playlist_id;
    return false;
  end if;
  insert into public.playlist_follows(user_id, playlist_id) values (auth.uid(), p_playlist_id);
  return true;
end; $$;

create or replace function public.toggle_artist_follow(p_artist_name text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_name text := left(btrim(p_artist_name), 180); v_key text;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  v_key := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
  if v_key = '' then raise exception 'invalid_artist' using errcode = '22023'; end if;
  if exists (select 1 from public.artist_follows f where f.user_id = auth.uid() and f.artist_key = v_key) then
    delete from public.artist_follows where user_id = auth.uid() and artist_key = v_key;
    return false;
  end if;
  insert into public.artist_follows(user_id, artist_key, artist_name) values (auth.uid(), v_key, v_name);
  return true;
end; $$;

create or replace function public.toggle_track_like(p_track_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_playlist_id uuid;
begin
  select t.playlist_id into v_playlist_id from public.tracks t where t.id = p_track_id;
  if auth.uid() is null or v_playlist_id is null or not public.can_read_playlist(v_playlist_id) then raise exception 'track_access_denied' using errcode = '42501'; end if;
  if exists (select 1 from public.track_likes l where l.user_id = auth.uid() and l.track_id = p_track_id) then
    delete from public.track_likes where user_id = auth.uid() and track_id = p_track_id;
    return false;
  end if;
  insert into public.track_likes(user_id, track_id) values (auth.uid(), p_track_id);
  return true;
end; $$;

create or replace function public.toggle_comment_like(p_comment_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_playlist_id uuid;
begin
  select t.playlist_id into v_playlist_id from public.track_comments c join public.tracks t on t.id = c.track_id where c.id = p_comment_id;
  if auth.uid() is null or v_playlist_id is null or not public.can_read_playlist(v_playlist_id) then raise exception 'comment_access_denied' using errcode = '42501'; end if;
  if exists (select 1 from public.comment_likes l where l.user_id = auth.uid() and l.comment_id = p_comment_id) then
    delete from public.comment_likes where user_id = auth.uid() and comment_id = p_comment_id;
    return false;
  end if;
  insert into public.comment_likes(user_id, comment_id) values (auth.uid(), p_comment_id);
  return true;
end; $$;

create or replace function public.record_playlist_view(p_playlist_id uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_total bigint;
begin
  if auth.uid() is null or not public.can_read_playlist(p_playlist_id) then raise exception 'playlist_access_denied' using errcode = '42501'; end if;
  insert into public.playlist_views(playlist_id, user_id) values (p_playlist_id, auth.uid())
  on conflict (playlist_id, user_id) do update set last_viewed_at = now(), view_count = public.playlist_views.view_count + 1;
  select count(*) into v_total from public.playlist_views v where v.playlist_id = p_playlist_id;
  return v_total;
end; $$;

create or replace function public.library_playlists_social(p_scope text default 'all')
returns table (
  id uuid, owner_id uuid, title text, artist_name text, summary text, cover_path text,
  visibility public.playlist_visibility, share_token uuid, is_featured boolean,
  created_at timestamptz, updated_at timestamptz, track_count bigint,
  view_count bigint, follower_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.owner_id, p.title, p.artist_name, p.summary, p.cover_path,
         p.visibility, p.share_token, p.is_featured, p.created_at, p.updated_at,
         (select count(*) from public.tracks t where t.playlist_id = p.id),
         (select count(*) from public.playlist_views v where v.playlist_id = p.id),
         (select count(*) from public.playlist_follows f where f.playlist_id = p.id),
         exists(select 1 from public.playlist_follows f where f.playlist_id = p.id and f.user_id = auth.uid())
  from public.playlists p
  where (p_scope = 'all')
     or (p_scope = 'mine' and p.owner_id = auth.uid())
     or (p_scope = 'shared' and p.owner_id <> auth.uid() and exists (
       select 1 from public.playlist_members m where m.playlist_id = p.id and m.user_id = auth.uid()
     ))
  order by p.is_featured desc, p.updated_at desc
$$;

create or replace function public.playlist_with_social(p_playlist_id uuid)
returns table (
  id uuid, owner_id uuid, title text, artist_name text, summary text, cover_path text,
  visibility public.playlist_visibility, share_token uuid, is_featured boolean,
  created_at timestamptz, updated_at timestamptz, track_count bigint,
  view_count bigint, follower_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.owner_id, p.title, p.artist_name, p.summary, p.cover_path,
         p.visibility, p.share_token, p.is_featured, p.created_at, p.updated_at,
         (select count(*) from public.tracks t where t.playlist_id = p.id),
         (select count(*) from public.playlist_views v where v.playlist_id = p.id),
         (select count(*) from public.playlist_follows f where f.playlist_id = p.id),
         exists(select 1 from public.playlist_follows f where f.playlist_id = p.id and f.user_id = auth.uid())
  from public.playlists p where p.id = p_playlist_id
$$;

create or replace function public.playlist_tracks_with_social(p_playlist_id uuid)
returns table (
  id uuid, playlist_id uuid, uploader_id uuid, title text, artist_name text, album_name text,
  duration_seconds double precision, audio_path text, artwork_path text, "position" integer,
  file_size_bytes bigint, created_at timestamptz, like_count bigint, comment_count bigint, is_liked boolean
)
language sql stable security invoker set search_path = '' as $$
  select t.id, t.playlist_id, t.uploader_id, t.title, t.artist_name, t.album_name,
         t.duration_seconds, t.audio_path, t.artwork_path, t.position, t.file_size_bytes, t.created_at,
         (select count(*) from public.track_likes l where l.track_id = t.id),
         (select count(*) from public.track_comments c where c.track_id = t.id),
         exists(select 1 from public.track_likes l where l.track_id = t.id and l.user_id = auth.uid())
  from public.tracks t where t.playlist_id = p_playlist_id order by t.position
$$;

create or replace function public.search_profiles(p_query text default '', p_limit integer default 30)
returns table (
  id uuid, display_name text, username text, avatar_path text, bio text, tastes text[], role public.user_role,
  created_at timestamptz, follower_count bigint, following_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.username, p.avatar_path, p.bio, p.tastes, p.role, p.created_at,
         (select count(*) from public.user_follows f where f.followed_user_id = p.id),
         (select count(*) from public.user_follows f where f.follower_id = p.id),
         exists(select 1 from public.user_follows f where f.follower_id = auth.uid() and f.followed_user_id = p.id)
  from public.profiles p
  where p.id <> auth.uid() and (btrim(p_query) = '' or p.display_name ilike '%' || btrim(p_query) || '%' or p.username ilike '%' || btrim(p_query) || '%')
  order by 9 desc, p.display_name
  limit least(greatest(p_limit, 1), 50)
$$;

create or replace function public.profile_with_social(p_profile_id uuid)
returns table (
  id uuid, display_name text, username text, avatar_path text, bio text, tastes text[], role public.user_role,
  created_at timestamptz, follower_count bigint, following_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.username, p.avatar_path, p.bio, p.tastes, p.role, p.created_at,
         (select count(*) from public.user_follows f where f.followed_user_id = p.id),
         (select count(*) from public.user_follows f where f.follower_id = p.id),
         exists(select 1 from public.user_follows f where f.follower_id = auth.uid() and f.followed_user_id = p.id)
  from public.profiles p where p.id = p_profile_id
$$;

create or replace function public.search_playlists(p_query text default '', p_limit integer default 40)
returns table (
  id uuid, owner_id uuid, title text, artist_name text, summary text, cover_path text,
  visibility public.playlist_visibility, share_token uuid, is_featured boolean,
  created_at timestamptz, updated_at timestamptz, track_count bigint,
  view_count bigint, follower_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.owner_id, p.title, p.artist_name, p.summary, p.cover_path, p.visibility, p.share_token,
         p.is_featured, p.created_at, p.updated_at,
         (select count(*) from public.tracks t where t.playlist_id = p.id),
         (select count(*) from public.playlist_views v where v.playlist_id = p.id),
         (select count(*) from public.playlist_follows f where f.playlist_id = p.id),
         exists(select 1 from public.playlist_follows f where f.playlist_id = p.id and f.user_id = auth.uid())
  from public.playlists p
  where btrim(p_query) = '' or p.title ilike '%' || btrim(p_query) || '%' or p.artist_name ilike '%' || btrim(p_query) || '%'
  order by 14 desc, 13 desc, p.updated_at desc
  limit least(greatest(p_limit, 1), 60)
$$;

create or replace function public.search_artists(p_query text default '', p_limit integer default 30)
returns table (artist_key text, artist_name text, playlist_count bigint, track_count bigint, follower_count bigint, is_followed boolean)
language sql stable security invoker set search_path = '' as $$
  with candidates as (
    select p.artist_name as name from public.playlists p
    union
    select t.artist_name as name from public.tracks t
  ), normalized as (
    select lower(regexp_replace(btrim(name), '\s+', ' ', 'g')) as key, min(name) as display_name
    from candidates where btrim(name) <> '' group by lower(regexp_replace(btrim(name), '\s+', ' ', 'g'))
  )
  select n.key, n.display_name,
         (select count(*) from public.playlists p where lower(regexp_replace(btrim(p.artist_name), '\s+', ' ', 'g')) = n.key),
         (select count(*) from public.tracks t where lower(regexp_replace(btrim(t.artist_name), '\s+', ' ', 'g')) = n.key),
         (select count(*) from public.artist_follows f where f.artist_key = n.key),
         exists(select 1 from public.artist_follows f where f.artist_key = n.key and f.user_id = auth.uid())
  from normalized n
  where btrim(p_query) = '' or n.display_name ilike '%' || btrim(p_query) || '%'
  order by 5 desc, n.display_name
  limit least(greatest(p_limit, 1), 50)
$$;

create or replace function public.artist_playlists(p_artist_key text)
returns table (
  id uuid, owner_id uuid, title text, artist_name text, summary text, cover_path text,
  visibility public.playlist_visibility, share_token uuid, is_featured boolean,
  created_at timestamptz, updated_at timestamptz, track_count bigint,
  view_count bigint, follower_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.owner_id, p.title, p.artist_name, p.summary, p.cover_path, p.visibility, p.share_token,
         p.is_featured, p.created_at, p.updated_at,
         (select count(*) from public.tracks t where t.playlist_id = p.id),
         (select count(*) from public.playlist_views v where v.playlist_id = p.id),
         (select count(*) from public.playlist_follows f where f.playlist_id = p.id),
         exists(select 1 from public.playlist_follows f where f.playlist_id = p.id and f.user_id = auth.uid())
  from public.playlists p
  where lower(regexp_replace(btrim(p.artist_name), '\s+', ' ', 'g')) = lower(btrim(p_artist_key))
  order by p.updated_at desc
$$;

create or replace function public.track_comments_with_social(p_track_id uuid)
returns table (
  id uuid, track_id uuid, user_id uuid, body text, created_at timestamptz, updated_at timestamptz,
  display_name text, username text, avatar_path text, like_count bigint, is_liked boolean
)
language sql stable security invoker set search_path = '' as $$
  select c.id, c.track_id, c.user_id, c.body, c.created_at, c.updated_at,
         p.display_name, p.username, p.avatar_path,
         (select count(*) from public.comment_likes l where l.comment_id = c.id),
         exists(select 1 from public.comment_likes l where l.comment_id = c.id and l.user_id = auth.uid())
  from public.track_comments c join public.profiles p on p.id = c.user_id
  where c.track_id = p_track_id order by c.created_at desc
$$;

create or replace function public.track_social_summary(p_track_id uuid)
returns table (like_count bigint, comment_count bigint, is_liked boolean)
language sql stable security invoker set search_path = '' as $$
  select (select count(*) from public.track_likes l where l.track_id = p_track_id),
         (select count(*) from public.track_comments c where c.track_id = p_track_id),
         exists(select 1 from public.track_likes l where l.track_id = p_track_id and l.user_id = auth.uid())
$$;

grant select, insert, delete on public.user_follows, public.playlist_follows, public.artist_follows, public.track_likes, public.comment_likes to authenticated;
grant select, insert, update, delete on public.track_comments to authenticated;

revoke all on function public.toggle_user_follow(uuid) from public;
revoke all on function public.toggle_playlist_follow(uuid) from public;
revoke all on function public.toggle_artist_follow(text) from public;
revoke all on function public.toggle_track_like(uuid) from public;
revoke all on function public.toggle_comment_like(uuid) from public;
revoke all on function public.record_playlist_view(uuid) from public;
revoke all on function public.library_playlists_social(text) from public;
revoke all on function public.playlist_with_social(uuid) from public;
revoke all on function public.playlist_tracks_with_social(uuid) from public;
revoke all on function public.search_profiles(text, integer) from public;
revoke all on function public.profile_with_social(uuid) from public;
revoke all on function public.search_playlists(text, integer) from public;
revoke all on function public.search_artists(text, integer) from public;
revoke all on function public.artist_playlists(text) from public;
revoke all on function public.track_comments_with_social(uuid) from public;
revoke all on function public.track_social_summary(uuid) from public;

grant execute on function public.toggle_user_follow(uuid), public.toggle_playlist_follow(uuid), public.toggle_artist_follow(text),
  public.toggle_track_like(uuid), public.toggle_comment_like(uuid), public.record_playlist_view(uuid),
  public.library_playlists_social(text), public.playlist_with_social(uuid), public.playlist_tracks_with_social(uuid),
  public.search_profiles(text, integer), public.profile_with_social(uuid), public.search_playlists(text, integer),
  public.search_artists(text, integer), public.artist_playlists(text), public.track_comments_with_social(uuid),
  public.track_social_summary(uuid) to authenticated;

comment on table public.playlist_views is 'One row per viewer and playlist; view_count stores repeat opens while unique views use row count.';
comment on table public.track_comments is 'User comments attached to tracks and protected by playlist access policies.';

commit;
