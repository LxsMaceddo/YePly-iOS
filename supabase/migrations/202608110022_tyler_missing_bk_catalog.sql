begin;

create or replace function pg_temp.yeply_album(
  p_spotify_album_id text,
  p_title text,
  p_release_date date,
  p_artist_name text,
  p_rows jsonb
) returns jsonb
language sql
as $$
  select jsonb_build_object(
    'spotify_album_id', p_spotify_album_id,
    'title', p_title,
    'release_date', p_release_date::text,
    'artwork_url', 'catalog/spotify/' || p_spotify_album_id || '.jpg',
    'spotify_url', 'https://open.spotify.com/album/' || p_spotify_album_id,
    'tracks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'spotify_track_id', substr(md5(p_spotify_album_id || ':' || r.ordinality::text), 1, 22),
          'title', r.value ->> 0,
          'artist_name', p_artist_name,
          'duration_ms', 0,
          'disc_number', 1,
          'track_number', r.ordinality,
          'spotify_url', null,
          'global_listens', greatest(0, (r.value ->> 1)::bigint),
          'global_listeners', 0
        )
        order by r.ordinality
      )
      from jsonb_array_elements(p_rows) with ordinality as r(value, ordinality)
    ), '[]'::jsonb)
  )
$$;

do $migration$
declare
  v_admin uuid;
  v_existing jsonb;
  v_new jsonb;
  v_payload jsonb;
begin
  select id into v_admin
  from public.profiles
  where role = 'admin'
  order by created_at
  limit 1;
  if v_admin is null then
    raise exception 'admin_profile_required_for_catalog_seed';
  end if;

  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', v_admin::text,
      'role', 'authenticated',
      'app_metadata', jsonb_build_object('role', 'admin')
    )::text,
    true
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'spotify_album_id', al.spotify_album_id,
      'title', al.title,
      'release_date', al.release_date::text,
      'artwork_url', al.artwork_path,
      'spotify_url', al.source_url,
      'tracks', (
        select jsonb_agg(
          jsonb_build_object(
            'spotify_track_id', d.spotify_track_id,
            'title', d.title,
            'artist_name', d.artist_name,
            'duration_ms', d.duration_ms,
            'disc_number', d.disc_number,
            'track_number', d.track_number,
            'spotify_url', d.source_url,
            'global_listens', coalesce(d.manual_view_count, d.global_listen_count, 0),
            'global_listeners', coalesce(d.global_listener_count, 0)
          )
          order by d.disc_number, d.track_number, d.created_at
        )
        from public.collectible_card_definitions d
        where d.album_id = al.id
      )
    )
    order by al.release_date, al.title
  ), '[]'::jsonb)
  into v_existing
  from public.collectible_albums al
  join public.collectible_artists ar on ar.id = al.artist_id
  where ar.artist_key = 'tyler, the creator'
    and al.spotify_album_id not in (
      '6VNF6KnJ3X7Kc7x5cJ5mct',
      '3CxknRPQLbOJRwQrNekNyU',
      '1GG6U2SSJPHO6XsFiBzxYv',
      '3pj1ebiwii7X06BNZglObJ'
    );

  v_new := jsonb_build_array(
    pg_temp.yeply_album('6VNF6KnJ3X7Kc7x5cJ5mct','IGOR','2019-05-17','Tyler, The Creator','[["IGOR''S THEME",203433460],["EARFQUAKE",1351640251],["I THINK",422823722],["EXACTLY WHAT YOU RUN FROM YOU END UP CHASING",71385],["RUNNING OUT OF TIME",391712025],["NEW MAGIC WAND",912151260],["A BOY IS A GUN*",293007200],["PUPPET",204831973],["WHAT''S GOOD",156163436],["GONE, GONE / THANK YOU",583005551],["I DON''T LOVE YOU ANYMORE",148103181],["ARE WE STILL FRIENDS?",934398114]]'::jsonb),
    pg_temp.yeply_album('3CxknRPQLbOJRwQrNekNyU','BEST INTEREST','2020-01-25','Tyler, The Creator','[["BEST INTEREST",829179148]]'::jsonb),
    pg_temp.yeply_album('1GG6U2SSJPHO6XsFiBzxYv','CALL ME IF YOU GET LOST: The Estate Sale','2023-03-31','Tyler, The Creator','[["SIR BAUDELAIRE (feat. DJ Drama)",107588667],["CORSO",142519102],["LEMONHEAD (feat. 42 Dugg)",140384892],["WUSYANAME (feat. Youngboy Never Broke Again & Ty Dolla $ign)",466184175],["LUMBERJACK",175892939],["HOT WIND BLOWS (feat. Lil Wayne)",187879320],["MASSA",92134927],["RUNITUP (feat. Teezo Touchdown)",99083605],["MANIFESTO (feat. Domo Genesis)",65916281],["SWEET / I THOUGHT YOU WANTED TO DANCE (feat. Brent Faiyaz & Fana Hues)",427706625],["MOMMA TALK",32765245],["RISE! (feat. DAISY WORLD)",75456791],["BLESSED",50743836],["JUGGERNAUT (feat. Lil Uzi Vert & Pharrell Williams)",178222472],["WILSHIRE",106498153],["SAFARI",72057261],["EVERYTHING MUST GO",119888],["STUNTMAN (feat. Vince Staples)",33577172],["WHAT A DAY",53507853],["WHARF TALK (feat. A$AP Rocky)",81113758],["DOGTOOTH",218388807],["HEAVEN TO ME",39559526],["BOYFRIEND, GIRLFRIEND (2020 Demo) (feat. YG)",46788076],["SORRY NOT SORRY",152236619]]'::jsonb),
    pg_temp.yeply_album('3pj1ebiwii7X06BNZglObJ','CHROMAKOPIA +','2024-10-28','Tyler, The Creator','[["St. Chroma (feat. Daniel Caesar)",341636110],["Rah Tah Tah",195731688],["Noid",176445076],["Darling, I (feat. Teezo Touchdown)",238583196],["Hey Jane",86315014],["I Killed You",83982778],["Judge Judy",105427617],["Sticky (feat. GloRilla, Sexyy Red & Lil Wayne)",538970582],["Take Your Mask Off (feat. Daniel Caesar & LaToiya Williams)",115537164],["Tomorrow",74262256],["Thought I Was Dead (feat. ScHoolboy Q & Santigold)",184196740],["Mother",10112336],["Like Him (feat. Lola Young)",812302794],["Balloon (feat. Doechii)",183090242],["I Hope You Find Your Way Home",70823015]]'::jsonb)
  );

  v_payload := jsonb_build_object(
    'artist', jsonb_build_object(
      'name', 'Tyler, The Creator',
      'spotify_id', '4V8LLVI7PbaPR0K2TGSxFF',
      'musicbrainz_id', 'f6beac20-5dfe-4d1f-ae02-0b0a740aafd6',
      'artwork_url', 'https://image-cdn-ak.spotifycdn.com/image/ab67616100005174df2728294ff77dd11eeb18fb'
    ),
    'albums', v_existing || v_new,
    'metadata_source', 'spotify',
    'popularity_sources', jsonb_build_array('admin-screenshots-2026-08')
  );
  perform public.import_spotify_card_catalog(v_payload);

  v_payload := jsonb_build_object(
    'artist', jsonb_build_object(
      'name', 'BK',
      'spotify_id', '1YOVBTvznjiDvtAj4ExHeo',
      'musicbrainz_id', '4d278397-9843-4e4d-abc3-afcbf64a992f',
      'artwork_url', 'catalog/spotify/2R3jSaMM1H6qecjhZtlgJH.jpg'
    ),
    'albums', jsonb_build_array(
      pg_temp.yeply_album('2R3jSaMM1H6qecjhZtlgJH','Castelos & Ruínas','2016-01-01','BK','[["Sigo na Sombra",19915272],["C&R Interlúdio I",7421824],["Quadros",20893159],["O Que Sobra Disso Tudo",8876105],["Visão Ampla",9731801],["Caminhos",27247620],["Castelos & Ruínas",33089464],["Pirâmide",7378438],["Amores, Vícios e Obsessões",56317300],["Não Me Espere",8975397],["Um Dia de Chuva Qualquer",8148803],["C&R Interlúdio II",5409761],["O Próximo Nascer do Sol",17994936]]'::jsonb),
      pg_temp.yeply_album('3HWIvqzXPCK4KNgzn6h1LL','Antes dos Gigantes Chegarem, Vol. 1','2017-01-01','BK','[["Top Boys",2181316],["Take Your Little Vision",2318424],["Deus das Ruas",5110370]]'::jsonb),
      pg_temp.yeply_album('4ImH7XwaBuqBBQQ4V16jW7','Antes dos Gigantes Chegarem, Vol. 2','2017-06-01','BK','[["Antes dos Gigantes Chegarem",21703308],["Adeus",4353538],["Almas",13102899]]'::jsonb),
      pg_temp.yeply_album('6kjXPFw0BT3SdpWgHwjr32','Gigantes','2018-01-01','BK','[["Novo Poder",4386388],["Porcentos",3745954],["Gigantes",8340269],["Exóticos",3871896],["Julius",10007842],["Abebe Bikila",3996277],["Titãs",14788213],["Vivos",13228880],["Planos",197934320],["Jovens",4583430],["Deus do Furdunço",13115976],["Falam",4605532],["Correria - Remix",4217302]]'::jsonb),
      pg_temp.yeply_album('22qXEcma67stw3AZOaDWmq','O Líder em Movimento','2020-01-01','BK','[["Movimento",9278081],["Bloco 7",5450169],["Porcentos 2",3374993],["Visão",3357850],["Amor",13874430],["Poder",4663567],["Megazord",3685598],["Pessoas",7756665],["Lugar",2597150],["Universo",35132753]]'::jsonb),
      pg_temp.yeply_album('1rqGgyvgN6ypRrnh0s6hsn','Cidade do Pecado','2021-01-01','BK','[["Cidade do Pecado",13228406],["Não Preciso Que Você Duvide",2886877],["Último Baile Antes da Guerra",1864348],["Paraíso Que Me Cerca",6523363],["E Se Eu Morrer",1962697]]'::jsonb),
      pg_temp.yeply_album('4YxPiDQY2qbVb0tJHEhAxS','ICARUS','2022-01-01','BK','[["Luzes",9714610],["Lugar na mesa",9657661],["Continuação de um sonho",27857478],["Nome nas ruas",17218648],["Tudo mudou e nada mudou",8497299],["Foto armado",10295140],["Só me ligar",152164175],["Luta e lucro",7442845],["Em nome do que sinto",19543048],["Músicas de amor nunca mais",196094987],["Se eu não lembrar",26310173],["Carta aberta",15252910],["Amanhecer",137307132]]'::jsonb),
      pg_temp.yeply_album('4CGf0iysUv0JUMoBqx4GOx','VERÃO CRIMINOSO','2023-01-01','BK','[["SOY JEFE",2174165],["DO NECTAR FREESTYLE - REMIX",1605829],["ESPECIALISTA",2056718],["FASE BOA",1220256],["VOCE SABE QUEM",1435499],["3 DA MADRUGA",2844290],["ESPAIRECER",1277398],["CABELO VOA",1574541],["ESCURINATTI",2029192],["ÁGUIA NÃO COME MOSCA",716947],["DUAS ARMAS",1037515],["BOM TE ENCONTRAR",57294485],["HOTEL ZONA SUL",13470110],["CLIMA DE AMOR",1739412],["REAL NIGGA",2074363],["DARK GLOCK",627990],["VINI JR.",682341],["DEPOIS DO BAILE",1176043]]'::jsonb),
      pg_temp.yeply_album('5FVM8teszzq7kZyIjkI4Vu','Diamantes, Lágrimas e Rostos para Esquecer','2025-01-01','BK','[["Você Pode Ir Além",15123245],["Só Eu Sei",21818394],["Não Adianta Chorar",20125032],["Medo De Mim",14660888],["Só Quero Ver",68693212],["Da Madrugada",13689008],["Quem Não Volta",7845131],["Monstro (interlúdio)",7409741],["Te Devo Nada",33702489],["Eu Consegui",9973846],["Real",25725934],["Amém, Amém",19982524],["Abaixo Das Nuvens",12703654],["Cacos De Vidro (sample: Esperar pra Ver)",127572702],["Ninguém Vai Tirar Minha Paz",8901741],["Mandamentos",6524591]]'::jsonb),
      pg_temp.yeply_album('3OB3nqd1Vm38NSTT4gC1gN','PRODUTO DO AMBIENTE','2025-08-01','BK','[["Até Amanhã",2411853],["Guru do Asfalto",1866728],["Gatilhos",5444091],["Bonde Passando",3023422],["Sonho",2492714],["Morro Sem Você",6462336],["Se Eu Não Manter",2789655],["Por Aí",4039409],["Deusa",30109741],["Trem Lotado",1685980],["Amém, Amém - Deekapz Remix",2411259]]'::jsonb)
    ),
    'metadata_source', 'spotify',
    'popularity_sources', jsonb_build_array('admin-screenshots-2026-08')
  );
  perform public.import_spotify_card_catalog(v_payload);

  update public.collectible_card_definitions d
  set manual_view_count = d.global_listen_count,
      manual_metric_source = 'admin-screenshots-2026-08',
      artwork_path = coalesce(nullif(d.artwork_path, ''), al.artwork_path),
      updated_at = now()
  from public.collectible_albums al
  join public.collectible_artists ar on ar.id = al.artist_id
  where d.album_id = al.id
    and ar.artist_key in ('tyler, the creator', 'bk');

  perform public.refresh_card_rarities_internal();
end
$migration$;

commit;
