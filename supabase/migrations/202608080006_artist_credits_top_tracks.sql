begin;

create index if not exists playback_history_track_popularity_idx
  on public.playback_history(track_id);

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
    play_count = case
      when public.playback_history.last_played_at <= now() - interval '30 seconds'
        then public.playback_history.play_count + 1
      else public.playback_history.play_count
    end,
    last_position_seconds = greatest(coalesce(excluded.last_position_seconds, 0), 0);
end; $$;

create or replace function public.search_artists_v2(p_query text default '', p_limit integer default 30)
returns table (
  artist_key text, artist_name text, playlist_count bigint, track_count bigint,
  follower_count bigint, is_followed boolean, is_verified boolean
)
language sql stable security invoker set search_path = '' as $$
  with credits as (
    select btrim(credit.name) as name
    from public.playlists p
    cross join lateral regexp_split_to_table(p.artist_name, '\s*,\s*') as credit(name)
    union all
    select btrim(credit.name) as name
    from public.tracks t
    cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') as credit(name)
  ), normalized as (
    select lower(regexp_replace(name, '\s+', ' ', 'g')) as key, min(name) as display_name
    from credits
    where name <> ''
    group by lower(regexp_replace(name, '\s+', ' ', 'g'))
  )
  select n.key, n.display_name,
         (
           select count(*)
           from public.playlists p
           where exists (
             select 1
             from regexp_split_to_table(p.artist_name, '\s*,\s*') as credit(name)
             where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = n.key
           ) or exists (
             select 1
             from public.tracks t
             where t.playlist_id = p.id
               and exists (
                 select 1
                 from regexp_split_to_table(t.artist_name, '\s*,\s*') as credit(name)
                 where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = n.key
               )
           )
         ),
         (
           select count(*)
           from public.tracks t
           where exists (
             select 1
             from regexp_split_to_table(t.artist_name, '\s*,\s*') as credit(name)
             where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = n.key
           )
         ),
         (select count(*) from public.artist_follows f where f.artist_key = n.key),
         exists(select 1 from public.artist_follows f where f.artist_key = n.key and f.user_id = auth.uid()),
         exists(select 1 from public.artist_verifications v where v.artist_key = n.key)
  from normalized n
  where btrim(p_query) = '' or n.display_name ilike '%' || btrim(p_query) || '%'
  order by 5 desc, 4 desc, n.display_name
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
  where exists (
    select 1
    from regexp_split_to_table(p.artist_name, '\s*,\s*') as credit(name)
    where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g'))
  ) or exists (
    select 1
    from public.tracks t
    where t.playlist_id = p.id
      and exists (
        select 1
        from regexp_split_to_table(t.artist_name, '\s*,\s*') as credit(name)
        where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g'))
      )
  )
  order by p.updated_at desc
$$;

create or replace function public.top_public_tracks(p_limit integer default 25)
returns table (
  track_id uuid, playlist_id uuid, uploader_id uuid, title text, artist_name text, album_name text,
  duration_seconds double precision, audio_path text, artwork_path text, "position" integer,
  file_size_bytes bigint, track_created_at timestamptz, waveform_samples real[],
  playlist_title text, playlist_cover_path text, play_count bigint
)
language sql stable security definer set search_path = '' as $$
  select t.id, t.playlist_id, t.uploader_id, t.title, t.artist_name, t.album_name,
         t.duration_seconds, t.audio_path, t.artwork_path, t.position, t.file_size_bytes, t.created_at,
         t.waveform_samples, p.title, p.cover_path,
         coalesce((select sum(h.play_count) from public.playback_history h where h.track_id = t.id), 0::bigint)
  from public.tracks t
  join public.playlists p on p.id = t.playlist_id
  where p.visibility = 'public'::public.playlist_visibility
    and exists (select 1 from public.playback_history h where h.track_id = t.id)
  order by 16 desc,
           (select max(h.last_played_at) from public.playback_history h where h.track_id = t.id) desc nulls last,
           t.created_at desc
  limit least(greatest(p_limit, 1), 100)
$$;

revoke all on function public.top_public_tracks(integer) from public;
grant execute on function public.top_public_tracks(integer) to authenticated;

comment on function public.top_public_tracks(integer) is
  'Aggregated playback ranking containing tracks from public playlists only; no listener identity is exposed.';

commit;
