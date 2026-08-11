begin;

-- Playlist covers are social content. Authenticated users must be able to sign
-- the cover of a playlist they can see, including shared/public playlists.
drop policy if exists covers_read_allowed on storage.objects;
create policy covers_read_allowed on storage.objects for select to authenticated using (
  bucket_id = 'covers' and (
    (storage.foldername(name))[1] = 'catalog'
    or case
      when (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        then public.can_read_playlist(((storage.foldername(name))[1])::uuid)
      else false
    end
  )
);

-- The visible edition is local to the song definition: copy N of total minted.
create or replace function public.card_inventory_social_feed_v2_page(
  p_offset integer default 0,
  p_limit integer default 500
) returns table(
  instance_id uuid,serial_number bigint,edition_number bigint,edition_total bigint,
  definition_id uuid,track_id uuid,title text,artist_name text,album_name text,
  artwork_path text,rarity public.card_rarity,acquired_at timestamptz,external_url text,
  catalog_source text,global_listen_count bigint,global_listener_count bigint,
  popularity_score numeric,artist_popularity_rank integer,artist_catalog_size integer,is_protected boolean
) language sql stable security definer set search_path='' as $$
  with editions as (
    select i.id,
      row_number() over(partition by i.definition_id order by i.serial_number) as edition_number,
      count(*) over(partition by i.definition_id) as edition_total
    from public.card_instances i where i.retired_at is null
  )
  select i.id,i.serial_number,e.edition_number,e.edition_total,d.id,d.track_id,
    coalesce(d.title,t.title),coalesce(d.artist_name,t.artist_name,a.display_name),
    coalesce(d.album_name,t.album_name,al.title,p.title),
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(t.artwork_path),''),nullif(btrim(p.cover_path),'')),
    coalesce(i.rarity_at_mint,d.rarity),i.acquired_at,d.source_url,d.catalog_source,
    d.global_listen_count,d.global_listener_count,coalesce(i.popularity_score_at_mint,d.popularity_score),
    d.artist_popularity_rank,d.artist_catalog_size,i.is_protected
  from public.card_instances i join editions e on e.id=i.id
  join public.collectible_card_definitions d on d.id=i.definition_id
  join public.collectible_artists a on a.id=d.artist_id join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id left join public.playlists p on p.id=t.playlist_id
  where i.owner_id=auth.uid() and i.retired_at is null
  order by i.acquired_at desc,i.serial_number desc
  limit least(greatest(p_limit,1),500) offset greatest(p_offset,0)
$$;

create or replace function public.card_public_offer_feed_v2(p_profile_id uuid default null)
returns table(offer_id uuid,owner_id uuid,username text,display_name text,avatar_path text,
  card_instance_id uuid,serial_number bigint,edition_number bigint,edition_total bigint,
  definition_id uuid,title text,artist_name text,album_name text,artwork_path text,
  rarity public.card_rarity,asking_coins bigint,note text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
  with editions as (
    select i.id,row_number() over(partition by i.definition_id order by i.serial_number) edition_number,
      count(*) over(partition by i.definition_id) edition_total
    from public.card_instances i where i.retired_at is null
  )
  select o.id,o.owner_id,p.username,p.display_name,p.avatar_path,i.id,i.serial_number,
    e.edition_number,e.edition_total,d.id,coalesce(d.title,t.title),
    coalesce(d.artist_name,t.artist_name,a.display_name),coalesce(d.album_name,t.album_name,al.title),
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(t.artwork_path),'')),
    coalesce(i.rarity_at_mint,d.rarity),o.asking_coins,o.note,o.created_at
  from public.card_public_offers o join public.profiles p on p.id=o.owner_id
  join public.card_instances i on i.id=o.card_instance_id and i.owner_id=o.owner_id and i.retired_at is null and not i.is_protected
  join editions e on e.id=i.id join public.collectible_card_definitions d on d.id=i.definition_id
  join public.collectible_artists a on a.id=d.artist_id join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id
  where auth.uid() is not null and o.status='open' and (p_profile_id is null or o.owner_id=p_profile_id)
  order by o.created_at desc limit 300
$$;

create or replace function public.buy_public_card_offer(p_offer_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_offer public.card_public_offers; v_instance public.card_instances;
  v_tax bigint; v_seller_receives bigint; v_buyer_balance bigint;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  select * into v_offer from public.card_public_offers o where o.id=p_offer_id for update;
  if v_offer.id is null or v_offer.status<>'open' then raise exception 'offer_not_available' using errcode='P0002'; end if;
  if v_offer.owner_id=auth.uid() then raise exception 'cannot_buy_own_offer' using errcode='22023'; end if;
  select * into v_instance from public.card_instances i where i.id=v_offer.card_instance_id for update;
  if v_instance.id is null or v_instance.owner_id<>v_offer.owner_id or v_instance.retired_at is not null
     or v_instance.is_protected or v_instance.locked_trade_id is not null then
    update public.card_public_offers set status='closed' where id=v_offer.id;
    raise exception 'offer_card_unavailable' using errcode='P0002';
  end if;
  if exists(select 1 from public.card_instances i where i.owner_id=auth.uid()
    and i.definition_id=v_instance.definition_id and i.retired_at is null) then
    raise exception 'card_already_owned' using errcode='23505';
  end if;

  v_tax := case when v_offer.asking_coins=0 then 0 else greatest(1,ceil(v_offer.asking_coins*0.07)::bigint) end;
  v_seller_receives := greatest(0,v_offer.asking_coins-v_tax);
  if v_offer.asking_coins>0 then
    v_buyer_balance := public.apply_card_coins(auth.uid(),-v_offer.asking_coins,'market_purchase',v_offer.id,
      jsonb_build_object('seller_id',v_offer.owner_id,'tax',v_tax));
  else
    perform public.ensure_card_wallet(auth.uid());
    select balance into v_buyer_balance from public.card_wallets where user_id=auth.uid();
  end if;
  if v_seller_receives>0 then
    perform public.apply_card_coins(v_offer.owner_id,v_seller_receives,'market_sale',v_offer.id,
      jsonb_build_object('buyer_id',auth.uid(),'gross',v_offer.asking_coins,'tax',v_tax));
  end if;
  delete from public.card_folder_items where card_instance_id=v_instance.id;
  update public.card_instances set owner_id=auth.uid(),acquired_at=now() where id=v_instance.id;
  delete from public.card_wishlist where user_id=auth.uid() and definition_id=v_instance.definition_id;
  update public.card_public_offers set status='closed' where id=v_offer.id;
  update public.profiles set featured_card_instance_id=null,updated_at=now()
    where id=v_offer.owner_id and featured_card_instance_id=v_instance.id;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_album_badges(v_offer.owner_id);
  perform public.refresh_card_achievements(auth.uid());
  return jsonb_build_object('success',true,'offer_id',v_offer.id,'instance_id',v_instance.id,
    'price',v_offer.asking_coins,'tax',v_tax,'seller_receives',v_seller_receives,'coin_balance',v_buyer_balance);
end; $$;

revoke all on function public.card_inventory_social_feed_v2_page(integer,integer),public.card_public_offer_feed_v2(uuid),
  public.buy_public_card_offer(uuid) from public,anon;
grant execute on function public.card_inventory_social_feed_v2_page(integer,integer),public.card_public_offer_feed_v2(uuid),
  public.buy_public_card_offer(uuid) to authenticated;

commit;
