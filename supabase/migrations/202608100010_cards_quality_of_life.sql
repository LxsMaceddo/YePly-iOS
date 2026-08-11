-- YePly Cards 2.3: realistic three-tier rarity, album browser, YePly search and bulk opening.

begin;

alter table public.collectible_card_definitions
  add column if not exists artist_popularity_rank integer,
  add column if not exists artist_catalog_size integer,
  add column if not exists popularity_ratio numeric(8,6) not null default 0;

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_artist_rank_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_artist_rank_check check (
    (artist_popularity_rank is null and artist_catalog_size is null)
    or (artist_popularity_rank between 1 and artist_catalog_size and artist_catalog_size > 0)
  );

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_popularity_ratio_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_popularity_ratio_check
  check (popularity_ratio between 0 and 1);

-- Release-group artwork is canonical and avoids editions without front art.
update public.collectible_albums
set artwork_path = 'https://coverartarchive.org/release-group/' || source_release_group_id || '/front-500',
    updated_at = now()
where catalog_source = 'musicbrainz'
  and source_release_group_id is not null;

update public.collectible_card_definitions d
set artwork_path = al.artwork_path,
    updated_at = now()
from public.collectible_albums al
where al.id = d.album_id
  and d.catalog_source = 'musicbrainz'
  and al.artwork_path like 'https://coverartarchive.org/release-group/%';

-- Keep legacy enum labels for backwards decoding, but stop assigning them.
create or replace function public.card_rarity_rank(p_rarity public.card_rarity)
returns smallint language sql immutable set search_path = '' as $$
  select case p_rarity
    when 'common'::public.card_rarity then 1
    when 'rare'::public.card_rarity then 1
    when 'epic'::public.card_rarity then 2
    when 'legendary'::public.card_rarity then 2
    when 'mythic'::public.card_rarity then 3
  end::smallint
$$;

create or replace function public.card_rarity_from_percentile(p_percentile double precision)
returns public.card_rarity language sql immutable set search_path = '' as $$
  select case
    when coalesce(p_percentile, 0) >= 0.95 then 'mythic'::public.card_rarity
    when coalesce(p_percentile, 0) >= 0.65 then 'epic'::public.card_rarity
    else 'common'::public.card_rarity
  end
$$;

-- Normalize every legacy rarity before refreshing the model.
update public.collectible_card_definitions
set rarity = case when rarity = 'rare' then 'common'::public.card_rarity
                  when rarity = 'legendary' then 'epic'::public.card_rarity else rarity end,
    rarity_override = case when rarity_override = 'rare' then 'common'::public.card_rarity
                           when rarity_override = 'legendary' then 'epic'::public.card_rarity else rarity_override end,
    updated_at = now()
where rarity in ('rare', 'legendary') or rarity_override in ('rare', 'legendary');

update public.card_packs
set rarity_floor = case when rarity_floor = 'rare' then 'common'::public.card_rarity
                        when rarity_floor = 'legendary' then 'epic'::public.card_rarity else rarity_floor end
where rarity_floor in ('rare', 'legendary');
update public.card_pack_codes
set rarity_floor = case when rarity_floor = 'rare' then 'common'::public.card_rarity
                        when rarity_floor = 'legendary' then 'epic'::public.card_rarity else rarity_floor end
where rarity_floor in ('rare', 'legendary');
update public.card_admin_pack_grants
set rarity_floor = case when rarity_floor = 'rare' then 'common'::public.card_rarity
                        when rarity_floor = 'legendary' then 'epic'::public.card_rarity else rarity_floor end
where rarity_floor in ('rare', 'legendary');

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
      max(greatest(ip.plays, 0)) over (partition by d.artist_id)::double precision as max_yeply_plays
    from public.collectible_card_definitions d
    join internal_plays ip on ip.id = d.id
    where d.is_enabled
  ), normalized as (
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
  ), scored as (
    select n.*,
      (n.listen_strength * 0.68 + n.listener_strength * 0.20
        + n.apple_strength * 0.10 + n.yeply_strength * 0.02)::double precision as composite_score
    from normalized n
  ), ranked as (
    select s.*,
      cume_dist() over (partition by s.artist_id order by s.composite_score)::double precision as artist_percentile,
      rank() over (partition by s.artist_id order by s.composite_score desc, s.id)::integer as artist_rank,
      count(*) over (partition by s.artist_id)::integer as catalog_size
    from scored s
  ), classified as (
    select r.*,
      case
        when not r.has_signal then 'common'::public.card_rarity
        when r.artist_percentile >= 0.95
             and (r.listen_ratio >= 0.08 or coalesce(r.apple_music_rank, 999) <= 10)
          then 'mythic'::public.card_rarity
        when r.artist_percentile >= 0.65
             and (r.listen_ratio >= 0.003 or r.listener_strength >= 0.25
                  or coalesce(r.apple_music_rank, 999) <= 100 or r.plays > 0)
          then 'epic'::public.card_rarity
        else 'common'::public.card_rarity
      end as calculated_rarity
    from ranked r
  )
  update public.collectible_card_definitions d
  set yeply_play_count = c.plays,
      play_count_snapshot = greatest(d.global_listen_count, c.plays),
      popularity_score = round((c.composite_score * 100)::numeric, 3),
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
        when 'epic'::public.card_rarity then 150
        when 'legendary'::public.card_rarity then 150
        when 'mythic'::public.card_rarity then 12
      end,
      rarity_version = 'reality-v3:' || to_char(current_date, 'YYYY-MM'),
      updated_at = now()
  from classified c
  where c.id = d.id;
end;
$$;

select public.refresh_card_rarities_internal();

-- This release intentionally rebalances existing copies so the collection no longer
-- displays obsolete or misleading rarity labels.
update public.card_instances i
set rarity_at_mint = d.rarity,
    popularity_score_at_mint = d.popularity_score,
    rarity_version_at_mint = d.rarity_version
from public.collectible_card_definitions d
where d.id = i.definition_id;

drop function if exists public.open_card_pack(uuid);
create function public.open_card_pack(p_pack_id uuid)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer
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
    join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
    join public.collectible_albums al on al.id = d.album_id and al.is_enabled
    where d.is_enabled
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
           coalesce(d.title, t.title), coalesce(d.artist_name, t.artist_name, a.display_name),
           coalesce(d.album_name, t.album_name, al.title, p.title),
           coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
           v_rarity, v_acquired, d.source_url, d.catalog_source,
           d.global_listen_count, d.global_listener_count, v_score,
           d.artist_popularity_rank, d.artist_catalog_size
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
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, d.track_id,
         coalesce(d.title, t.title), coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title, p.title),
         coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
         coalesce(i.rarity_at_mint, d.rarity), i.acquired_at, d.source_url,
         d.catalog_source, d.global_listen_count, d.global_listener_count,
         coalesce(i.popularity_score_at_mint, d.popularity_score),
         d.artist_popularity_rank, d.artist_catalog_size
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
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, d.track_id,
         coalesce(d.title, t.title), coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title, p.title),
         coalesce(d.artwork_path, t.artwork_path, al.artwork_path, p.cover_path),
         coalesce(i.rarity_at_mint, d.rarity), i.acquired_at, d.source_url,
         d.catalog_source, d.global_listen_count, d.global_listener_count,
         coalesce(i.popularity_score_at_mint, d.popularity_score),
         d.artist_popularity_rank, d.artist_catalog_size
  from public.profiles target
  join public.card_instances i on i.owner_id = target.id and i.locked_trade_id is null
  join public.collectible_card_definitions d on d.id = i.definition_id
  join public.collectible_artists a on a.id = d.artist_id
  join public.collectible_albums al on al.id = d.album_id
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  where auth.uid() is not null and target.username = lower(regexp_replace(btrim(p_username), '^@', ''))
  order by i.acquired_at desc, i.serial_number desc
$$;

create or replace function public.card_album_catalog_feed()
returns table (
  definition_id uuid, album_id uuid, album_title text, artist_key text, artist_name text,
  artwork_path text, track_number integer, title text, rarity public.card_rarity,
  global_listen_count bigint, global_listener_count bigint, popularity_score numeric,
  artist_popularity_rank integer, artist_catalog_size integer,
  owned_count bigint, owned_instance_id uuid
)
language sql stable security definer set search_path = '' as $$
  select d.id, al.id, al.title, a.artist_key, a.display_name,
         coalesce(d.artwork_path, al.artwork_path, p.cover_path),
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

create or replace function public.open_all_card_packs()
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer
)
language plpgsql security definer set search_path = '' as $$
declare v_pack_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  for v_pack_id in
    select p.id from public.card_packs p
    where p.owner_id = auth.uid() and p.status = 'sealed'::public.card_pack_status
    order by p.created_at, p.id
    for update skip locked
  loop
    return query select * from public.open_card_pack(v_pack_id);
  end loop;
end;
$$;

create or replace function public.search_public_tracks(p_query text, p_limit integer default 40)
returns table (
  track_id uuid, playlist_id uuid, uploader_id uuid, title text, artist_name text, album_name text,
  duration_seconds double precision, audio_path text, artwork_path text, "position" integer,
  file_size_bytes bigint, track_created_at timestamptz, waveform_samples real[],
  playlist_title text, playlist_cover_path text, play_count bigint
)
language sql stable security definer set search_path = '' as $$
  select t.id, t.playlist_id, t.uploader_id, t.title, t.artist_name, t.album_name,
         t.duration_seconds, t.audio_path, t.artwork_path, t.position, t.file_size_bytes,
         t.created_at, t.waveform_samples, p.title, p.cover_path,
         coalesce((select sum(h.play_count) from public.playback_history h where h.track_id = t.id), 0::bigint)
  from public.tracks t
  join public.playlists p on p.id = t.playlist_id
  where auth.uid() is not null and p.visibility = 'public'::public.playlist_visibility
    and btrim(p_query) <> ''
    and (t.title ilike '%' || btrim(p_query) || '%'
      or t.artist_name ilike '%' || btrim(p_query) || '%'
      or coalesce(t.album_name, '') ilike '%' || btrim(p_query) || '%'
      or p.title ilike '%' || btrim(p_query) || '%')
  order by case when lower(t.title) = lower(btrim(p_query)) then 0
                when t.title ilike btrim(p_query) || '%' then 1 else 2 end,
           16 desc, t.created_at desc
  limit least(greatest(p_limit, 1), 100)
$$;

create or replace function public.refresh_card_rarities()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  perform public.refresh_card_rarities_internal();
  update public.card_instances i
  set rarity_at_mint = d.rarity,
      popularity_score_at_mint = d.popularity_score,
      rarity_version_at_mint = d.rarity_version
  from public.collectible_card_definitions d where d.id = i.definition_id;
  return jsonb_build_object(
    'success', true,
    'message', 'Raridades atualizadas: Comum, Épica e Mítica.',
    'card_count', (select count(*) from public.collectible_card_definitions where is_enabled),
    'rarity_model', 'reality-v3'
  );
end;
$$;

revoke all on function public.open_card_pack(uuid), public.card_inventory_feed(),
  public.card_tradeable_inventory(text), public.card_album_catalog_feed(),
  public.open_all_card_packs(), public.search_public_tracks(text, integer),
  public.refresh_card_rarities() from public, anon;
grant execute on function public.open_card_pack(uuid), public.card_inventory_feed(),
  public.card_tradeable_inventory(text), public.card_album_catalog_feed(),
  public.open_all_card_packs(), public.search_public_tracks(text, integer),
  public.refresh_card_rarities() to authenticated;

comment on function public.card_album_catalog_feed() is
  'Complete enabled catalog grouped by artist and album, including the caller ownership state.';
comment on function public.open_all_card_packs() is
  'Atomically opens every sealed pack owned by the authenticated user.';
comment on function public.search_public_tracks(text, integer) is
  'Searches playable tracks in public YePly playlists without exposing private catalogs.';

commit;
