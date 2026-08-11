-- YePly iOS 1.4: waveform player, timed comments, history, verification and notifications.

begin;

alter table public.tracks add column if not exists waveform_samples real[];
alter table public.track_comments add column if not exists timestamp_seconds double precision;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'track_comments_timestamp_valid') then
    alter table public.track_comments add constraint track_comments_timestamp_valid
      check (timestamp_seconds is null or timestamp_seconds >= 0);
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'tracks_waveform_size_valid') then
    alter table public.tracks add constraint tracks_waveform_size_valid
      check (waveform_samples is null or cardinality(waveform_samples) between 24 and 256);
  end if;
end $$;

create table if not exists public.artist_verifications (
  artist_key text primary key,
  artist_name text not null,
  verified_by uuid not null references public.profiles(id),
  verified_at timestamptz not null default now(),
  check (char_length(artist_key) between 1 and 180),
  check (char_length(artist_name) between 1 and 180)
);

create table if not exists public.playback_history (
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  first_played_at timestamptz not null default now(),
  last_played_at timestamptz not null default now(),
  play_count integer not null default 1 check (play_count > 0),
  last_position_seconds double precision not null default 0 check (last_position_seconds >= 0),
  primary key (user_id, track_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('new_follower', 'playlist_follow', 'track_like', 'track_comment')),
  playlist_id uuid references public.playlists(id) on delete cascade,
  track_id uuid references public.tracks(id) on delete cascade,
  comment_id uuid references public.track_comments(id) on delete cascade,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (recipient_id <> actor_id)
);

create index if not exists playback_history_recent_idx on public.playback_history(user_id, last_played_at desc);
create index if not exists notifications_recipient_recent_idx on public.notifications(recipient_id, created_at desc);
create index if not exists notifications_recipient_unread_idx on public.notifications(recipient_id, read_at) where read_at is null;
create index if not exists track_comments_timeline_idx on public.track_comments(track_id, timestamp_seconds) where timestamp_seconds is not null;

alter table public.artist_verifications enable row level security;
alter table public.playback_history enable row level security;
alter table public.notifications enable row level security;

drop policy if exists artist_verifications_read on public.artist_verifications;
create policy artist_verifications_read on public.artist_verifications for select to authenticated using (true);
drop policy if exists artist_verifications_admin_insert on public.artist_verifications;
create policy artist_verifications_admin_insert on public.artist_verifications for insert to authenticated with check (public.is_admin());
drop policy if exists artist_verifications_admin_delete on public.artist_verifications;
create policy artist_verifications_admin_delete on public.artist_verifications for delete to authenticated using (public.is_admin());

drop policy if exists playback_history_owner_read on public.playback_history;
create policy playback_history_owner_read on public.playback_history for select to authenticated using (user_id = auth.uid());
drop policy if exists playback_history_owner_insert on public.playback_history;
create policy playback_history_owner_insert on public.playback_history for insert to authenticated with check (user_id = auth.uid());
drop policy if exists playback_history_owner_update on public.playback_history;
create policy playback_history_owner_update on public.playback_history for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists playback_history_owner_delete on public.playback_history;
create policy playback_history_owner_delete on public.playback_history for delete to authenticated using (user_id = auth.uid());

drop policy if exists notifications_recipient_read on public.notifications;
create policy notifications_recipient_read on public.notifications for select to authenticated using (recipient_id = auth.uid());
drop policy if exists notifications_recipient_update on public.notifications;
create policy notifications_recipient_update on public.notifications for update to authenticated using (recipient_id = auth.uid()) with check (recipient_id = auth.uid());
drop policy if exists notifications_recipient_delete on public.notifications;
create policy notifications_recipient_delete on public.notifications for delete to authenticated using (recipient_id = auth.uid());

create or replace function public.toggle_artist_verification(p_artist_name text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_name text := left(btrim(p_artist_name), 180); v_key text;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  v_key := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
  if v_key = '' then raise exception 'invalid_artist' using errcode = '22023'; end if;
  if exists (select 1 from public.artist_verifications v where v.artist_key = v_key) then
    delete from public.artist_verifications where artist_key = v_key;
    return false;
  end if;
  insert into public.artist_verifications(artist_key, artist_name, verified_by) values (v_key, v_name, auth.uid());
  return true;
end; $$;

create or replace function public.validate_track_comment_timestamp()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_duration double precision;
begin
  if new.timestamp_seconds is null then return new; end if;
  select t.duration_seconds into v_duration from public.tracks t where t.id = new.track_id;
  if v_duration is null or new.timestamp_seconds < 0 or new.timestamp_seconds > v_duration then
    raise exception 'invalid_comment_timestamp' using errcode = '22023';
  end if;
  new.timestamp_seconds := round(new.timestamp_seconds::numeric, 1)::double precision;
  return new;
end; $$;

drop trigger if exists track_comments_validate_timestamp on public.track_comments;
create trigger track_comments_validate_timestamp before insert or update of timestamp_seconds, track_id on public.track_comments
for each row execute procedure public.validate_track_comment_timestamp();

create or replace function public.record_playback(p_track_id uuid, p_position_seconds double precision default 0)
returns void language plpgsql security definer set search_path = '' as $$
declare v_playlist_id uuid;
begin
  select t.playlist_id into v_playlist_id from public.tracks t where t.id = p_track_id;
  if auth.uid() is null or v_playlist_id is null or not public.can_read_playlist(v_playlist_id) then
    raise exception 'track_access_denied' using errcode = '42501';
  end if;
  insert into public.playback_history(user_id, track_id, last_position_seconds)
  values (auth.uid(), p_track_id, greatest(coalesce(p_position_seconds, 0), 0))
  on conflict (user_id, track_id) do update set
    last_played_at = now(),
    play_count = public.playback_history.play_count + 1,
    last_position_seconds = greatest(coalesce(excluded.last_position_seconds, 0), 0);
end; $$;

create or replace function public.clear_playback_history()
returns void language sql security invoker set search_path = '' as $$
  delete from public.playback_history where user_id = auth.uid()
$$;

create or replace function public.playback_history_feed(p_limit integer default 100)
returns table (
  track_id uuid, playlist_id uuid, uploader_id uuid, title text, artist_name text, album_name text,
  duration_seconds double precision, audio_path text, artwork_path text, "position" integer,
  file_size_bytes bigint, track_created_at timestamptz, waveform_samples real[],
  playlist_title text, playlist_cover_path text, last_played_at timestamptz, play_count integer
)
language sql stable security invoker set search_path = '' as $$
  select t.id, t.playlist_id, t.uploader_id, t.title, t.artist_name, t.album_name,
         t.duration_seconds, t.audio_path, t.artwork_path, t.position, t.file_size_bytes, t.created_at,
         t.waveform_samples, p.title, p.cover_path, h.last_played_at, h.play_count
  from public.playback_history h
  join public.tracks t on t.id = h.track_id
  join public.playlists p on p.id = t.playlist_id
  where h.user_id = auth.uid()
  order by h.last_played_at desc
  limit least(greatest(p_limit, 1), 250)
$$;

create or replace function public.search_artists_v2(p_query text default '', p_limit integer default 30)
returns table (artist_key text, artist_name text, playlist_count bigint, track_count bigint, follower_count bigint, is_followed boolean, is_verified boolean)
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
         exists(select 1 from public.artist_follows f where f.artist_key = n.key and f.user_id = auth.uid()),
         exists(select 1 from public.artist_verifications v where v.artist_key = n.key)
  from normalized n
  where btrim(p_query) = '' or n.display_name ilike '%' || btrim(p_query) || '%'
  order by 5 desc, n.display_name
  limit least(greatest(p_limit, 1), 50)
$$;

create or replace function public.playlist_tracks_v2(p_playlist_id uuid)
returns table (
  id uuid, playlist_id uuid, uploader_id uuid, title text, artist_name text, album_name text,
  duration_seconds double precision, audio_path text, artwork_path text, "position" integer,
  file_size_bytes bigint, created_at timestamptz, waveform_samples real[],
  like_count bigint, comment_count bigint, is_liked boolean
)
language sql stable security invoker set search_path = '' as $$
  select t.id, t.playlist_id, t.uploader_id, t.title, t.artist_name, t.album_name,
         t.duration_seconds, t.audio_path, t.artwork_path, t.position, t.file_size_bytes, t.created_at,
         t.waveform_samples,
         (select count(*) from public.track_likes l where l.track_id = t.id),
         (select count(*) from public.track_comments c where c.track_id = t.id),
         exists(select 1 from public.track_likes l where l.track_id = t.id and l.user_id = auth.uid())
  from public.tracks t where t.playlist_id = p_playlist_id order by t.position
$$;

create or replace function public.track_comments_with_timestamps(p_track_id uuid)
returns table (
  id uuid, track_id uuid, user_id uuid, body text, timestamp_seconds double precision,
  created_at timestamptz, updated_at timestamptz, display_name text, username text,
  avatar_path text, like_count bigint, is_liked boolean
)
language sql stable security invoker set search_path = '' as $$
  select c.id, c.track_id, c.user_id, c.body, c.timestamp_seconds, c.created_at, c.updated_at,
         p.display_name, p.username, p.avatar_path,
         (select count(*) from public.comment_likes l where l.comment_id = c.id),
         exists(select 1 from public.comment_likes l where l.comment_id = c.id and l.user_id = auth.uid())
  from public.track_comments c join public.profiles p on p.id = c.user_id
  where c.track_id = p_track_id order by c.created_at desc
$$;

create or replace function public.create_social_notification()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_recipient uuid; v_actor uuid; v_kind text; v_playlist uuid; v_track uuid; v_comment uuid;
begin
  if tg_table_name = 'user_follows' then
    v_recipient := new.followed_user_id; v_actor := new.follower_id; v_kind := 'new_follower';
  elsif tg_table_name = 'playlist_follows' then
    select p.owner_id into v_recipient from public.playlists p where p.id = new.playlist_id;
    v_actor := new.user_id; v_kind := 'playlist_follow'; v_playlist := new.playlist_id;
  elsif tg_table_name = 'track_likes' then
    select t.uploader_id, t.playlist_id into v_recipient, v_playlist from public.tracks t where t.id = new.track_id;
    v_actor := new.user_id; v_kind := 'track_like'; v_track := new.track_id;
  elsif tg_table_name = 'track_comments' then
    select t.uploader_id, t.playlist_id into v_recipient, v_playlist from public.tracks t where t.id = new.track_id;
    v_actor := new.user_id; v_kind := 'track_comment'; v_track := new.track_id; v_comment := new.id;
  end if;
  if v_recipient is not null and v_actor is not null and v_recipient <> v_actor then
    insert into public.notifications(recipient_id, actor_id, kind, playlist_id, track_id, comment_id)
    values (v_recipient, v_actor, v_kind, v_playlist, v_track, v_comment);
  end if;
  return new;
end; $$;

drop trigger if exists user_follows_notify on public.user_follows;
create trigger user_follows_notify after insert on public.user_follows for each row execute procedure public.create_social_notification();
drop trigger if exists playlist_follows_notify on public.playlist_follows;
create trigger playlist_follows_notify after insert on public.playlist_follows for each row execute procedure public.create_social_notification();
drop trigger if exists track_likes_notify on public.track_likes;
create trigger track_likes_notify after insert on public.track_likes for each row execute procedure public.create_social_notification();
drop trigger if exists track_comments_notify on public.track_comments;
create trigger track_comments_notify after insert on public.track_comments for each row execute procedure public.create_social_notification();

create or replace function public.notifications_feed(p_limit integer default 60)
returns table (
  id uuid, kind text, actor_id uuid, actor_display_name text, actor_username text, actor_avatar_path text,
  playlist_id uuid, playlist_title text, track_id uuid, track_title text, comment_id uuid,
  created_at timestamptz, read_at timestamptz
)
language sql stable security invoker set search_path = '' as $$
  select n.id, n.kind, n.actor_id, a.display_name, a.username, a.avatar_path,
         n.playlist_id, p.title, n.track_id, t.title, n.comment_id, n.created_at, n.read_at
  from public.notifications n
  join public.profiles a on a.id = n.actor_id
  left join public.playlists p on p.id = n.playlist_id
  left join public.tracks t on t.id = n.track_id
  where n.recipient_id = auth.uid()
  order by n.created_at desc
  limit least(greatest(p_limit, 1), 100)
$$;

create or replace function public.mark_all_notifications_read()
returns void language sql security invoker set search_path = '' as $$
  update public.notifications set read_at = now() where recipient_id = auth.uid() and read_at is null
$$;

grant select on public.artist_verifications, public.playback_history, public.notifications to authenticated;
grant insert, update, delete on public.playback_history to authenticated;
grant update, delete on public.notifications to authenticated;

revoke all on function public.toggle_artist_verification(text) from public;
revoke all on function public.validate_track_comment_timestamp() from public;
revoke all on function public.record_playback(uuid, double precision) from public;
revoke all on function public.clear_playback_history() from public;
revoke all on function public.playback_history_feed(integer) from public;
revoke all on function public.search_artists_v2(text, integer) from public;
revoke all on function public.playlist_tracks_v2(uuid) from public;
revoke all on function public.track_comments_with_timestamps(uuid) from public;
revoke all on function public.create_social_notification() from public;
revoke all on function public.notifications_feed(integer) from public;
revoke all on function public.mark_all_notifications_read() from public;

grant execute on function public.record_playback(uuid, double precision), public.clear_playback_history(),
  public.playback_history_feed(integer), public.search_artists_v2(text, integer), public.playlist_tracks_v2(uuid),
  public.track_comments_with_timestamps(uuid), public.notifications_feed(integer), public.mark_all_notifications_read() to authenticated;
grant execute on function public.toggle_artist_verification(text) to authenticated;

comment on table public.playback_history is 'Private per-user listening history with latest position and play count.';
comment on table public.artist_verifications is 'Admin-managed verified artist identities.';
comment on table public.notifications is 'In-app social notifications generated by trusted database triggers.';

commit;
