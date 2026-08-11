-- YePly 2.5: unbounded paginated card inventory and customizable profile art.
begin;

alter table public.profiles
  add column if not exists background_path text;

alter table public.profiles drop constraint if exists profiles_background_path_owner;
alter table public.profiles add constraint profiles_background_path_owner check (
  background_path is null or background_path like lower(id::text) || '/background/%'
);

-- Public profile feeds expose only the storage object path. The avatars bucket
-- remains private and clients receive short-lived signed URLs.
drop function if exists public.search_profiles(text, integer);
create function public.search_profiles(p_query text default '', p_limit integer default 30)
returns table (
  id uuid, display_name text, username text, avatar_path text, background_path text,
  bio text, tastes text[], role public.user_role, created_at timestamptz,
  follower_count bigint, following_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.username, p.avatar_path, p.background_path,
         p.bio, p.tastes, p.role, p.created_at,
         (select count(*) from public.user_follows f where f.followed_user_id = p.id),
         (select count(*) from public.user_follows f where f.follower_id = p.id),
         exists(
           select 1 from public.user_follows f
           where f.follower_id = auth.uid() and f.followed_user_id = p.id
         )
  from public.profiles p
  where p.id <> auth.uid()
    and (
      btrim(p_query) = ''
      or p.display_name ilike '%' || btrim(p_query) || '%'
      or p.username ilike '%' || btrim(p_query) || '%'
    )
  order by (select count(*) from public.user_follows f where f.followed_user_id = p.id) desc,
           p.display_name
  limit least(greatest(p_limit, 1), 50)
$$;

drop function if exists public.profile_with_social(uuid);
create function public.profile_with_social(p_profile_id uuid)
returns table (
  id uuid, display_name text, username text, avatar_path text, background_path text,
  bio text, tastes text[], role public.user_role, created_at timestamptz,
  follower_count bigint, following_count bigint, is_followed boolean
)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.username, p.avatar_path, p.background_path,
         p.bio, p.tastes, p.role, p.created_at,
         (select count(*) from public.user_follows f where f.followed_user_id = p.id),
         (select count(*) from public.user_follows f where f.follower_id = p.id),
         exists(
           select 1 from public.user_follows f
           where f.follower_id = auth.uid() and f.followed_user_id = p.id
         )
  from public.profiles p
  where p.id = p_profile_id
$$;

-- PostgREST returns at most 1,000 rows per request. This explicit page RPC lets
-- the iPhone load inventories of any size without displaying a false total.
create or replace function public.card_inventory_feed_page(
  p_offset integer default 0,
  p_limit integer default 500
)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, d.track_id,
         coalesce(d.title, t.title),
         coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title, p.title),
         coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(t.artwork_path), ''),
                  nullif(btrim(al.artwork_path), ''), nullif(btrim(p.cover_path), '')),
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
  where auth.uid() is not null and i.owner_id = auth.uid()
  order by i.acquired_at desc, i.serial_number desc
  limit least(greatest(p_limit, 1), 500)
  offset greatest(p_offset, 0)
$$;

-- Repair older definitions that were imported before album artwork was copied
-- into each card definition. New pack results will now always have a cover when
-- the album itself has one.
update public.collectible_card_definitions d
set artwork_path = al.artwork_path,
    updated_at = now()
from public.collectible_albums al
where al.id = d.album_id
  and nullif(btrim(d.artwork_path), '') is null
  and nullif(btrim(al.artwork_path), '') is not null;

revoke all on function public.search_profiles(text, integer),
  public.profile_with_social(uuid), public.card_inventory_feed_page(integer, integer)
  from public, anon;
grant execute on function public.search_profiles(text, integer),
  public.profile_with_social(uuid), public.card_inventory_feed_page(integer, integer)
  to authenticated;

comment on column public.profiles.background_path is
  'Optional user-selected profile backdrop stored privately in the avatars bucket.';
comment on function public.card_inventory_feed_page(integer, integer) is
  'Stable authenticated inventory pagination that is not capped at 1,000 total cards.';

commit;
