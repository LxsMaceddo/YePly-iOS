-- YePly Admin 1.1: atomic playlist track reordering.

create or replace function public.reorder_playlist_tracks(
  p_playlist_id uuid,
  p_track_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected_count integer;
  v_received_count integer;
  v_offset integer;
begin
  if auth.uid() is null or not public.can_manage_playlist(p_playlist_id) then
    raise exception 'playlist_manager_required' using errcode = '42501';
  end if;

  select count(*)::integer, coalesce(max(position), 0)::integer
  into v_expected_count, v_offset
  from public.tracks
  where playlist_id = p_playlist_id;

  v_received_count := coalesce(cardinality(p_track_ids), 0);

  if v_received_count <> v_expected_count then
    raise exception 'track_list_must_include_every_playlist_track' using errcode = '22023';
  end if;

  if (select count(distinct track_id) from unnest(p_track_ids) as ids(track_id)) <> v_received_count then
    raise exception 'duplicate_track_id' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(p_track_ids) as requested(track_id)
    left join public.tracks t
      on t.id = requested.track_id and t.playlist_id = p_playlist_id
    where t.id is null
  ) then
    raise exception 'track_does_not_belong_to_playlist' using errcode = '22023';
  end if;

  -- Move all positions outside the current range first to avoid unique conflicts.
  v_offset := v_offset + v_expected_count + 1;
  update public.tracks
  set position = position + v_offset
  where playlist_id = p_playlist_id;

  update public.tracks as target
  set position = requested.ordinality::integer - 1
  from unnest(p_track_ids) with ordinality as requested(track_id, ordinality)
  where target.id = requested.track_id
    and target.playlist_id = p_playlist_id;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'tracks_reordered',
    'playlist',
    p_playlist_id,
    jsonb_build_object('track_count', v_received_count)
  );
end;
$$;

revoke all on function public.reorder_playlist_tracks(uuid, uuid[]) from public;
grant execute on function public.reorder_playlist_tracks(uuid, uuid[]) to authenticated;

comment on function public.reorder_playlist_tracks(uuid, uuid[])
is 'Atomically assigns sequential positions to every track in a playlist. Only playlist managers may execute it.';
