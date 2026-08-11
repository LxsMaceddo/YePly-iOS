-- YePly Cards 2.2: Apple Music Top Songs signal, hybrid rarity and admin pack grants.
-- Apple Music publishes a storefront-specific popularity order, not public play counts.

begin;

alter table public.collectible_card_definitions
  add column if not exists apple_music_id text,
  add column if not exists apple_music_url text,
  add column if not exists apple_music_rank integer,
  add column if not exists apple_music_storefront text,
  add column if not exists apple_music_snapshot_at timestamptz;

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_apple_music_rank_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_apple_music_rank_check
  check (apple_music_rank is null or apple_music_rank between 1 and 200);

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_apple_music_url_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_apple_music_url_check
  check (apple_music_url is null or apple_music_url like 'https://music.apple.com/%');

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_apple_music_storefront_check;
alter table public.collectible_card_definitions
  add constraint collectible_cards_apple_music_storefront_check
  check (apple_music_storefront is null or apple_music_storefront ~ '^[a-z]{2}$');

create or replace function public.refresh_card_rarities_internal()
returns void language plpgsql security definer set search_path = '' as $$
begin
  with internal_plays as (
    select d.id, coalesce(sum(h.play_count), 0)::bigint as plays
    from public.collectible_card_definitions d
    left join public.playback_history h on h.track_id = d.track_id
    where d.is_enabled
    group by d.id
  ), component_percentiles as (
    select d.id, d.artist_id, ip.plays,
      case when max(d.global_listen_count) over (partition by d.artist_id) > 0
        then cume_dist() over (partition by d.artist_id order by d.global_listen_count)
        else 0 end::double precision as listen_score,
      case when max(d.global_listener_count) over (partition by d.artist_id) > 0
        then cume_dist() over (partition by d.artist_id order by d.global_listener_count)
        else 0 end::double precision as listener_score,
      case when d.apple_music_rank is not null
        then greatest(0::double precision, 1 - ((d.apple_music_rank - 1)::double precision / 99))
        else 0 end as apple_score,
      case when max(ip.plays) over (partition by d.artist_id) > 0
        then cume_dist() over (partition by d.artist_id order by ip.plays)
        else 0 end::double precision as yeply_score,
      (d.global_listen_count > 0 or d.global_listener_count > 0
        or d.apple_music_rank is not null or ip.plays > 0) as has_signal
    from public.collectible_card_definitions d
    join internal_plays ip on ip.id = d.id
    where d.is_enabled
  ), composite as (
    select c.*,
      (c.listen_score * 0.60 + c.listener_score * 0.20
        + c.apple_score * 0.15 + c.yeply_score * 0.05)::double precision as composite_score
    from component_percentiles c
  ), ranked as (
    select c.*,
      cume_dist() over (partition by c.artist_id order by c.composite_score)::double precision
        as popularity_percentile
    from composite c
  )
  update public.collectible_card_definitions d
  set yeply_play_count = r.plays,
      play_count_snapshot = greatest(d.global_listen_count, r.plays),
      popularity_score = round(((case when r.has_signal then r.popularity_percentile else 0 end) * 100)::numeric, 3),
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
      rarity_version = 'hybrid-v2:' || to_char(current_date, 'YYYY-MM'),
      updated_at = now()
  from ranked r
  where r.id = d.id;
end;
$$;

create or replace function public.import_apple_music_card_ranking(
  p_artist_mbid uuid,
  p_storefront text,
  p_rows jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_artist_id uuid;
  v_storefront text := lower(btrim(coalesce(p_storefront, '')));
  v_row jsonb;
  v_recording_mbid uuid;
  v_url text;
  v_updated integer := 0;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if p_artist_mbid is null or v_storefront !~ '^[a-z]{2}$'
     or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 200 then
    raise exception 'invalid_apple_music_payload' using errcode = '22023';
  end if;

  select a.id into v_artist_id
  from public.collectible_artists a
  where a.source_artist_id = p_artist_mbid and a.is_enabled;
  if v_artist_id is null then
    raise exception 'artist_not_found' using errcode = 'P0002';
  end if;

  update public.collectible_card_definitions
  set apple_music_id = null, apple_music_url = null, apple_music_rank = null,
      apple_music_storefront = null, apple_music_snapshot_at = null, updated_at = now()
  where artist_id = v_artist_id;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    begin
      v_recording_mbid := nullif(v_row ->> 'recording_mbid', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid_recording_mbid' using errcode = '22023';
    end;
    v_url := nullif(left(btrim(coalesce(v_row ->> 'apple_music_url', '')), 1000), '');
    if v_recording_mbid is null
       or coalesce((v_row ->> 'rank')::integer, 0) not between 1 and 200
       or (v_url is not null and v_url not like 'https://music.apple.com/%') then
      raise exception 'invalid_apple_music_row' using errcode = '22023';
    end if;

    update public.collectible_card_definitions
    set apple_music_id = nullif(left(btrim(coalesce(v_row ->> 'apple_music_id', '')), 80), ''),
        apple_music_url = v_url,
        apple_music_rank = (v_row ->> 'rank')::integer,
        apple_music_storefront = v_storefront,
        apple_music_snapshot_at = now(),
        updated_at = now()
    where artist_id = v_artist_id and source_recording_id = v_recording_mbid and is_enabled;
    if found then v_updated := v_updated + 1; end if;
  end loop;

  perform public.refresh_card_rarities_internal();
  return jsonb_build_object(
    'success', true,
    'message', v_updated || ' músicas combinadas com o Top Songs do Apple Music.',
    'matched_tracks', v_updated,
    'storefront', v_storefront,
    'rarity_model', 'hybrid-v2'
  );
end;
$$;

create table if not exists public.card_admin_pack_grants (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete restrict,
  recipient_id uuid not null references public.profiles(id) on delete restrict,
  pack_count smallint not null check (pack_count between 1 and 25),
  cards_per_pack smallint not null check (cards_per_pack between 1 and 5),
  artist_id uuid references public.collectible_artists(id) on delete set null,
  rarity_floor public.card_rarity not null default 'common',
  reason text check (reason is null or char_length(reason) <= 200),
  created_at timestamptz not null default now()
);

alter table public.card_admin_pack_grants enable row level security;
drop policy if exists card_admin_pack_grants_admin_read on public.card_admin_pack_grants;
create policy card_admin_pack_grants_admin_read on public.card_admin_pack_grants
  for select to authenticated using (public.is_admin());

create index if not exists card_admin_pack_grants_recipient_idx
  on public.card_admin_pack_grants(recipient_id, created_at desc);

create or replace function public.admin_grant_card_packs(
  p_username text,
  p_pack_count integer default 1,
  p_card_count integer default 3,
  p_artist_key text default null,
  p_rarity_floor public.card_rarity default 'common',
  p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_username text := lower(regexp_replace(btrim(coalesce(p_username, '')), '^@', ''));
  v_recipient_id uuid;
  v_artist_id uuid;
  v_artist_key text := nullif(lower(regexp_replace(btrim(coalesce(p_artist_key, '')), '\s+', ' ', 'g')), '');
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_counter integer;
  v_pack_id uuid;
  v_pack_ids jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  if v_username !~ '^[a-z0-9_]{3,30}$' or p_pack_count not between 1 and 25
     or p_card_count not between 1 and 5 or char_length(coalesce(v_reason, '')) > 200 then
    raise exception 'invalid_pack_grant' using errcode = '22023';
  end if;

  select p.id into v_recipient_id from public.profiles p where p.username = v_username;
  if v_recipient_id is null then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  if v_artist_key is not null then
    select a.id into v_artist_id
    from public.collectible_artists a
    where a.artist_key = v_artist_key and a.is_enabled;
    if v_artist_id is null then
      raise exception 'artist_not_found' using errcode = 'P0002';
    end if;
  end if;

  for v_counter in 1..p_pack_count loop
    v_pack_id := public.create_card_pack_internal(
      v_recipient_id, 'admin', v_artist_id, p_card_count, p_rarity_floor
    );
    v_pack_ids := v_pack_ids || jsonb_build_array(v_pack_id);
  end loop;

  insert into public.card_admin_pack_grants(
    admin_id, recipient_id, pack_count, cards_per_pack, artist_id, rarity_floor, reason
  ) values (
    auth.uid(), v_recipient_id, p_pack_count, p_card_count, v_artist_id, p_rarity_floor, v_reason
  );

  return jsonb_build_object(
    'success', true,
    'message', p_pack_count || case when p_pack_count = 1 then ' pack enviado para @' else ' packs enviados para @' end || v_username || '.',
    'recipient_username', v_username,
    'packs_awarded', p_pack_count,
    'pack_ids', v_pack_ids
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
  return jsonb_build_object(
    'success', true,
    'message', 'Raridades recalculadas pelo modelo híbrido por artista.',
    'card_count', (select count(*) from public.collectible_card_definitions where is_enabled),
    'rarity_model', 'hybrid-v2'
  );
end;
$$;

revoke all on table public.card_admin_pack_grants from public, anon, authenticated;
grant select on table public.card_admin_pack_grants to authenticated;

revoke all on function public.import_apple_music_card_ranking(uuid, text, jsonb),
  public.admin_grant_card_packs(text, integer, integer, text, public.card_rarity, text)
  from public, anon, authenticated;
grant execute on function public.import_apple_music_card_ranking(uuid, text, jsonb),
  public.admin_grant_card_packs(text, integer, integer, text, public.card_rarity, text)
  to authenticated;

comment on table public.card_admin_pack_grants is
  'Immutable audit trail of packs granted by YePly administrators.';
comment on function public.import_apple_music_card_ranking(uuid, text, jsonb) is
  'Admin-only Apple Music Top Songs snapshot. Stores ranking, not fabricated play counts.';
comment on function public.admin_grant_card_packs(text, integer, integer, text, public.card_rarity, text) is
  'Admin-only pack delivery with recipient validation and an audit record.';

commit;
