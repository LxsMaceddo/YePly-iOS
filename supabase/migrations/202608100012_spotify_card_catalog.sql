-- YePly Cards 2.4: Spotify-native discography import and signal-safe rarity.
--
-- Spotify is the source of the canonical album/track catalogue. Spotify removed
-- the public popularity fields in 2026, so rarity is deliberately calculated
-- from ListenBrainz, Apple Music chart placement and YePly playback. All rarity
-- comparisons are relative to the same artist and tracks without a real signal
-- always remain common.

begin;

alter table public.collectible_albums
  add column if not exists spotify_album_id text;

alter table public.collectible_card_definitions
  add column if not exists spotify_track_id text,
  add column if not exists spotify_isrc text;

alter table public.collectible_albums
  drop constraint if exists collectible_albums_spotify_id_check;
alter table public.collectible_albums
  add constraint collectible_albums_spotify_id_check check (
    spotify_album_id is null or spotify_album_id ~ '^[A-Za-z0-9]{22}$'
  );

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_spotify_track_id_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_spotify_track_id_check check (
    spotify_track_id is null or spotify_track_id ~ '^[A-Za-z0-9]{22}$'
  );
alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_spotify_isrc_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_spotify_isrc_check check (
    spotify_isrc is null or spotify_isrc ~ '^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$'
  );

alter table public.collectible_artists drop constraint if exists collectible_artists_catalog_source_check;
alter table public.collectible_artists add constraint collectible_artists_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz', 'spotify'));
alter table public.collectible_albums drop constraint if exists collectible_albums_catalog_source_check;
alter table public.collectible_albums add constraint collectible_albums_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz', 'spotify'));
alter table public.collectible_card_definitions drop constraint if exists collectible_cards_catalog_source_check;
alter table public.collectible_card_definitions add constraint collectible_cards_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz', 'spotify'));

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_external_identity_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_external_identity_check check (
    track_id is not null or source_recording_id is not null or spotify_track_id is not null
  );

create unique index if not exists collectible_albums_spotify_unique
  on public.collectible_albums(artist_id, spotify_album_id)
  where spotify_album_id is not null;
create unique index if not exists collectible_cards_spotify_unique
  on public.collectible_card_definitions(artist_id, album_id, spotify_track_id)
  where spotify_track_id is not null;

create or replace function public.refresh_card_rarities_internal()
returns void language plpgsql security definer set search_path = '' as $$
begin
  with internal_plays as (
    select d.id, coalesce(sum(h.play_count), 0)::bigint as plays
    from public.collectible_card_definitions d
    left join public.playback_history h on h.track_id = d.track_id
    where d.is_enabled
    group by d.id
  ), metrics as (
    select d.id, d.artist_id, ip.plays, d.apple_music_rank,
      greatest(d.global_listen_count, 0)::double precision as listens,
      greatest(d.global_listener_count, 0)::double precision as listeners,
      max(greatest(d.global_listen_count, 0)) over (partition by d.artist_id)::double precision as max_listens,
      max(greatest(d.global_listener_count, 0)) over (partition by d.artist_id)::double precision as max_listeners,
      max(greatest(ip.plays, 0)) over (partition by d.artist_id)::double precision as max_yeply_plays,
      count(*) over (partition by d.artist_id)::integer as catalog_size
    from public.collectible_card_definitions d
    join internal_plays ip on ip.id = d.id
    where d.is_enabled
  ), scored as (
    select m.*,
      case when m.max_listens > 0 then ln(1 + m.listens) / ln(1 + m.max_listens) else 0 end as listen_strength,
      case when m.max_listeners > 0 then ln(1 + m.listeners) / ln(1 + m.max_listeners) else 0 end as listener_strength,
      case when m.apple_music_rank is not null
        then greatest(0::double precision, 1 - ((m.apple_music_rank - 1)::double precision / 99))
        else 0 end as apple_strength,
      case when m.max_yeply_plays > 0 then ln(1 + m.plays) / ln(1 + m.max_yeply_plays) else 0 end as yeply_strength,
      case when m.max_listens > 0 then least(1::double precision, m.listens / m.max_listens) else 0 end as listen_ratio,
      (m.listens > 0 or m.listeners > 0 or m.apple_music_rank is not null or m.plays > 0) as has_signal
    from metrics m
  ), composite as (
    select s.*,
      (s.listen_strength * 0.50
       + s.listener_strength * 0.15
       + s.apple_strength * 0.30
       + s.yeply_strength * 0.05)::double precision as composite_score
    from scored s
  ), signal_ranked as (
    select c.id,
      cume_dist() over (partition by c.artist_id order by c.composite_score)::double precision as artist_percentile,
      rank() over (partition by c.artist_id order by c.composite_score desc, c.id)::integer as artist_rank,
      count(*) over (partition by c.artist_id)::integer as signal_count
    from composite c
    where c.has_signal
  ), classified as (
    select c.*, coalesce(sr.artist_percentile, 0) as artist_percentile,
      sr.artist_rank, coalesce(sr.signal_count, 0) as signal_count,
      case
        when not c.has_signal then 'common'::public.card_rarity
        when sr.signal_count >= 12
         and sr.artist_percentile >= 0.93
         and (coalesce(c.apple_music_rank, 999) <= 10 or c.listen_ratio >= 0.08 or c.listeners >= 1000)
          then 'mythic'::public.card_rarity
        when sr.signal_count >= 4 and sr.artist_percentile >= 0.62
          then 'epic'::public.card_rarity
        else 'common'::public.card_rarity
      end as calculated_rarity
    from composite c
    left join signal_ranked sr on sr.id = c.id
  )
  update public.collectible_card_definitions d
  set yeply_play_count = c.plays,
      play_count_snapshot = greatest(d.global_listen_count, c.plays),
      popularity_score = round((c.artist_percentile * 100)::numeric, 3),
      popularity_ratio = round(c.listen_ratio::numeric, 6),
      artist_popularity_rank = c.artist_rank,
      artist_catalog_size = c.catalog_size,
      rarity = coalesce(
        case when d.rarity_override = 'rare' then 'common'::public.card_rarity
             when d.rarity_override = 'legendary' then 'epic'::public.card_rarity
             else d.rarity_override end,
        c.calculated_rarity
      ),
      drop_weight = case coalesce(
        case when d.rarity_override = 'rare' then 'common'::public.card_rarity
             when d.rarity_override = 'legendary' then 'epic'::public.card_rarity
             else d.rarity_override end,
        c.calculated_rarity
      )
        when 'common'::public.card_rarity then 1000
        when 'rare'::public.card_rarity then 1000
        when 'epic'::public.card_rarity then 125
        when 'legendary'::public.card_rarity then 125
        when 'mythic'::public.card_rarity then 10
      end,
      rarity_version = 'relative-signals-v5:' || to_char(current_date, 'YYYY-MM'),
      updated_at = now()
  from classified c
  where c.id = d.id;
end;
$$;

create or replace function public.import_spotify_card_catalog(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_artist jsonb := p_payload -> 'artist';
  v_album jsonb;
  v_track jsonb;
  v_artist_id uuid;
  v_album_id uuid;
  v_definition_id uuid;
  v_artist_mbid uuid;
  v_recording_mbid uuid;
  v_artist_name text;
  v_artist_key text;
  v_spotify_artist_id text;
  v_spotify_album_id text;
  v_spotify_track_id text;
  v_album_key text;
  v_album_count integer := 0;
  v_card_count integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(v_artist) <> 'object'
     or jsonb_typeof(p_payload -> 'albums') <> 'array'
     or jsonb_array_length(p_payload -> 'albums') not between 1 and 60 then
    raise exception 'invalid_spotify_catalog_payload' using errcode = '22023';
  end if;

  v_artist_name := left(btrim(v_artist ->> 'name'), 180);
  v_artist_key := lower(regexp_replace(v_artist_name, '\s+', ' ', 'g'));
  v_spotify_artist_id := btrim(v_artist ->> 'spotify_id');
  v_artist_mbid := nullif(v_artist ->> 'musicbrainz_id', '')::uuid;
  if v_artist_key = '' or v_spotify_artist_id !~ '^[A-Za-z0-9]{22}$' then
    raise exception 'invalid_spotify_artist' using errcode = '22023';
  end if;

  insert into public.collectible_artists(
    artist_key, display_name, artwork_path, catalog_source, source_artist_id,
    source_url, spotify_artist_id, spotify_url, is_enabled, created_by,
    last_catalog_sync_at, updated_at
  ) values (
    v_artist_key, v_artist_name, nullif(v_artist ->> 'artwork_url', ''), 'spotify',
    v_artist_mbid, 'https://open.spotify.com/artist/' || v_spotify_artist_id,
    v_spotify_artist_id, 'https://open.spotify.com/artist/' || v_spotify_artist_id,
    true, auth.uid(), now(), now()
  )
  on conflict (artist_key) do update set
    display_name = excluded.display_name,
    artwork_path = coalesce(excluded.artwork_path, public.collectible_artists.artwork_path),
    catalog_source = 'spotify',
    source_artist_id = coalesce(excluded.source_artist_id, public.collectible_artists.source_artist_id),
    source_url = excluded.source_url,
    spotify_artist_id = excluded.spotify_artist_id,
    spotify_url = excluded.spotify_url,
    is_enabled = true,
    last_catalog_sync_at = now(),
    updated_at = now()
  returning id into v_artist_id;

  -- A successful Spotify snapshot is authoritative. Stale definitions remain in
  -- existing inventories, but they cannot drop from new packs.
  update public.collectible_card_definitions
  set is_enabled = false, updated_at = now()
  where artist_id = v_artist_id;
  update public.collectible_albums
  set is_enabled = false, updated_at = now()
  where artist_id = v_artist_id;

  for v_album in select value from jsonb_array_elements(p_payload -> 'albums') loop
    if jsonb_typeof(v_album -> 'tracks') <> 'array'
       or jsonb_array_length(v_album -> 'tracks') not between 1 and 100 then
      raise exception 'invalid_spotify_album' using errcode = '22023';
    end if;
    v_spotify_album_id := btrim(v_album ->> 'spotify_album_id');
    v_album_key := lower(regexp_replace(left(btrim(v_album ->> 'title'), 180), '\s+', ' ', 'g'));
    if v_spotify_album_id !~ '^[A-Za-z0-9]{22}$' or v_album_key = '' then
      raise exception 'invalid_spotify_album_identity' using errcode = '22023';
    end if;

    insert into public.collectible_albums(
      artist_id, album_key, title, artwork_path, catalog_source,
      source_release_group_id, source_url, release_date, spotify_album_id,
      is_enabled, updated_at
    ) values (
      v_artist_id, v_album_key, left(btrim(v_album ->> 'title'), 180),
      nullif(v_album ->> 'artwork_url', ''), 'spotify',
      nullif(v_album ->> 'musicbrainz_release_group_id', '')::uuid,
      'https://open.spotify.com/album/' || v_spotify_album_id,
      nullif(v_album ->> 'release_date', '')::date,
      v_spotify_album_id, true, now()
    )
    on conflict (artist_id, album_key) do update set
      title = excluded.title,
      artwork_path = excluded.artwork_path,
      catalog_source = 'spotify',
      source_release_group_id = coalesce(excluded.source_release_group_id, public.collectible_albums.source_release_group_id),
      source_url = excluded.source_url,
      release_date = excluded.release_date,
      spotify_album_id = excluded.spotify_album_id,
      is_enabled = true,
      updated_at = now()
    returning id into v_album_id;

    v_album_count := v_album_count + 1;
    for v_track in select value from jsonb_array_elements(v_album -> 'tracks') loop
      v_spotify_track_id := btrim(v_track ->> 'spotify_track_id');
      v_recording_mbid := nullif(v_track ->> 'musicbrainz_recording_id', '')::uuid;
      if v_spotify_track_id !~ '^[A-Za-z0-9]{22}$'
         or btrim(coalesce(v_track ->> 'title', '')) = '' then
        raise exception 'invalid_spotify_track' using errcode = '22023';
      end if;

      select d.id into v_definition_id
      from public.collectible_card_definitions d
      where d.artist_id = v_artist_id and d.album_id = v_album_id
        and (
          d.spotify_track_id = v_spotify_track_id
          or (v_recording_mbid is not null and d.source_recording_id = v_recording_mbid)
          or (
            lower(regexp_replace(btrim(coalesce(d.title, '')), '\s+', ' ', 'g')) =
              lower(regexp_replace(btrim(v_track ->> 'title'), '\s+', ' ', 'g'))
            and coalesce(d.disc_number, 1) = greatest(1, least(coalesce((v_track ->> 'disc_number')::smallint, 1), 99))
            and coalesce(d.track_number, 1) = greatest(1, least(coalesce((v_track ->> 'track_number')::smallint, 1), 999))
          )
        )
      order by (d.spotify_track_id = v_spotify_track_id) desc, d.created_at
      limit 1;

      if v_definition_id is null then
        insert into public.collectible_card_definitions(
          track_id, artist_id, album_id, catalog_source, source_recording_id,
          source_url, spotify_track_id, spotify_isrc, title, artist_name,
          album_name, artwork_path, duration_ms, disc_number, track_number,
          global_listen_count, global_listener_count, apple_music_id,
          apple_music_url, apple_music_rank, is_enabled, updated_at
        ) values (
          null, v_artist_id, v_album_id, 'spotify', v_recording_mbid,
          'https://open.spotify.com/track/' || v_spotify_track_id,
          v_spotify_track_id, nullif(upper(v_track ->> 'isrc'), ''),
          left(btrim(v_track ->> 'title'), 300),
          left(btrim(coalesce(nullif(v_track ->> 'artist_name', ''), v_artist_name)), 300),
          left(btrim(v_album ->> 'title'), 180), nullif(v_album ->> 'artwork_url', ''),
          greatest(0, least(coalesce((v_track ->> 'duration_ms')::integer, 0), 7200000)),
          greatest(1, least(coalesce((v_track ->> 'disc_number')::smallint, 1), 99)),
          greatest(1, least(coalesce((v_track ->> 'track_number')::smallint, 1), 999)),
          greatest(0, coalesce((v_track ->> 'global_listens')::bigint, 0)),
          greatest(0, coalesce((v_track ->> 'global_listeners')::bigint, 0)),
          nullif(v_track ->> 'apple_music_id', ''), nullif(v_track ->> 'apple_music_url', ''),
          nullif(v_track ->> 'apple_music_rank', '')::integer, true, now()
        );
      else
        update public.collectible_card_definitions d
        set catalog_source = 'spotify',
            source_recording_id = coalesce(v_recording_mbid, d.source_recording_id),
            source_url = 'https://open.spotify.com/track/' || v_spotify_track_id,
            spotify_track_id = v_spotify_track_id,
            spotify_isrc = coalesce(nullif(upper(v_track ->> 'isrc'), ''), d.spotify_isrc),
            title = left(btrim(v_track ->> 'title'), 300),
            artist_name = left(btrim(coalesce(nullif(v_track ->> 'artist_name', ''), v_artist_name)), 300),
            album_name = left(btrim(v_album ->> 'title'), 180),
            artwork_path = nullif(v_album ->> 'artwork_url', ''),
            duration_ms = greatest(0, least(coalesce((v_track ->> 'duration_ms')::integer, 0), 7200000)),
            disc_number = greatest(1, least(coalesce((v_track ->> 'disc_number')::smallint, 1), 99)),
            track_number = greatest(1, least(coalesce((v_track ->> 'track_number')::smallint, 1), 999)),
            global_listen_count = greatest(0, coalesce((v_track ->> 'global_listens')::bigint, 0)),
            global_listener_count = greatest(0, coalesce((v_track ->> 'global_listeners')::bigint, 0)),
            apple_music_id = coalesce(nullif(v_track ->> 'apple_music_id', ''), d.apple_music_id),
            apple_music_url = coalesce(nullif(v_track ->> 'apple_music_url', ''), d.apple_music_url),
            apple_music_rank = coalesce(nullif(v_track ->> 'apple_music_rank', '')::integer, d.apple_music_rank),
            is_enabled = true,
            updated_at = now()
        where d.id = v_definition_id;
      end if;
      v_card_count := v_card_count + 1;
      v_definition_id := null;
    end loop;

    insert into public.card_badges(album_id, title, artwork_path)
    values (v_album_id, left(btrim(v_album ->> 'title'), 180), nullif(v_album ->> 'artwork_url', ''))
    on conflict (album_id) do update set
      title = excluded.title,
      artwork_path = excluded.artwork_path;
  end loop;

  perform public.refresh_card_rarities_internal();
  update public.card_instances i
  set rarity_at_mint = d.rarity,
      popularity_score_at_mint = d.popularity_score,
      rarity_version_at_mint = d.rarity_version
  from public.collectible_card_definitions d
  where d.id = i.definition_id and d.artist_id = v_artist_id;

  return jsonb_build_object(
    'success', true,
    'message', v_album_count || ' álbuns e ' || v_card_count || ' cartas do Spotify sincronizados.',
    'artist_id', v_artist_id,
    'album_count', v_album_count,
    'card_count', v_card_count,
    'rarity_model', 'relative-signals-v5'
  );
end;
$$;

drop function if exists public.card_album_catalog_feed();
create function public.card_album_catalog_feed()
returns table (
  definition_id uuid, album_id uuid, album_title text, artist_key text, artist_name text,
  artwork_path text, disc_number integer, track_number integer, title text,
  rarity public.card_rarity, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer,
  owned_count bigint, owned_instance_id uuid
)
language sql stable security definer set search_path = '' as $$
  select d.id, al.id, al.title, a.artist_key, a.display_name,
         coalesce(d.artwork_path, al.artwork_path, p.cover_path),
         coalesce(d.disc_number::integer, 1),
         coalesce(d.track_number::integer, t.position + 1, 1),
         coalesce(d.title, t.title), d.rarity, d.global_listen_count,
         d.global_listener_count, d.popularity_score, d.artist_popularity_rank,
         d.artist_catalog_size, count(i.id),
         (array_agg(i.id order by i.acquired_at desc) filter (where i.id is not null))[1]
  from public.collectible_card_definitions d
  join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id = d.album_id and al.is_enabled
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  left join public.card_instances i on i.definition_id = d.id and i.owner_id = auth.uid()
  where auth.uid() is not null and d.is_enabled
  group by d.id, al.id, a.id, p.cover_path, t.position, t.title
  order by a.display_name, al.release_date nulls last, al.title,
           coalesce(d.disc_number, 1), coalesce(d.track_number, 1), coalesce(d.title, t.title)
$$;

revoke all on function public.import_spotify_card_catalog(jsonb) from public, anon;
grant execute on function public.import_spotify_card_catalog(jsonb) to authenticated;
revoke all on function public.card_album_catalog_feed() from public, anon;
grant execute on function public.card_album_catalog_feed() to authenticated;

comment on column public.collectible_albums.spotify_album_id is
  'Canonical Spotify album identifier imported by the admin catalogue synchronizer.';
comment on column public.collectible_card_definitions.spotify_track_id is
  'Canonical Spotify track identifier; never contains or grants access to audio.';
comment on function public.import_spotify_card_catalog(jsonb) is
  'Admin-only atomic import of Spotify metadata enriched by independent popularity signals.';
comment on function public.card_album_catalog_feed() is
  'Complete ordered album catalogue plus the authenticated collector ownership state.';

commit;
