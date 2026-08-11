-- Fix `open_card_pack` after the card economy rollout.
-- RETURNS TABLE fields are PL/pgSQL variables, so every potentially
-- conflicting column reference must be qualified.

create or replace function public.open_card_pack(p_pack_id uuid)
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer,
  converted_to_coins boolean, coins_awarded bigint
)
language plpgsql security definer set search_path = '' as $$
declare
  v_pack public.card_packs; v_definition_id uuid; v_instance_id uuid;
  v_serial bigint; v_acquired timestamptz; v_rarity public.card_rarity;
  v_score numeric; v_version text; v_counter integer; v_owned_count integer;
  v_coins bigint := 0;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 0));
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
      and (v_pack.pack_type <> 'favorites' or exists (
        select 1 from public.card_favorite_artists f
        where f.user_id = auth.uid() and f.artist_id = d.artist_id
      ))
      and public.card_rarity_rank(d.rarity) >= public.card_rarity_rank(v_pack.rarity_floor)
    order by (
      -ln(greatest(random(), 0.000000001)) /
      (d.drop_weight * case
        when d.rarity = 'mythic'::public.card_rarity then v_pack.mythic_weight_multiplier
        when v_pack.pack_type = 'mythic_boost' and d.rarity = 'epic'::public.card_rarity then 1.5
        else 1 end)
    ), d.id limit 1;
    if v_definition_id is null then raise exception 'empty_card_pool' using errcode = 'P0002'; end if;

    select count(*) into v_owned_count from public.card_instances i
    where i.owner_id = auth.uid() and i.definition_id = v_definition_id and i.retired_at is null;
    v_acquired := now(); v_coins := 0;
    if v_owned_count >= 2 then
      v_instance_id := gen_random_uuid(); v_serial := 0;
      v_coins := public.card_coin_value(v_definition_id, true);
      perform public.apply_card_coins(
        auth.uid(), v_coins, 'duplicate_conversion', v_instance_id,
        jsonb_build_object('definition_id', v_definition_id, 'source_pack_id', v_pack.id)
      );
    else
      insert into public.card_instances(
        definition_id, owner_id, source_pack_id, rarity_at_mint,
        popularity_score_at_mint, rarity_version_at_mint
      ) values (v_definition_id, auth.uid(), v_pack.id, v_rarity, v_score, v_version)
      returning id, card_instances.serial_number, card_instances.acquired_at
      into v_instance_id, v_serial, v_acquired;
      delete from public.card_wishlist as wishlist
      where wishlist.user_id = auth.uid()
        and wishlist.definition_id = v_definition_id;
    end if;

    return query
    select v_instance_id, v_serial, d.id, d.track_id,
           coalesce(d.title, t.title), coalesce(d.artist_name, t.artist_name, a.display_name),
           coalesce(d.album_name, t.album_name, al.title, p.title),
           coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(al.artwork_path), ''),
                    nullif(btrim(t.artwork_path), ''), nullif(btrim(p.cover_path), '')),
           v_rarity, v_acquired, d.source_url, d.catalog_source,
           d.global_listen_count, d.global_listener_count, v_score,
           d.artist_popularity_rank, d.artist_catalog_size,
           (v_owned_count >= 2), v_coins
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

revoke all on function public.open_card_pack(uuid) from public;
grant execute on function public.open_card_pack(uuid) to authenticated;
