begin;

-- Keep a single canonical edition for album progress and future pack drops.
-- Existing card instances are preserved in their owners' inventories.
with excluded_albums as (
  select al.id
  from public.collectible_albums al
  cross join lateral (
    select lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) as normalized_title
  ) normalized
  where normalized.normalized_title ~ '^late orchestration( |$)'
     or (
       normalized.normalized_title ~ '^bully( |$)'
       and normalized.normalized_title !~ '(^| )deluxe( |$)'
     )
     or (
       normalized.normalized_title ~ '^watch the throne( |$)'
       and normalized.normalized_title !~ '(^| )deluxe( |$)'
     )
)
update public.collectible_card_definitions d
set is_enabled = false,
    updated_at = now()
where d.album_id in (select id from excluded_albums);

update public.collectible_albums al
set is_enabled = false,
    updated_at = now()
where lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '^late orchestration( |$)'
   or (
     lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '^bully( |$)'
     and lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) !~ '(^| )deluxe( |$)'
   )
   or (
     lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) ~ '^watch the throne( |$)'
     and lower(regexp_replace(btrim(al.title), '[^a-zA-Z0-9]+', ' ', 'g')) !~ '(^| )deluxe( |$)'
   );

drop function if exists public.card_album_progress();
create function public.card_album_progress()
returns table (
  album_id uuid, album_title text, artist_name text,
  artist_artwork_path text, artist_source_url text, artwork_path text,
  release_date date, owned_unique integer, total_cards integer,
  is_complete boolean, badge_id uuid, badge_equipped boolean
)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  perform public.refresh_card_album_badges(auth.uid());
  return query
  select al.id, al.title, a.display_name, a.artwork_path, a.spotify_url,
         coalesce(al.artwork_path, b.artwork_path), al.release_date,
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
  order by a.display_name, al.release_date nulls last, al.title;
end;
$$;

revoke all on function public.card_album_progress() from public, anon;
grant execute on function public.card_album_progress() to authenticated;

comment on function public.card_album_progress() is
  'Returns canonical enabled albums in original release order with collector progress.';

commit;
