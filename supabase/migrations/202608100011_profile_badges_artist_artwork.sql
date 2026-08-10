-- YePly Cards 2.3.2: public equipped badges and Spotify artist artwork metadata.

begin;

alter table public.collectible_artists
  add column if not exists spotify_artist_id text,
  add column if not exists spotify_url text;

alter table public.collectible_artists
  drop constraint if exists collectible_artists_spotify_id_check;
alter table public.collectible_artists
  add constraint collectible_artists_spotify_id_check check (
    spotify_artist_id is null or spotify_artist_id ~ '^[A-Za-z0-9]{22}$'
  );

alter table public.collectible_artists
  drop constraint if exists collectible_artists_spotify_url_check;
alter table public.collectible_artists
  add constraint collectible_artists_spotify_url_check check (
    spotify_url is null or spotify_url ~ '^https://open[.]spotify[.]com/artist/[A-Za-z0-9]{22}$'
  );

-- Seed the current curated test artist immediately; future syncs refresh this
-- metadata through update_collectible_artist_spotify().
update public.collectible_artists
set spotify_artist_id = '5K4W6rqBFWDnAN6FQUkS6x',
    spotify_url = 'https://open.spotify.com/artist/5K4W6rqBFWDnAN6FQUkS6x',
    artwork_path = 'https://image-cdn-fa.spotifycdn.com/image/ab676161000051746e835a500e791bf9c27a422a',
    updated_at = now()
where source_artist_id = '164f0d73-1234-4e2c-8743-d77bf2191051'::uuid;

update public.card_badges b
set artwork_path = al.artwork_path
from public.collectible_albums al
where al.id = b.album_id and al.artwork_path is not null;

create or replace function public.update_collectible_artist_spotify(
  p_artist_mbid uuid,
  p_spotify_artist_id text,
  p_spotify_url text,
  p_artwork_url text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_artist_id uuid;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_spotify_artist_id !~ '^[A-Za-z0-9]{22}$'
     or p_spotify_url <> 'https://open.spotify.com/artist/' || p_spotify_artist_id
     or p_artwork_url !~ '^https://image-cdn-[A-Za-z0-9-]+[.]spotifycdn[.]com/image/[A-Za-z0-9]+$' then
    raise exception 'invalid_spotify_artist_metadata' using errcode = '22023';
  end if;

  update public.collectible_artists
  set spotify_artist_id = p_spotify_artist_id,
      spotify_url = p_spotify_url,
      artwork_path = p_artwork_url,
      updated_at = now()
  where source_artist_id = p_artist_mbid
  returning id into v_artist_id;

  if v_artist_id is null then
    raise exception 'collectible_artist_not_found' using errcode = 'P0002';
  end if;
  return jsonb_build_object('success', true, 'artist_id', v_artist_id);
end;
$$;

drop function if exists public.card_album_progress();
create function public.card_album_progress()
returns table (
  album_id uuid, album_title text, artist_name text,
  artist_artwork_path text, artist_source_url text, artwork_path text,
  owned_unique integer, total_cards integer, is_complete boolean,
  badge_id uuid, badge_equipped boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  return query
  select al.id, al.title, a.display_name, a.artwork_path, a.spotify_url,
         coalesce(al.artwork_path, b.artwork_path),
         count(distinct i.definition_id)::integer,
         count(distinct d.id)::integer,
         count(distinct i.definition_id) = count(distinct d.id) and count(distinct d.id) > 0,
         ub.badge_id,
         ub.equipped_slot is not null
  from public.collectible_albums al
  join public.collectible_artists a on a.id = al.artist_id and a.is_enabled
  join public.collectible_card_definitions d on d.album_id = al.id and d.is_enabled
  left join public.card_instances i on i.definition_id = d.id and i.owner_id = auth.uid()
  left join public.card_badges b on b.album_id = al.id
  left join public.card_user_badges ub on ub.badge_id = b.id and ub.user_id = auth.uid()
  where al.is_enabled
  group by al.id, a.id, b.artwork_path, ub.badge_id, ub.equipped_slot
  order by a.display_name, al.title;
end;
$$;

create or replace function public.profile_equipped_card_badges(p_profile_id uuid)
returns table (
  badge_id uuid, album_id uuid, title text, artwork_path text, slot integer
)
language sql stable security definer set search_path = '' as $$
  select b.id, al.id, b.title, coalesce(al.artwork_path, b.artwork_path), ub.equipped_slot::integer
  from public.card_user_badges ub
  join public.card_badges b on b.id = ub.badge_id
  join public.collectible_albums al on al.id = b.album_id
  join public.profiles p on p.id = ub.user_id
  where auth.uid() is not null
    and ub.user_id = p_profile_id
    and ub.equipped_slot is not null
  order by ub.equipped_slot
  limit 3
$$;

revoke all on function public.update_collectible_artist_spotify(uuid, text, text, text),
  public.card_album_progress(), public.profile_equipped_card_badges(uuid) from public, anon;
grant execute on function public.update_collectible_artist_spotify(uuid, text, text, text),
  public.card_album_progress(), public.profile_equipped_card_badges(uuid) to authenticated;

comment on function public.profile_equipped_card_badges(uuid) is
  'Returns the three album-cover badges selected for a profile showcase.';
comment on column public.collectible_artists.artwork_path is
  'Artist profile artwork; Spotify-derived images retain spotify_url attribution.';

commit;
