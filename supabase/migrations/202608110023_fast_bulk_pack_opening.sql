-- Open every sealed pack in one request without recalculating album badges and
-- achievements after each individual pack. The public single-pack contract is
-- unchanged; only the bulk transaction opts into the deferred refresh.

create or replace function public.open_all_card_packs()
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
  v_pack_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  perform pg_catalog.set_config('app.bulk_pack_opening', 'on', true);
  for v_pack_id in
    select p.id from public.card_packs p
    where p.owner_id = auth.uid()
      and p.status = 'sealed'::public.card_pack_status
    order by p.created_at, p.id
    for update skip locked
  loop
    return query select * from public.open_card_pack(v_pack_id);
  end loop;
  perform pg_catalog.set_config('app.bulk_pack_opening', 'off', true);
  perform public.refresh_card_album_badges(auth.uid());
  perform public.refresh_card_achievements(auth.uid());
end;
$$;

do $$
declare
  v_definition text;
begin
  select pg_catalog.pg_get_functiondef('public.open_card_pack(uuid)'::regprocedure)
    into v_definition;
  v_definition := replace(
    v_definition,
    '  perform public.refresh_card_album_badges(auth.uid());' || chr(10) ||
    '  perform public.refresh_card_achievements(auth.uid());',
    '  if coalesce(pg_catalog.current_setting(''app.bulk_pack_opening'', true), ''off'') <> ''on'' then' || chr(10) ||
    '    perform public.refresh_card_album_badges(auth.uid());' || chr(10) ||
    '    perform public.refresh_card_achievements(auth.uid());' || chr(10) ||
    '  end if;'
  );
  if position('app.bulk_pack_opening' in v_definition) = 0 then
    raise exception 'open_card_pack refresh block was not found';
  end if;
  execute v_definition;
end;
$$;

revoke all on function public.open_all_card_packs() from public;
grant execute on function public.open_all_card_packs() to authenticated;

comment on function public.open_all_card_packs() is
  'Atomically opens all sealed packs in one round-trip and refreshes derived card state once.';
