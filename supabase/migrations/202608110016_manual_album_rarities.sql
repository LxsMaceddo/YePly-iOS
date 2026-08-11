begin;

alter table public.collectible_card_definitions
  add column if not exists manual_view_count bigint,
  add column if not exists manual_metric_source text;

alter table public.collectible_card_definitions
  drop constraint if exists collectible_cards_manual_views_nonnegative;
alter table public.collectible_card_definitions
  add constraint collectible_cards_manual_views_nonnegative
  check (manual_view_count is null or manual_view_count >= 0);

-- View totals supplied by the YePly administrator. Arrays follow each album's
-- Spotify track order, making punctuation/title variations harmless.
with manual_album(spotify_album_id, source_label, views) as (values
  ('3ff2p3LnR6V7m6BinwhNaQ', 'admin-screenshots-2026-08', array[122309,136270352,37128758,1135385409,39072445,140580133,344553929,103693087,75027607,24848372,117986426,317675270,47683536,19033752,50933268,17899378,18152904,82934655,509551777,164506929,72243811]::bigint[]),
  ('4GRDFQ9HRoO0by8H0r2a3I', 'admin-screenshots-2026-08', array[28400855,191242431,574984860,1553138917,23059004,135456749,41930369,40406858,113606568,36860887,65412524,22406012,102137092,103629942,32034,136820461,37368483,12796536,63615743,61392100,55533175]::bigint[]),
  ('6V0srAdQfEIarFvIxAYilH', 'admin-screenshots-2026-08', array[428270210,360897324,1859960410,1202863134,617346977,1057506043,91496387,78716530,1856285436,376351298,131511312,1115156613,99018308]::bigint[]),
  ('3WFTGIO6E3Xh4paEOBY9OU', 'admin-screenshots-2026-08', array[58497330,101914943,2075236504,198313962,242983709,134753179,53900481,104933887,47220226,53441138,61800588,22773362]::bigint[]),
  ('20r762YmB5HeofjMCiPMLv', 'admin-screenshots-2026-08', array[294280205,296180842,1216018183,88981627,987442939,486885125,113480627,733155792,1233644557,145941417,112045344,140701938,42049674]::bigint[]),
  ('4P63UgNDUcF11MnWzyvVrh', 'admin-screenshots-2026-08', array[604071502,75321444,1874915003,335953990,300030727,55676590,45438066,38377445,115895394,68826882,44283126,249036762,4867004,68141671,31116025,21596864]::bigint[]),
  ('7D2NdGvBHIavgLhmcwhluK', 'admin-screenshots-2026-08', array[253118863,724661371,96743268,181345375,162666661,77504253,231174536,69736774,77832093,1403129654]::bigint[]),
  ('7gsWAHLeT0w7es6FofOXk1', 'admin-screenshots-2026-08', array[405915832,1515757677,279087734,710973856,140206808,74451616,119630893,92177291,140687878,532649428,252547028,238728733,323975810,94900908,46485141,149597486,330805535,107168166,277597068,272135590]::bigint[]),
  ('2Ek1q2haOnxVqhvVKqMvJe', 'admin-screenshots-2026-08', array[125920978,254998747,587680554,137356934,134432392,804694186,973530658]::bigint[]),
  ('1oK1GzEMNDjCt7EYYpomwc', 'admin-screenshots-2026-08', array[144274485,99627915,238950153,83203742,359117810,93914554,124842169]::bigint[]),
  ('0FgZKfoU2Br5sHOfvZKTI9', 'admin-screenshots-2026-08', array[66379410,113845639,541353659,137893841,111614180,98051239,65190740,284130513,61871844,107178438,51269232]::bigint[]),
  ('2Wiyo7LzdeBCsVZiRA6vVZ', 'admin-screenshots-2026-08', array[30081089,485587959,393188297,94388732,331020690,76500739,580629951,85411764,157767309,127966088,12183067,13959748,57740372,65916782,94774960,37248587,9381074,41786001,71478137,6001932,108970420,77949398,30137536,81037505,109965102,35250954,75375509,5182050,3984160,37248587,76500739,71478137]::bigint[]),
  ('0k7oanYS9dXYWLXaFOYxJ8', 'admin-screenshots-2026-08', array[23951243,14268450,6636938,11340715,6358184,8057582,5533481,3262324,3089244,3869645,10038465,22612844,6187540,3537474,6860318,3667608,2993659,3247804,4736066,6295292]::bigint[]),
  ('0k7ALIqqds5oGFtpMsaHLK', 'admin-screenshots-2026-08', array[98923504,49381016,70763139,76878419,136184722,39671173,110423411,63835919,294111159,240554761,72501270,932760435,56607675,0,56084912,36379711]::bigint[]),
  ('5RV2TNyjylqWJNxQyHBTeJ', 'admin-screenshots-2026-08', array[39900577,22941844,162087210,34975269,26910,65309588,59338558,32153397,18277642,15478511,36344061,6810834,1156195,10078797,17977141,4977684]::bigint[]),
  ('3hwveWhYFxGDLy6K6xlwFh', 'admin-screenshots-2026-08', array[36561957,26779457,88884665,86140678,33976092,30285548,22794475,24259663,26230713,33278750,6597979,22207493,16169897,55036274,39615851,29398693,2466425,19710977,20585393,2846633]::bigint[])
), expanded as (
  select m.spotify_album_id, m.source_label, u.view_count, u.track_number
  from manual_album m
  cross join lateral unnest(m.views) with ordinality u(view_count, track_number)
)
update public.collectible_card_definitions d
set manual_view_count = e.view_count,
    manual_metric_source = e.source_label,
    updated_at = now()
from public.collectible_albums al, expanded e
where al.id = d.album_id
  and al.spotify_album_id = e.spotify_album_id
  and coalesce(d.track_number, 1) = e.track_number;

-- The supplied Donda Deluxe metrics also cover the same songs on Donda.
update public.collectible_card_definitions target
set manual_view_count = source.manual_view_count,
    manual_metric_source = 'admin-screenshots-2026-08:donda-deluxe-match',
    updated_at = now()
from public.collectible_albums target_album,
     public.collectible_card_definitions source,
     public.collectible_albums source_album
where target.album_id = target_album.id
  and source.album_id = source_album.id
  and target_album.spotify_album_id = '5CnpZV3q5BcESefcB3WJmz'
  and source_album.spotify_album_id = '2Wiyo7LzdeBCsVZiRA6vVZ'
  and source.manual_view_count is not null
  and lower(regexp_replace(target.title, '[^a-zA-Z0-9]+', ' ', 'g')) =
      lower(regexp_replace(source.title, '[^a-zA-Z0-9]+', ' ', 'g'));

-- Albums/tracks not present in this batch keep a frozen baseline, never a live
-- external recalculation. A future admin batch can replace these values.
update public.collectible_card_definitions d
set manual_view_count = greatest(d.global_listen_count, 0),
    manual_metric_source = 'frozen-baseline-2026-08',
    updated_at = now()
from public.collectible_albums al
where al.id = d.album_id and al.is_enabled and d.is_enabled
  and d.manual_view_count is null;

create or replace function public.refresh_card_rarities_internal()
returns void language plpgsql security definer set search_path = '' as $$
begin
  with ranked as (
    select d.id, d.album_id, d.manual_view_count,
      count(*) over (partition by d.album_id)::integer as album_size,
      avg(d.manual_view_count) over (partition by d.album_id)::numeric as album_average,
      row_number() over (
        partition by d.album_id
        order by d.manual_view_count desc, coalesce(d.disc_number, 1), coalesce(d.track_number, 1), d.id
      )::integer as album_rank
    from public.collectible_card_definitions d
    join public.collectible_albums al on al.id = d.album_id and al.is_enabled
    where d.is_enabled and d.manual_view_count is not null
  ), classified as (
    select r.*,
      case when r.album_size >= 12 then 3 when r.album_size >= 8 then 2 else 1 end as mythic_slots,
      greatest(
        case when r.album_size >= 12 then 3 when r.album_size >= 8 then 2 else 1 end + 2,
        ceil(r.album_size * 0.45)::integer
      ) as epic_rank_limit
    from ranked r
  ), final as (
    select c.*,
      case
        when c.album_rank <= c.mythic_slots then 'mythic'::public.card_rarity
        when c.manual_view_count >= c.album_average or c.album_rank <= c.epic_rank_limit
          then 'epic'::public.card_rarity
        else 'common'::public.card_rarity
      end as calculated_rarity,
      case when c.album_size <= 1 then 100::numeric
           else round(((c.album_size - c.album_rank)::numeric / (c.album_size - 1)) * 100, 3)
      end as album_percentile
    from classified c
  )
  update public.collectible_card_definitions d
  set global_listen_count = f.manual_view_count,
      play_count_snapshot = f.manual_view_count,
      popularity_score = f.album_percentile,
      popularity_ratio = case when f.album_average > 0
        then least(1::numeric, round((f.manual_view_count::numeric / f.album_average), 6)) else 0 end,
      artist_popularity_rank = f.album_rank,
      artist_catalog_size = f.album_size,
      rarity = f.calculated_rarity,
      drop_weight = case f.calculated_rarity
        when 'common'::public.card_rarity then 1000
        when 'epic'::public.card_rarity then 125
        when 'mythic'::public.card_rarity then 10
        else 1000
      end,
      rarity_version = 'manual-album-v1',
      updated_at = now()
  from final f
  where f.id = d.id;

  update public.card_instances i
  set rarity_at_mint = d.rarity,
      popularity_score_at_mint = d.popularity_score,
      rarity_version_at_mint = d.rarity_version
  from public.collectible_card_definitions d
  where d.id = i.definition_id and d.manual_view_count is not null;
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
    'message', 'Raridades manuais recalculadas pela média e ranking de cada álbum.',
    'card_count', (select count(*) from public.collectible_card_definitions where is_enabled),
    'rarity_model', 'manual-album-v1'
  );
end;
$$;

-- Repair every empty per-track path so pack results can always fall back to the
-- canonical album cover before reaching the iPhone.
update public.collectible_card_definitions d
set artwork_path = al.artwork_path,
    updated_at = now()
from public.collectible_albums al
where al.id = d.album_id
  and nullif(btrim(d.artwork_path), '') is null
  and nullif(btrim(al.artwork_path), '') is not null;

select public.refresh_card_rarities_internal();

revoke all on function public.refresh_card_rarities() from public, anon;
grant execute on function public.refresh_card_rarities() to authenticated;

comment on column public.collectible_card_definitions.manual_view_count is
  'Admin-provided immutable view snapshot used as the sole rarity metric.';
comment on function public.refresh_card_rarities_internal() is
  'Manual per-album rarity model: 1-3 top mythics, epics around/above the album mean, remaining cards common.';

commit;
