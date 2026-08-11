begin;

-- Stable public artwork for the curated catalog. Old snapshots sometimes kept
-- a Storage path whose object was never mirrored, producing permanent placeholders.
with artwork(album_key, artwork_url) as (values
  ('the college dropout','https://coverartarchive.org/release-group/8a01217e-6947-3927-a39b-6691104694f1/front-500'),
  ('late registration','https://coverartarchive.org/release-group/c563d738-3841-31ce-b29d-ec6b40fd1e7b/front-500'),
  ('graduation','https://coverartarchive.org/release-group/d44c50ad-61fd-3fce-95fc-27024d7f1d30/front-500'),
  ('808s heartbreak','https://coverartarchive.org/release-group/1c1b50ec-828b-3d7c-9b1b-54cb1fe97d55/front-500'),
  ('my beautiful dark twisted fantasy','https://coverartarchive.org/release-group/5d6e21e1-deb5-428e-bb42-c2a567f3619b/front-500'),
  ('watch the throne deluxe','https://coverartarchive.org/release-group/a96597aa-93b4-4e14-9e6e-03892ab24979/front-500'),
  ('kanye west presents good music cruel summer','https://coverartarchive.org/release-group/1e06bb4d-3e20-4d1c-8d0a-0c179df397b5/front-500'),
  ('yeezus','https://coverartarchive.org/release-group/5d4d0f2d-9be7-4922-bc9a-cbd2880b12c2/front-500'),
  ('the life of pablo','https://coverartarchive.org/release-group/8c18657a-6338-490d-a952-897663596b96/front-500'),
  ('ye','https://coverartarchive.org/release-group/6448381d-9d98-4f84-b99d-733b6acde906/front-500'),
  ('kids see ghosts','https://coverartarchive.org/release-group/3346a9d9-031e-49e2-84b0-3734d790d7e5/front-500'),
  ('jesus is king','https://coverartarchive.org/release-group/ee26718c-2633-4278-8718-f3a45a95f20e/front-500'),
  ('donda deluxe','https://coverartarchive.org/release-group/7f4792fe-b563-4554-849a-95a89be71f84/front-500'),
  ('donda 2','https://coverartarchive.org/release-group/26584460-df1f-4a91-b036-8d0bf6f8ce95/front-500'),
  ('vultures 1','https://coverartarchive.org/release-group/c4d999c3-983d-4149-8580-9ccb4567a12a/front-500'),
  ('vultures 2','https://coverartarchive.org/release-group/d69250da-c94d-436d-bacf-7e52da48bc68/front-500')
), matched as (
  select al.id, artwork.artwork_url
  from public.collectible_albums al
  join artwork on artwork.album_key = trim(regexp_replace(
    lower(replace(replace(al.title,'&',' '),'(deluxe)',' deluxe')),
    '[^a-z0-9]+',' ','g'))
)
update public.collectible_albums al set artwork_path = matched.artwork_url
from matched where matched.id = al.id;

update public.collectible_card_definitions d set artwork_path = al.artwork_path
from public.collectible_albums al
where al.id = d.album_id and al.artwork_path like 'https://coverartarchive.org/%';

alter table public.card_instances add column if not exists is_protected boolean not null default false;
create index if not exists card_instances_protected_owner_idx
  on public.card_instances(owner_id,is_protected) where retired_at is null;

create table if not exists public.card_folders (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check(length(btrim(name)) between 1 and 40),
  emoji text not null default '📁' check(length(emoji) between 1 and 16),
  is_public boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(owner_id,name)
);
create table if not exists public.card_folder_items (
  folder_id uuid not null references public.card_folders(id) on delete cascade,
  card_instance_id uuid not null references public.card_instances(id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key(folder_id,card_instance_id)
);

create table if not exists public.profile_music_presence (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  track_id uuid references public.tracks(id) on delete set null,
  title text not null,
  artist_name text not null,
  album_name text,
  artwork_path text,
  position_seconds integer not null default 0 check(position_seconds >= 0),
  duration_seconds integer not null default 0 check(duration_seconds >= 0),
  is_playing boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.card_public_offers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  card_instance_id uuid not null references public.card_instances(id) on delete cascade,
  asking_coins bigint not null default 0 check(asking_coins between 0 and 10000000),
  note text check(note is null or length(note) <= 180),
  status text not null default 'open' check(status in ('open','closed')),
  created_at timestamptz not null default now(),
  unique(card_instance_id)
);

alter table public.card_folders enable row level security;
alter table public.card_folder_items enable row level security;
alter table public.profile_music_presence enable row level security;
alter table public.card_public_offers enable row level security;

drop policy if exists card_folders_visible on public.card_folders;
create policy card_folders_visible on public.card_folders for select to authenticated
using(owner_id=auth.uid() or is_public);
drop policy if exists card_folders_owner_write on public.card_folders;
create policy card_folders_owner_write on public.card_folders for all to authenticated
using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists card_folder_items_visible on public.card_folder_items;
create policy card_folder_items_visible on public.card_folder_items for select to authenticated
using(exists(select 1 from public.card_folders f where f.id=folder_id and (f.owner_id=auth.uid() or f.is_public)));
drop policy if exists card_folder_items_owner_write on public.card_folder_items;
create policy card_folder_items_owner_write on public.card_folder_items for all to authenticated
using(exists(select 1 from public.card_folders f where f.id=folder_id and f.owner_id=auth.uid()))
with check(exists(select 1 from public.card_folders f where f.id=folder_id and f.owner_id=auth.uid()));
drop policy if exists profile_presence_visible on public.profile_music_presence;
create policy profile_presence_visible on public.profile_music_presence for select to authenticated using(true);
drop policy if exists profile_presence_owner_write on public.profile_music_presence;
create policy profile_presence_owner_write on public.profile_music_presence for all to authenticated
using(profile_id=auth.uid()) with check(profile_id=auth.uid());
drop policy if exists card_public_offers_visible on public.card_public_offers;
create policy card_public_offers_visible on public.card_public_offers for select to authenticated using(status='open' or owner_id=auth.uid());
drop policy if exists card_public_offers_owner_write on public.card_public_offers;
create policy card_public_offers_owner_write on public.card_public_offers for all to authenticated
using(owner_id=auth.uid()) with check(owner_id=auth.uid());

create or replace function public.toggle_card_protection(p_instance_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_value boolean;
begin
  update public.card_instances i set is_protected=not i.is_protected
  where i.id=p_instance_id and i.owner_id=auth.uid() and i.retired_at is null
    and i.locked_trade_id is null
  returning i.is_protected into v_value;
  if v_value is null then raise exception 'card_not_available' using errcode='P0002'; end if;
  if v_value then
    update public.card_public_offers set status='closed'
    where card_instance_id=p_instance_id and owner_id=auth.uid() and status='open';
  end if;
  return jsonb_build_object('success',true,'is_protected',v_value,'message',case when v_value then 'Carta protegida.' else 'Proteção removida.' end);
end; $$;

create or replace function public.prevent_protected_card_trade()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from public.card_instances i where i.id=new.card_instance_id and i.is_protected) then
    raise exception 'protected_card_cannot_be_traded' using errcode='42501';
  end if;
  return new;
end; $$;
drop trigger if exists card_trade_items_reject_protected on public.card_trade_items;
create trigger card_trade_items_reject_protected before insert on public.card_trade_items
for each row execute function public.prevent_protected_card_trade();

create or replace function public.card_inventory_social_feed_page(p_offset integer default 0,p_limit integer default 500)
returns table(
  instance_id uuid,serial_number bigint,definition_id uuid,track_id uuid,title text,
  artist_name text,album_name text,artwork_path text,rarity public.card_rarity,
  acquired_at timestamptz,external_url text,catalog_source text,global_listen_count bigint,
  global_listener_count bigint,popularity_score numeric,artist_popularity_rank integer,
  artist_catalog_size integer,is_protected boolean
) language sql stable security definer set search_path='' as $$
  select i.id,i.serial_number,d.id,d.track_id,coalesce(d.title,t.title),
    coalesce(d.artist_name,t.artist_name,a.display_name),coalesce(d.album_name,t.album_name,al.title,p.title),
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(t.artwork_path),''),nullif(btrim(p.cover_path),'')),
    coalesce(i.rarity_at_mint,d.rarity),i.acquired_at,d.source_url,d.catalog_source,d.global_listen_count,
    d.global_listener_count,coalesce(i.popularity_score_at_mint,d.popularity_score),d.artist_popularity_rank,
    d.artist_catalog_size,i.is_protected
  from public.card_instances i join public.collectible_card_definitions d on d.id=i.definition_id
  join public.collectible_artists a on a.id=d.artist_id join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id left join public.playlists p on p.id=t.playlist_id
  where i.owner_id=auth.uid() and i.retired_at is null
  order by i.acquired_at desc,i.serial_number desc
  limit least(greatest(p_limit,1),500) offset greatest(p_offset,0)
$$;

create or replace function public.create_card_folder(p_name text,p_emoji text default '📁',p_is_public boolean default true)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  insert into public.card_folders(owner_id,name,emoji,is_public)
  values(auth.uid(),btrim(p_name),coalesce(nullif(btrim(p_emoji),''),'📁'),p_is_public) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.delete_card_folder(p_folder_id uuid)
returns boolean language sql security definer set search_path='' as $$
  with deleted as(delete from public.card_folders where id=p_folder_id and owner_id=auth.uid() returning 1)
  select exists(select 1 from deleted)
$$;

create or replace function public.toggle_card_folder_item(p_folder_id uuid,p_instance_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_added boolean;
begin
  if not exists(select 1 from public.card_folders f where f.id=p_folder_id and f.owner_id=auth.uid())
    or not exists(select 1 from public.card_instances i where i.id=p_instance_id and i.owner_id=auth.uid() and i.retired_at is null)
  then raise exception 'folder_or_card_not_found' using errcode='P0002'; end if;
  delete from public.card_folder_items x where x.folder_id=p_folder_id and x.card_instance_id=p_instance_id;
  if found then v_added=false;
  else insert into public.card_folder_items(folder_id,card_instance_id) values(p_folder_id,p_instance_id);v_added=true;end if;
  return jsonb_build_object('success',true,'is_added',v_added);
end; $$;

create or replace function public.card_folder_feed(p_profile_id uuid default null)
returns table(folder_id uuid,owner_id uuid,name text,emoji text,is_public boolean,item_count bigint,items jsonb)
language sql stable security definer set search_path='' as $$
  select f.id,f.owner_id,f.name,f.emoji,f.is_public,count(fi.card_instance_id),
    coalesce(jsonb_agg(jsonb_build_object(
      'instance_id',i.id,'serial_number',i.serial_number,'definition_id',d.id,'track_id',d.track_id,
      'title',coalesce(d.title,t.title),'artist_name',coalesce(d.artist_name,t.artist_name,a.display_name),
      'album_name',coalesce(d.album_name,t.album_name,al.title),'artwork_path',coalesce(d.artwork_path,al.artwork_path,t.artwork_path),
      'rarity',coalesce(i.rarity_at_mint,d.rarity),'acquired_at',i.acquired_at,'is_protected',i.is_protected
    ) order by fi.added_at) filter(where i.id is not null),'[]'::jsonb)
  from public.card_folders f left join public.card_folder_items fi on fi.folder_id=f.id
  left join public.card_instances i on i.id=fi.card_instance_id and i.retired_at is null
  left join public.collectible_card_definitions d on d.id=i.definition_id
  left join public.collectible_artists a on a.id=d.artist_id left join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id
  where f.owner_id=coalesce(p_profile_id,auth.uid()) and (f.owner_id=auth.uid() or f.is_public)
  group by f.id order by f.sort_order,f.created_at
$$;

create or replace function public.upsert_profile_music_presence(
  p_track_id uuid,p_title text,p_artist_name text,p_album_name text,p_artwork_path text,
  p_position_seconds integer,p_duration_seconds integer,p_is_playing boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
begin
  insert into public.profile_music_presence(profile_id,track_id,title,artist_name,album_name,artwork_path,position_seconds,duration_seconds,is_playing,updated_at)
  values(auth.uid(),p_track_id,left(p_title,200),left(p_artist_name,200),left(p_album_name,200),p_artwork_path,
    greatest(p_position_seconds,0),greatest(p_duration_seconds,0),p_is_playing,now())
  on conflict(profile_id) do update set track_id=excluded.track_id,title=excluded.title,artist_name=excluded.artist_name,
    album_name=excluded.album_name,artwork_path=excluded.artwork_path,position_seconds=excluded.position_seconds,
    duration_seconds=excluded.duration_seconds,is_playing=excluded.is_playing,updated_at=now();
  return jsonb_build_object('success',true);
end; $$;

create or replace function public.profile_music_presence(p_profile_id uuid)
returns table(profile_id uuid,track_id uuid,title text,artist_name text,album_name text,artwork_path text,
  position_seconds integer,duration_seconds integer,is_playing boolean,updated_at timestamptz)
language sql stable security definer set search_path='' as $$
  select x.profile_id,x.track_id,x.title,x.artist_name,x.album_name,x.artwork_path,x.position_seconds,x.duration_seconds,
    x.is_playing and x.updated_at>now()-interval '90 seconds',x.updated_at
  from public.profile_music_presence x where x.profile_id=p_profile_id and x.updated_at>now()-interval '15 minutes'
$$;

create or replace function public.card_collector_profile(p_profile_id uuid)
returns table(total_cards bigint,unique_cards bigint,completed_albums bigint,completed_trades bigint,
  wishlist_count bigint,folder_count bigint,rarest_title text,rarest_rarity public.card_rarity)
language sql stable security definer set search_path='' as $$
  select count(i.id),count(distinct i.definition_id),
    (select count(*) from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
      where ub.user_id=p_profile_id and b.badge_kind='album'),
    (select count(*) from public.card_trades tr where tr.status='accepted' and (tr.proposer_id=p_profile_id or tr.recipient_id=p_profile_id)),
    (select count(*) from public.card_wishlist w where w.user_id=p_profile_id),
    (select count(*) from public.card_folders f where f.owner_id=p_profile_id and (p_profile_id=auth.uid() or f.is_public)),
    (array_agg(coalesce(d.title,t.title) order by public.card_rarity_rank(coalesce(i.rarity_at_mint,d.rarity)) desc,i.serial_number) filter(where i.id is not null))[1],
    (array_agg(coalesce(i.rarity_at_mint,d.rarity) order by public.card_rarity_rank(coalesce(i.rarity_at_mint,d.rarity)) desc,i.serial_number) filter(where i.id is not null))[1]
  from public.card_instances i join public.collectible_card_definitions d on d.id=i.definition_id
  left join public.tracks t on t.id=d.track_id where i.owner_id=p_profile_id and i.retired_at is null
$$;

create or replace function public.toggle_public_card_offer(p_instance_id uuid,p_asking_coins bigint default 0,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if exists(select 1 from public.card_public_offers o where o.card_instance_id=p_instance_id and o.owner_id=auth.uid() and o.status='open') then
    update public.card_public_offers set status='closed' where card_instance_id=p_instance_id and owner_id=auth.uid();
    return jsonb_build_object('success',true,'is_open',false);
  end if;
  if not exists(select 1 from public.card_instances i where i.id=p_instance_id and i.owner_id=auth.uid() and i.retired_at is null and not i.is_protected and i.locked_trade_id is null)
  then raise exception 'card_not_tradeable' using errcode='P0002';end if;
  insert into public.card_public_offers(owner_id,card_instance_id,asking_coins,note,status)
  values(auth.uid(),p_instance_id,greatest(p_asking_coins,0),nullif(btrim(p_note),''),'open')
  on conflict(card_instance_id) do update set asking_coins=excluded.asking_coins,note=excluded.note,status='open',created_at=now()
  returning id into v_id;
  return jsonb_build_object('success',true,'is_open',true,'offer_id',v_id);
end; $$;

create or replace function public.card_public_offer_feed()
returns table(offer_id uuid,owner_id uuid,username text,display_name text,avatar_path text,card_instance_id uuid,
  serial_number bigint,definition_id uuid,title text,artist_name text,album_name text,artwork_path text,
  rarity public.card_rarity,asking_coins bigint,note text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
  select o.id,o.owner_id,p.username,p.display_name,p.avatar_path,i.id,i.serial_number,d.id,coalesce(d.title,t.title),
    coalesce(d.artist_name,t.artist_name,a.display_name),coalesce(d.album_name,t.album_name,al.title),
    coalesce(d.artwork_path,al.artwork_path,t.artwork_path),coalesce(i.rarity_at_mint,d.rarity),o.asking_coins,o.note,o.created_at
  from public.card_public_offers o join public.profiles p on p.id=o.owner_id
  join public.card_instances i on i.id=o.card_instance_id and i.owner_id=o.owner_id and i.retired_at is null and not i.is_protected
  join public.collectible_card_definitions d on d.id=i.definition_id join public.collectible_artists a on a.id=d.artist_id
  join public.collectible_albums al on al.id=d.album_id left join public.tracks t on t.id=d.track_id
  where auth.uid() is not null and o.status='open' order by o.created_at desc limit 200
$$;

create or replace function public.card_trade_detail(p_trade_id uuid)
returns table(side text,instance_id uuid,serial_number bigint,definition_id uuid,title text,artist_name text,
  album_name text,artwork_path text,rarity public.card_rarity)
language sql stable security definer set search_path='' as $$
  select ti.side,i.id,i.serial_number,d.id,coalesce(d.title,t.title),coalesce(d.artist_name,t.artist_name,a.display_name),
    coalesce(d.album_name,t.album_name,al.title),coalesce(d.artwork_path,al.artwork_path,t.artwork_path),coalesce(i.rarity_at_mint,d.rarity)
  from public.card_trades tr join public.card_trade_items ti on ti.trade_id=tr.id
  join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id
  join public.collectible_artists a on a.id=d.artist_id join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id
  where tr.id=p_trade_id and (tr.proposer_id=auth.uid() or tr.recipient_id=auth.uid()) order by ti.side,i.serial_number
$$;

-- Protected cards never appear as tradeable and can never enter a new trade.
create or replace function public.card_tradeable_inventory(p_username text)
returns table(instance_id uuid,serial_number bigint,definition_id uuid,track_id uuid,title text,artist_name text,
  album_name text,artwork_path text,rarity public.card_rarity,acquired_at timestamptz,external_url text,
  catalog_source text,global_listen_count bigint,global_listener_count bigint,popularity_score numeric,
  artist_popularity_rank integer,artist_catalog_size integer)
language sql stable security definer set search_path='' as $$
  select i.id,i.serial_number,d.id,d.track_id,coalesce(d.title,t.title),coalesce(d.artist_name,t.artist_name,a.display_name),
    coalesce(d.album_name,t.album_name,al.title,p.title),coalesce(d.artwork_path,al.artwork_path,t.artwork_path,p.cover_path),
    coalesce(i.rarity_at_mint,d.rarity),i.acquired_at,d.source_url,d.catalog_source,d.global_listen_count,d.global_listener_count,
    coalesce(i.popularity_score_at_mint,d.popularity_score),d.artist_popularity_rank,d.artist_catalog_size
  from public.profiles target join public.card_instances i on i.owner_id=target.id and i.locked_trade_id is null
    and i.retired_at is null and not i.is_protected
  join public.collectible_card_definitions d on d.id=i.definition_id and d.is_enabled
  join public.collectible_artists a on a.id=d.artist_id and a.is_enabled join public.collectible_albums al on al.id=d.album_id and al.is_enabled
  left join public.tracks t on t.id=d.track_id left join public.playlists p on p.id=t.playlist_id
  where auth.uid() is not null and target.username=lower(regexp_replace(btrim(p_username),'^@',''))
  order by i.acquired_at desc,i.serial_number desc
$$;

revoke all on function public.toggle_card_protection(uuid),public.card_inventory_social_feed_page(integer,integer),
  public.create_card_folder(text,text,boolean),public.delete_card_folder(uuid),public.toggle_card_folder_item(uuid,uuid),
  public.card_folder_feed(uuid),public.upsert_profile_music_presence(uuid,text,text,text,text,integer,integer,boolean),
  public.profile_music_presence(uuid),public.card_collector_profile(uuid),public.toggle_public_card_offer(uuid,bigint,text),
  public.card_public_offer_feed(),public.card_trade_detail(uuid) from public,anon;
grant execute on function public.toggle_card_protection(uuid),public.card_inventory_social_feed_page(integer,integer),
  public.create_card_folder(text,text,boolean),public.delete_card_folder(uuid),public.toggle_card_folder_item(uuid,uuid),
  public.card_folder_feed(uuid),public.upsert_profile_music_presence(uuid,text,text,text,text,integer,integer,boolean),
  public.profile_music_presence(uuid),public.card_collector_profile(uuid),public.toggle_public_card_offer(uuid,bigint,text),
  public.card_public_offer_feed(),public.card_trade_detail(uuid) to authenticated;

commit;
