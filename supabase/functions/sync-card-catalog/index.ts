import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MUSICBRAINZ_BASE = "https://musicbrainz.org/ws/2";
const LISTENBRAINZ_BASE = "https://api.listenbrainz.org/1";
const USER_AGENT = "YePly/2.3 (https://yeply.app)";

type KnownAlbum = {
  releaseGroupMBID: string;
  title: string;
  expectedTrackCount: number;
};

type KnownArtist = {
  mbid: string;
  appleMusicID: string;
  spotifyID: string;
  displayName: string;
  aliases: string[];
  albums: KnownAlbum[];
};

// Initial curated test catalog. Release-group IDs are stable MusicBrainz identifiers.
// Curating the canonical studio albums avoids bootlegs, fan uploads, compilations and
// duplicate deluxe editions that can appear in a broad artist search.
const knownArtists: KnownArtist[] = [
  {
    mbid: "164f0d73-1234-4e2c-8743-d77bf2191051",
    appleMusicID: "2715720",
    spotifyID: "5K4W6rqBFWDnAN6FQUkS6x",
    displayName: "Kanye West",
    aliases: ["kanye west", "ye"],
    albums: [
      { releaseGroupMBID: "8a01217e-6947-3927-a39b-6691104694f1", title: "The College Dropout", expectedTrackCount: 21 },
      { releaseGroupMBID: "c563d738-3841-31ce-b29d-ec6b40fd1e7b", title: "Late Registration", expectedTrackCount: 21 },
      { releaseGroupMBID: "d44c50ad-61fd-3fce-95fc-27024d7f1d30", title: "Graduation", expectedTrackCount: 13 },
      { releaseGroupMBID: "1c1b50ec-828b-3d7c-9b1b-54cb1fe97d55", title: "808s & Heartbreak", expectedTrackCount: 12 },
      { releaseGroupMBID: "5d6e21e1-deb5-428e-bb42-c2a567f3619b", title: "My Beautiful Dark Twisted Fantasy", expectedTrackCount: 13 },
      { releaseGroupMBID: "5d4d0f2d-9be7-4922-bc9a-cbd2880b12c2", title: "Yeezus", expectedTrackCount: 10 },
      { releaseGroupMBID: "8c18657a-6338-490d-a952-897663596b96", title: "The Life of Pablo", expectedTrackCount: 20 },
      { releaseGroupMBID: "6448381d-9d98-4f84-b99d-733b6acde906", title: "ye", expectedTrackCount: 7 },
      { releaseGroupMBID: "ee26718c-2633-4278-8718-f3a45a95f20e", title: "Jesus Is King", expectedTrackCount: 11 },
      { releaseGroupMBID: "7f4792fe-b563-4554-849a-95a89be71f84", title: "Donda", expectedTrackCount: 27 },
    ],
  },
];

type MBArtistCredit = { name?: string; joinphrase?: string };
type MBTrack = {
  position?: number;
  number?: string;
  length?: number;
  title?: string;
  recording?: {
    id?: string;
    title?: string;
    length?: number;
    "artist-credit"?: MBArtistCredit[];
  };
};
type MBMedium = { position?: number; tracks?: MBTrack[]; format?: string };
type MBRelease = {
  id?: string;
  title?: string;
  status?: string;
  date?: string;
  country?: string;
  disambiguation?: string;
  media?: MBMedium[];
};
type MBReleaseResponse = { releases?: MBRelease[] };
type PopularityRow = {
  recording_mbid?: string;
  total_listen_count?: number | null;
  total_user_count?: number | null;
};

type AppleMusicSong = {
  id?: string;
  attributes?: {
    name?: string;
    artistName?: string;
    albumName?: string;
    url?: string;
  };
};
type AppleMusicTopSongsResponse = { data?: AppleMusicSong[] };
type SpotifyOEmbedResponse = {
  title?: string;
  thumbnail_url?: string | null;
};
type SpotifyArtistProfile = {
  artistID: string;
  url: string;
  artworkURL: string;
};

type ImportedTrack = {
  recording_mbid: string;
  title: string;
  artist_name: string;
  duration_ms: number;
  disc_number: number;
  track_number: number;
  global_listens: number;
  global_listeners: number;
  apple_music_id?: string;
  apple_music_url?: string;
  apple_music_rank?: number;
};

type ImportedAlbum = {
  release_group_mbid: string;
  release_mbid: string;
  title: string;
  release_date: string | null;
  artwork_url: string;
  tracks: ImportedTrack[];
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalize(value: string): string {
  return value.trim().toLocaleLowerCase("en-US").replace(/\s+/g, " ");
}

function songMatchKey(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\p{Diacritic}/gu, "")
    .toLocaleLowerCase("en-US")
    .replace(/[’']/g, "")
    .replace(/\s*[([{](feat\.?|ft\.?|with)\b[^\])}]*[\])}]/gi, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function sleep(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function fetchWithRetry(url: string, init: RequestInit = {}, attempts = 4): Promise<Response> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await fetch(url, {
        ...init,
        headers: {
          "User-Agent": USER_AGENT,
          Accept: "application/json",
          ...(init.headers ?? {}),
        },
      });
      if (response.ok) return response;
      if (![429, 500, 502, 503, 504].includes(response.status)) {
        throw new Error(`upstream_${response.status}: ${await response.text()}`);
      }
      lastError = new Error(`upstream_${response.status}`);
    } catch (error) {
      lastError = error;
    }
    await sleep(750 * 2 ** attempt);
  }
  throw lastError instanceof Error ? lastError : new Error("upstream_unavailable");
}

function releaseScore(release: MBRelease, album: KnownAlbum): number {
  const countryScore: Record<string, number> = { US: 100, XW: 85, XE: 75, GB: 65, CA: 55 };
  const disambiguation = normalize(release.disambiguation ?? "");
  const exactTitle = normalize(release.title ?? "") === normalize(album.title) ? 40 : 0;
  const baseEdition = disambiguation.length === 0 ? 55 : 0;
  const deluxePenalty = /deluxe|bonus|anniversary|clean|instrumental/.test(disambiguation) ? 80 : 0;
  const trackCount = (release.media ?? []).reduce((total, medium) => total + (medium.tracks?.length ?? 0), 0);
  const hasTracks = trackCount > 0 ? 30 : -500;
  const canonicalTrackCount = Math.max(0, 220 - Math.abs(trackCount - album.expectedTrackCount) * 80);
  return (countryScore[release.country ?? ""] ?? 45) + exactTitle + baseEdition + hasTracks
    + canonicalTrackCount - deluxePenalty;
}

function chooseCanonicalRelease(releases: MBRelease[], album: KnownAlbum): MBRelease {
  const candidates = releases.filter((release) =>
    release.id && release.status === "Official" && (release.media ?? []).some((medium) => (medium.tracks?.length ?? 0) > 0)
  );
  candidates.sort((left, right) => {
    const scoreDifference = releaseScore(right, album) - releaseScore(left, album);
    if (scoreDifference !== 0) return scoreDifference;
    return (left.date ?? "9999").localeCompare(right.date ?? "9999");
  });
  const selected = candidates[0];
  if (!selected?.id) throw new Error(`canonical_release_not_found:${album.title}`);
  return selected;
}

function artistCreditName(credit: MBArtistCredit[] | undefined, fallback: string): string {
  if (!credit?.length) return fallback;
  const result = credit.map((entry) => `${entry.name ?? ""}${entry.joinphrase ?? ""}`).join("").trim();
  return result || fallback;
}

function releaseTracks(release: MBRelease, fallbackArtist: string): ImportedTrack[] {
  const seen = new Set<string>();
  const tracks: ImportedTrack[] = [];
  for (const medium of release.media ?? []) {
    for (const track of medium.tracks ?? []) {
      const recording = track.recording;
      if (!recording?.id || !recording.title || seen.has(recording.id)) continue;
      seen.add(recording.id);
      const parsedTrackNumber = Number.parseInt(track.number ?? "1", 10);
      const trackNumber = track.position ?? (Number.isFinite(parsedTrackNumber) ? parsedTrackNumber : 1);
      tracks.push({
        recording_mbid: recording.id,
        title: recording.title,
        artist_name: artistCreditName(recording["artist-credit"], fallbackArtist),
        duration_ms: Math.max(0, Math.min(track.length ?? recording.length ?? 0, 7_200_000)),
        disc_number: Math.max(1, Math.min(medium.position ?? 1, 99)),
        track_number: Math.max(1, Math.min(trackNumber, 999)),
        global_listens: 0,
        global_listeners: 0,
      });
    }
  }
  return tracks;
}

async function fetchAlbum(album: KnownAlbum, fallbackArtist: string): Promise<ImportedAlbum> {
  const params = new URLSearchParams({
    "release-group": album.releaseGroupMBID,
    status: "official",
    inc: "recordings+artist-credits",
    limit: "100",
    fmt: "json",
  });
  const response = await fetchWithRetry(`${MUSICBRAINZ_BASE}/release?${params.toString()}`);
  const data = (await response.json()) as MBReleaseResponse;
  const release = chooseCanonicalRelease(data.releases ?? [], album);
  const tracks = releaseTracks(release, fallbackArtist);
  if (tracks.length === 0) throw new Error(`empty_release:${album.title}`);
  return {
    release_group_mbid: album.releaseGroupMBID,
    release_mbid: release.id!,
    title: album.title,
    release_date: release.date?.match(/^\d{4}-\d{2}-\d{2}$/) ? release.date : null,
    // A canonical release can legitimately have no front image even when the
    // release group does. The release-group endpoint follows the preferred
    // cover selected by Cover Art Archive and is therefore much more stable.
    artwork_url: `https://coverartarchive.org/release-group/${album.releaseGroupMBID}/front-500`,
    tracks,
  };
}

async function attachPopularity(albums: ImportedAlbum[]): Promise<void> {
  const allTracks = albums.flatMap((album) => album.tracks);
  const byID = new Map(allTracks.map((track) => [track.recording_mbid, track]));
  const ids = [...byID.keys()];
  for (let start = 0; start < ids.length; start += 100) {
    const recordingIDs = ids.slice(start, start + 100);
    const response = await fetchWithRetry(`${LISTENBRAINZ_BASE}/popularity/recording`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ recording_mbids: recordingIDs }),
    });
    const rows = (await response.json()) as PopularityRow[];
    for (const row of rows) {
      if (!row.recording_mbid) continue;
      const track = byID.get(row.recording_mbid);
      if (!track) continue;
      track.global_listens = Math.max(0, Math.trunc(row.total_listen_count ?? 0));
      track.global_listeners = Math.max(0, Math.trunc(row.total_user_count ?? 0));
    }
  }
}

async function attachAppleMusicRanking(
  artist: KnownArtist,
  albums: ImportedAlbum[],
  developerToken: string,
  storefront: string,
): Promise<number> {
  const response = await fetchWithRetry(
    `https://api.music.apple.com/v1/catalog/${encodeURIComponent(storefront)}/artists/${artist.appleMusicID}/view/top-songs?limit=100&with=attributes`,
    { headers: { Authorization: `Bearer ${developerToken}` } },
  );
  const payload = (await response.json()) as AppleMusicTopSongsResponse;
  const candidates = albums.flatMap((album) => album.tracks.map((track) => ({ album, track })));
  let matched = 0;
  for (const [index, song] of (payload.data ?? []).entries()) {
    const attributes = song.attributes;
    if (!song.id || !attributes?.name) continue;
    const titleKey = songMatchKey(attributes.name);
    const matches = candidates.filter((candidate) => songMatchKey(candidate.track.title) === titleKey);
    if (matches.length === 0) continue;
    const albumKey = songMatchKey(attributes.albumName ?? "");
    const selected = matches.find((candidate) => songMatchKey(candidate.album.title) === albumKey) ?? matches[0];
    if (selected.track.apple_music_rank != null && selected.track.apple_music_rank <= index + 1) continue;
    selected.track.apple_music_id = song.id;
    selected.track.apple_music_url = attributes.url;
    selected.track.apple_music_rank = index + 1;
    matched += 1;
  }
  return matched;
}

async function fetchSpotifyArtistProfile(artist: KnownArtist): Promise<SpotifyArtistProfile> {
  const spotifyURL = `https://open.spotify.com/artist/${artist.spotifyID}`;
  const response = await fetchWithRetry(
    `https://open.spotify.com/oembed?url=${encodeURIComponent(spotifyURL)}`,
    {},
    2,
  );
  const payload = (await response.json()) as SpotifyOEmbedResponse;
  const artworkURL = payload.thumbnail_url?.trim() ?? "";
  if (!artworkURL.match(/^https:\/\/image-cdn-[A-Za-z0-9-]+\.spotifycdn\.com\/image\/[A-Za-z0-9]+$/)) {
    throw new Error("invalid_spotify_artist_artwork");
  }
  return { artistID: artist.spotifyID, url: spotifyURL, artworkURL };
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization) return jsonResponse({ error: "authentication_required" }, 401);

  try {
    const body = await request.json().catch(() => ({})) as { artist_name?: string };
    const requestedName = normalize(body.artist_name ?? "Kanye West");
    const artist = knownArtists.find((candidate) => candidate.aliases.includes(requestedName));
    if (!artist) return jsonResponse({ error: "artist_not_curated_yet" }, 422);

    let spotifyProfile: SpotifyArtistProfile | null = null;
    try {
      spotifyProfile = await fetchSpotifyArtistProfile(artist);
    } catch (error) {
      console.warn("spotify_artist_artwork_unavailable", error);
    }

    const albums: ImportedAlbum[] = [];
    for (const album of artist.albums) {
      albums.push(await fetchAlbum(album, artist.displayName));
      // MusicBrainz asks clients to stay at or below one request per second per IP.
      await sleep(1_100);
    }
    let listenBrainzAvailable = true;
    try {
      await attachPopularity(albums);
    } catch (error) {
      // Popularity is enrichment, not a prerequisite for importing the official
      // discography. ListenBrainz can temporarily throttle or disable this
      // endpoint; keeping the sync alive avoids an empty catalog in the app.
      listenBrainzAvailable = false;
      console.warn("listenbrainz_enrichment_unavailable", error);
    }
    const appleMusicToken = Deno.env.get("APPLE_MUSIC_DEVELOPER_TOKEN")?.trim();
    const appleMusicStorefront = normalize(Deno.env.get("APPLE_MUSIC_STOREFRONT") ?? "us");
    let appleMusicMatches = 0;
    let appleMusicAvailable = Boolean(appleMusicToken);
    if (appleMusicToken) {
      try {
        appleMusicMatches = await attachAppleMusicRanking(artist, albums, appleMusicToken, appleMusicStorefront);
      } catch (error) {
        appleMusicAvailable = false;
        console.warn("apple_music_enrichment_unavailable", error);
      }
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseURL || !anonKey) throw new Error("missing_supabase_environment");
    const supabase = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const payload = {
      artist: { mbid: artist.mbid, name: artist.displayName },
      albums,
      generated_at: new Date().toISOString(),
      metadata_source: "musicbrainz",
      popularity_source: listenBrainzAvailable ? "listenbrainz" : "pending",
    };
    const { data, error } = await supabase.rpc("import_external_card_catalog", { p_payload: payload });
    if (error) throw new Error(`database_import_failed:${error.message}`);
    if (spotifyProfile) {
      const { error: spotifyError } = await supabase.rpc("update_collectible_artist_spotify", {
        p_artist_mbid: artist.mbid,
        p_spotify_artist_id: spotifyProfile.artistID,
        p_spotify_url: spotifyProfile.url,
        p_artwork_url: spotifyProfile.artworkURL,
      });
      if (spotifyError) console.warn(`spotify_artist_update_failed:${spotifyError.message}`);
    }
    if (appleMusicAvailable && appleMusicMatches > 0) {
      const rankedRows = albums.flatMap((album) => album.tracks)
        .filter((track) => track.apple_music_rank != null)
        .map((track) => ({
          recording_mbid: track.recording_mbid,
          apple_music_id: track.apple_music_id,
          apple_music_url: track.apple_music_url,
          rank: track.apple_music_rank,
        }));
      const { error: rankingError } = await supabase.rpc("import_apple_music_card_ranking", {
        p_artist_mbid: artist.mbid,
        p_storefront: appleMusicStorefront,
        p_rows: rankedRows,
      });
      if (rankingError) throw new Error(`apple_music_import_failed:${rankingError.message}`);
    }
    const result = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const baseMessage = typeof result.message === "string" ? result.message : "Catálogo sincronizado.";
    return jsonResponse({
      ...result,
      success: true,
      listenbrainz_available: listenBrainzAvailable,
      apple_music_enabled: appleMusicAvailable,
      apple_music_matches: appleMusicMatches,
      apple_music_storefront: appleMusicStorefront,
      spotify_artist_artwork: Boolean(spotifyProfile),
      message: appleMusicAvailable
        ? `${baseMessage} Apple Music: ${appleMusicMatches} músicas ranqueadas.`
        : listenBrainzAvailable
          ? `${baseMessage} Popularidade global atualizada.`
          : `${baseMessage} As métricas de popularidade serão atualizadas na próxima sincronização.`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    console.error(message);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
