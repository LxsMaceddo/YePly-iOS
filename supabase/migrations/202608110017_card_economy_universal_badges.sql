-- YePly Cards 2.6: canonical deluxe catalogue, universal profile badges,
-- server-authoritative coin economy, store packs, wishlists and safer trades.

begin;

-- The official sync now mirrors provider artwork into this stable, private
-- catalogue prefix. Authenticated clients may create signed URLs for it.
drop policy if exists covers_catalog_read_authenticated on storage.objects;
create policy covers_catalog_read_authenticated on storage.objects
for select to authenticated
using (bucket_id = 'covers' and (storage.foldername(name))[1] = 'catalog');
drop policy if exists covers_read_allowed on storage.objects;
create policy covers_read_allowed on storage.objects for select to authenticated using (
  bucket_id='covers' and case
    when (storage.foldername(name))[1]='catalog' then true
    when (storage.foldername(name))[1] ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then public.can_read_playlist(((storage.foldername(name))[1])::uuid)
    else false end
);

-- Only the 32-track Deluxe edition participates in progress and future drops.
-- Preserve already minted standard-edition cards by moving them to the matching
-- Deluxe definition before disabling the legacy album.
with artist as (
  select id from public.collectible_artists
  where artist_key in ('kanye west', 'ye')
  order by (artist_key = 'kanye west') desc
  limit 1
), deluxe as (
  select al.id
  from public.collectible_albums al join artist a on a.id = al.artist_id
  where lower(al.title) like 'donda%deluxe%'
  order by al.updated_at desc limit 1
), legacy as (
  select al.id
  from public.collectible_albums al join artist a on a.id = al.artist_id
  where lower(btrim(al.title)) = 'donda'
), matches as (
  select old.id as old_definition_id, replacement.id as new_definition_id
  from public.collectible_card_definitions old
  join legacy l on l.id = old.album_id
  join deluxe x on true
  join public.collectible_card_definitions replacement
    on replacement.album_id = x.id
   and lower(regexp_replace(btrim(coalesce(replacement.title, '')), '[^a-z0-9]+', '', 'g')) =
       lower(regexp_replace(btrim(coalesce(old.title, '')), '[^a-z0-9]+', '', 'g'))
)
update public.card_instances i
set definition_id = m.new_definition_id
from matches m
where i.definition_id = m.old_definition_id;

update public.collectible_card_definitions d
set is_enabled = false, updated_at = now()
where d.album_id in (
  select al.id from public.collectible_albums al
  join public.collectible_artists a on a.id = al.artist_id
  where a.artist_key in ('kanye west', 'ye') and lower(btrim(al.title)) = 'donda'
);
update public.collectible_albums al
set is_enabled = false, source_release_group_id = null, updated_at = now()
from public.collectible_artists a
where a.id = al.artist_id and a.artist_key in ('kanye west', 'ye')
  and lower(btrim(al.title)) = 'donda';
delete from public.card_badges b using public.collectible_albums al,public.collectible_artists a
where b.album_id=al.id and a.id=al.artist_id and a.artist_key in ('kanye west','ye')
  and lower(btrim(al.title))='donda';

update public.collectible_albums al
set source_release_group_id = '7f4792fe-b563-4554-849a-95a89be71f84'::uuid,
    release_date = '2021-11-14'::date,
    updated_at = now()
from public.collectible_artists a
where a.id = al.artist_id and a.artist_key in ('kanye west', 'ye')
  and lower(al.title) like 'donda%deluxe%';

-- Immediate stable artwork fallback for the already imported catalogue. The
-- next official sync replaces these URLs with private Supabase Storage paths.
update public.collectible_albums al
set artwork_path = 'https://coverartarchive.org/release-group/' || al.source_release_group_id::text || '/front-500',
    updated_at = now()
where al.source_release_group_id is not null and al.is_enabled;
update public.collectible_card_definitions d
set artwork_path = al.artwork_path, updated_at = now()
from public.collectible_albums al
where al.id = d.album_id and al.source_release_group_id is not null and al.is_enabled and d.is_enabled;
update public.card_badges b
set artwork_path = al.artwork_path
from public.collectible_albums al
where al.id = b.album_id and al.source_release_group_id is not null and al.is_enabled;

-- Codes are case-insensitive and may contain !, dot, underscore or hyphen.
-- The previous six-character minimum accidentally rejected friendly codes such
-- as BETA!, despite there never being a semantic need for a hyphen.
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
  if char_length(v_code) not between 3 and 80
     or v_code ~ '[[:cntrl:]]'
     or v_code ~ '\s{2,}'
     or p_max_redemptions not between 1 and 100000
     or p_card_count not between 1 and 10 then
    raise exception 'invalid_pack_code' using errcode = '22023';
  end if;
  if p_artist_key is not null then
    select a.id into v_artist_id from public.collectible_artists a
    where a.artist_key = lower(regexp_replace(btrim(p_artist_key), '\s+', ' ', 'g')) and a.is_enabled;
    if v_artist_id is null then raise exception 'artist_not_available' using errcode = 'P0002'; end if;
  end if;
  insert into public.card_pack_codes(code_digest, label, artist_id, rarity_floor, card_count, max_redemptions, expires_at, created_by)
  values (extensions.digest(v_code, 'sha256'), left(btrim(p_label), 100), v_artist_id, p_rarity_floor,
          p_card_count, p_max_redemptions, p_expires_at, auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

alter table public.card_packs drop constraint if exists card_packs_source_check;
alter table public.card_packs add constraint card_packs_source_check
  check (source in ('listening', 'daily', 'code', 'achievement', 'level', 'admin', 'store'));
alter table public.card_packs drop constraint if exists card_packs_card_count_check;
alter table public.card_packs add constraint card_packs_card_count_check check (card_count between 1 and 10);
alter table public.card_pack_codes drop constraint if exists card_pack_codes_card_count_check;
alter table public.card_pack_codes add constraint card_pack_codes_card_count_check check (card_count between 1 and 10);
alter table public.card_packs
  add column if not exists pack_type text not null default 'standard',
  add column if not exists product_key text,
  add column if not exists mythic_weight_multiplier numeric(6,2) not null default 1;
alter table public.card_packs drop constraint if exists card_packs_pack_type_check;
alter table public.card_packs add constraint card_packs_pack_type_check
  check (pack_type in ('standard', 'common', 'epic', 'favorites', 'booster10', 'mythic_boost'));
alter table public.card_packs drop constraint if exists card_packs_mythic_multiplier_check;
alter table public.card_packs add constraint card_packs_mythic_multiplier_check
  check (mythic_weight_multiplier between 1 and 100);

create table if not exists public.card_wallets (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  balance bigint not null default 15000 check (balance >= 0),
  lifetime_earned bigint not null default 15000 check (lifetime_earned >= 0),
  lifetime_spent bigint not null default 0 check (lifetime_spent >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.card_coin_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount bigint not null check (amount <> 0),
  balance_after bigint not null check (balance_after >= 0),
  reason text not null check (reason in (
    'welcome', 'duplicate_conversion', 'legacy_excess_conversion', 'store_purchase',
    'trade_escrow', 'trade_refund', 'trade_sent', 'trade_received', 'admin_adjustment'
  )),
  reference_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create unique index if not exists card_coin_ledger_idempotency_idx
  on public.card_coin_ledger(user_id, reason, reference_id) where reference_id is not null;
create index if not exists card_coin_ledger_user_time_idx
  on public.card_coin_ledger(user_id, created_at desc);

insert into public.card_wallets(user_id)
select id from public.profiles on conflict (user_id) do nothing;
insert into public.card_coin_ledger(user_id, amount, balance_after, reason)
select w.user_id, 15000, w.balance, 'welcome'
from public.card_wallets w
where not exists (select 1 from public.card_coin_ledger l where l.user_id = w.user_id and l.reason = 'welcome');

create table if not exists public.card_pack_products (
  product_key text primary key,
  title text not null,
  subtitle text not null,
  emoji text not null,
  price bigint not null check (price between 1000 and 1000000),
  card_count smallint not null check (card_count between 1 and 10),
  rarity_floor public.card_rarity not null default 'common',
  pack_type text not null,
  mythic_weight_multiplier numeric(6,2) not null default 1,
  accent_hex text not null check (accent_hex ~ '^#[0-9A-Fa-f]{6}$'),
  sort_order smallint not null unique,
  is_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  check (pack_type in ('common', 'epic', 'favorites', 'booster10', 'mythic_boost'))
);

insert into public.card_pack_products(
  product_key, title, subtitle, emoji, price, card_count, rarity_floor,
  pack_type, mythic_weight_multiplier, accent_hex, sort_order
) values
  ('common', 'Pack Essencial', '3 cartas com chances naturais de raridade.', '🎵', 7500, 3, 'common', 'common', 1, '#6B7280', 1),
  ('epic', 'Pack Épico', '3 cartas garantidas entre Épica e Mítica.', '✨', 28000, 3, 'epic', 'epic', 1, '#A855F7', 2),
  ('favorites', 'Seus Favoritos', '5 cartas apenas dos seus artistas favoritos.', '❤️', 45000, 5, 'common', 'favorites', 1, '#FF6B57', 3),
  ('booster10', 'Booster 10', '10 cartas por um preço melhor, sem garantia de raridade.', '🚀', 58000, 10, 'common', 'booster10', 1, '#3B82F6', 4),
  ('mythic_boost', 'Pulso Mítico', '5 cartas com chance Mítica fortemente aumentada.', '🌌', 105000, 5, 'common', 'mythic_boost', 18, '#EC4899', 5)
on conflict (product_key) do update set
  title = excluded.title, subtitle = excluded.subtitle, emoji = excluded.emoji,
  price = excluded.price, card_count = excluded.card_count,
  rarity_floor = excluded.rarity_floor, pack_type = excluded.pack_type,
  mythic_weight_multiplier = excluded.mythic_weight_multiplier,
  accent_hex = excluded.accent_hex, sort_order = excluded.sort_order,
  is_enabled = true, updated_at = now();

alter table public.card_instances
  add column if not exists retired_at timestamptz,
  add column if not exists retirement_reason text;
alter table public.card_instances drop constraint if exists card_instances_retirement_reason_check;
alter table public.card_instances add constraint card_instances_retirement_reason_check
  check (retirement_reason is null or retirement_reason in ('duplicate_conversion', 'legacy_excess_conversion'));
create index if not exists card_instances_active_owner_definition_idx
  on public.card_instances(owner_id, definition_id, acquired_at) where retired_at is null;

create table if not exists public.card_wishlist (
  user_id uuid not null references public.profiles(id) on delete cascade,
  definition_id uuid not null references public.collectible_card_definitions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, definition_id)
);

alter table public.card_trades
  add column if not exists offered_coins bigint not null default 0,
  add column if not exists requested_coins bigint not null default 0,
  add column if not exists offered_coins_escrowed boolean not null default false;
alter table public.card_trades drop constraint if exists card_trades_coin_amounts_check;
alter table public.card_trades add constraint card_trades_coin_amounts_check
  check (offered_coins between 0 and 1000000000 and requested_coins between 0 and 1000000000);

-- Universal profile badge catalogue. Existing album badges migrate without
-- changing their IDs, so equipped selections remain intact.
alter table public.card_badges alter column album_id drop not null;
alter table public.card_badges
  add column if not exists badge_kind text not null default 'album',
  add column if not exists artist_id uuid references public.collectible_artists(id) on delete cascade,
  add column if not exists achievement_key text references public.card_achievement_definitions(achievement_key) on delete cascade,
  add column if not exists source_key text,
  add column if not exists subtitle text,
  add column if not exists emoji text;
update public.card_badges set badge_kind = 'album', source_key = 'album:' || album_id::text where album_id is not null;
alter table public.card_badges drop constraint if exists card_badges_kind_source_check;
alter table public.card_badges add constraint card_badges_kind_source_check check (
  (badge_kind = 'album' and album_id is not null and artist_id is null and achievement_key is null)
  or (badge_kind = 'discography' and album_id is null and artist_id is not null and achievement_key is null)
  or (badge_kind = 'achievement' and album_id is null and artist_id is null and achievement_key is not null)
);
create unique index if not exists card_badges_source_key_unique on public.card_badges(source_key);

create or replace function public.normalize_card_badge_source()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.album_id is not null then
    new.badge_kind := 'album'; new.source_key := 'album:' || new.album_id::text;
  elsif new.artist_id is not null then
    new.badge_kind := 'discography'; new.source_key := 'discography:' || new.artist_id::text;
  elsif new.achievement_key is not null then
    new.badge_kind := 'achievement'; new.source_key := 'achievement:' || new.achievement_key;
  end if;
  return new;
end;
$$;
drop trigger if exists card_badges_normalize_source on public.card_badges;
create trigger card_badges_normalize_source before insert or update on public.card_badges
for each row execute procedure public.normalize_card_badge_source();

alter table public.card_user_badges drop constraint if exists card_user_badges_equipped_slot_check;
alter table public.card_user_badges add constraint card_user_badges_equipped_slot_check
  check (equipped_slot between 1 and 4);

alter table public.card_achievement_definitions
  add column if not exists category text not null default 'geral',
  add column if not exists emoji text;

alter table public.profiles
  add column if not exists featured_card_instance_id uuid references public.card_instances(id) on delete set null,
  add column if not exists residence_country_code text;
alter table public.profiles drop constraint if exists profiles_residence_country_check;
alter table public.profiles add constraint profiles_residence_country_check
  check (residence_country_code is null or residence_country_code ~ '^[A-Z]{2}$');
alter table public.collectible_artists add column if not exists country_code text;
alter table public.collectible_artists drop constraint if exists collectible_artists_country_check;
alter table public.collectible_artists add constraint collectible_artists_country_check
  check (country_code is null or country_code ~ '^[A-Z]{2}$');
update public.collectible_artists set country_code = 'US'
where artist_key in ('kanye west', 'ye') and country_code is null;

-- Musical signature is a controlled, future-proof preset set rather than
-- arbitrary free text. Existing unknown entries are discarded once here.
update public.profiles p set tastes = coalesce((
  select array_agg(distinct preset order by preset)
  from unnest(p.tastes) value
  cross join lateral (values (
    case lower(regexp_replace(btrim(value), '[^a-z0-9&]+', '', 'g'))
      when 'rap' then 'Rap' when 'trap' then 'Trap' when 'r&b' then 'R&B'
      when 'rb' then 'R&B' when 'mpb' then 'MPB' when 'pop' then 'Pop'
      when 'metal' then 'Metal' when 'numetal' then 'NuMetal'
      when 'rock' then 'Rock' when 'indie' then 'Indie'
      when 'eletronica' then 'Eletrônica' when 'electronic' then 'Eletrônica'
      when 'funk' then 'Funk' when 'jazz' then 'Jazz'
      when 'samba' then 'Samba' when 'reggae' then 'Reggae'
    end
  )) normalized(preset)
  where preset is not null
), '{}'::text[]);
alter table public.profiles drop constraint if exists profiles_tastes_limit;
alter table public.profiles add constraint profiles_tastes_limit check (
  cardinality(tastes) <= 8
  and tastes <@ array['Rap','Trap','R&B','MPB','Pop','Metal','NuMetal','Rock','Indie','Eletrônica','Funk','Jazz','Samba','Reggae']::text[]
);

create or replace function public.ensure_card_wallet(p_user_id uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.card_wallets(user_id) values (p_user_id) on conflict (user_id) do nothing
$$;

create or replace function public.card_coin_value(
  p_definition_id uuid,
  p_randomize boolean default true
)
returns bigint language plpgsql volatile security definer set search_path = '' as $$
declare v_value numeric; v_factor numeric := 1; v_rarity public.card_rarity;
begin
  select d.rarity,
         case d.rarity
           when 'mythic'::public.card_rarity then
             least(14000, 5000 + log(10, 1 + greatest(d.global_listen_count, d.play_count_snapshot, 0)::numeric) * 1000)
           when 'epic'::public.card_rarity then
             least(2800, 900 + log(10, 1 + greatest(d.global_listen_count, d.play_count_snapshot, 0)::numeric) * 220)
           else
             least(650, 120 + log(10, 1 + greatest(d.global_listen_count, d.play_count_snapshot, 0)::numeric) * 60)
         end
  into v_rarity, v_value
  from public.collectible_card_definitions d where d.id = p_definition_id;
  if v_value is null then raise exception 'card_definition_not_found' using errcode = 'P0002'; end if;
  if p_randomize then v_factor := 0.85 + random() * 0.30; end if;
  return case v_rarity
    when 'mythic'::public.card_rarity then greatest(5000, least(14000, round(v_value * v_factor)))
    when 'epic'::public.card_rarity then greatest(900, least(2800, round(v_value * v_factor)))
    else greatest(120, least(650, round(v_value * v_factor)))
  end::bigint;
end;
$$;

create or replace function public.apply_card_coins(
  p_user_id uuid,
  p_amount bigint,
  p_reason text,
  p_reference_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint language plpgsql security definer set search_path = '' as $$
declare v_balance bigint;
begin
  if p_user_id is null or p_amount = 0 or abs(p_amount) > 1000000000 then
    raise exception 'invalid_coin_transaction' using errcode = '22023';
  end if;
  perform public.ensure_card_wallet(p_user_id);
  update public.card_wallets
  set balance = balance + p_amount,
      lifetime_earned = lifetime_earned + greatest(p_amount, 0),
      lifetime_spent = lifetime_spent + greatest(-p_amount, 0),
      updated_at = now()
  where user_id = p_user_id and balance + p_amount >= 0
  returning balance into v_balance;
  if v_balance is null then raise exception 'insufficient_coins' using errcode = '22003'; end if;
  insert into public.card_coin_ledger(user_id, amount, balance_after, reason, reference_id, metadata)
  values (p_user_id, p_amount, v_balance, p_reason, p_reference_id, coalesce(p_metadata, '{}'::jsonb));
  return v_balance;
exception when unique_violation then
  select balance into v_balance from public.card_wallets where user_id = p_user_id;
  return v_balance;
end;
$$;

create or replace function public.init_card_wallet_from_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_balance bigint;
begin
  insert into public.card_wallets(user_id) values (new.id)
  on conflict (user_id) do nothing returning balance into v_balance;
  if v_balance is not null then
    insert into public.card_coin_ledger(user_id, amount, balance_after, reason)
    values (new.id, 15000, v_balance, 'welcome');
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_init_card_wallet on public.profiles;
create trigger profiles_init_card_wallet after insert on public.profiles
for each row execute procedure public.init_card_wallet_from_profile();

create or replace function public.convert_card_excess_for_user(p_user_id uuid)
returns bigint language plpgsql security definer set search_path = '' as $$
declare r record;v_amount bigint;v_total bigint:=0;
begin
  for r in
    select instance_id, owner_id, definition_id
    from (
      select i.id as instance_id, i.owner_id, i.definition_id,
             row_number() over (partition by i.owner_id, i.definition_id order by i.acquired_at, i.serial_number) as copy_number
      from public.card_instances i
      where i.owner_id=p_user_id and i.retired_at is null
    ) ranked
    where copy_number > 2 and exists(
      select 1 from public.card_instances unlocked where unlocked.id=instance_id and unlocked.locked_trade_id is null
    )
  loop
    v_amount := public.card_coin_value(r.definition_id, false);
    update public.card_instances set retired_at = now(), retirement_reason = 'legacy_excess_conversion'
    where id = r.instance_id and retired_at is null;
    if found then
      perform public.apply_card_coins(
        r.owner_id, v_amount, 'legacy_excess_conversion', r.instance_id,
        jsonb_build_object('definition_id', r.definition_id)
      );
      v_total:=v_total+v_amount;
    end if;
  end loop;
  return v_total;
end;
$$;

-- Convert historical third-and-later active copies to coins. Retiring instead
-- of deleting keeps immutable trade history and serial numbers auditable.
do $$
declare v_user_id uuid;
begin
  for v_user_id in select distinct owner_id from public.card_instances where retired_at is null
  loop perform public.convert_card_excess_for_user(v_user_id); end loop;
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
  if p_owner_id is null
     or p_source not in ('listening', 'daily', 'code', 'achievement', 'level', 'admin', 'store')
     or p_card_count not between 1 and 10 then
    raise exception 'invalid_pack' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.collectible_card_definitions d
    join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
    join public.collectible_albums al on al.id = d.album_id and al.is_enabled
    where d.is_enabled
      and (p_artist_id is null or d.artist_id = p_artist_id)
      and public.card_rarity_rank(d.rarity) >= public.card_rarity_rank(p_rarity_floor)
  ) then raise exception 'empty_card_pool' using errcode = 'P0002'; end if;
  insert into public.card_packs(owner_id, source, artist_id, rarity_floor, card_count)
  values (p_owner_id, p_source, p_artist_id, p_rarity_floor, p_card_count)
  returning id into v_pack_id;
  return v_pack_id;
end;
$$;

create or replace function public.card_pack_store()
returns table (
  product_key text, title text, subtitle text, emoji text, price bigint,
  card_count integer, rarity_floor public.card_rarity, pack_type text,
  mythic_weight_multiplier numeric, accent_hex text, sort_order integer
)
language sql stable security definer set search_path = '' as $$
  select p.product_key, p.title, p.subtitle, p.emoji, p.price,
         p.card_count::integer, p.rarity_floor, p.pack_type,
         p.mythic_weight_multiplier, p.accent_hex, p.sort_order::integer
  from public.card_pack_products p
  where auth.uid() is not null and p.is_enabled
  order by p.sort_order
$$;

create or replace function public.buy_card_pack(p_product_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_product public.card_pack_products; v_pack_id uuid; v_balance bigint;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into v_product from public.card_pack_products p
  where p.product_key = lower(btrim(p_product_key)) and p.is_enabled;
  if v_product.product_key is null then raise exception 'pack_product_not_found' using errcode = 'P0002'; end if;
  if v_product.pack_type = 'favorites' and not exists (
    select 1 from public.card_favorite_artists f
    join public.collectible_card_definitions d on d.artist_id = f.artist_id and d.is_enabled
    where f.user_id = auth.uid()
  ) then raise exception 'favorite_artists_required' using errcode = '22023'; end if;

  v_pack_id := gen_random_uuid();
  v_balance := public.apply_card_coins(
    auth.uid(), -v_product.price, 'store_purchase', v_pack_id,
    jsonb_build_object('product_key', v_product.product_key)
  );
  insert into public.card_packs(
    id, owner_id, source, rarity_floor, card_count, pack_type,
    product_key, mythic_weight_multiplier
  ) values (
    v_pack_id, auth.uid(), 'store', v_product.rarity_floor, v_product.card_count,
    v_product.pack_type, v_product.product_key, v_product.mythic_weight_multiplier
  );
  return jsonb_build_object(
    'success', true, 'purchased', true, 'message', v_product.title || ' adicionado aos seus packs.',
    'pack_id', v_pack_id, 'product_key', v_product.product_key,
    'price', v_product.price, 'coin_balance', v_balance, 'card_count', v_product.card_count
  );
end;
$$;

drop function if exists public.open_all_card_packs();
drop function if exists public.open_card_pack(uuid);
create function public.open_card_pack(p_pack_id uuid)
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
      delete from public.card_wishlist where user_id = auth.uid() and definition_id = v_definition_id;
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

create function public.open_all_card_packs()
returns table (
  instance_id uuid, serial_number bigint, definition_id uuid, track_id uuid,
  title text, artist_name text, album_name text, artwork_path text,
  rarity public.card_rarity, acquired_at timestamptz, external_url text,
  catalog_source text, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer,
  converted_to_coins boolean, coins_awarded bigint
)
language plpgsql security definer set search_path = '' as $$
declare v_pack_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  for v_pack_id in
    select p.id from public.card_packs p
    where p.owner_id = auth.uid() and p.status = 'sealed'::public.card_pack_status
    order by p.created_at, p.id for update skip locked
  loop return query select * from public.open_card_pack(v_pack_id); end loop;
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
         coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(al.artwork_path), ''),
                  nullif(btrim(t.artwork_path), ''), nullif(btrim(p.cover_path), '')),
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
  where i.owner_id = auth.uid() and i.retired_at is null
  order by i.acquired_at desc, i.serial_number desc
$$;

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
  select * from public.card_inventory_feed()
  limit least(greatest(p_limit, 1), 500) offset greatest(p_offset, 0)
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
         coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(al.artwork_path), ''),
                  nullif(btrim(t.artwork_path), ''), nullif(btrim(p.cover_path), '')),
         coalesce(i.rarity_at_mint, d.rarity), i.acquired_at, d.source_url,
         d.catalog_source, d.global_listen_count, d.global_listener_count,
         coalesce(i.popularity_score_at_mint, d.popularity_score),
         d.artist_popularity_rank, d.artist_catalog_size
  from public.profiles target
  join public.card_instances i on i.owner_id = target.id and i.locked_trade_id is null and i.retired_at is null
  join public.collectible_card_definitions d on d.id = i.definition_id and d.is_enabled
  join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id = d.album_id and al.is_enabled
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  where auth.uid() is not null and target.username = lower(regexp_replace(btrim(p_username), '^@', ''))
  order by i.acquired_at desc, i.serial_number desc
$$;

-- Complete, deterministic album track list. This avoids implicit PostgREST page
-- caps and never hides missing cards: every enabled definition is returned.
create or replace function public.card_album_tracklist(p_album_id uuid)
returns table (
  definition_id uuid, album_id uuid, album_title text, artist_key text, artist_name text,
  artwork_path text, disc_number integer, track_number integer, title text,
  rarity public.card_rarity, global_listen_count bigint, global_listener_count bigint,
  popularity_score numeric, artist_popularity_rank integer, artist_catalog_size integer,
  owned_count bigint, owned_instance_id uuid
)
language sql stable security definer set search_path = '' as $$
  select d.id, al.id, al.title, a.artist_key, a.display_name,
         coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(al.artwork_path), ''), nullif(btrim(p.cover_path), '')),
         coalesce(d.disc_number::integer, 1), coalesce(d.track_number::integer, t.position + 1, 1),
         coalesce(d.title, t.title), d.rarity, d.global_listen_count,
         d.global_listener_count, d.popularity_score, d.artist_popularity_rank,
         d.artist_catalog_size, count(i.id),
         (array_agg(i.id order by i.acquired_at desc) filter (where i.id is not null))[1]
  from public.collectible_card_definitions d
  join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id = d.album_id and al.is_enabled
  left join public.tracks t on t.id = d.track_id
  left join public.playlists p on p.id = t.playlist_id
  left join public.card_instances i on i.definition_id = d.id and i.owner_id = auth.uid() and i.retired_at is null
  where auth.uid() is not null and d.is_enabled and al.id = p_album_id
  group by d.id, al.id, a.id, p.cover_path, t.position, t.title
  order by coalesce(d.disc_number, 1), coalesce(d.track_number, 1), coalesce(d.title, t.title), d.id
$$;

create or replace function public.toggle_card_wishlist(p_definition_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_added boolean;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.collectible_card_definitions d
    join public.collectible_albums al on al.id = d.album_id and al.is_enabled
    join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
    where d.id = p_definition_id and d.is_enabled
  ) then raise exception 'card_definition_not_found' using errcode = 'P0002'; end if;
  if exists (
    select 1 from public.card_instances i
    where i.owner_id = auth.uid() and i.definition_id = p_definition_id and i.retired_at is null
  ) then raise exception 'card_already_owned' using errcode = '23505'; end if;
  delete from public.card_wishlist where user_id = auth.uid() and definition_id = p_definition_id;
  if found then v_added := false;
  else
    insert into public.card_wishlist(user_id, definition_id) values (auth.uid(), p_definition_id);
    v_added := true;
  end if;
  return jsonb_build_object(
    'success',true,'definition_id',p_definition_id,'is_wanted',v_added,
    'message',case when v_added then 'Carta adicionada à lista de desejos.' else 'Carta removida da lista de desejos.' end
  );
end;
$$;

create or replace function public.card_wishlist_feed()
returns table (
  definition_id uuid, title text, artist_name text, album_name text,
  artwork_path text, rarity public.card_rarity, global_listen_count bigint,
  artist_popularity_rank integer, added_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select d.id, coalesce(d.title, t.title), coalesce(d.artist_name, t.artist_name, a.display_name),
         coalesce(d.album_name, t.album_name, al.title),
         coalesce(nullif(btrim(d.artwork_path), ''), nullif(btrim(al.artwork_path), ''), nullif(btrim(t.artwork_path), '')),
         d.rarity, d.global_listen_count, d.artist_popularity_rank, w.created_at
  from public.card_wishlist w
  join public.collectible_card_definitions d on d.id = w.definition_id and d.is_enabled
  join public.collectible_artists a on a.id = d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id = d.album_id and al.is_enabled
  left join public.tracks t on t.id = d.track_id
  where w.user_id = auth.uid()
    and not exists (select 1 from public.card_instances i where i.owner_id = auth.uid()
                    and i.definition_id = d.id and i.retired_at is null)
  order by w.created_at desc
$$;

create or replace function public.card_user_wishlist(p_username text)
returns table (
  definition_id uuid, title text, artist_name text, album_name text,
  artwork_path text, rarity public.card_rarity, global_listen_count bigint,
  artist_popularity_rank integer, added_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select d.id,coalesce(d.title,t.title),coalesce(d.artist_name,t.artist_name,a.display_name),
    coalesce(d.album_name,t.album_name,al.title),
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(t.artwork_path),'')),
    d.rarity,d.global_listen_count,d.artist_popularity_rank,w.created_at
  from public.profiles profile join public.card_wishlist w on w.user_id=profile.id
  join public.collectible_card_definitions d on d.id=w.definition_id and d.is_enabled
  join public.collectible_artists a on a.id=d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id=d.album_id and al.is_enabled left join public.tracks t on t.id=d.track_id
  where auth.uid() is not null and profile.username=lower(regexp_replace(btrim(p_username),'^@',''))
    and not exists(select 1 from public.card_instances i where i.owner_id=profile.id and i.definition_id=d.id and i.retired_at is null)
  order by w.created_at desc
$$;

drop function if exists public.card_album_catalog_feed();
create function public.card_album_catalog_feed()
returns table (
  definition_id uuid, album_id uuid, album_title text, artist_key text, artist_name text,
  artwork_path text, disc_number integer, track_number integer, title text, rarity public.card_rarity,
  global_listen_count bigint, global_listener_count bigint, popularity_score numeric,
  artist_popularity_rank integer, artist_catalog_size integer,
  owned_count bigint, owned_instance_id uuid
)
language sql stable security definer set search_path = '' as $$
  select d.id,al.id,al.title,a.artist_key,a.display_name,
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(p.cover_path),'')),
    coalesce(d.disc_number::integer,1),coalesce(d.track_number::integer,t.position+1,1),coalesce(d.title,t.title),d.rarity,
    d.global_listen_count,d.global_listener_count,d.popularity_score,d.artist_popularity_rank,d.artist_catalog_size,
    count(i.id),(array_agg(i.id order by i.acquired_at desc) filter(where i.id is not null))[1]
  from public.collectible_card_definitions d join public.collectible_artists a on a.id=d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id=d.album_id and al.is_enabled left join public.tracks t on t.id=d.track_id
  left join public.playlists p on p.id=t.playlist_id
  left join public.card_instances i on i.definition_id=d.id and i.owner_id=auth.uid() and i.retired_at is null
  where auth.uid() is not null and d.is_enabled group by d.id,al.id,a.id,p.cover_path,t.position,t.title
  order by a.display_name,al.release_date nulls last,al.title,coalesce(d.disc_number,1),coalesce(d.track_number,1),coalesce(d.title,t.title),d.id
$$;

create or replace function public.card_album_catalog_feed_page(
  p_offset integer default 0,p_limit integer default 500
)
returns table (
  definition_id uuid, album_id uuid, album_title text, artist_key text, artist_name text,
  artwork_path text, disc_number integer, track_number integer, title text, rarity public.card_rarity,
  global_listen_count bigint, global_listener_count bigint, popularity_score numeric,
  artist_popularity_rank integer, artist_catalog_size integer,
  owned_count bigint, owned_instance_id uuid
)
language sql stable security definer set search_path = '' as $$
  select d.id,al.id,al.title,a.artist_key,a.display_name,
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(p.cover_path),'')),
    coalesce(d.disc_number::integer,1),coalesce(d.track_number::integer,t.position+1,1),coalesce(d.title,t.title),d.rarity,
    d.global_listen_count,d.global_listener_count,d.popularity_score,d.artist_popularity_rank,d.artist_catalog_size,
    count(i.id),(array_agg(i.id order by i.acquired_at desc) filter(where i.id is not null))[1]
  from public.collectible_card_definitions d join public.collectible_artists a on a.id=d.artist_id and a.is_enabled
  join public.collectible_albums al on al.id=d.album_id and al.is_enabled left join public.tracks t on t.id=d.track_id
  left join public.playlists p on p.id=t.playlist_id
  left join public.card_instances i on i.definition_id=d.id and i.owner_id=auth.uid() and i.retired_at is null
  where auth.uid() is not null and d.is_enabled group by d.id,al.id,a.id,p.cover_path,t.position,t.title
  order by a.display_name,al.release_date nulls last,al.title,coalesce(d.disc_number,1),coalesce(d.track_number,1),coalesce(d.title,t.title),d.id
  limit least(greatest(p_limit,1),500) offset greatest(p_offset,0)
$$;

insert into public.card_achievement_definitions(
  achievement_key, title, description, icon, emoji, category, target, sort_order, is_enabled
) values
  ('night_listener', 'Night Listener', 'Ouviu 100 músicas entre 00:00 e 05:00.', '🌙', '🌙', 'Escuta', 100, 1, true),
  ('again', 'Again?!', 'Ouviu a mesma música 100 vezes.', '🔁', '🔁', 'Escuta', 100, 2, true),
  ('day_one', 'Day One', 'Está no YePly desde a versão Beta.', '🗿', '🗿', 'Legado', 1, 3, true),
  ('audiophile', 'Audiophile', 'Ouviu 10.000 músicas.', '🎧', '🎧', 'Escuta', 10000, 4, true),
  ('collector', 'Collector', 'Completou 10 álbuns.', '💿', '💿', 'Coleção', 10, 5, true),
  ('trader', 'Trader', 'Realizou 100 trocas.', '🤝', '🤝', 'Trocas', 100, 6, true),
  ('obsessed', 'Obsessed', 'Ouviu 1.000 vezes o mesmo artista.', '❤️', '❤️', 'Escuta', 1000, 7, true),
  ('show_off', 'Show Off!', 'Compartilhou o que está ouvindo agora.', '📣', '📣', 'Comunidade', 1, 8, true),
  ('first_album', 'Primeiro Álbum', 'Completou seu primeiro álbum.', '💿', '💿', 'Coleção', 1, 9, true),
  ('discography_beginning', 'Discografia Começando', 'Completou 5 álbuns.', '🗂️', '🗂️', 'Coleção', 5, 10, true),
  ('no_skipping', 'Sem Pular Faixa', 'Completou um álbum com 10 ou mais músicas.', '⏭️', '⏭️', 'Coleção', 1, 11, true),
  ('start_to_finish', 'Do Início ao Fim', 'Ouviu todas as músicas de um álbum que completou.', '🎼', '🎼', 'Escuta', 1, 12, true),
  ('i_was_there_first', 'Eu Tava Lá Antes', 'Completou o primeiro álbum de um artista.', '🌅', '🌅', 'Coleção', 1, 13, true),
  ('first_play', 'Dá o Play', 'Ouviu sua primeira música.', '▶️', '▶️', 'Escuta', 1, 14, true),
  ('music_explorer', 'Explorador Musical', 'Ouviu 30 artistas diferentes.', '🧭', '🧭', 'Escuta', 30, 15, true),
  ('streak_30', 'Não Para Agora', 'Entrou no YePly por 30 dias consecutivos.', '🔥', '🔥', 'Sequência', 30, 16, true),
  ('streak_100', 'YePly Faz Parte da Rotina', 'Entrou no YePly por 100 dias consecutivos.', '💯', '💯', 'Sequência', 100, 17, true),
  ('pack_opener_50', 'Só Mais Um', 'Abriu 50 packs.', '📦', '📦', 'Packs', 50, 18, true),
  ('upgrade', 'Upgrade', 'Recebeu em uma troca uma carta de raridade superior à entregue.', '⬆️', '⬆️', 'Trocas', 1, 19, true),
  ('networker', 'Rede de Contatos', 'Trocou com 25 usuários diferentes.', '🌐', '🌐', 'Trocas', 25, 20, true),
  ('familiar_faces', 'Velhos Conhecidos', 'Fez 10 trocas com o mesmo usuário.', '🫂', '🫂', 'Trocas', 10, 21, true),
  ('community_dj', 'DJ da Comunidade', 'Uma playlist sua chegou a 30 seguidores.', '🎛️', '🎛️', 'Comunidade', 30, 22, true),
  ('top_10', 'Top 10', 'Conseguiu uma música Top 10 de um artista.', '🔟', '🔟', 'Coleção', 1, 23, true),
  ('national_superfan', 'MUITO Fan Nacional', 'Completou a discografia de um artista do seu país.', '🏆', '🏆', 'Coleção', 1, 24, true),
  ('national_fan', 'Fan Nacional', 'Completou um álbum de um artista do seu país.', '🇧🇷', '🇧🇷', 'Coleção', 1, 25, true)
on conflict (achievement_key) do update set
  title = excluded.title, description = excluded.description, icon = excluded.icon,
  emoji = excluded.emoji, category = excluded.category, target = excluded.target,
  sort_order = excluded.sort_order, is_enabled = excluded.is_enabled;

create or replace function public.refresh_card_album_badges(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  -- Keep badge definitions synchronized even if an import did not create them.
  insert into public.card_badges(album_id, badge_kind, source_key, title, subtitle, artwork_path)
  select al.id, 'album', 'album:' || al.id::text, al.title, a.display_name, al.artwork_path
  from public.collectible_albums al join public.collectible_artists a on a.id = al.artist_id
  where al.is_enabled
  on conflict (source_key) do update set
    title = excluded.title, subtitle = excluded.subtitle, artwork_path = excluded.artwork_path;

  insert into public.card_badges(artist_id, badge_kind, source_key, title, subtitle, artwork_path, emoji)
  select a.id, 'discography', 'discography:' || a.id::text,
         'Discografia completa', a.display_name, a.artwork_path, '🏆'
  from public.collectible_artists a where a.is_enabled
  on conflict (source_key) do update set
    title = excluded.title, subtitle = excluded.subtitle, artwork_path = excluded.artwork_path, emoji = excluded.emoji;

  insert into public.card_user_badges(user_id, badge_id)
  select p_user_id, b.id
  from public.card_badges b
  join public.collectible_albums al on al.id = b.album_id and al.is_enabled
  where b.badge_kind = 'album'
    and exists (select 1 from public.collectible_card_definitions d where d.album_id = al.id and d.is_enabled)
    and not exists (
      select 1 from public.collectible_card_definitions d
      where d.album_id = al.id and d.is_enabled
        and not exists (
          select 1 from public.card_instances i
          where i.owner_id = p_user_id and i.definition_id = d.id and i.retired_at is null
        )
    )
  on conflict (user_id, badge_id) do nothing;

  insert into public.card_user_badges(user_id, badge_id)
  select p_user_id, b.id
  from public.card_badges b
  join public.collectible_artists a on a.id = b.artist_id and a.is_enabled
  where b.badge_kind = 'discography'
    and exists (
      select 1 from public.collectible_albums al
      join public.collectible_card_definitions d on d.album_id = al.id and d.is_enabled
      where al.artist_id = a.id and al.is_enabled
    )
    and not exists (
      select 1 from public.collectible_albums al
      join public.collectible_card_definitions d on d.album_id = al.id and d.is_enabled
      where al.artist_id = a.id and al.is_enabled
        and not exists (
          select 1 from public.card_instances i
          where i.owner_id = p_user_id and i.definition_id = d.id and i.retired_at is null
        )
    )
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
      where e.user_id = p_user_id and e.counts_as_play
        and extract(hour from e.created_at at time zone 'America/Sao_Paulo') between 0 and 4;
    when 'again' then
      select coalesce(max(h.play_count), 0) into v_progress from public.playback_history h where h.user_id = p_user_id;
    when 'day_one' then
      select case when exists(select 1 from public.card_beta_members b where b.user_id = p_user_id) then 1 else 0 end into v_progress;
    when 'audiophile' then
      select coalesce(sum(h.play_count), 0) into v_progress from public.playback_history h where h.user_id = p_user_id;
    when 'collector' then
      select count(*) into v_progress from public.card_user_badges ub
      join public.card_badges b on b.id = ub.badge_id where ub.user_id = p_user_id and b.badge_kind = 'album';
    when 'trader' then
      select count(*) into v_progress from public.card_trades t
      where t.status = 'accepted'::public.card_trade_status and (t.proposer_id = p_user_id or t.recipient_id = p_user_id);
    when 'obsessed' then
      select coalesce(max(x.plays), 0) into v_progress from (
        select lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g')) artist_key,
               sum(h.play_count)::bigint plays
        from public.playback_history h join public.tracks t on t.id = h.track_id
        cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
        where h.user_id = p_user_id group by 1
      ) x;
    when 'show_off' then
      select case when exists(select 1 from public.card_share_events e where e.user_id = p_user_id) then 1 else 0 end into v_progress;
    when 'first_album' then
      select count(*) into v_progress from public.card_user_badges ub join public.card_badges b on b.id = ub.badge_id
      where ub.user_id = p_user_id and b.badge_kind = 'album';
    when 'discography_beginning' then
      select count(*) into v_progress from public.card_user_badges ub join public.card_badges b on b.id = ub.badge_id
      where ub.user_id = p_user_id and b.badge_kind = 'album';
    when 'no_skipping' then
      select case when exists (
        select 1 from public.card_user_badges ub join public.card_badges b on b.id = ub.badge_id
        where ub.user_id = p_user_id and b.badge_kind = 'album'
          and (select count(*) from public.collectible_card_definitions d where d.album_id = b.album_id and d.is_enabled) >= 10
      ) then 1 else 0 end into v_progress;
    when 'start_to_finish' then
      select case when exists (
        select 1 from public.card_user_badges ub join public.card_badges b on b.id = ub.badge_id
        where ub.user_id = p_user_id and b.badge_kind = 'album'
          and not exists (
            select 1 from public.collectible_card_definitions d
            where d.album_id = b.album_id and d.is_enabled
              and not exists (
                select 1 from public.playback_history h join public.tracks t on t.id = h.track_id
                where h.user_id = p_user_id and h.play_count > 0 and (
                  h.track_id = d.track_id or
                  lower(regexp_replace(btrim(t.title), '[^a-z0-9]+', '', 'g')) =
                  lower(regexp_replace(btrim(coalesce(d.title, '')), '[^a-z0-9]+', '', 'g'))
                )
              )
          )
      ) then 1 else 0 end into v_progress;
    when 'i_was_there_first' then
      select case when exists (
        select 1 from public.card_user_badges ub join public.card_badges b on b.id = ub.badge_id
        join public.collectible_albums al on al.id = b.album_id
        where ub.user_id = p_user_id and b.badge_kind = 'album' and al.release_date = (
          select min(first_al.release_date) from public.collectible_albums first_al
          where first_al.artist_id = al.artist_id and first_al.is_enabled and first_al.release_date is not null
        )
      ) then 1 else 0 end into v_progress;
    when 'first_play' then
      select coalesce(sum(h.play_count), 0) into v_progress from public.playback_history h where h.user_id = p_user_id;
    when 'music_explorer' then
      select count(distinct lower(regexp_replace(btrim(credit.name), '\s+', ' ', 'g'))) into v_progress
      from public.playback_history h join public.tracks t on t.id = h.track_id
      cross join lateral regexp_split_to_table(t.artist_name, '\s*,\s*') credit(name)
      where h.user_id = p_user_id and h.play_count > 0;
    when 'streak_30' then
      select coalesce(best_streak, 0) into v_progress from public.card_player_stats where user_id = p_user_id;
    when 'streak_100' then
      select coalesce(best_streak, 0) into v_progress from public.card_player_stats where user_id = p_user_id;
    when 'pack_opener_50' then
      select count(*) into v_progress from public.card_packs p where p.owner_id = p_user_id and p.status = 'opened';
    when 'upgrade' then
      select case when exists (
        select 1 from public.card_trades tr where tr.status = 'accepted' and (
          (tr.proposer_id = p_user_id and
            coalesce((select max(public.card_rarity_rank(coalesce(i.rarity_at_mint, d.rarity))) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id where ti.trade_id=tr.id and ti.side='requested'),0)
            > coalesce((select max(public.card_rarity_rank(coalesce(i.rarity_at_mint, d.rarity))) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id where ti.trade_id=tr.id and ti.side='offered'),0))
          or (tr.recipient_id = p_user_id and
            coalesce((select max(public.card_rarity_rank(coalesce(i.rarity_at_mint, d.rarity))) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id where ti.trade_id=tr.id and ti.side='offered'),0)
            > coalesce((select max(public.card_rarity_rank(coalesce(i.rarity_at_mint, d.rarity))) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id where ti.trade_id=tr.id and ti.side='requested'),0))
        )
      ) then 1 else 0 end into v_progress;
    when 'networker' then
      select count(distinct case when t.proposer_id = p_user_id then t.recipient_id else t.proposer_id end)
      into v_progress from public.card_trades t where t.status='accepted' and (t.proposer_id=p_user_id or t.recipient_id=p_user_id);
    when 'familiar_faces' then
      select coalesce(max(x.trade_count),0) into v_progress from (
        select case when t.proposer_id=p_user_id then t.recipient_id else t.proposer_id end other_id, count(*) trade_count
        from public.card_trades t where t.status='accepted' and (t.proposer_id=p_user_id or t.recipient_id=p_user_id) group by 1
      ) x;
    when 'community_dj' then
      select coalesce(max(x.followers),0) into v_progress from (
        select count(f.user_id) followers from public.playlists p left join public.playlist_follows f on f.playlist_id=p.id
        where p.owner_id=p_user_id group by p.id
      ) x;
    when 'top_10' then
      select case when exists(select 1 from public.card_instances i join public.collectible_card_definitions d on d.id=i.definition_id
        where i.owner_id=p_user_id and i.retired_at is null and d.artist_popularity_rank between 1 and 10) then 1 else 0 end into v_progress;
    when 'national_superfan' then
      select case when exists(select 1 from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
        join public.collectible_artists a on a.id=b.artist_id join public.profiles p on p.id=p_user_id
        where ub.user_id=p_user_id and b.badge_kind='discography' and p.residence_country_code=a.country_code) then 1 else 0 end into v_progress;
    when 'national_fan' then
      select case when exists(select 1 from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
        join public.collectible_albums al on al.id=b.album_id join public.collectible_artists a on a.id=al.artist_id
        join public.profiles p on p.id=p_user_id where ub.user_id=p_user_id and b.badge_kind='album'
        and p.residence_country_code=a.country_code) then 1 else 0 end into v_progress;
    else v_progress := 0;
  end case;
  return coalesce(v_progress, 0);
end;
$$;

create or replace function public.refresh_card_achievements(p_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.card_user_achievements(user_id, achievement_key)
  select p_user_id, d.achievement_key from public.card_achievement_definitions d
  where d.is_enabled and public.card_achievement_progress_for(p_user_id, d.achievement_key) >= d.target
  on conflict (user_id, achievement_key) do nothing;

  insert into public.card_badges(achievement_key, badge_kind, source_key, title, subtitle, emoji)
  select d.achievement_key, 'achievement', 'achievement:' || d.achievement_key,
         d.title, d.category, coalesce(d.emoji, d.icon)
  from public.card_achievement_definitions d where d.is_enabled
  on conflict (source_key) do update set
    title=excluded.title, subtitle=excluded.subtitle, emoji=excluded.emoji;

  insert into public.card_user_badges(user_id, badge_id)
  select p_user_id, b.id from public.card_user_achievements ua
  join public.card_badges b on b.achievement_key=ua.achievement_key and b.badge_kind='achievement'
  where ua.user_id=p_user_id on conflict (user_id,badge_id) do nothing;
end;
$$;

drop function if exists public.card_achievement_feed();
create function public.card_achievement_feed()
returns table (
  achievement_key text, title text, description text, icon text, emoji text, category text,
  progress bigint, target bigint, unlocked_at timestamptz, reward_claimed_at timestamptz
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
  return query select d.achievement_key,d.title,d.description,d.icon,coalesce(d.emoji,d.icon),d.category,
    least(public.card_achievement_progress_for(auth.uid(),d.achievement_key),d.target),d.target,ua.unlocked_at,ua.reward_claimed_at
  from public.card_achievement_definitions d left join public.card_user_achievements ua
    on ua.user_id=auth.uid() and ua.achievement_key=d.achievement_key
  where d.is_enabled order by d.category,d.sort_order;
end;
$$;

drop function if exists public.card_album_progress();
create function public.card_album_progress()
returns table (
  album_id uuid, album_title text, artist_name text,
  artist_artwork_path text, artist_source_url text, artwork_path text,
  release_date text,
  owned_unique integer, total_cards integer, is_complete boolean,
  badge_id uuid, badge_equipped boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  return query
  select al.id,al.title,a.display_name,a.artwork_path,a.spotify_url,
         coalesce(nullif(btrim(al.artwork_path),''),nullif(btrim(b.artwork_path),'')),
         al.release_date::text,
         count(distinct i.definition_id)::integer,count(distinct d.id)::integer,
         count(distinct i.definition_id)=count(distinct d.id) and count(distinct d.id)>0,
         ub.badge_id,ub.equipped_slot is not null
  from public.collectible_albums al join public.collectible_artists a on a.id=al.artist_id and a.is_enabled
  join public.collectible_card_definitions d on d.album_id=al.id and d.is_enabled
  left join public.card_instances i on i.definition_id=d.id and i.owner_id=auth.uid() and i.retired_at is null
  left join public.card_badges b on b.album_id=al.id and b.badge_kind='album'
  left join public.card_user_badges ub on ub.badge_id=b.id and ub.user_id=auth.uid()
  where al.is_enabled group by al.id,a.id,b.artwork_path,ub.badge_id,ub.equipped_slot
  order by a.display_name,al.release_date nulls last,al.title;
end;
$$;

create or replace function public.equip_card_badge(p_badge_id uuid,p_slot smallint)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if p_slot not between 1 and 4 then raise exception 'invalid_badge_slot' using errcode='22023'; end if;
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
  if not exists(select 1 from public.card_user_badges where user_id=auth.uid() and badge_id=p_badge_id) then
    raise exception 'badge_not_owned' using errcode='42501';
  end if;
  update public.card_user_badges set equipped_slot=null where user_id=auth.uid() and equipped_slot=p_slot;
  update public.card_user_badges set equipped_slot=p_slot where user_id=auth.uid() and badge_id=p_badge_id;
  return jsonb_build_object('equipped',true,'badge_id',p_badge_id,'slot',p_slot);
end;
$$;

drop function if exists public.profile_equipped_card_badges(uuid);
create function public.profile_equipped_card_badges(p_profile_id uuid)
returns table (
  badge_id uuid, album_id uuid, title text, artwork_path text, slot integer,
  badge_kind text, subtitle text, emoji text, source_id text
)
language sql stable security definer set search_path = '' as $$
  select b.id,b.album_id,b.title,
         coalesce(nullif(btrim(b.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(a.artwork_path),'')),
         ub.equipped_slot::integer,b.badge_kind,b.subtitle,b.emoji,
         coalesce(b.album_id::text,b.artist_id::text,b.achievement_key)
  from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
  left join public.collectible_albums al on al.id=b.album_id
  left join public.collectible_artists a on a.id=b.artist_id
  where auth.uid() is not null and ub.user_id=p_profile_id and ub.equipped_slot is not null
  order by ub.equipped_slot limit 4
$$;

create or replace function public.profile_owned_badges(p_profile_id uuid)
returns table (
  badge_id uuid,badge_kind text,title text,subtitle text,artwork_path text,
  emoji text,slot integer,source_id text
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if p_profile_id=auth.uid() then
    perform public.refresh_card_album_badges(p_profile_id);
    perform public.refresh_card_achievements(p_profile_id);
  end if;
  return query select b.id,b.badge_kind,b.title,b.subtitle,
    coalesce(nullif(btrim(b.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(a.artwork_path),'')),
    b.emoji,ub.equipped_slot::integer,coalesce(b.album_id::text,b.artist_id::text,b.achievement_key)
  from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
  left join public.collectible_albums al on al.id=b.album_id
  left join public.collectible_artists a on a.id=b.artist_id
  where ub.user_id=p_profile_id
  order by ub.equipped_slot nulls last,ub.acquired_at,b.title;
end;
$$;

create or replace function public.set_profile_featured_card(p_instance_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if p_instance_id is not null and not exists(
    select 1 from public.card_instances i where i.id=p_instance_id and i.owner_id=auth.uid() and i.retired_at is null
  ) then raise exception 'featured_card_not_owned' using errcode='42501'; end if;
  update public.profiles set featured_card_instance_id=p_instance_id,updated_at=now() where id=auth.uid();
  return jsonb_build_object('updated',true,'instance_id',p_instance_id);
end;
$$;

create or replace function public.profile_featured_card(p_profile_id uuid)
returns table (
  instance_id uuid,serial_number bigint,definition_id uuid,track_id uuid,title text,
  artist_name text,album_name text,artwork_path text,rarity public.card_rarity,
  acquired_at timestamptz,external_url text,catalog_source text,
  global_listen_count bigint,global_listener_count bigint,popularity_score numeric,
  artist_popularity_rank integer,artist_catalog_size integer
)
language sql stable security definer set search_path = '' as $$
  select i.id,i.serial_number,d.id,d.track_id,coalesce(d.title,t.title),
    coalesce(d.artist_name,t.artist_name,a.display_name),coalesce(d.album_name,t.album_name,al.title),
    coalesce(nullif(btrim(d.artwork_path),''),nullif(btrim(al.artwork_path),''),nullif(btrim(t.artwork_path),'')),
    coalesce(i.rarity_at_mint,d.rarity),i.acquired_at,d.source_url,d.catalog_source,
    d.global_listen_count,d.global_listener_count,coalesce(i.popularity_score_at_mint,d.popularity_score),
    d.artist_popularity_rank,d.artist_catalog_size
  from public.profiles profile join public.card_instances i on i.id=profile.featured_card_instance_id
  join public.collectible_card_definitions d on d.id=i.definition_id
  join public.collectible_artists a on a.id=d.artist_id join public.collectible_albums al on al.id=d.album_id
  left join public.tracks t on t.id=d.track_id
  where auth.uid() is not null and profile.id=p_profile_id and i.owner_id=p_profile_id and i.retired_at is null
$$;

create or replace function public.set_profile_genres(p_genres text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_genres text[];
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  select coalesce(array_agg(value order by first_position),'{}'::text[]) into v_genres from (
    select value,min(ordinality) first_position from unnest(coalesce(p_genres,'{}'::text[])) with ordinality x(value,ordinality)
    where value=any(array['Rap','Trap','R&B','MPB','Pop','Metal','NuMetal','Rock','Indie','Eletrônica','Funk','Jazz','Samba','Reggae']::text[])
    group by value
  ) normalized;
  if cardinality(v_genres)>8 or cardinality(v_genres)<>cardinality(coalesce(p_genres,'{}'::text[])) then
    raise exception 'invalid_music_genres' using errcode='22023';
  end if;
  update public.profiles set tastes=v_genres,updated_at=now() where id=auth.uid();
  return jsonb_build_object('updated',true,'genres',to_jsonb(v_genres));
end;
$$;

create or replace function public.card_game_dashboard()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_stats public.card_player_stats;v_badges jsonb;v_balance bigint;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  perform public.ensure_card_player(auth.uid());perform public.ensure_card_wallet(auth.uid());
  perform public.refresh_card_album_badges(auth.uid());perform public.refresh_card_achievements(auth.uid());
  select * into v_stats from public.card_player_stats where user_id=auth.uid();
  select balance into v_balance from public.card_wallets where user_id=auth.uid();
  select coalesce(jsonb_agg(jsonb_build_object(
    'badge_id',b.id,'album_id',b.album_id,'badge_kind',b.badge_kind,'title',b.title,'subtitle',b.subtitle,
    'artwork_path',coalesce(b.artwork_path,al.artwork_path,a.artwork_path),'emoji',b.emoji,
    'source_id',coalesce(b.album_id::text,b.artist_id::text,b.achievement_key),'slot',ub.equipped_slot
  ) order by ub.equipped_slot),'[]'::jsonb) into v_badges
  from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id
  left join public.collectible_albums al on al.id=b.album_id left join public.collectible_artists a on a.id=b.artist_id
  where ub.user_id=auth.uid() and ub.equipped_slot is not null;
  return jsonb_build_object(
    'user_id',auth.uid(),'xp',v_stats.xp,'level',v_stats.level,
    'xp_for_next_level',greatest(0,(v_stats.level::bigint*v_stats.level::bigint*500)-v_stats.xp),
    'next_level_xp',v_stats.level::bigint*v_stats.level::bigint*500,
    'current_streak',v_stats.current_streak,'best_streak',v_stats.best_streak,
    'streak_day',v_stats.streak_day,'streak_cycle',v_stats.streak_cycle,'last_daily_claim',v_stats.last_daily_claim,
    'coin_balance',v_balance,
    'unopened_pack_count',(select count(*) from public.card_packs where owner_id=auth.uid() and status='sealed'),
    'unopened_packs',(select count(*) from public.card_packs where owner_id=auth.uid() and status='sealed'),
    'daily_claim_available',v_stats.last_daily_claim is distinct from (now() at time zone 'UTC')::date,
    'favorite_artists',(select coalesce(array_agg(a.artist_key order by f.position),'{}'::text[]) from public.card_favorite_artists f join public.collectible_artists a on a.id=f.artist_id where f.user_id=auth.uid()),
    'total_cards',(select count(*) from public.card_instances where owner_id=auth.uid() and retired_at is null),
    'unique_cards',(select count(distinct definition_id) from public.card_instances where owner_id=auth.uid() and retired_at is null),
    'completed_albums',(select count(*) from public.card_user_badges ub join public.card_badges b on b.id=ub.badge_id where ub.user_id=auth.uid() and b.badge_kind='album'),
    'owned_badge_count',(select count(*) from public.card_user_badges where user_id=auth.uid()),
    'completed_trades',(select count(*) from public.card_trades where status='accepted' and (proposer_id=auth.uid() or recipient_id=auth.uid())),
    'achievement_count',(select count(*) from public.card_user_achievements where user_id=auth.uid()),
    'unclaimed_achievement_rewards',(select count(*) from public.card_user_achievements where user_id=auth.uid() and reward_claimed_at is null),
    'wishlist_count',(select count(*) from public.card_wishlist where user_id=auth.uid()),
    'equipped_badges',v_badges
  );
end;
$$;

create or replace function public.release_expired_card_trades()
returns void language plpgsql security definer set search_path = '' as $$
declare r record;v_user_id uuid;
begin
  for r in select id,proposer_id,offered_coins from public.card_trades
    where status='pending' and expires_at<=now() and offered_coins_escrowed for update
  loop
    if r.offered_coins>0 then
      perform public.apply_card_coins(r.proposer_id,r.offered_coins,'trade_refund',r.id,
        jsonb_build_object('reason','expired'));
    end if;
    update public.card_trades set offered_coins_escrowed=false where id=r.id;
  end loop;
  update public.card_instances i set locked_trade_id=null where i.locked_trade_id in (
    select id from public.card_trades where status='pending' and expires_at<=now()
  );
  for v_user_id in
    select proposer_id from public.card_trades where status='pending' and expires_at<=now()
    union select recipient_id from public.card_trades where status='pending' and expires_at<=now()
  loop perform public.convert_card_excess_for_user(v_user_id); end loop;
  update public.card_trades set status='expired',responded_at=now()
  where status='pending' and expires_at<=now();
end;
$$;

create or replace function public.create_card_trade(
  p_recipient_id uuid,p_offered_ids uuid[],p_requested_ids uuid[],
  p_offered_coins bigint,p_requested_coins bigint
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_trade_id uuid;v_offered_count integer;v_requested_count integer;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if p_recipient_id is null or p_recipient_id=auth.uid() or not exists(select 1 from public.profiles where id=p_recipient_id) then
    raise exception 'invalid_trade_recipient' using errcode='22023';
  end if;
  p_offered_coins:=coalesce(p_offered_coins,0);p_requested_coins:=coalesce(p_requested_coins,0);
  if p_offered_coins not between 0 and 1000000000 or p_requested_coins not between 0 and 1000000000 then
    raise exception 'invalid_trade_coins' using errcode='22023';
  end if;
  v_offered_count:=cardinality(coalesce(p_offered_ids,'{}'::uuid[]));
  v_requested_count:=cardinality(coalesce(p_requested_ids,'{}'::uuid[]));
  if v_offered_count>20 or v_requested_count>20
     or (v_offered_count=0 and p_offered_coins=0)
     or (v_requested_count=0 and p_requested_coins=0) then
    raise exception 'invalid_trade_size' using errcode='22023';
  end if;
  if (select count(distinct x) from unnest(coalesce(p_offered_ids,'{}'::uuid[])) x)<>v_offered_count
     or (select count(distinct x) from unnest(coalesce(p_requested_ids,'{}'::uuid[])) x)<>v_requested_count
     or coalesce(p_offered_ids,'{}'::uuid[])&&coalesce(p_requested_ids,'{}'::uuid[]) then
    raise exception 'duplicate_trade_card' using errcode='22023';
  end if;
  perform public.release_expired_card_trades();
  perform 1 from public.card_instances i where i.id=any(coalesce(p_offered_ids,'{}'::uuid[])) order by i.id for update;
  perform 1 from public.card_instances i where i.id=any(coalesce(p_requested_ids,'{}'::uuid[])) order by i.id for update;
  if (select count(*) from public.card_instances i where i.id=any(coalesce(p_offered_ids,'{}'::uuid[]))
      and i.owner_id=auth.uid() and i.locked_trade_id is null and i.retired_at is null)<>v_offered_count then
    raise exception 'offered_card_unavailable' using errcode='42501';
  end if;
  if (select count(*) from public.card_instances i where i.id=any(coalesce(p_requested_ids,'{}'::uuid[]))
      and i.owner_id=p_recipient_id and i.locked_trade_id is null and i.retired_at is null)<>v_requested_count then
    raise exception 'requested_card_unavailable' using errcode='42501';
  end if;
  if exists(
    select 1 from public.card_instances offered
    join public.card_instances already on already.owner_id=p_recipient_id
      and already.definition_id=offered.definition_id and already.retired_at is null
    where offered.id=any(coalesce(p_offered_ids,'{}'::uuid[]))
  ) then raise exception 'recipient_already_owns_offered_card' using errcode='23505'; end if;
  if exists(
    select 1 from public.card_instances requested
    join public.card_instances already on already.owner_id=auth.uid()
      and already.definition_id=requested.definition_id and already.retired_at is null
    where requested.id=any(coalesce(p_requested_ids,'{}'::uuid[]))
  ) then raise exception 'proposer_already_owns_requested_card' using errcode='23505'; end if;
  if (select count(distinct definition_id) from public.card_instances where id=any(coalesce(p_offered_ids,'{}'::uuid[])))<>v_offered_count
     or (select count(distinct definition_id) from public.card_instances where id=any(coalesce(p_requested_ids,'{}'::uuid[])))<>v_requested_count then
    raise exception 'duplicate_trade_definition' using errcode='22023';
  end if;
  insert into public.card_trades(proposer_id,recipient_id,offered_coins,requested_coins,offered_coins_escrowed)
  values(auth.uid(),p_recipient_id,p_offered_coins,p_requested_coins,p_offered_coins>0) returning id into v_trade_id;
  if p_offered_coins>0 then
    perform public.apply_card_coins(auth.uid(),-p_offered_coins,'trade_escrow',v_trade_id,
      jsonb_build_object('recipient_id',p_recipient_id));
  end if;
  insert into public.card_trade_items(trade_id,card_instance_id,side)
  select v_trade_id,x,'offered' from unnest(coalesce(p_offered_ids,'{}'::uuid[])) x
  union all select v_trade_id,x,'requested' from unnest(coalesce(p_requested_ids,'{}'::uuid[])) x;
  update public.card_instances set locked_trade_id=v_trade_id where id=any(coalesce(p_offered_ids,'{}'::uuid[]));
  return v_trade_id;
end;
$$;

create or replace function public.create_card_trade(p_recipient_id uuid,p_offered_ids uuid[],p_requested_ids uuid[])
returns uuid language sql security definer set search_path = '' as $$
  select public.create_card_trade(p_recipient_id,p_offered_ids,p_requested_ids,0,0)
$$;

create or replace function public.respond_card_trade(p_trade_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trade public.card_trades;v_item_count integer;v_xp integer:=0;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  select * into v_trade from public.card_trades where id=p_trade_id for update;
  if v_trade.id is null or v_trade.recipient_id<>auth.uid() then raise exception 'trade_not_found' using errcode='P0002'; end if;
  if v_trade.status<>'pending' then raise exception 'trade_not_pending' using errcode='55000'; end if;
  if v_trade.expires_at<=now() then
    if v_trade.offered_coins_escrowed and v_trade.offered_coins>0 then
      perform public.apply_card_coins(v_trade.proposer_id,v_trade.offered_coins,'trade_refund',v_trade.id,jsonb_build_object('reason','expired'));
    end if;
    update public.card_instances set locked_trade_id=null where locked_trade_id=v_trade.id;
    perform public.convert_card_excess_for_user(v_trade.proposer_id);
    update public.card_trades set status='expired',responded_at=now(),offered_coins_escrowed=false where id=v_trade.id;
    return jsonb_build_object('trade_id',v_trade.id,'status','expired','completed_at',now(),'xp_awarded',0);
  end if;
  if not p_accept then
    if v_trade.offered_coins_escrowed and v_trade.offered_coins>0 then
      perform public.apply_card_coins(v_trade.proposer_id,v_trade.offered_coins,'trade_refund',v_trade.id,jsonb_build_object('reason','declined'));
    end if;
    update public.card_instances set locked_trade_id=null where locked_trade_id=v_trade.id;
    perform public.convert_card_excess_for_user(v_trade.proposer_id);
    update public.card_trades set status='declined',responded_at=now(),offered_coins_escrowed=false where id=v_trade.id;
    return jsonb_build_object('trade_id',v_trade.id,'status','declined','completed_at',now(),'xp_awarded',0);
  end if;
  perform 1 from public.card_instances i join public.card_trade_items ti on ti.card_instance_id=i.id
    where ti.trade_id=v_trade.id order by i.id for update of i;
  select count(*) into v_item_count from public.card_trade_items where trade_id=v_trade.id;
  if (select count(*) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id
      where ti.trade_id=v_trade.id and i.retired_at is null and
        ((ti.side='offered' and i.owner_id=v_trade.proposer_id and i.locked_trade_id=v_trade.id)
         or (ti.side='requested' and i.owner_id=v_trade.recipient_id and i.locked_trade_id is null)))<>v_item_count then
    raise exception 'trade_inventory_changed' using errcode='40001';
  end if;
  if exists(select 1 from public.card_trade_items ti join public.card_instances incoming on incoming.id=ti.card_instance_id
    join public.card_instances owned on owned.definition_id=incoming.definition_id and owned.retired_at is null
    where ti.trade_id=v_trade.id and ((ti.side='offered' and owned.owner_id=v_trade.recipient_id)
      or (ti.side='requested' and owned.owner_id=v_trade.proposer_id))) then
    raise exception 'trade_would_create_owned_duplicate' using errcode='23505';
  end if;
  if v_trade.requested_coins>0 then
    perform public.apply_card_coins(v_trade.recipient_id,-v_trade.requested_coins,'trade_sent',v_trade.id,
      jsonb_build_object('recipient_id',v_trade.proposer_id));
  end if;
  update public.card_instances i set owner_id=case ti.side when 'offered' then v_trade.recipient_id else v_trade.proposer_id end,
    locked_trade_id=null from public.card_trade_items ti where ti.trade_id=v_trade.id and ti.card_instance_id=i.id;
  delete from public.card_wishlist w using public.card_trade_items ti,public.card_instances i
  where ti.trade_id=v_trade.id and i.id=ti.card_instance_id and w.user_id=i.owner_id and w.definition_id=i.definition_id;
  if v_trade.offered_coins>0 then
    perform public.apply_card_coins(v_trade.recipient_id,v_trade.offered_coins,'trade_received',v_trade.id,
      jsonb_build_object('sender_id',v_trade.proposer_id));
  end if;
  if v_trade.requested_coins>0 then
    perform public.apply_card_coins(v_trade.proposer_id,v_trade.requested_coins,'trade_received',v_trade.id,
      jsonb_build_object('sender_id',v_trade.recipient_id));
  end if;
  update public.profiles p set featured_card_instance_id=null,updated_at=now()
  where p.featured_card_instance_id in (select card_instance_id from public.card_trade_items where trade_id=v_trade.id)
    and not exists(select 1 from public.card_instances i where i.id=p.featured_card_instance_id and i.owner_id=p.id);
  update public.card_trades set status='accepted',responded_at=now(),offered_coins_escrowed=false where id=v_trade.id;
  v_xp:=50;perform public.award_card_xp(v_trade.proposer_id,v_xp);perform public.award_card_xp(v_trade.recipient_id,v_xp);
  perform public.refresh_card_album_badges(v_trade.proposer_id);perform public.refresh_card_album_badges(v_trade.recipient_id);
  perform public.refresh_card_achievements(v_trade.proposer_id);perform public.refresh_card_achievements(v_trade.recipient_id);
  return jsonb_build_object('trade_id',v_trade.id,'status','accepted','completed_at',now(),'xp_awarded',v_xp);
end;
$$;

create or replace function public.cancel_card_trade(p_trade_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_trade public.card_trades;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  select * into v_trade from public.card_trades where id=p_trade_id for update;
  if v_trade.id is null or v_trade.proposer_id<>auth.uid() or v_trade.status<>'pending' then
    raise exception 'trade_not_cancellable' using errcode='42501';
  end if;
  if v_trade.offered_coins_escrowed and v_trade.offered_coins>0 then
    perform public.apply_card_coins(v_trade.proposer_id,v_trade.offered_coins,'trade_refund',v_trade.id,jsonb_build_object('reason','cancelled'));
  end if;
  update public.card_instances set locked_trade_id=null where locked_trade_id=v_trade.id;
  perform public.convert_card_excess_for_user(v_trade.proposer_id);
  update public.card_trades set status='cancelled',responded_at=now(),offered_coins_escrowed=false where id=v_trade.id;
  return jsonb_build_object('trade_id',v_trade.id,'status','cancelled');
end;
$$;

create or replace function public.card_trade_feed()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode='42501'; end if;
  perform public.release_expired_card_trades();
  select jsonb_build_object('trades',coalesce(jsonb_agg(jsonb_build_object(
    'trade_id',t.id,'direction',case when t.recipient_id=auth.uid() then 'incoming' else 'outgoing' end,
    'status',t.status::text,'other_user_id',case when t.recipient_id=auth.uid() then t.proposer_id else t.recipient_id end,
    'other_username',other_profile.username,'other_display_name',other_profile.display_name,
    'created_at',t.created_at,'expires_at',t.expires_at,'responded_at',t.responded_at,
    'offered_coins',t.offered_coins,'requested_coins',t.requested_coins,
    'offered_instance_ids',(select coalesce(jsonb_agg(ti.card_instance_id order by ti.card_instance_id),'[]'::jsonb) from public.card_trade_items ti where ti.trade_id=t.id and ti.side='offered'),
    'requested_instance_ids',(select coalesce(jsonb_agg(ti.card_instance_id order by ti.card_instance_id),'[]'::jsonb) from public.card_trade_items ti where ti.trade_id=t.id and ti.side='requested'),
    'offered_titles',(select coalesce(jsonb_agg(coalesce(d.title,track.title) order by i.serial_number),'[]'::jsonb) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id left join public.tracks track on track.id=d.track_id where ti.trade_id=t.id and ti.side='offered'),
    'requested_titles',(select coalesce(jsonb_agg(coalesce(d.title,track.title) order by i.serial_number),'[]'::jsonb) from public.card_trade_items ti join public.card_instances i on i.id=ti.card_instance_id join public.collectible_card_definitions d on d.id=i.definition_id left join public.tracks track on track.id=d.track_id where ti.trade_id=t.id and ti.side='requested')
  ) order by t.created_at desc),'[]'::jsonb)) into v_result
  from public.card_trades t join public.profiles other_profile on other_profile.id=case when t.recipient_id=auth.uid() then t.proposer_id else t.recipient_id end
  where t.proposer_id=auth.uid() or t.recipient_id=auth.uid();
  return v_result;
end;
$$;

alter table public.card_wallets enable row level security;
alter table public.card_coin_ledger enable row level security;
alter table public.card_pack_products enable row level security;
alter table public.card_wishlist enable row level security;

drop policy if exists card_wallet_owner_read on public.card_wallets;
create policy card_wallet_owner_read on public.card_wallets for select to authenticated using(user_id=auth.uid());
drop policy if exists card_coin_ledger_owner_read on public.card_coin_ledger;
create policy card_coin_ledger_owner_read on public.card_coin_ledger for select to authenticated using(user_id=auth.uid());
drop policy if exists card_pack_products_read on public.card_pack_products;
create policy card_pack_products_read on public.card_pack_products for select to authenticated using(is_enabled or public.is_admin());
drop policy if exists card_pack_products_admin_all on public.card_pack_products;
create policy card_pack_products_admin_all on public.card_pack_products for all to authenticated
using(public.is_admin()) with check(public.is_admin());
drop policy if exists card_wishlist_owner_read on public.card_wishlist;
create policy card_wishlist_owner_read on public.card_wishlist for select to authenticated using(user_id=auth.uid());

revoke all on public.card_wallets,public.card_coin_ledger,public.card_pack_products,public.card_wishlist from public,anon,authenticated;
grant select on public.card_wallets,public.card_coin_ledger,public.card_pack_products,public.card_wishlist to authenticated;
grant select,insert,update,delete on public.card_pack_products to authenticated;

revoke all on function
  public.ensure_card_wallet(uuid),public.card_coin_value(uuid,boolean),
  public.apply_card_coins(uuid,bigint,text,uuid,jsonb),public.init_card_wallet_from_profile(),
  public.normalize_card_badge_source(),
  public.convert_card_excess_for_user(uuid),
  public.create_card_pack_internal(uuid,text,uuid,integer,public.card_rarity),
  public.refresh_card_album_badges(uuid),public.card_achievement_progress_for(uuid,text),
  public.refresh_card_achievements(uuid),public.release_expired_card_trades()
from public,anon,authenticated;

revoke all on function
  public.card_pack_store(),public.buy_card_pack(text),public.open_card_pack(uuid),public.open_all_card_packs(),
  public.card_inventory_feed(),public.card_inventory_feed_page(integer,integer),
  public.card_tradeable_inventory(text),public.card_album_catalog_feed(),public.card_album_catalog_feed_page(integer,integer),public.card_album_tracklist(uuid),
  public.toggle_card_wishlist(uuid),public.card_wishlist_feed(),public.card_user_wishlist(text),public.card_achievement_feed(),
  public.card_album_progress(),public.equip_card_badge(uuid,smallint),
  public.profile_equipped_card_badges(uuid),public.profile_owned_badges(uuid),
  public.set_profile_featured_card(uuid),public.profile_featured_card(uuid),public.set_profile_genres(text[]),
  public.card_game_dashboard(),public.create_card_trade(uuid,uuid[],uuid[],bigint,bigint),
  public.create_card_trade(uuid,uuid[],uuid[]),public.respond_card_trade(uuid,boolean),
  public.cancel_card_trade(uuid),public.card_trade_feed()
from public,anon;

grant execute on function
  public.card_pack_store(),public.buy_card_pack(text),public.open_card_pack(uuid),public.open_all_card_packs(),
  public.card_inventory_feed(),public.card_inventory_feed_page(integer,integer),
  public.card_tradeable_inventory(text),public.card_album_catalog_feed(),public.card_album_catalog_feed_page(integer,integer),public.card_album_tracklist(uuid),
  public.toggle_card_wishlist(uuid),public.card_wishlist_feed(),public.card_user_wishlist(text),public.card_achievement_feed(),
  public.card_album_progress(),public.equip_card_badge(uuid,smallint),
  public.profile_equipped_card_badges(uuid),public.profile_owned_badges(uuid),
  public.set_profile_featured_card(uuid),public.profile_featured_card(uuid),public.set_profile_genres(text[]),
  public.card_game_dashboard(),public.create_card_trade(uuid,uuid[],uuid[],bigint,bigint),
  public.create_card_trade(uuid,uuid[],uuid[]),public.respond_card_trade(uuid,boolean),
  public.cancel_card_trade(uuid),public.card_trade_feed()
to authenticated;

comment on table public.card_wallets is 'Server-authoritative YePly Cards coin balance. Direct client writes are forbidden.';
comment on function public.open_card_pack(uuid) is 'Mints at most two active copies per definition; later duplicates are atomically converted into coins.';
comment on function public.card_album_tracklist(uuid) is 'Returns every enabled track in one album, including missing cards, in disc/track order.';
comment on function public.profile_owned_badges(uuid) is 'Returns all album, full-discography and achievement badges; equipped slot is optional.';

commit;
