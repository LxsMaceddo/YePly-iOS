-- YePly iOS 1.6: server-authoritative collectible cards, packs, badges and trades.
-- The catalogue is populated only from tracks that already exist in YePly.
-- No Spotify credentials, external metadata or copyrighted media are stored here.

begin;

create extension if not exists pgcrypto;

do $$
begin
  create type public.card_rarity as enum ('common', 'rare', 'epic', 'legendary', 'mythic');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.card_pack_status as enum ('sealed', 'opened');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.card_trade_status as enum ('pending', 'accepted', 'declined', 'cancelled', 'expired');
exception when duplicate_object then null;
end $$;

create table if not exists public.card_game_config (
  singleton boolean primary key default true check (singleton),
  minimum_drop_seconds integer not null default 600 check (minimum_drop_seconds between 60 and 86400),
  pity_drop_seconds integer not null default 1800 check (pity_drop_seconds between minimum_drop_seconds and 172800),
  drop_chance_per_minute numeric(6,5) not null default 0.035 check (drop_chance_per_minute between 0 and 1),
  report_cooldown_seconds integer not null default 10 check (report_cooldown_seconds between 5 and 120),
  updated_at timestamptz not null default now()
);

insert into public.card_game_config(singleton) values (true) on conflict (singleton) do nothing;

create table if not exists public.collectible_artists (
  id uuid primary key default gen_random_uuid(),
  artist_key text not null unique check (char_length(artist_key) between 1 and 180),
  display_name text not null check (char_length(display_name) between 1 and 180),
  artwork_path text,
  is_enabled boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.collectible_albums (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.collectible_artists(id) on delete cascade,
  album_key text not null check (char_length(album_key) between 1 and 180),
  title text not null check (char_length(title) between 1 and 180),
  artwork_path text,
  source_playlist_id uuid references public.playlists(id) on delete set null,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (artist_id, album_key)
);

create table if not exists public.collectible_card_definitions (
  id uuid primary key default gen_random_uuid(),
  track_id uuid not null references public.tracks(id) on delete restrict,
  artist_id uuid not null references public.collectible_artists(id) on delete cascade,
  album_id uuid not null references public.collectible_albums(id) on delete cascade,
  rarity public.card_rarity not null default 'common',
  rarity_override public.card_rarity,
  play_count_snapshot bigint not null default 0 check (play_count_snapshot >= 0),
  drop_weight integer not null default 600 check (drop_weight between 1 and 10000),
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (track_id, artist_id)
);

create table if not exists public.card_player_stats (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  xp bigint not null default 0 check (xp >= 0),
  level integer not null default 1 check (level >= 1),
  current_streak integer not null default 0 check (current_streak >= 0),
  best_streak integer not null default 0 check (best_streak >= 0),
  streak_day smallint not null default 0 check (streak_day between 0 and 7),
  streak_cycle integer not null default 0 check (streak_cycle >= 0),
  last_daily_claim date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.card_favorite_artists (
  user_id uuid not null references public.profiles(id) on delete cascade,
  artist_id uuid not null references public.collectible_artists(id) on delete cascade,
  position smallint not null check (position between 0 and 9),
  created_at timestamptz not null default now(),
  primary key (user_id, artist_id),
  unique (user_id, position)
);

create table if not exists public.card_packs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  source text not null check (source in ('listening', 'daily', 'code', 'achievement', 'level', 'admin')),
  artist_id uuid references public.collectible_artists(id) on delete set null,
  rarity_floor public.card_rarity not null default 'common',
  card_count smallint not null default 3 check (card_count between 1 and 5),
  status public.card_pack_status not null default 'sealed',
  created_at timestamptz not null default now(),
  opened_at timestamptz
);

create table if not exists public.card_pack_codes (
  id uuid primary key default gen_random_uuid(),
  code_digest bytea not null unique,
  label text check (label is null or char_length(label) <= 100),
  artist_id uuid references public.collectible_artists(id) on delete set null,
  rarity_floor public.card_rarity not null default 'common',
  card_count smallint not null default 3 check (card_count between 1 and 5),
  max_redemptions integer not null default 1 check (max_redemptions > 0),
  redemption_count integer not null default 0 check (redemption_count between 0 and max_redemptions),
  expires_at timestamptz,
  is_enabled boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.card_pack_code_redemptions (
  code_id uuid not null references public.card_pack_codes(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  pack_id uuid not null unique references public.card_packs(id) on delete restrict,
  redeemed_at timestamptz not null default now(),
  primary key (code_id, user_id)
);

create table if not exists public.card_trades (
  id uuid primary key default gen_random_uuid(),
  proposer_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status public.card_trade_status not null default 'pending',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  responded_at timestamptz,
  check (proposer_id <> recipient_id)
);

create table if not exists public.card_instances (
  id uuid primary key default gen_random_uuid(),
  serial_number bigint generated always as identity unique,
  definition_id uuid not null references public.collectible_card_definitions(id) on delete restrict,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  source_pack_id uuid references public.card_packs(id) on delete set null,
  locked_trade_id uuid references public.card_trades(id) on delete set null,
  acquired_at timestamptz not null default now()
);

create table if not exists public.card_trade_items (
  trade_id uuid not null references public.card_trades(id) on delete cascade,
  card_instance_id uuid not null references public.card_instances(id) on delete restrict,
  side text not null check (side in ('offered', 'requested')),
  primary key (trade_id, card_instance_id)
);

create table if not exists public.card_listen_state (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  eligible_seconds integer not null default 0 check (eligible_seconds >= 0),
  last_report_at timestamptz,
  last_track_id uuid references public.tracks(id) on delete set null,
  last_drop_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.card_listen_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  accepted_seconds smallint not null check (accepted_seconds between 1 and 90),
  counts_as_play boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.card_daily_claims (
  user_id uuid not null references public.profiles(id) on delete cascade,
  claim_date date not null,
  streak_day smallint not null check (streak_day between 1 and 7),
  streak_cycle integer not null check (streak_cycle >= 1),
  pack_id uuid not null unique references public.card_packs(id) on delete restrict,
  xp_awarded integer not null check (xp_awarded >= 0),
  claimed_at timestamptz not null default now(),
  primary key (user_id, claim_date)
);

create table if not exists public.card_beta_members (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  recorded_at timestamptz not null default now()
);

create table if not exists public.card_achievement_definitions (
  achievement_key text primary key,
  title text not null,
  description text not null,
  icon text not null,
  target bigint not null check (target > 0),
  sort_order smallint not null unique,
  is_enabled boolean not null default true
);

create table if not exists public.card_user_achievements (
  user_id uuid not null references public.profiles(id) on delete cascade,
  achievement_key text not null references public.card_achievement_definitions(achievement_key) on delete restrict,
  unlocked_at timestamptz not null default now(),
  reward_claimed_at timestamptz,
  reward_pack_id uuid unique references public.card_packs(id) on delete set null,
  primary key (user_id, achievement_key)
);

create table if not exists public.card_share_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  track_id uuid not null references public.tracks(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.card_badges (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null unique references public.collectible_albums(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 180),
  artwork_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.card_user_badges (
  user_id uuid not null references public.profiles(id) on delete cascade,
  badge_id uuid not null references public.card_badges(id) on delete cascade,
  acquired_at timestamptz not null default now(),
  equipped_slot smallint check (equipped_slot between 1 and 3),
  primary key (user_id, badge_id)
);

create index if not exists collectible_cards_artist_idx on public.collectible_card_definitions(artist_id, rarity);
create index if not exists collectible_cards_album_idx on public.collectible_card_definitions(album_id);
create index if not exists card_instances_owner_idx on public.card_instances(owner_id, acquired_at desc);
create index if not exists card_instances_definition_idx on public.card_instances(definition_id);
create index if not exists card_packs_owner_sealed_idx on public.card_packs(owner_id, created_at desc) where status = 'sealed';
create index if not exists card_trades_participants_idx on public.card_trades(recipient_id, proposer_id, created_at desc);
create index if not exists card_trade_items_card_idx on public.card_trade_items(card_instance_id);
create index if not exists card_listen_events_user_time_idx on public.card_listen_events(user_id, created_at desc);
create index if not exists card_share_events_user_time_idx on public.card_share_events(user_id, created_at desc);
create unique index if not exists card_user_badges_equipped_slot_idx
  on public.card_user_badges(user_id, equipped_slot) where equipped_slot is not null;

insert into public.card_player_stats(user_id)
select p.id from public.profiles p on conflict (user_id) do nothing;

-- Everyone present when this migration is installed is a Beta member. New accounts are not.
insert into public.card_beta_members(user_id)
select p.id from public.profiles p on conflict (user_id) do nothing;

insert into public.card_achievement_definitions(achievement_key, title, description, icon, target, sort_order)
values
  ('night_listener', 'Night Listener', 'Ouviu 100 músicas entre 00:00 e 05:00.', '🌙', 100, 1),
  ('again', 'Again?!', 'Ouviu a mesma música 100 vezes.', '🔁', 100, 2),
  ('day_one', 'Day One', 'Está no YePly desde a versão Beta.', '🗿', 1, 3),
  ('audiophile', 'Audiophile', 'Ouviu 10.000 músicas.', '🎧', 10000, 4),
  ('collector', 'Collector', 'Completou 10 álbuns.', '💿', 10, 5),
  ('trader', 'Trader', 'Realizou 100 trocas.', '🤝', 100, 6),
  ('obsessed', 'Obsessed', 'Ouviu 1.000 vezes o mesmo artista.', '❤️', 1000, 7),
  ('show_off', 'Show Off!', 'Compartilhou o que está ouvindo agora.', '📣', 1, 8)
on conflict (achievement_key) do update set
  title = excluded.title,
  description = excluded.description,
  icon = excluded.icon,
  target = excluded.target,
  sort_order = excluded.sort_order;

create or replace function public.card_level_for_xp(p_xp bigint)
returns integer language sql immutable set search_path = '' as $$
  select greatest(1, floor(sqrt(greatest(coalesce(p_xp, 0), 0)::numeric / 500))::integer + 1)
$$;

create or replace function public.card_rarity_rank(p_rarity public.card_rarity)
returns smallint language sql immutable set search_path = '' as $$
  select case p_rarity
    when 'common'::public.card_rarity then 1
    when 'rare'::public.card_rarity then 2
    when 'epic'::public.card_rarity then 3
    when 'legendary'::public.card_rarity then 4
    when 'mythic'::public.card_rarity then 5
  end::smallint
$$;

create or replace function public.card_rarity_from_popularity(p_plays bigint, p_rank double precision)
returns public.card_rarity language sql immutable set search_path = '' as $$
  select case
    when coalesce(p_plays, 0) >= 100 and p_rank < 0.02 then 'mythic'::public.card_rarity
    when coalesce(p_plays, 0) >= 25 and p_rank < 0.10 then 'legendary'::public.card_rarity
    when coalesce(p_plays, 0) >= 10 and p_rank < 0.30 then 'epic'::public.card_rarity
    when coalesce(p_plays, 0) >= 3 and p_rank < 0.60 then 'rare'::public.card_rarity
    else 'common'::public.card_rarity
  end
$$;

create or replace function public.ensure_card_player(p_user_id uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.card_player_stats(user_id) values (p_user_id) on conflict (user_id) do nothing
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
  set xp = xp + p_amount,
      level = v_new_level,
      updated_at = now()
  where user_id = p_user_id;
  if v_new_level > v_old_level and exists (
    select 1 from public.collectible_card_definitions d
    join public.tracks t on t.id = d.track_id
    join public.playlists p on p.id = t.playlist_id
    where d.is_enabled and p.visibility = 'public'::public.playlist_visibility
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
  p_owner_id uuid,
  p_source text,
  p_artist_id uuid default null,
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
    select 1
    from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id
    join public.collectible_albums al on al.id = d.album_id
    join public.tracks t on t.id = d.track_id
    join public.playlists p on p.id = t.playlist_id
    where d.is_enabled and a.is_enabled and al.is_enabled
      and p.visibility = 'public'::public.playlist_visibility
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

create or replace function public.refresh_card_rarities_internal()
returns void language plpgsql security definer set search_path = '' as $$
begin
  with scores as (
    select d.id,
           coalesce(sum(h.play_count), 0)::bigint as plays
    from public.collectible_card_definitions d
    left join public.playback_history h on h.track_id = d.track_id
    where d.is_enabled
    group by d.id
  ), ranked as (
    select s.id, s.plays,
           percent_rank() over (order by s.plays desc) as popularity_rank
    from scores s
  )
  update public.collectible_card_definitions d
  set play_count_snapshot = r.plays,
      rarity = coalesce(d.rarity_override, public.card_rarity_from_popularity(r.plays, r.popularity_rank)),
      drop_weight = case coalesce(d.rarity_override, public.card_rarity_from_popularity(r.plays, r.popularity_rank))
        when 'common'::public.card_rarity then 600
        when 'rare'::public.card_rarity then 250
        when 'epic'::public.card_rarity then 100
        when 'legendary'::public.card_rarity then 40
        when 'mythic'::public.card_rarity then 10
      end,
      updated_at = now()
  from ranked r where r.id = d.id;
end;
$$;

-- Initial test catalogue: only public YePly tracks that explicitly credit Kanye West.
insert into public.collectible_artists(artist_key, display_name)
select 'kanye west', 'Kanye West'
where exists (
  select 1 from public.tracks t
  join public.playlists p on p.id = t.playlist_id
  cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
  where p.visibility = 'public'::public.playlist_visibility
    and lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = 'kanye west'
)
on conflict (artist_key) do nothing;

insert into public.collectible_albums(artist_id, album_key, title, artwork_path, source_playlist_id)
select distinct on (a.id, lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')))
       a.id,
       lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')),
       btrim(coalesce(nullif(t.album_name, ''), p.title)),
       coalesce(t.artwork_path, p.cover_path),
       p.id
from public.collectible_artists a
join public.tracks t on exists (
  select 1 from regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
  where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = a.artist_key
)
join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
where a.artist_key = 'kanye west'
  and btrim(coalesce(nullif(t.album_name, ''), p.title)) <> ''
order by a.id, lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')), t.position
on conflict (artist_id, album_key) do update set
  artwork_path = coalesce(public.collectible_albums.artwork_path, excluded.artwork_path),
  source_playlist_id = coalesce(public.collectible_albums.source_playlist_id, excluded.source_playlist_id),
  updated_at = now();

insert into public.collectible_card_definitions(track_id, artist_id, album_id)
select t.id, a.id, al.id
from public.collectible_artists a
join public.tracks t on exists (
  select 1 from regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
  where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = a.artist_key
)
join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
join public.collectible_albums al on al.artist_id = a.id
  and al.album_key = lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g'))
where a.artist_key = 'kanye west'
on conflict (track_id, artist_id) do nothing;

insert into public.card_badges(album_id, title, artwork_path)
select al.id, al.title, al.artwork_path from public.collectible_albums al
on conflict (album_id) do update set
  title = excluded.title,
  artwork_path = coalesce(public.card_badges.artwork_path, excluded.artwork_path);

select public.refresh_card_rarities_internal();

create or replace function public.sync_collectible_catalog(p_artist_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_name text := left(btrim(p_artist_name), 180);
  v_key text;
  v_artist_id uuid;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  v_key := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
  if v_key = '' then raise exception 'invalid_artist' using errcode = '22023'; end if;

  if not exists (
    select 1 from public.tracks t
    join public.playlists p on p.id = t.playlist_id
    cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
    where p.visibility = 'public'::public.playlist_visibility
      and lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = v_key
  ) then
    raise exception 'artist_has_no_public_yeply_tracks' using errcode = 'P0002';
  end if;

  insert into public.collectible_artists(artist_key, display_name, created_by)
  values (v_key, v_name, auth.uid())
  on conflict (artist_key) do update set display_name = excluded.display_name, is_enabled = true, updated_at = now()
  returning id into v_artist_id;

  insert into public.collectible_albums(artist_id, album_key, title, artwork_path, source_playlist_id)
  select distinct on (lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')))
         v_artist_id,
         lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')),
         btrim(coalesce(nullif(t.album_name, ''), p.title)),
         coalesce(t.artwork_path, p.cover_path), p.id
  from public.tracks t
  join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
  where exists (
    select 1 from regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
    where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = v_key
  )
  order by lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g')), t.position
  on conflict (artist_id, album_key) do update set
    title = excluded.title,
    artwork_path = coalesce(excluded.artwork_path, public.collectible_albums.artwork_path),
    source_playlist_id = coalesce(excluded.source_playlist_id, public.collectible_albums.source_playlist_id),
    is_enabled = true,
    updated_at = now();

  insert into public.collectible_card_definitions(track_id, artist_id, album_id)
  select t.id, v_artist_id, al.id
  from public.tracks t
  join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
  join public.collectible_albums al on al.artist_id = v_artist_id
    and al.album_key = lower(regexp_replace(btrim(coalesce(nullif(t.album_name, ''), p.title)), '\s+', ' ', 'g'))
  where exists (
    select 1 from regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
    where lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) = v_key
  )
  on conflict (track_id, artist_id) do update set
    album_id = excluded.album_id, is_enabled = true, updated_at = now();

  insert into public.card_badges(album_id, title, artwork_path)
  select al.id, al.title, al.artwork_path from public.collectible_albums al where al.artist_id = v_artist_id
  on conflict (album_id) do update set title = excluded.title,
    artwork_path = coalesce(excluded.artwork_path, public.card_badges.artwork_path);

  perform public.refresh_card_rarities_internal();
  return jsonb_build_object(
    'artist_id', v_artist_id,
    'artist_key', v_key,
    'album_count', (select count(*) from public.collectible_albums al where al.artist_id = v_artist_id and al.is_enabled),
    'card_count', (select count(*) from public.collectible_card_definitions d where d.artist_id = v_artist_id and d.is_enabled)
  );
end;
$$;

create or replace function public.refresh_card_rarities()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  perform public.refresh_card_rarities_internal();
  return jsonb_build_object('refreshed', true, 'card_count', (select count(*) from public.collectible_card_definitions where is_enabled));
end;
$$;

create or replace function public.create_card_pack_code(
  p_code text,
  p_label text default null,
  p_max_redemptions integer default 1,
  p_expires_at timestamptz default null,
  p_artist_key text default null,
  p_card_count integer default 3,
  p_rarity_floor public.card_rarity default 'common'
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_artist_id uuid; v_id uuid; v_code text := lower(btrim(p_code));
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'admin_required' using errcode = '42501'; end if;
  if char_length(v_code) not between 6 and 80 or p_max_redemptions not between 1 and 100000 or p_card_count not between 1 and 5 then
    raise exception 'invalid_pack_code' using errcode = '22023';
  end if;
  if p_artist_key is not null then
    select a.id into v_artist_id from public.collectible_artists a
    where a.artist_key = lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g')) and a.is_enabled;
    if v_artist_id is null then raise exception 'artist_not_available' using errcode = 'P0002'; end if;
  end if;
  insert into public.card_pack_codes(code_digest, label, artist_id, rarity_floor, card_count, max_redemptions, expires_at, created_by)
  values (extensions.digest(v_code, 'sha256'), left(btrim(p_label), 100), v_artist_id, p_rarity_floor, p_card_count, p_max_redemptions, p_expires_at, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.redeem_pack_code(p_code text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_code public.card_pack_codes; v_pack_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_code from public.card_pack_codes
  where code_digest = extensions.digest(lower(btrim(p_code)), 'sha256') for update;
  if v_code.id is null or not v_code.is_enabled then raise exception 'invalid_pack_code' using errcode = 'P0002'; end if;
  if v_code.expires_at is not null and v_code.expires_at <= now() then raise exception 'pack_code_expired' using errcode = '22023'; end if;
  if v_code.redemption_count >= v_code.max_redemptions then raise exception 'pack_code_exhausted' using errcode = '22023'; end if;
  if exists (select 1 from public.card_pack_code_redemptions r where r.code_id = v_code.id and r.user_id = auth.uid()) then
    raise exception 'pack_code_already_redeemed' using errcode = '23505';
  end if;
  v_pack_id := public.create_card_pack_internal(auth.uid(), 'code', v_code.artist_id, v_code.card_count, v_code.rarity_floor);
  insert into public.card_pack_code_redemptions(code_id, user_id, pack_id) values (v_code.id, auth.uid(), v_pack_id);
  update public.card_pack_codes set redemption_count = redemption_count + 1 where id = v_code.id;
  return jsonb_build_object('redeemed', true, 'pack_id', v_pack_id, 'card_count', v_code.card_count, 'source', 'code');
end;
$$;

create or replace function public.refresh_card_album_badges(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.card_user_badges(user_id, badge_id)
  select p_user_id, b.id
  from public.card_badges b
  join public.collectible_albums al on al.id = b.album_id and al.is_enabled
  where not exists (
    select 1 from public.collectible_card_definitions d
    where d.album_id = al.id and d.is_enabled
      and not exists (
        select 1 from public.card_instances i where i.owner_id = p_user_id and i.definition_id = d.id
      )
  )
  and exists (select 1 from public.collectible_card_definitions d where d.album_id = al.id and d.is_enabled)
  on conflict (user_id, badge_id) do nothing;
end;
$$;

create or replace function public.card_achievement_progress_for(p_user_id uuid, p_key text)
returns bigint language plpgsql stable security definer set search_path = '' as $$
declare v_progress bigint := 0;
begin
  case p_key
    when 'night_listener' then
      select count(*) into v_progress from public.card_listen_events e
      where e.user_id = p_user_id and e.counts_as_play and extract(hour from e.created_at at time zone 'UTC') between 0 and 4;
    when 'again' then
      select coalesce(max(h.play_count), 0) into v_progress from public.playback_history h where h.user_id = p_user_id;
    when 'day_one' then
      select case when exists(select 1 from public.card_beta_members b where b.user_id = p_user_id) then 1 else 0 end into v_progress;
    when 'audiophile' then
      select coalesce(sum(h.play_count), 0) into v_progress from public.playback_history h where h.user_id = p_user_id;
    when 'collector' then
      select count(*) into v_progress from public.card_user_badges b where b.user_id = p_user_id;
    when 'trader' then
      select count(*) into v_progress from public.card_trades t
      where t.status = 'accepted'::public.card_trade_status and (t.proposer_id = p_user_id or t.recipient_id = p_user_id);
    when 'obsessed' then
      select coalesce(max(x.plays), 0) into v_progress
      from (
        select lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) as artist_key, sum(h.play_count)::bigint as plays
        from public.playback_history h
        join public.tracks t on t.id = h.track_id
        cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
        where h.user_id = p_user_id
        group by lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g'))
      ) x;
    when 'show_off' then
      select case when exists(select 1 from public.card_share_events e where e.user_id = p_user_id) then 1 else 0 end into v_progress;
    else v_progress := 0;
  end case;
  return coalesce(v_progress, 0);
end;
$$;

create or replace function public.refresh_card_achievements(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.card_user_achievements(user_id, achievement_key)
  select p_user_id, d.achievement_key
  from public.card_achievement_definitions d
  where d.is_enabled and public.card_achievement_progress_for(p_user_id, d.achievement_key) >= d.target
  on conflict (user_id, achievement_key) do nothing;
end;
$$;

create or replace function public.open_card_pack(p_pack_id uuid)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
declare
  v_pack public.card_packs;
  v_definition_id uuid;
  v_instance_id uuid;
  v_serial bigint;
  v_acquired timestamptz;
  v_counter integer;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_pack from public.card_packs p where p.id = p_pack_id for update;
  if v_pack.id is null or v_pack.owner_id <> auth.uid() then raise exception 'pack_not_found' using errcode = 'P0002'; end if;
  if v_pack.status <> 'sealed'::public.card_pack_status then raise exception 'pack_already_opened' using errcode = '55000'; end if;

  for v_counter in 1..v_pack.card_count loop
    select d.id into v_definition_id
    from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id
    join public.collectible_albums al on al.id = d.album_id
    join public.tracks t on t.id = d.track_id
    join public.playlists p on p.id = t.playlist_id
    where d.is_enabled and a.is_enabled and al.is_enabled
      and p.visibility = 'public'::public.playlist_visibility
      and (v_pack.artist_id is null or d.artist_id = v_pack.artist_id)
      and public.card_rarity_rank(d.rarity) >= public.card_rarity_rank(v_pack.rarity_floor)
    order by (-ln(greatest(random(), 0.000000001)) / d.drop_weight), d.id
    limit 1;
    if v_definition_id is null then raise exception 'empty_card_pool' using errcode = 'P0002'; end if;

    insert into public.card_instances(definition_id, owner_id, source_pack_id)
    values (v_definition_id, auth.uid(), v_pack.id)
    returning id, card_instances.serial_number, card_instances.acquired_at into v_instance_id, v_serial, v_acquired;

    return query
    select v_instance_id, v_serial, d.id, t.id, t.title, t.artist_name,
           coalesce(t.album_name, p.title), coalesce(t.artwork_path, p.cover_path), d.rarity, v_acquired
    from public.collectible_card_definitions d
    join public.tracks t on t.id = d.track_id
    join public.playlists p on p.id = t.playlist_id
    where d.id = v_definition_id;
  end loop;

  update public.card_packs set status = 'opened', opened_at = now() where id = v_pack.id;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
end;
$$;

create or replace function public.card_pack_feed()
returns table(pack_id uuid, source text, card_count integer, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.source, p.card_count::integer, p.created_at
  from public.card_packs p
  where p.owner_id = auth.uid() and p.status = 'sealed'::public.card_pack_status
  order by p.created_at desc
$$;

create or replace function public.card_inventory_feed()
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, t.id, t.title, t.artist_name,
         coalesce(t.album_name, p.title), coalesce(t.artwork_path, p.cover_path), d.rarity, i.acquired_at
  from public.card_instances i
  join public.collectible_card_definitions d on d.id = i.definition_id
  join public.tracks t on t.id = d.track_id
  join public.playlists p on p.id = t.playlist_id
  where i.owner_id = auth.uid()
  order by i.acquired_at desc, i.serial_number desc
$$;

create or replace function public.card_tradeable_inventory(p_username text)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select i.id, i.serial_number, d.id, t.id, t.title, t.artist_name,
         coalesce(t.album_name, p.title), coalesce(t.artwork_path, p.cover_path), d.rarity, i.acquired_at
  from public.profiles target
  join public.card_instances i on i.owner_id = target.id and i.locked_trade_id is null
  join public.collectible_card_definitions d on d.id = i.definition_id and d.is_enabled
  join public.tracks t on t.id = d.track_id
  join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
  where auth.uid() is not null and target.username = lower(btrim(p_username))
  order by i.acquired_at desc, i.serial_number desc
$$;

create or replace function public.card_available_artists()
returns table(artist_key text, artist_name text, card_count bigint)
language sql stable security definer set search_path = '' as $$
  select a.artist_key, a.display_name, count(d.id)
  from public.collectible_artists a
  join public.collectible_card_definitions d on d.artist_id = a.id and d.is_enabled
  join public.tracks t on t.id = d.track_id
  join public.playlists p on p.id = t.playlist_id and p.visibility = 'public'::public.playlist_visibility
  where a.is_enabled
  group by a.id
  order by a.display_name
$$;

create or replace function public.card_album_progress()
returns table (
  album_id uuid, album_title text, artist_name text, artwork_path text,
  owned_unique integer, total_cards integer, is_complete boolean,
  badge_id uuid, badge_equipped boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  return query
  select al.id, al.title, a.display_name, coalesce(al.artwork_path, b.artwork_path),
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
  group by al.id, a.display_name, b.artwork_path, ub.badge_id, ub.equipped_slot
  order by a.display_name, al.title;
end;
$$;

create or replace function public.card_achievement_feed()
returns table (
  achievement_key text, title text, description text, icon text,
  progress bigint, target bigint, unlocked_at timestamptz, reward_claimed_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
  return query
  select d.achievement_key, d.title, d.description, d.icon,
         least(public.card_achievement_progress_for(auth.uid(), d.achievement_key), d.target),
         d.target, ua.unlocked_at, ua.reward_claimed_at
  from public.card_achievement_definitions d
  left join public.card_user_achievements ua on ua.user_id = auth.uid() and ua.achievement_key = d.achievement_key
  where d.is_enabled order by d.sort_order;
end;
$$;

create or replace function public.set_favorite_artists(p_artist_keys text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_normalized text[]; v_requested integer; v_found integer;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select coalesce(array_agg(key order by first_ordinality), '{}'::text[])
  into v_normalized
  from (
    select lower(regexp_replace(btrim(x.key), '\s+', ' ', 'g')) as key, min(x.ordinality) as first_ordinality
    from unnest(coalesce(p_artist_keys, '{}'::text[])) with ordinality x(key, ordinality)
    where btrim(x.key) <> ''
    group by lower(regexp_replace(btrim(x.key), '\s+', ' ', 'g'))
  ) n;
  v_requested := cardinality(v_normalized);
  if v_requested > 10 then raise exception 'too_many_favorite_artists' using errcode = '22023'; end if;
  select count(*) into v_found from public.collectible_artists a where a.is_enabled and a.artist_key = any(v_normalized);
  if v_found <> v_requested then raise exception 'artist_not_available' using errcode = 'P0002'; end if;
  delete from public.card_favorite_artists where user_id = auth.uid();
  insert into public.card_favorite_artists(user_id, artist_id, position)
  select auth.uid(), a.id, (x.ordinality - 1)::smallint
  from unnest(v_normalized) with ordinality x(key, ordinality)
  join public.collectible_artists a on a.artist_key = x.key;
  return jsonb_build_object('updated', true, 'artist_keys', to_jsonb(v_normalized));
end;
$$;

create or replace function public.equip_card_badge(p_badge_id uuid, p_slot smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if p_slot not between 1 and 3 then raise exception 'invalid_badge_slot' using errcode = '22023'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  if not exists (select 1 from public.card_user_badges b where b.user_id = auth.uid() and b.badge_id = p_badge_id) then
    raise exception 'badge_not_owned' using errcode = '42501';
  end if;
  update public.card_user_badges set equipped_slot = null where user_id = auth.uid() and equipped_slot = p_slot;
  update public.card_user_badges set equipped_slot = p_slot where user_id = auth.uid() and badge_id = p_badge_id;
  return jsonb_build_object('equipped', true, 'badge_id', p_badge_id, 'slot', p_slot);
end;
$$;

create or replace function public.claim_daily_card_reward()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_stats public.card_player_stats;
  v_today date := (now() at time zone 'UTC')::date;
  v_streak integer;
  v_day smallint;
  v_cycle integer;
  v_floor public.card_rarity := 'common';
  v_xp integer;
  v_pack_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.ensure_card_player(auth.uid());
  select * into v_stats from public.card_player_stats s where s.user_id = auth.uid() for update;
  if v_stats.last_daily_claim = v_today then
    return jsonb_build_object('claimed', false, 'streak_day', v_stats.streak_day, 'streak_cycle', v_stats.streak_cycle,
      'pack_id', null, 'pack_card_count', 0, 'rarity_floor', null, 'xp_awarded', 0, 'level', v_stats.level);
  end if;
  v_streak := case when v_stats.last_daily_claim = v_today - 1 then v_stats.current_streak + 1 else 1 end;
  v_day := (((v_streak - 1) % 7) + 1)::smallint;
  v_cycle := ((v_streak - 1) / 7) + 1;
  if v_day = 7 then v_floor := case when v_cycle >= 4 then 'epic'::public.card_rarity else 'rare'::public.card_rarity end; end if;
  v_xp := case when v_day = 7 then 100 else 25 end;
  v_pack_id := public.create_card_pack_internal(auth.uid(), 'daily', null, 3, v_floor);
  update public.card_player_stats
  set current_streak = v_streak, best_streak = greatest(best_streak, v_streak),
      streak_day = v_day, streak_cycle = v_cycle,
      last_daily_claim = v_today, updated_at = now()
  where user_id = auth.uid();
  perform public.award_card_xp(auth.uid(), v_xp);
  insert into public.card_daily_claims(user_id, claim_date, streak_day, streak_cycle, pack_id, xp_awarded)
  values (auth.uid(), v_today, v_day, v_cycle, v_pack_id, v_xp);
  select * into v_stats from public.card_player_stats where user_id = auth.uid();
  return jsonb_build_object('claimed', true, 'streak_day', v_day, 'streak_cycle', v_cycle,
    'pack_id', v_pack_id, 'pack_card_count', 3, 'rarity_floor', v_floor::text, 'xp_awarded', v_xp, 'level', v_stats.level);
end;
$$;

create or replace function public.record_card_listening(p_track_id uuid, p_listened_seconds integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_playlist_id uuid;
  v_state public.card_listen_state;
  v_config public.card_game_config;
  v_elapsed integer;
  v_accepted integer;
  v_total integer;
  v_xp_awarded integer;
  v_pack_id uuid;
  v_drop boolean := false;
  v_counts_as_play boolean;
  v_stats public.card_player_stats;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if p_listened_seconds not between 15 and 90 then raise exception 'invalid_listening_interval' using errcode = '22023'; end if;
  select t.playlist_id into v_playlist_id from public.tracks t where t.id = p_track_id;
  if v_playlist_id is null or not public.can_read_playlist(v_playlist_id) then raise exception 'track_access_denied' using errcode = '42501'; end if;
  select * into v_config from public.card_game_config where singleton;
  perform public.ensure_card_player(auth.uid());
  insert into public.card_listen_state(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select * into v_state from public.card_listen_state s where s.user_id = auth.uid() for update;

  if v_state.last_report_at is null then
    v_accepted := least(p_listened_seconds, 30);
    v_elapsed := 0;
  else
    v_elapsed := floor(extract(epoch from (now() - v_state.last_report_at)))::integer;
    if v_elapsed < v_config.report_cooldown_seconds then
      select * into v_stats from public.card_player_stats where user_id = auth.uid();
      return jsonb_build_object('accepted', false, 'accepted_seconds', 0, 'total_eligible_seconds', v_state.eligible_seconds,
        'xp_awarded', 0, 'xp', v_stats.xp, 'level', v_stats.level, 'pack_dropped', false, 'pack_id', null,
        'drop_threshold_seconds', v_config.minimum_drop_seconds,
        'next_report_after_seconds', v_config.report_cooldown_seconds - v_elapsed);
    end if;
    v_accepted := least(p_listened_seconds, v_elapsed + 5, 90);
    if v_accepted < 15 then raise exception 'listening_interval_not_elapsed' using errcode = '22023'; end if;
  end if;

  v_counts_as_play := v_state.last_track_id is distinct from p_track_id
    or v_state.last_report_at is null
    or v_state.last_report_at < now() - interval '10 minutes';
  v_total := v_state.eligible_seconds + v_accepted;
  v_xp_awarded := greatest(1, floor(v_accepted::numeric / 30)::integer) * 5;

  if v_total >= v_config.minimum_drop_seconds and (
       v_total >= v_config.pity_drop_seconds
       or random() < least(0.35, v_config.drop_chance_per_minute * (v_accepted::numeric / 60))
     ) then
    v_pack_id := public.create_card_pack_internal(auth.uid(), 'listening', null, 3, 'common');
    v_drop := true;
    v_total := 0;
  end if;

  update public.card_listen_state
  set eligible_seconds = v_total, last_report_at = now(), last_track_id = p_track_id,
      last_drop_at = case when v_drop then now() else last_drop_at end, updated_at = now()
  where user_id = auth.uid();
  insert into public.card_listen_events(user_id, track_id, accepted_seconds, counts_as_play)
  values (auth.uid(), p_track_id, v_accepted, v_counts_as_play);
  perform public.award_card_xp(auth.uid(), v_xp_awarded);
  perform public.refresh_card_achievements(auth.uid());
  select * into v_stats from public.card_player_stats where user_id = auth.uid();
  return jsonb_build_object('accepted', true, 'accepted_seconds', v_accepted, 'total_eligible_seconds', v_total,
    'xp_awarded', v_xp_awarded, 'xp', v_stats.xp, 'level', v_stats.level,
    'pack_dropped', v_drop, 'pack_id', v_pack_id, 'drop_threshold_seconds', v_config.minimum_drop_seconds,
    'next_report_after_seconds', v_config.report_cooldown_seconds);
end;
$$;

create or replace function public.record_now_playing_share(p_track_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_playlist_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select t.playlist_id into v_playlist_id from public.tracks t where t.id = p_track_id;
  if v_playlist_id is null or not public.can_read_playlist(v_playlist_id) then raise exception 'track_access_denied' using errcode = '42501'; end if;
  if exists (select 1 from public.card_share_events e where e.user_id = auth.uid() and e.created_at > now() - interval '1 minute') then
    return jsonb_build_object('recorded', false, 'reason', 'rate_limited');
  end if;
  insert into public.card_share_events(user_id, track_id) values (auth.uid(), p_track_id);
  perform public.refresh_card_achievements(auth.uid());
  return jsonb_build_object('recorded', true, 'achievement_key', 'show_off');
end;
$$;

create or replace function public.claim_card_achievement(p_achievement_key text, p_artist_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_achievement public.card_user_achievements; v_artist_id uuid; v_pack_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.refresh_card_achievements(auth.uid());
  select * into v_achievement from public.card_user_achievements a
  where a.user_id = auth.uid() and a.achievement_key = p_achievement_key for update;
  if v_achievement.user_id is null then raise exception 'achievement_not_unlocked' using errcode = '42501'; end if;
  if v_achievement.reward_claimed_at is not null then raise exception 'achievement_reward_already_claimed' using errcode = '23505'; end if;
  select a.id into v_artist_id
  from public.collectible_artists a
  join public.card_favorite_artists f on f.artist_id = a.id and f.user_id = auth.uid()
  where a.artist_key = lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g')) and a.is_enabled;
  if v_artist_id is null then raise exception 'artist_must_be_favorite' using errcode = '42501'; end if;
  v_pack_id := public.create_card_pack_internal(auth.uid(), 'achievement', v_artist_id, 5, 'common');
  update public.card_user_achievements set reward_claimed_at = now(), reward_pack_id = v_pack_id
  where user_id = auth.uid() and achievement_key = p_achievement_key;
  perform public.award_card_xp(auth.uid(), 100);
  return jsonb_build_object('claimed', true, 'achievement_key', p_achievement_key,
    'artist_key', lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g')), 'pack_id', v_pack_id,
    'card_count', 5, 'xp_awarded', 100);
end;
$$;

create or replace function public.release_expired_card_trades()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.card_instances i set locked_trade_id = null
  where i.locked_trade_id in (
    select t.id from public.card_trades t where t.status = 'pending'::public.card_trade_status and t.expires_at <= now()
  );
  update public.card_trades set status = 'expired', responded_at = now()
  where status = 'pending'::public.card_trade_status and expires_at <= now();
end;
$$;

create or replace function public.create_card_trade(p_recipient_id uuid, p_offered_ids uuid[], p_requested_ids uuid[])
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_trade_id uuid; v_offered_count integer; v_requested_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if p_recipient_id is null or p_recipient_id = auth.uid() or not exists(select 1 from public.profiles p where p.id = p_recipient_id) then
    raise exception 'invalid_trade_recipient' using errcode = '22023';
  end if;
  v_offered_count := cardinality(coalesce(p_offered_ids, '{}'::uuid[]));
  v_requested_count := cardinality(coalesce(p_requested_ids, '{}'::uuid[]));
  if v_offered_count not between 1 and 20 or v_requested_count not between 1 and 20 then
    raise exception 'invalid_trade_size' using errcode = '22023';
  end if;
  if (select count(distinct x) from unnest(p_offered_ids) x) <> v_offered_count
     or (select count(distinct x) from unnest(p_requested_ids) x) <> v_requested_count
     or p_offered_ids && p_requested_ids then
    raise exception 'duplicate_trade_card' using errcode = '22023';
  end if;
  perform public.release_expired_card_trades();
  perform 1 from public.card_instances i where i.id = any(p_offered_ids) order by i.id for update;
  perform 1 from public.card_instances i where i.id = any(p_requested_ids) order by i.id for update;
  if (select count(*) from public.card_instances i where i.id = any(p_offered_ids) and i.owner_id = auth.uid() and i.locked_trade_id is null) <> v_offered_count then
    raise exception 'offered_card_unavailable' using errcode = '42501';
  end if;
  if (select count(*) from public.card_instances i where i.id = any(p_requested_ids) and i.owner_id = p_recipient_id and i.locked_trade_id is null) <> v_requested_count then
    raise exception 'requested_card_unavailable' using errcode = '42501';
  end if;
  insert into public.card_trades(proposer_id, recipient_id) values (auth.uid(), p_recipient_id) returning id into v_trade_id;
  insert into public.card_trade_items(trade_id, card_instance_id, side)
  select v_trade_id, x, 'offered' from unnest(p_offered_ids) x
  union all select v_trade_id, x, 'requested' from unnest(p_requested_ids) x;
  -- Only the proposer's offered cards are reserved. Requested cards remain usable
  -- until acceptance, preventing malicious proposals from freezing another user.
  update public.card_instances set locked_trade_id = v_trade_id where id = any(p_offered_ids);
  return v_trade_id;
end;
$$;

create or replace function public.respond_card_trade(p_trade_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trade public.card_trades; v_item_count integer; v_xp integer := 0;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_trade from public.card_trades t where t.id = p_trade_id for update;
  if v_trade.id is null or v_trade.recipient_id <> auth.uid() then raise exception 'trade_not_found' using errcode = 'P0002'; end if;
  if v_trade.status <> 'pending'::public.card_trade_status then raise exception 'trade_not_pending' using errcode = '55000'; end if;
  if v_trade.expires_at <= now() then
    update public.card_instances set locked_trade_id = null where locked_trade_id = v_trade.id;
    update public.card_trades set status = 'expired', responded_at = now() where id = v_trade.id;
    return jsonb_build_object('trade_id', v_trade.id, 'status', 'expired', 'completed_at', now(), 'xp_awarded', 0);
  end if;
  if not p_accept then
    update public.card_instances set locked_trade_id = null where locked_trade_id = v_trade.id;
    update public.card_trades set status = 'declined', responded_at = now() where id = v_trade.id;
    return jsonb_build_object('trade_id', v_trade.id, 'status', 'declined', 'completed_at', now(), 'xp_awarded', 0);
  end if;
  perform 1 from public.card_instances i
  join public.card_trade_items ti on ti.card_instance_id = i.id
  where ti.trade_id = v_trade.id order by i.id for update of i;
  select count(*) into v_item_count from public.card_trade_items where trade_id = v_trade.id;
  if (select count(*) from public.card_trade_items ti join public.card_instances i on i.id = ti.card_instance_id
      where ti.trade_id = v_trade.id
        and ((ti.side = 'offered' and i.owner_id = v_trade.proposer_id and i.locked_trade_id = v_trade.id)
          or (ti.side = 'requested' and i.owner_id = v_trade.recipient_id and i.locked_trade_id is null))) <> v_item_count then
    raise exception 'trade_inventory_changed' using errcode = '40001';
  end if;
  update public.card_instances i set
    owner_id = case ti.side when 'offered' then v_trade.recipient_id else v_trade.proposer_id end,
    locked_trade_id = null
  from public.card_trade_items ti where ti.trade_id = v_trade.id and ti.card_instance_id = i.id;
  update public.card_trades set status = 'accepted', responded_at = now() where id = v_trade.id;
  v_xp := 50;
  perform public.award_card_xp(v_trade.proposer_id, v_xp);
  perform public.award_card_xp(v_trade.recipient_id, v_xp);
  perform public.refresh_card_album_badges(v_trade.proposer_id);
  perform public.refresh_card_album_badges(v_trade.recipient_id);
  perform public.refresh_card_achievements(v_trade.proposer_id);
  perform public.refresh_card_achievements(v_trade.recipient_id);
  return jsonb_build_object('trade_id', v_trade.id, 'status', 'accepted', 'completed_at', now(), 'xp_awarded', v_xp);
end;
$$;

create or replace function public.cancel_card_trade(p_trade_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trade public.card_trades;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_trade from public.card_trades t where t.id = p_trade_id for update;
  if v_trade.id is null or v_trade.proposer_id <> auth.uid() or v_trade.status <> 'pending'::public.card_trade_status then
    raise exception 'trade_not_cancellable' using errcode = '42501';
  end if;
  update public.card_instances set locked_trade_id = null where locked_trade_id = v_trade.id;
  update public.card_trades set status = 'cancelled', responded_at = now() where id = v_trade.id;
  return jsonb_build_object('trade_id', v_trade.id, 'status', 'cancelled');
end;
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
    'offered_titles', (select coalesce(jsonb_agg(track.title order by ci.serial_number), '[]'::jsonb)
      from public.card_trade_items ti
      join public.card_instances ci on ci.id = ti.card_instance_id
      join public.collectible_card_definitions cd on cd.id = ci.definition_id
      join public.tracks track on track.id = cd.track_id
      where ti.trade_id = t.id and ti.side = 'offered'),
    'requested_titles', (select coalesce(jsonb_agg(track.title order by ci.serial_number), '[]'::jsonb)
      from public.card_trade_items ti
      join public.card_instances ci on ci.id = ti.card_instance_id
      join public.collectible_card_definitions cd on cd.id = ci.definition_id
      join public.tracks track on track.id = cd.track_id
      where ti.trade_id = t.id and ti.side = 'requested')
  ) order by t.created_at desc), '[]'::jsonb)) into v_result
  from public.card_trades t
  join public.profiles other_profile on other_profile.id = case when t.recipient_id = auth.uid() then t.proposer_id else t.recipient_id end
  where t.proposer_id = auth.uid() or t.recipient_id = auth.uid();
  return v_result;
end;
$$;

create or replace function public.card_game_dashboard()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_stats public.card_player_stats; v_badges jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform public.ensure_card_player(auth.uid());
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
  select * into v_stats from public.card_player_stats s where s.user_id = auth.uid();
  select coalesce(jsonb_agg(jsonb_build_object(
    'badge_id', b.id, 'album_id', al.id, 'title', b.title,
    'artwork_path', coalesce(b.artwork_path, al.artwork_path), 'slot', ub.equipped_slot
  ) order by ub.equipped_slot), '[]'::jsonb) into v_badges
  from public.card_user_badges ub
  join public.card_badges b on b.id = ub.badge_id
  join public.collectible_albums al on al.id = b.album_id
  where ub.user_id = auth.uid() and ub.equipped_slot is not null;
  return jsonb_build_object(
    'user_id', auth.uid(), 'xp', v_stats.xp, 'level', v_stats.level,
    'xp_for_next_level', greatest(0, (v_stats.level::bigint * v_stats.level::bigint * 500) - v_stats.xp),
    'next_level_xp', v_stats.level::bigint * v_stats.level::bigint * 500,
    'current_streak', v_stats.current_streak, 'best_streak', v_stats.best_streak,
    'streak_day', v_stats.streak_day, 'streak_cycle', v_stats.streak_cycle,
    'last_daily_claim', v_stats.last_daily_claim,
    'unopened_pack_count', (select count(*) from public.card_packs p where p.owner_id = auth.uid() and p.status = 'sealed'),
    'unopened_packs', (select count(*) from public.card_packs p where p.owner_id = auth.uid() and p.status = 'sealed'),
    'daily_claim_available', v_stats.last_daily_claim is distinct from (now() at time zone 'UTC')::date,
    'favorite_artists', (select coalesce(array_agg(a.artist_key order by f.position), '{}'::text[])
      from public.card_favorite_artists f join public.collectible_artists a on a.id = f.artist_id
      where f.user_id = auth.uid()),
    'total_cards', (select count(*) from public.card_instances i where i.owner_id = auth.uid()),
    'unique_cards', (select count(distinct i.definition_id) from public.card_instances i where i.owner_id = auth.uid()),
    'completed_albums', (select count(*) from public.card_user_badges b where b.user_id = auth.uid()),
    'completed_trades', (select count(*) from public.card_trades t where t.status = 'accepted' and (t.proposer_id = auth.uid() or t.recipient_id = auth.uid())),
    'achievement_count', (select count(*) from public.card_user_achievements a where a.user_id = auth.uid()),
    'unclaimed_achievement_rewards', (select count(*) from public.card_user_achievements a where a.user_id = auth.uid() and a.reward_claimed_at is null),
    'equipped_badges', v_badges
  );
end;
$$;

create or replace function public.init_card_player_from_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.card_player_stats(user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists profiles_init_card_player on public.profiles;
create trigger profiles_init_card_player after insert on public.profiles
for each row execute procedure public.init_card_player_from_profile();

-- RLS: catalogue is readable, private state is owner/participant-only, mutations use RPCs.
alter table public.card_game_config enable row level security;
alter table public.collectible_artists enable row level security;
alter table public.collectible_albums enable row level security;
alter table public.collectible_card_definitions enable row level security;
alter table public.card_player_stats enable row level security;
alter table public.card_favorite_artists enable row level security;
alter table public.card_packs enable row level security;
alter table public.card_pack_codes enable row level security;
alter table public.card_pack_code_redemptions enable row level security;
alter table public.card_instances enable row level security;
alter table public.card_listen_state enable row level security;
alter table public.card_listen_events enable row level security;
alter table public.card_daily_claims enable row level security;
alter table public.card_beta_members enable row level security;
alter table public.card_achievement_definitions enable row level security;
alter table public.card_user_achievements enable row level security;
alter table public.card_share_events enable row level security;
alter table public.card_badges enable row level security;
alter table public.card_user_badges enable row level security;
alter table public.card_trades enable row level security;
alter table public.card_trade_items enable row level security;

drop policy if exists card_game_config_read on public.card_game_config;
create policy card_game_config_read on public.card_game_config for select to authenticated using (true);
drop policy if exists card_game_config_admin_all on public.card_game_config;
create policy card_game_config_admin_all on public.card_game_config for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists collectible_artists_read on public.collectible_artists;
create policy collectible_artists_read on public.collectible_artists for select to authenticated using (is_enabled or public.is_admin());
drop policy if exists collectible_artists_admin_all on public.collectible_artists;
create policy collectible_artists_admin_all on public.collectible_artists for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists collectible_albums_read on public.collectible_albums;
create policy collectible_albums_read on public.collectible_albums for select to authenticated using (is_enabled or public.is_admin());
drop policy if exists collectible_albums_admin_all on public.collectible_albums;
create policy collectible_albums_admin_all on public.collectible_albums for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists collectible_cards_read on public.collectible_card_definitions;
create policy collectible_cards_read on public.collectible_card_definitions for select to authenticated using (is_enabled or public.is_admin());
drop policy if exists collectible_cards_admin_all on public.collectible_card_definitions;
create policy collectible_cards_admin_all on public.collectible_card_definitions for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists card_stats_owner_read on public.card_player_stats;
create policy card_stats_owner_read on public.card_player_stats for select to authenticated using (user_id = auth.uid());
drop policy if exists card_favorites_read on public.card_favorite_artists;
create policy card_favorites_read on public.card_favorite_artists for select to authenticated using (true);
drop policy if exists card_packs_owner_read on public.card_packs;
create policy card_packs_owner_read on public.card_packs for select to authenticated using (owner_id = auth.uid());
drop policy if exists card_codes_admin_read on public.card_pack_codes;
create policy card_codes_admin_read on public.card_pack_codes for select to authenticated using (public.is_admin());
drop policy if exists card_redemptions_owner_read on public.card_pack_code_redemptions;
create policy card_redemptions_owner_read on public.card_pack_code_redemptions for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists card_instances_owner_read on public.card_instances;
create policy card_instances_owner_read on public.card_instances for select to authenticated using (owner_id = auth.uid());
drop policy if exists card_listen_state_owner_read on public.card_listen_state;
create policy card_listen_state_owner_read on public.card_listen_state for select to authenticated using (user_id = auth.uid());
drop policy if exists card_listen_events_owner_read on public.card_listen_events;
create policy card_listen_events_owner_read on public.card_listen_events for select to authenticated using (user_id = auth.uid());
drop policy if exists card_daily_owner_read on public.card_daily_claims;
create policy card_daily_owner_read on public.card_daily_claims for select to authenticated using (user_id = auth.uid());
drop policy if exists card_beta_owner_read on public.card_beta_members;
create policy card_beta_owner_read on public.card_beta_members for select to authenticated using (user_id = auth.uid());
drop policy if exists card_achievements_catalog_read on public.card_achievement_definitions;
create policy card_achievements_catalog_read on public.card_achievement_definitions for select to authenticated using (is_enabled or public.is_admin());
drop policy if exists card_achievements_owner_read on public.card_user_achievements;
create policy card_achievements_owner_read on public.card_user_achievements for select to authenticated using (user_id = auth.uid());
drop policy if exists card_shares_owner_read on public.card_share_events;
create policy card_shares_owner_read on public.card_share_events for select to authenticated using (user_id = auth.uid());
drop policy if exists card_badges_read on public.card_badges;
create policy card_badges_read on public.card_badges for select to authenticated using (true);
drop policy if exists card_user_badges_read on public.card_user_badges;
create policy card_user_badges_read on public.card_user_badges for select to authenticated using (true);
drop policy if exists card_trades_participant_read on public.card_trades;
create policy card_trades_participant_read on public.card_trades for select to authenticated using (proposer_id = auth.uid() or recipient_id = auth.uid());
drop policy if exists card_trade_items_participant_read on public.card_trade_items;
create policy card_trade_items_participant_read on public.card_trade_items for select to authenticated using (
  exists (select 1 from public.card_trades t where t.id = trade_id and (t.proposer_id = auth.uid() or t.recipient_id = auth.uid()))
);

-- Explicit least privilege. No direct writes to game state are granted to clients.
revoke all on public.card_game_config, public.collectible_artists, public.collectible_albums,
  public.collectible_card_definitions, public.card_player_stats, public.card_favorite_artists,
  public.card_packs, public.card_pack_codes, public.card_pack_code_redemptions, public.card_instances,
  public.card_listen_state, public.card_listen_events, public.card_daily_claims, public.card_beta_members,
  public.card_achievement_definitions, public.card_user_achievements, public.card_share_events,
  public.card_badges, public.card_user_badges, public.card_trades, public.card_trade_items from anon, authenticated;

grant select on public.card_game_config, public.collectible_artists, public.collectible_albums,
  public.collectible_card_definitions, public.card_player_stats, public.card_favorite_artists,
  public.card_packs, public.card_pack_code_redemptions, public.card_instances,
  public.card_listen_state, public.card_listen_events, public.card_daily_claims, public.card_beta_members,
  public.card_achievement_definitions, public.card_user_achievements, public.card_share_events,
  public.card_badges, public.card_user_badges, public.card_trades, public.card_trade_items to authenticated;
grant select, insert, update, delete on public.collectible_artists, public.collectible_albums,
  public.collectible_card_definitions to authenticated;
grant select, insert, update, delete on public.card_game_config to authenticated;
grant select on public.card_pack_codes to authenticated;
grant usage on type public.card_rarity, public.card_pack_status, public.card_trade_status to authenticated;

revoke all on function public.card_level_for_xp(bigint), public.card_rarity_rank(public.card_rarity),
  public.card_rarity_from_popularity(bigint, double precision),
  public.ensure_card_player(uuid), public.award_card_xp(uuid, integer),
  public.create_card_pack_internal(uuid, text, uuid, integer, public.card_rarity),
  public.refresh_card_rarities_internal(), public.refresh_card_album_badges(uuid),
  public.card_achievement_progress_for(uuid, text), public.refresh_card_achievements(uuid),
  public.release_expired_card_trades(), public.init_card_player_from_profile() from public, anon, authenticated;

revoke all on function public.sync_collectible_catalog(text), public.refresh_card_rarities(),
  public.create_card_pack_code(text, text, integer, timestamptz, text, integer, public.card_rarity),
  public.redeem_pack_code(text), public.open_card_pack(uuid), public.card_pack_feed(),
  public.card_inventory_feed(), public.card_tradeable_inventory(text), public.card_available_artists(),
  public.card_album_progress(), public.card_achievement_feed(), public.set_favorite_artists(text[]),
  public.equip_card_badge(uuid, smallint), public.claim_daily_card_reward(),
  public.record_card_listening(uuid, integer), public.record_now_playing_share(uuid),
  public.claim_card_achievement(text, text), public.create_card_trade(uuid, uuid[], uuid[]),
  public.respond_card_trade(uuid, boolean), public.cancel_card_trade(uuid), public.card_trade_feed(),
  public.card_game_dashboard() from public, anon;

grant execute on function public.sync_collectible_catalog(text), public.refresh_card_rarities(),
  public.create_card_pack_code(text, text, integer, timestamptz, text, integer, public.card_rarity),
  public.redeem_pack_code(text), public.open_card_pack(uuid), public.card_pack_feed(),
  public.card_inventory_feed(), public.card_tradeable_inventory(text), public.card_available_artists(),
  public.card_album_progress(), public.card_achievement_feed(), public.set_favorite_artists(text[]),
  public.equip_card_badge(uuid, smallint), public.claim_daily_card_reward(),
  public.record_card_listening(uuid, integer), public.record_now_playing_share(uuid),
  public.claim_card_achievement(text, text), public.create_card_trade(uuid, uuid[], uuid[]),
  public.respond_card_trade(uuid, boolean), public.cancel_card_trade(uuid), public.card_trade_feed(),
  public.card_game_dashboard() to authenticated;

comment on table public.collectible_card_definitions is
  'Card catalogue referencing public YePly tracks; no external provider metadata is copied.';
comment on table public.card_instances is
  'Server-issued card instances. UUID is the public instance ID and serial_number is a monotonic display serial.';
comment on function public.record_card_listening(uuid, integer) is
  'Rate-limited listening heartbeat. It limits casual client fraud but cannot prove real playback without a trusted attestation service.';
comment on function public.respond_card_trade(uuid, boolean) is
  'Atomically validates locked ownership and transfers both sides of a trade.';

commit;
