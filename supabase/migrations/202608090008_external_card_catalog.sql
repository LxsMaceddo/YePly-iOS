-- YePly Cards 2.1: provider-independent official discography and stable rarity snapshots.
-- Catalog metadata comes from MusicBrainz, popularity from ListenBrainz, and artwork
-- links from the Cover Art Archive. Spotify is intentionally not used as a game data
-- source because its Developer Policy prohibits games and derived listenership metrics.

begin;

alter table public.collectible_artists
  add column if not exists catalog_source text not null default 'yeply',
  add column if not exists source_artist_id uuid,
  add column if not exists source_url text,
  add column if not exists last_catalog_sync_at timestamptz;

alter table public.collectible_albums
  add column if not exists catalog_source text not null default 'yeply',
  add column if not exists source_release_group_id uuid,
  add column if not exists source_release_id uuid,
  add column if not exists source_url text,
  add column if not exists release_date date;

alter table public.collectible_card_definitions
  alter column track_id drop not null,
  add column if not exists catalog_source text not null default 'yeply',
  add column if not exists source_recording_id uuid,
  add column if not exists source_url text,
  add column if not exists title text,
  add column if not exists artist_name text,
  add column if not exists album_name text,
  add column if not exists artwork_path text,
  add column if not exists duration_ms integer,
  add column if not exists disc_number smallint,
  add column if not exists track_number smallint,
  add column if not exists global_listen_count bigint not null default 0,
  add column if not exists global_listener_count bigint not null default 0,
  add column if not exists yeply_play_count bigint not null default 0,
  add column if not exists popularity_score numeric(6,3) not null default 0,
  add column if not exists rarity_version text not null default 'yeply-v1';

alter table public.card_instances
  add column if not exists rarity_at_mint public.card_rarity,
  add column if not exists popularity_score_at_mint numeric(6,3),
  add column if not exists rarity_version_at_mint text;

alter table public.collectible_artists drop constraint if exists collectible_artists_catalog_source_check;
alter table public.collectible_artists add constraint collectible_artists_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz'));
alter table public.collectible_albums drop constraint if exists collectible_albums_catalog_source_check;
alter table public.collectible_albums add constraint collectible_albums_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz'));
alter table public.collectible_card_definitions drop constraint if exists collectible_cards_catalog_source_check;
alter table public.collectible_card_definitions add constraint collectible_cards_catalog_source_check
  check (catalog_source in ('yeply', 'musicbrainz'));
alter table public.collectible_card_definitions drop constraint if exists collectible_cards_external_identity_check;
alter table public.collectible_card_definitions add constraint collectible_cards_external_identity_check
  check (track_id is not null or source_recording_id is not null);
alter table public.collectible_card_definitions drop constraint if exists collectible_cards_global_listens_check;
alter table public.collectible_card_definitions add constraint collectible_cards_global_listens_check
  check (global_listen_count >= 0 and global_listener_count >= 0 and yeply_play_count >= 0);

alter table public.collectible_card_definitions
  drop constraint if exists collectible_card_definitions_track_id_artist_id_key;

create unique index if not exists collectible_cards_yeply_track_unique
  on public.collectible_card_definitions(track_id, artist_id)
  where track_id is not null;
create unique index if not exists collectible_cards_external_recording_unique
  on public.collectible_card_definitions(artist_id, source_recording_id, album_id)
  where source_recording_id is not null;
create unique index if not exists collectible_artists_source_unique
  on public.collectible_artists(source_artist_id)
  where source_artist_id is not null;
create unique index if not exists collectible_albums_source_unique
  on public.collectible_albums(artist_id, source_release_group_id)
  where source_release_group_id is not null;

-- Preserve a self-contained display snapshot for the pre-existing YePly definitions.
update public.collectible_card_definitions d
set title = coalesce(d.title, t.title),
    artist_name = coalesce(d.artist_name, t.artist_name, a.display_name),
    album_name = coalesce(d.album_name, t.album_name, al.title, p.title),
    artwork_path = coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
    duration_ms = coalesce(d.duration_ms, round(t.duration_seconds * 1000)::integer),
    track_number = coalesce(d.track_number, nullif(t.position + 1, 0)::smallint),
    catalog_source = 'yeply'
from public.tracks t
join public.playlists p on p.id = t.playlist_id
join public.collectible_artists a on true
join public.collectible_albums al on al.artist_id = a.id
where d.track_id = t.id and d.artist_id = a.id and d.album_id = al.id;

update public.card_instances i
set rarity_at_mint = coalesce(i.rarity_at_mint, d.rarity),
    popularity_score_at_mint = coalesce(i.popularity_score_at_mint, d.popularity_score),
    rarity_version_at_mint = coalesce(i.rarity_version_at_mint, d.rarity_version)
from public.collectible_card_definitions d
where d.id = i.definition_id;

create or replace function public.card_rarity_from_percentile(p_percentile double precision)
returns public.card_rarity language sql immutable set search_path = '' as $$
  select case
    when coalesce(p_percentile, 0) >= 0.98 then 'mythic'::public.card_rarity
    when coalesce(p_percentile, 0) >= 0.92 then 'legendary'::public.card_rarity
    when coalesce(p_percentile, 0) >= 0.80 then 'epic'::public.card_rarity
    when coalesce(p_percentile, 0) >= 0.55 then 'rare'::public.card_rarity
    else 'common'::public.card_rarity
  end
$$;

create or replace function public.refresh_card_rarities_internal()
returns void language plpgsql security definer set search_path = '' as $$
begin
  with internal_plays as (
    select d.id, coalesce(sum(h.play_count), 0)::bigint as plays
    from public.collectible_card_definitions d
    left join public.playback_history h on h.track_id = d.track_id
    where d.is_enabled
    group by d.id
  ), raw_scores as (
    select d.id, d.artist_id,
           ip.plays,
           (
             ln(1 + greatest(d.global_listen_count, 0)) * 0.75
             + ln(1 + greatest(d.global_listener_count, 0)) * 0.20
             + ln(1 + greatest(ip.plays, 0)) * 0.05
           )::double precision as raw_score
    from public.collectible_card_definitions d
    join internal_plays ip on ip.id = d.id
    where d.is_enabled
  ), ranked as (
    select r.id, r.plays, (r.raw_score > 0) as has_signal,
           cume_dist() over (
             partition by r.artist_id
             order by r.raw_score, r.id
           )::double precision as popularity_percentile
    from raw_scores r
  )
  update public.collectible_card_definitions d
  set yeply_play_count = r.plays,
      play_count_snapshot = greatest(d.global_listen_count, r.plays),
      popularity_score = round((r.popularity_percentile * 100)::numeric, 3),
      rarity = coalesce(
        d.rarity_override,
        case when r.has_signal then public.card_rarity_from_percentile(r.popularity_percentile)
             else 'common'::public.card_rarity end
      ),
      drop_weight = case coalesce(
        d.rarity_override,
        case when r.has_signal then public.card_rarity_from_percentile(r.popularity_percentile)
             else 'common'::public.card_rarity end
      )
        when 'common'::public.card_rarity then 1000
        when 'rare'::public.card_rarity then 350
        when 'epic'::public.card_rarity then 110
        when 'legendary'::public.card_rarity then 30
        when 'mythic'::public.card_rarity then 8
      end,
      rarity_version = case
        when d.catalog_source = 'musicbrainz' then 'listenbrainz-v1:' || to_char(current_date, 'YYYY-MM')
        else 'yeply-v2:' || to_char(current_date, 'YYYY-MM')
      end,
      updated_at = now()
  from ranked r
  where r.id = d.id;
end;
$$;

-- Imports a validated metadata snapshot produced by the sync-card-catalog Edge Function.
-- Direct client writes remain forbidden; only an authenticated YePly administrator can call it.
create or replace function public.import_external_card_catalog(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_artist jsonb := p_payload -> 'artist';
  v_album jsonb;
  v_track jsonb;
  v_artist_id uuid;
  v_artist_mbid uuid;
  v_release_group_mbid uuid;
  v_release_mbid uuid;
  v_recording_mbid uuid;
  v_album_id uuid;
  v_artist_name text;
  v_artist_key text;
  v_album_count integer := 0;
  v_card_count integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(v_artist) <> 'object'
     or jsonb_typeof(p_payload -> 'albums') <> 'array'
     or jsonb_array_length(p_payload -> 'albums') not between 1 and 40 then
    raise exception 'invalid_catalog_payload' using errcode = '22023';
  end if;

  v_artist_mbid := nullif(v_artist ->> 'mbid', '')::uuid;
  v_artist_name := left(btrim(v_artist ->> 'name'), 180);
  v_artist_key := lower(regexp_replace(v_artist_name, '\s+', ' ', 'g'));
  if v_artist_mbid is null or v_artist_key = '' then
    raise exception 'invalid_catalog_artist' using errcode = '22023';
  end if;

  insert into public.collectible_artists(
    artist_key, display_name, catalog_source, source_artist_id, source_url,
    is_enabled, created_by, last_catalog_sync_at, updated_at
  ) values (
    v_artist_key, v_artist_name, 'musicbrainz', v_artist_mbid,
    'https://musicbrainz.org/artist/' || v_artist_mbid::text,
    true, auth.uid(), now(), now()
  )
  on conflict (artist_key) do update set
    display_name = excluded.display_name,
    catalog_source = excluded.catalog_source,
    source_artist_id = excluded.source_artist_id,
    source_url = excluded.source_url,
    is_enabled = true,
    last_catalog_sync_at = now(),
    updated_at = now()
  returning id into v_artist_id;

  -- A completed sync is authoritative for this artist. Old cards stay owned, while
  -- definitions absent from the official snapshot stop dropping from new packs.
  update public.collectible_card_definitions set is_enabled = false, updated_at = now()
  where artist_id = v_artist_id;
  update public.collectible_albums set is_enabled = false, updated_at = now()
  where artist_id = v_artist_id;

  for v_album in select value from jsonb_array_elements(p_payload -> 'albums') loop
    if jsonb_typeof(v_album -> 'tracks') <> 'array'
       or jsonb_array_length(v_album -> 'tracks') not between 1 and 80 then
      raise exception 'invalid_catalog_album' using errcode = '22023';
    end if;
    v_release_group_mbid := nullif(v_album ->> 'release_group_mbid', '')::uuid;
    v_release_mbid := nullif(v_album ->> 'release_mbid', '')::uuid;
    if v_release_group_mbid is null or v_release_mbid is null then
      raise exception 'invalid_catalog_release' using errcode = '22023';
    end if;

    insert into public.collectible_albums(
      artist_id, album_key, title, artwork_path, catalog_source,
      source_release_group_id, source_release_id, source_url, release_date,
      is_enabled, updated_at
    ) values (
      v_artist_id,
      lower(regexp_replace(left(btrim(v_album ->> 'title'), 180), '\s+', ' ', 'g')),
      left(btrim(v_album ->> 'title'), 180),
      nullif(v_album ->> 'artwork_url', ''),
      'musicbrainz', v_release_group_mbid, v_release_mbid,
      'https://musicbrainz.org/release-group/' || v_release_group_mbid::text,
      nullif(v_album ->> 'release_date', '')::date,
      true, now()
    )
    on conflict (artist_id, album_key) do update set
      title = excluded.title,
      artwork_path = excluded.artwork_path,
      catalog_source = excluded.catalog_source,
      source_release_group_id = excluded.source_release_group_id,
      source_release_id = excluded.source_release_id,
      source_url = excluded.source_url,
      release_date = excluded.release_date,
      is_enabled = true,
      updated_at = now()
    returning id into v_album_id;

    v_album_count := v_album_count + 1;
    for v_track in select value from jsonb_array_elements(v_album -> 'tracks') loop
      v_recording_mbid := nullif(v_track ->> 'recording_mbid', '')::uuid;
      if v_recording_mbid is null or btrim(coalesce(v_track ->> 'title', '')) = '' then
        raise exception 'invalid_catalog_recording' using errcode = '22023';
      end if;

      insert into public.collectible_card_definitions(
        track_id, artist_id, album_id, catalog_source, source_recording_id,
        source_url, title, artist_name, album_name, artwork_path, duration_ms,
        disc_number, track_number, global_listen_count, global_listener_count,
        is_enabled, updated_at
      ) values (
        null, v_artist_id, v_album_id, 'musicbrainz', v_recording_mbid,
        'https://musicbrainz.org/recording/' || v_recording_mbid::text,
        left(btrim(v_track ->> 'title'), 300),
        left(btrim(coalesce(nullif(v_track ->> 'artist_name', ''), v_artist_name)), 300),
        left(btrim(v_album ->> 'title'), 180),
        nullif(v_album ->> 'artwork_url', ''),
        greatest(0, least(coalesce((v_track ->> 'duration_ms')::integer, 0), 7200000)),
        greatest(1, least(coalesce((v_track ->> 'disc_number')::smallint, 1), 99)),
        greatest(1, least(coalesce((v_track ->> 'track_number')::smallint, 1), 999)),
        greatest(0, coalesce((v_track ->> 'global_listens')::bigint, 0)),
        greatest(0, coalesce((v_track ->> 'global_listeners')::bigint, 0)),
        true, now()
      )
      on conflict (artist_id, source_recording_id, album_id) where source_recording_id is not null
      do update set
        source_url = excluded.source_url,
        title = excluded.title,
        artist_name = excluded.artist_name,
        album_name = excluded.album_name,
        artwork_path = excluded.artwork_path,
        duration_ms = excluded.duration_ms,
        disc_number = excluded.disc_number,
        track_number = excluded.track_number,
        global_listen_count = excluded.global_listen_count,
        global_listener_count = excluded.global_listener_count,
        is_enabled = true,
        updated_at = now();
      v_card_count := v_card_count + 1;
    end loop;

    insert into public.card_badges(album_id, title, artwork_path)
    values (v_album_id, left(btrim(v_album ->> 'title'), 180), nullif(v_album ->> 'artwork_url', ''))
    on conflict (album_id) do update set
      title = excluded.title,
      artwork_path = excluded.artwork_path;
  end loop;

  perform public.refresh_card_rarities_internal();
  return jsonb_build_object(
    'success', true,
    'message', v_album_count || ' álbuns e ' || v_card_count || ' cartas oficiais sincronizados.',
    'artist_id', v_artist_id,
    'album_count', v_album_count,
    'card_count', v_card_count,
    'rarity_model', 'listenbrainz-v1'
  );
end;
$$;

create or replace function public.award_card_xp(p_user_id uuid, p_amount integer)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old_level integer; v_new_level integer; v_level integer;
begin
  if p_user_id is null or p_amount < 0 or p_amount > 10000 then
    raise exception 'invalid_xp_award' using errcode = '22023';
  end if;
  perform public.ensure_card_player(p_user_id);
  select s.level into v_old_level from public.card_player_stats s where s.user_id = p_user_id for update;
  v_new_level := public.card_level_for_xp((select s.xp + p_amount from public.card_player_stats s where s.user_id = p_user_id));
  update public.card_player_stats
  set xp = xp + p_amount, level = v_new_level, updated_at = now()
  where user_id = p_user_id;
  if v_new_level > v_old_level and exists (
    select 1 from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
    join public.collectible_albums al on al.id = d.album_id and al.is_enabled
    where d.is_enabled
  ) then
    for v_level in (v_old_level + 1)..v_new_level loop
      perform public.create_card_pack_internal(
        p_user_id, 'level', null, case when v_level % 5 = 0 then 5 else 3 end,
        'common'::public.card_rarity
      );
    end loop;
  end if;
end;
$$;

create or replace function public.create_card_pack_internal(
  p_owner_id uuid, p_source text, p_artist_id uuid default null,
  p_card_count integer default 3,
  p_rarity_floor public.card_rarity default 'common'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_pack_id uuid;
begin
  if p_owner_id is null or p_source not in ('listening', 'daily', 'code', 'achievement', 'level', 'admin')
     or p_card_count not between 1 and 5 then
    raise exception 'invalid_pack' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id
    join public.collectible_albums al on al.id = d.album_id
    where d.is_enabled and a.is_enabled and al.is_enabled
      and (p_artist_id is null or d.artist_id = p_artist_id)
      and public.card_rarity_rank(d.rarity) >= public.card_rarity_rank(p_rarity_floor)
  ) then
    raise exception 'empty_card_pool' using errcode = 'P0002';
  end if;
  insert into public.card_packs(owner_id, source, artist_id, rarity_floor, card_count)
  values (p_owner_id, p_source, p_artist_id, p_rarity_floor, p_card_count)
  returning id into v_pack_id;
  return v_pack_id;
end;
$$;

drop function if exists public.open_card_pack(uuid);
create function public.open_card_pack(p_pack_id uuid)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric
)
language plpgsql security definer set search_path = '' as $$
declare
  v_pack public.card_packs;
  v_definition_id uuid;
  v_instance_id uuid;
  v_serial bigint;
  v_acquired timestamptz;
  v_rarity public.card_rarity;
  v_score numeric;
  v_version text;
  v_counter integer;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_pack from public.card_packs p where p.id = p_pack_id for update;
  if v_pack.id is null or v_pack.owner_id <> auth.uid() then raise exception 'pack_not_found' using errcode = 'P0002'; end if;
  if v_pack.status <> 'sealed'::public.card_pack_status then raise exception 'pack_already_opened' using errcode = '55000'; end if;

  for v_counter in 1..v_pack.card_count loop
    select d.id, d.rarity, d.popularity_score, d.rarity_version
    into v_definition_id, v_rarity, v_score, v_version
    from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id
    join public.collectible_albums al on al.id = d.album_id
    where d.is_enabled and a.is_enabled and al.is_enabled
      and (v_pack.artist_id is null or d.artist_id = v_pack.artist_id)
      and public.card_rarity_rank(d.rarity) >= public.card_rarity_rank(v_pack.rarity_floor)
    order by (-ln(greatest(random(), 0.000000001)) / d.drop_weight), d.id
    limit 1;
    if v_definition_id is null then raise exception 'empty_card_pool' using errcode = 'P0002'; end if;

    insert into public.card_instances(
      definition_id, owner_id, source_pack_id, rarity_at_mint,
      popularity_score_at_mint, rarity_version_at_mint
    ) values (v_definition_id, auth.uid(), v_pack.id, v_rarity, v_score, v_version)
    returning id, card_instances.serial_number, card_instances.acquired_at
    into v_instance_id, v_serial, v_acquired;

    return query
    select v_instance_id, v_serial, d.id, d.track_id,
           coalesce(d.title, t.title),
           coalesce(d.artist_name, t.artist_name, a.display_name),
           coalesce(d.album_name, t.album_name, al.title, p.title),
           coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
           v_rarity, v_acquired, d.source_url, d.catalog_source,
           d.global_listen_count, d.global_listener_count, v_score
    from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id
    join public.collectible_albums al on al.id = d.album_id
    left join public.tracks t on t.id = d.track_id
    left join public.playlists p on p.id = t.playlist_id
    where d.id = v_definition_id;
  end loop;

  update public.card_packs set status = 'opened', opened_at = now() where id = v_pack.id;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
end;
$$;

drop function if exists public.card_inventory_feed();
create function public.card_inventory_feed()
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, d.track_id,
         coalesce(d.title, t.title),
         coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title, p.title),
         coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
         coalesce(i.rarity_at_mint, d.rarity), i.acquired_at, d.source_url,
         d.catalog_source, d.global_listen_count, d.global_listener_count,
         coalesce(i.popularity_score_at_mint, d.popularity_score)
  from public.card_instances i
  join public.collectible_card_definitions d on d.id = i.definition_id
  join public.collectible_artists a on a.id = d.artist_id
  join public.collectible_albums al on al.id = d.album_id
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  where i.owner_id = auth.uid()
  order by i.acquired_at desc, i.serial_number desc
$$;

drop function if exists public.card_tradeable_inventory(text);
create function public.card_tradeable_inventory(p_username text)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, d.track_id,
         coalesce(d.title, t.title),
         coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title, p.title),
         coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
         coalesce(i.rarity_at_mint, d.rarity), i.acquired_at, d.source_url,
         d.catalog_source, d.global_listen_count, d.global_listener_count,
         coalesce(i.popularity_score_at_mint, d.popularity_score)
  from public.profiles target
  join public.card_instances i on i.owner_id = target.id and i.locked_trade_id is null
  join public.collectible_card_definitions d on d.id = i.definition_id
  join public.collectible_artists a on a.id = d.artist_id
  join public.collectible_albums al on al.id = d.album_id
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  where auth.uid() is not null and target.username = lower(btrim(p_username))
  order by i.acquired_at desc, i.serial_number desc
$$;

create or replace function public.card_available_artists()
returns table(artist_key text, artist_name text, card_count bigint)
language sql stable security definer set search_path = '' as $$
  select a.artist_key, a.display_name, count(d.id)
  from public.collectible_artists a
  join public.collectible_card_definitions d on d.artist_id = a.id and d.is_enabled
  join public.collectible_albums al on al.id = d.album_id and al.is_enabled
  where a.is_enabled
  group by a.id
  order by a.display_name
$$;

create or replace function public.card_trade_feed()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.release_expired_card_trades();
  select jsonb_build_object('trades', coalesce(jsonb_agg(jsonb_build_object(
    'trade_id', t.id,
    'direction', case when t.recipient_id = auth.uid() then 'incoming' else 'outgoing' end,
    'status', t.status::text,
    'other_user_id', case when t.recipient_id = auth.uid() then t.proposer_id else t.recipient_id end,
    'other_username', other_profile.username,
    'other_display_name', other_profile.display_name,
    'created_at', t.created_at,
    'expires_at', t.expires_at,
    'responded_at', t.responded_at,
    'offered_instance_ids', (select coalesce(jsonb_agg(ti.card_instance_id order by ti.card_instance_id), '[]'::jsonb) from public.card_trade_items ti where ti.trade_id = t.id and ti.side = 'offered'),
    'requested_instance_ids', (select coalesce(jsonb_agg(ti.card_instance_id order by ti.card_instance_id), '[]'::jsonb) from public.card_trade_items ti where ti.trade_id = t.id and ti.side = 'requested'),
    'offered_titles', (select coalesce(jsonb_agg(coalesce(cd.title, track.title) order by ci.serial_number), '[]'::jsonb)
      from public.card_trade_items ti
      join public.card_instances ci on ci.id = ti.card_instance_id
      join public.collectible_card_definitions cd on cd.id = ci.definition_id
      left join public.tracks track on track.id = cd.track_id
      where ti.trade_id = t.id and ti.side = 'offered'),
    'requested_titles', (select coalesce(jsonb_agg(coalesce(cd.title, track.title) order by ci.serial_number), '[]'::jsonb)
      from public.card_trade_items ti
      join public.card_instances ci on ci.id = ti.card_instance_id
      join public.collectible_card_definitions cd on cd.id = ci.definition_id
      left join public.tracks track on track.id = cd.track_id
      where ti.trade_id = t.id and ti.side = 'requested')
  ) order by t.created_at desc), '[]'::jsonb)) into v_result
  from public.card_trades t
  join public.profiles other_profile on other_profile.id = case when t.recipient_id = auth.uid() then t.proposer_id else t.recipient_id end
  where t.proposer_id = auth.uid() or t.recipient_id = auth.uid();
  return v_result;
end;
$$;

create or replace function public.refresh_card_rarities()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  perform public.refresh_card_rarities_internal();
  return jsonb_build_object(
    'success', true,
    'message', 'Raridades recalculadas pelo modelo de percentis.',
    'card_count', (select count(*) from public.collectible_card_definitions where is_enabled),
    'rarity_model', 'listenbrainz-v1'
  );
end;
$$;

revoke all on function public.card_rarity_from_percentile(double precision),
  public.import_external_card_catalog(jsonb) from public, anon, authenticated;
grant execute on function public.import_external_card_catalog(jsonb) to authenticated;

revoke all on function public.open_card_pack(uuid), public.card_inventory_feed(),
  public.card_tradeable_inventory(text), public.card_available_artists(),
  public.card_trade_feed(), public.refresh_card_rarities() from public, anon;
grant execute on function public.open_card_pack(uuid), public.card_inventory_feed(),
  public.card_tradeable_inventory(text), public.card_available_artists(),
  public.card_trade_feed(), public.refresh_card_rarities() to authenticated;

comment on table public.collectible_card_definitions is
  'Provider-independent card catalog. External metadata is MusicBrainz/ListenBrainz; rarity is snapshotted on mint.';
comment on function public.import_external_card_catalog(jsonb) is
  'Admin-only import endpoint for a validated MusicBrainz/ListenBrainz snapshot.';

commit;
