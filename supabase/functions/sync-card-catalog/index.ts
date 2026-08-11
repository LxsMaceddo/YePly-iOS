import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SPOTIFY_API_BASE = "https://api.spotify.com/v1";
const MUSICBRAINZ_BASE = "https://musicbrainz.org/ws/2";
const LISTENBRAINZ_BASE = "https://api.listenbrainz.org/1";
const USER_AGENT = "YePly/2.4 (https://yeply.app)";

// Spotify may expose the date of a later re-upload. For the curated catalogue,
// YePly keeps the project's original release date so discographies stay historical.
const canonicalReleaseDates = new Map<string, string>([
  ["3ff2p3LnR6V7m6BinwhNaQ", "2004-02-10"],
  ["4GRDFQ9HRoO0by8H0r2a3I", "2005-08-30"],
  ["6V0srAdQfEIarFvIxAYilH", "2007-09-11"],
  ["3WFTGIO6E3Xh4paEOBY9OU", "2008-11-24"],
  ["20r762YmB5HeofjMCiPMLv", "2010-11-22"],
  ["4P63UgNDUcF11MnWzyvVrh", "2011-08-08"],
  ["0A3g19AGFd9Qe3rAIkP8e0", "2012-09-14"],
  ["7D2NdGvBHIavgLhmcwhluK", "2013-06-18"],
  ["7gsWAHLeT0w7es6FofOXk1", "2016-02-14"],
  ["2Ek1q2haOnxVqhvVKqMvJe", "2018-06-01"],
  ["1oK1GzEMNDjCt7EYYpomwc", "2018-06-08"],
  ["0FgZKfoU2Br5sHOfvZKTI9", "2019-10-25"],
  ["5CnpZV3q5BcESefcB3WJmz", "2021-08-29"],
  ["0k7oanYS9dXYWLXaFOYxJ8", "2022-02-23"],
  ["0k7ALIqqds5oGFtpMsaHLK", "2024-02-10"],
  ["5RV2TNyjylqWJNxQyHBTeJ", "2024-08-03"],
  ["3hwveWhYFxGDLy6K6xlwFh", "2026-06-19"],
]);

type KnownAlbum = {
  spotifyAlbumID: string;
  title: string;
  expectedTrackCount: number;
  releaseGroupMBID?: string;
};

type KnownArtist = {
  musicBrainzID: string;
  appleMusicID: string;
  primarySpotifyID: string;
  spotifyIDs: string[];
  displayName: string;
  aliases: string[];
  albums: KnownAlbum[];
};

// These verified releases are a safety net for collaborative albums that Spotify
// does not always return from every artist profile. The synchronizer also discovers
// new albums from both current Kanye/Ye profiles, so future releases do not require
// an app update.
const knownArtists: KnownArtist[] = [
  {
    musicBrainzID: "164f0d73-1234-4e2c-8743-d77bf2191051",
    appleMusicID: "2715720",
    primarySpotifyID: "5K4W6rqBFWDnAN6FQUkS6x",
    spotifyIDs: ["5K4W6rqBFWDnAN6FQUkS6x", "7wEE9uEujboYdmX95N5ZXq"],
    displayName: "Kanye West",
    aliases: ["kanye west", "ye"],
    albums: [
      { releaseGroupMBID: "8a01217e-6947-3927-a39b-6691104694f1", spotifyAlbumID: "3ff2p3LnR6V7m6BinwhNaQ", title: "The College Dropout", expectedTrackCount: 21 },
      { releaseGroupMBID: "c563d738-3841-31ce-b29d-ec6b40fd1e7b", spotifyAlbumID: "4GRDFQ9HRoO0by8H0r2a3I", title: "Late Registration", expectedTrackCount: 21 },
      { releaseGroupMBID: "d44c50ad-61fd-3fce-95fc-27024d7f1d30", spotifyAlbumID: "6V0srAdQfEIarFvIxAYilH", title: "Graduation", expectedTrackCount: 13 },
      { releaseGroupMBID: "1c1b50ec-828b-3d7c-9b1b-54cb1fe97d55", spotifyAlbumID: "3WFTGIO6E3Xh4paEOBY9OU", title: "808s & Heartbreak", expectedTrackCount: 12 },
      { releaseGroupMBID: "5d6e21e1-deb5-428e-bb42-c2a567f3619b", spotifyAlbumID: "20r762YmB5HeofjMCiPMLv", title: "My Beautiful Dark Twisted Fantasy", expectedTrackCount: 13 },
      { releaseGroupMBID: "a96597aa-93b4-4e14-9e6e-03892ab24979", spotifyAlbumID: "4P63UgNDUcF11MnWzyvVrh", title: "Watch The Throne (Deluxe)", expectedTrackCount: 16 },
      { releaseGroupMBID: "1e06bb4d-3e20-4d1c-8d0a-0c179df397b5", spotifyAlbumID: "0A3g19AGFd9Qe3rAIkP8e0", title: "Kanye West Presents Good Music Cruel Summer", expectedTrackCount: 12 },
      { releaseGroupMBID: "5d4d0f2d-9be7-4922-bc9a-cbd2880b12c2", spotifyAlbumID: "7D2NdGvBHIavgLhmcwhluK", title: "Yeezus", expectedTrackCount: 10 },
      { releaseGroupMBID: "8c18657a-6338-490d-a952-897663596b96", spotifyAlbumID: "7gsWAHLeT0w7es6FofOXk1", title: "The Life Of Pablo", expectedTrackCount: 20 },
      { releaseGroupMBID: "6448381d-9d98-4f84-b99d-733b6acde906", spotifyAlbumID: "2Ek1q2haOnxVqhvVKqMvJe", title: "ye", expectedTrackCount: 7 },
      { releaseGroupMBID: "3346a9d9-031e-49e2-84b0-3734d790d7e5", spotifyAlbumID: "1oK1GzEMNDjCt7EYYpomwc", title: "KIDS SEE GHOSTS", expectedTrackCount: 7 },
      { releaseGroupMBID: "ee26718c-2633-4278-8718-f3a45a95f20e", spotifyAlbumID: "0FgZKfoU2Br5sHOfvZKTI9", title: "JESUS IS KING", expectedTrackCount: 11 },
      { releaseGroupMBID: "7f4792fe-b563-4554-849a-95a89be71f84", spotifyAlbumID: "5CnpZV3q5BcESefcB3WJmz", title: "Donda", expectedTrackCount: 27 },
      { releaseGroupMBID: "26584460-df1f-4a91-b036-8d0bf6f8ce95", spotifyAlbumID: "0k7oanYS9dXYWLXaFOYxJ8", title: "DONDA 2", expectedTrackCount: 20 },
      { releaseGroupMBID: "c4d999c3-983d-4149-8580-9ccb4567a12a", spotifyAlbumID: "0k7ALIqqds5oGFtpMsaHLK", title: "VULTURES 1", expectedTrackCount: 16 },
      { releaseGroupMBID: "d69250da-c94d-436d-bacf-7e52da48bc68", spotifyAlbumID: "5RV2TNyjylqWJNxQyHBTeJ", title: "VULTURES 2", expectedTrackCount: 16 },
      { spotifyAlbumID: "3hwveWhYFxGDLy6K6xlwFh", title: "BULLY - DELUXE", expectedTrackCount: 20 },
    ],
  },
];

type SpotifyImage = { url?: string; width?: number | null; height?: number | null };
type SpotifyArtistCredit = { id?: string; name?: string };
type SpotifyTrack = {
  id?: string;
  name?: string;
  duration_ms?: number;
  disc_number?: number;
  track_number?: number;
  artists?: SpotifyArtistCredit[];
  external_urls?: { spotify?: string };
  external_ids?: { isrc?: string };
};
type SpotifyPaging<T> = { items?: T[]; next?: string | null };
type SpotifyAlbumSummary = {
  id?: string;
  name?: string;
  album_type?: string;
  total_tracks?: number;
  release_date?: string;
  artists?: SpotifyArtistCredit[];
  images?: SpotifyImage[];
  external_urls?: { spotify?: string };
};
type SpotifyAlbum = SpotifyAlbumSummary & { tracks?: SpotifyPaging<SpotifyTrack> };
type SpotifyTokenResponse = { access_token?: string; expires_in?: number };
type SpotifyOEmbedResponse = { thumbnail_url?: string | null };

type MBArtistCredit = { name?: string; joinphrase?: string };
type MBTrack = {
  position?: number;
  number?: string;
  length?: number;
  recording?: {
    id?: string;
    title?: string;
    length?: number;
    "artist-credit"?: MBArtistCredit[];
  };
};
type MBMedium = { position?: number; tracks?: MBTrack[] };
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
  recording_name?: string;
  total_listen_count?: number | null;
  total_user_count?: number | null;
};

type AppleMusicSong = {
  id?: string;
  attributes?: { name?: string; albumName?: string; url?: string };
};
type AppleMusicTopSongsResponse = { data?: AppleMusicSong[] };

type ImportedTrack = {
  spotify_track_id: string;
  title: string;
  artist_name: string;
  duration_ms: number;
  disc_number: number;
  track_number: number;
  spotify_url: string;
  isrc?: string;
  musicbrainz_recording_id?: string;
  global_listens: number;
  global_listeners: number;
  apple_music_id?: string;
  apple_music_url?: string;
  apple_music_rank?: number;
};

type ImportedAlbum = {
  spotify_album_id: string;
  title: string;
  release_date: string;
  artwork_url: string;
  spotify_url: string;
  musicbrainz_release_group_id?: string;
  tracks: ImportedTrack[];
};

type MBReferenceTrack = {
  recordingID: string;
  title: string;
  discNumber: number;
  trackNumber: number;
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
    .replace(/\b(album version|explicit version|edited|remaster(?:ed)?(?: \d{4})?)\b/gi, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function albumKey(value: string): string {
  return songMatchKey(value);
}

function normalizedReleaseDate(value: string | undefined): string {
  const candidate = value?.trim() ?? "";
  if (/^\d{4}-\d{2}-\d{2}$/.test(candidate)) return candidate;
  if (/^\d{4}-\d{2}$/.test(candidate)) return `${candidate}-01`;
  if (/^\d{4}$/.test(candidate)) return `${candidate}-01-01`;
  return "1970-01-01";
}

function artworkURL(images: SpotifyImage[] | undefined): string {
  return (images ?? [])
    .filter((image) => typeof image.url === "string" && image.url.startsWith("https://"))
    .sort((left, right) => Math.abs((left.width ?? 640) - 640) - Math.abs((right.width ?? 640) - 640))[0]?.url ?? "";
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
      const detail = await response.text();
      if (![429, 500, 502, 503, 504].includes(response.status)) {
        throw new Error(`upstream_${response.status}:${detail.slice(0, 240)}`);
      }
      lastError = new Error(`upstream_${response.status}:${detail.slice(0, 240)}`);
      const retryAfter = Number(response.headers.get("Retry-After") ?? "0");
      await sleep(retryAfter > 0 ? Math.min(retryAfter * 1000, 15_000) : 700 * 2 ** attempt);
      continue;
    } catch (error) {
      lastError = error;
    }
    await sleep(700 * 2 ** attempt);
  }
  throw lastError instanceof Error ? lastError : new Error("upstream_unavailable");
}

async function fetchSpotifyAccessToken(clientID: string, clientSecret: string): Promise<string> {
  const response = await fetchWithRetry("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${clientID}:${clientSecret}`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials",
  });
  const payload = (await response.json()) as SpotifyTokenResponse;
  if (!payload.access_token) throw new Error("spotify_access_token_missing");
  return payload.access_token;
}

async function fetchSpotifyProfileArtwork(artistID: string): Promise<string> {
  const spotifyURL = `https://open.spotify.com/artist/${artistID}`;
  const response = await fetchWithRetry(
    `https://open.spotify.com/oembed?url=${encodeURIComponent(spotifyURL)}`,
    {},
    2,
  );
  const payload = (await response.json()) as SpotifyOEmbedResponse;
  const url = payload.thumbnail_url?.trim() ?? "";
  return /^https:\/\/(?:image-cdn-[A-Za-z0-9-]+\.spotifycdn\.com|i\.scdn\.co)\/image\/[A-Za-z0-9]+$/.test(url)
    ? url
    : "";
}

async function fetchSpotifyArtistAlbums(artistID: string, token: string): Promise<SpotifyAlbumSummary[]> {
  const albums: SpotifyAlbumSummary[] = [];
  let pageURL: string | null = `${SPOTIFY_API_BASE}/artists/${artistID}/albums?include_groups=album&market=BR&limit=10&offset=0`;
  const headers = { Authorization: `Bearer ${token}` };
  while (pageURL && albums.length < 100) {
    const response = await fetchWithRetry(pageURL, { headers });
    const page = (await response.json()) as SpotifyPaging<SpotifyAlbumSummary>;
    albums.push(...(page.items ?? []));
    pageURL = page.next ?? null;
  }
  return albums;
}

async function fetchSpotifyAlbum(albumID: string, token: string): Promise<SpotifyAlbum> {
  const headers = { Authorization: `Bearer ${token}` };
  const response = await fetchWithRetry(`${SPOTIFY_API_BASE}/albums/${albumID}?market=BR`, { headers });
  const album = (await response.json()) as SpotifyAlbum;
  const tracks = [...(album.tracks?.items ?? [])];
  let next = album.tracks?.next ?? null;
  while (next && tracks.length < 100) {
    const pageResponse = await fetchWithRetry(next, { headers });
    const page = (await pageResponse.json()) as SpotifyPaging<SpotifyTrack>;
    tracks.push(...(page.items ?? []));
    next = page.next ?? null;
  }
  album.tracks = { items: tracks, next: null };
  return album;
}

function shouldImportDiscoveredAlbum(album: SpotifyAlbumSummary, artist: KnownArtist): boolean {
  if (!album.id || !album.name || album.album_type !== "album") return false;
  if (!(album.artists ?? []).some((credit) => credit.id && artist.spotifyIDs.includes(credit.id))) return false;
  if (/karaoke|tribute|instrumental|commentary|podcast/i.test(album.name)) return false;

  const key = albumKey(album.name);
  // Keep one canonical edition so album progress and badges are not split.
  if (key.startsWith("late orchestration")) return false;
  if (key.startsWith("bully") && !key.includes("deluxe")) return false;
  if (key.startsWith("watch the throne") && !key.includes("deluxe")) return false;
  return true;
}

function chooseDiscoveredAlbums(items: SpotifyAlbumSummary[], artist: KnownArtist): SpotifyAlbumSummary[] {
  const curatedKeys = new Set(artist.albums.map((album) => albumKey(album.title)));
  const byTitle = new Map<string, SpotifyAlbumSummary>();
  for (const item of items.filter((album) => shouldImportDiscoveredAlbum(album, artist))) {
    const key = albumKey(item.name ?? "");
    if (!key || curatedKeys.has(key)) continue;
    const existing = byTitle.get(key);
    const itemScore = (item.total_tracks ?? 0) * 10 + Number(normalizedReleaseDate(item.release_date).replaceAll("-", ""));
    const existingScore = existing
      ? (existing.total_tracks ?? 0) * 10 + Number(normalizedReleaseDate(existing.release_date).replaceAll("-", ""))
      : -1;
    if (!existing || itemScore > existingScore) byTitle.set(key, item);
  }
  return [...byTitle.values()]
    .sort((left, right) => normalizedReleaseDate(left.release_date).localeCompare(normalizedReleaseDate(right.release_date)))
    .slice(0, Math.max(0, 60 - artist.albums.length));
}

function importedSpotifyAlbum(album: SpotifyAlbum, known?: KnownAlbum): ImportedAlbum {
  if (!album.id || !album.name) throw new Error("spotify_album_missing_identity");
  const art = artworkURL(album.images);
  if (!art) throw new Error(`spotify_album_artwork_missing:${album.name}`);
  const tracks = (album.tracks?.items ?? []).flatMap((track): ImportedTrack[] => {
    if (!track.id || !track.name) return [];
    const credits = (track.artists ?? []).map((artist) => artist.name?.trim()).filter(Boolean).join(", ");
    return [{
      spotify_track_id: track.id,
      title: track.name.trim(),
      artist_name: credits || "Kanye West",
      duration_ms: Math.max(0, Math.min(track.duration_ms ?? 0, 7_200_000)),
      disc_number: Math.max(1, Math.min(track.disc_number ?? 1, 99)),
      track_number: Math.max(1, Math.min(track.track_number ?? 1, 999)),
      spotify_url: track.external_urls?.spotify ?? `https://open.spotify.com/track/${track.id}`,
      isrc: track.external_ids?.isrc?.toUpperCase(),
      global_listens: 0,
      global_listeners: 0,
    }];
  });
  if (tracks.length === 0) throw new Error(`spotify_album_empty:${album.name}`);
  return {
    spotify_album_id: album.id,
    title: album.name.trim(),
    release_date: canonicalReleaseDates.get(album.id) ?? normalizedReleaseDate(album.release_date),
    artwork_url: art,
    spotify_url: album.external_urls?.spotify ?? `https://open.spotify.com/album/${album.id}`,
    musicbrainz_release_group_id: known?.releaseGroupMBID,
    tracks,
  };
}

function releaseScore(release: MBRelease, album: KnownAlbum): number {
  const countryScore: Record<string, number> = { US: 100, XW: 85, XE: 75, GB: 65, CA: 55 };
  const disambiguation = normalize(release.disambiguation ?? "");
  const trackCount = (release.media ?? []).reduce((total, medium) => total + (medium.tracks?.length ?? 0), 0);
  return (countryScore[release.country ?? ""] ?? 45)
    + (normalize(release.title ?? "") === normalize(album.title) ? 40 : 0)
    + (disambiguation.length === 0 ? 55 : 0)
    + (trackCount > 0 ? 30 : -500)
    + Math.max(0, 220 - Math.abs(trackCount - album.expectedTrackCount) * 80)
    - (/clean|instrumental|commentary/.test(disambiguation) ? 100 : 0);
}

async function fetchMusicBrainzReference(album: KnownAlbum): Promise<MBReferenceTrack[]> {
  if (!album.releaseGroupMBID) return [];
  const params = new URLSearchParams({
    "release-group": album.releaseGroupMBID,
    status: "official",
    inc: "recordings+artist-credits",
    limit: "100",
    fmt: "json",
  });
  const response = await fetchWithRetry(`${MUSICBRAINZ_BASE}/release?${params.toString()}`);
  const payload = (await response.json()) as MBReleaseResponse;
  const releases = (payload.releases ?? []).filter((release) =>
    release.id && release.status === "Official" && (release.media ?? []).some((medium) => (medium.tracks?.length ?? 0) > 0)
  );
  releases.sort((left, right) => releaseScore(right, album) - releaseScore(left, album));
  const selected = releases[0];
  if (!selected) return [];
  const result: MBReferenceTrack[] = [];
  for (const medium of selected.media ?? []) {
    for (const track of medium.tracks ?? []) {
      if (!track.recording?.id || !track.recording.title) continue;
      const parsedNumber = Number.parseInt(track.number ?? "1", 10);
      result.push({
        recordingID: track.recording.id,
        title: track.recording.title,
        discNumber: Math.max(1, medium.position ?? 1),
        trackNumber: Math.max(1, track.position ?? (Number.isFinite(parsedNumber) ? parsedNumber : 1)),
      });
    }
  }
  return result;
}

function attachMusicBrainzReferences(album: ImportedAlbum, reference: MBReferenceTrack[]): number {
  const used = new Set<string>();
  let matches = 0;
  for (const track of album.tracks) {
    const key = songMatchKey(track.title);
    const candidates = reference.filter((item) => !used.has(item.recordingID) && songMatchKey(item.title) === key);
    const selected = candidates.find((item) =>
      item.discNumber === track.disc_number && item.trackNumber === track.track_number
    ) ?? candidates[0];
    if (!selected) continue;
    track.musicbrainz_recording_id = selected.recordingID;
    used.add(selected.recordingID);
    matches += 1;
  }
  return matches;
}

async function attachListenBrainzPopularity(artist: KnownArtist, albums: ImportedAlbum[]): Promise<number> {
  const allTracks = albums.flatMap((album) => album.tracks);
  const byMBID = new Map(
    allTracks.filter((track) => track.musicbrainz_recording_id)
      .map((track) => [track.musicbrainz_recording_id!, track]),
  );
  let matches = 0;
  const ids = [...byMBID.keys()];
  for (let start = 0; start < ids.length; start += 100) {
    const response = await fetchWithRetry(`${LISTENBRAINZ_BASE}/popularity/recording`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ recording_mbids: ids.slice(start, start + 100) }),
    });
    const rows = (await response.json()) as PopularityRow[];
    for (const row of rows) {
      const track = row.recording_mbid ? byMBID.get(row.recording_mbid) : undefined;
      if (!track) continue;
      track.global_listens = Math.max(0, Math.trunc(row.total_listen_count ?? 0));
      track.global_listeners = Math.max(0, Math.trunc(row.total_user_count ?? 0));
      if (track.global_listens > 0 || track.global_listeners > 0) matches += 1;
    }
  }

  // This artist-wide endpoint can enrich newly released Spotify tracks that do
  // not have a curated MusicBrainz album mapping yet. It is best-effort because
  // ListenBrainz occasionally returns 5xx while rebuilding popularity data.
  try {
    const response = await fetchWithRetry(
      `${LISTENBRAINZ_BASE}/popularity/top-recordings-for-artist/${artist.musicBrainzID}`,
      {},
      2,
    );
    const rows = (await response.json()) as PopularityRow[];
    const unmatched = allTracks.filter((track) => track.global_listens === 0 && track.global_listeners === 0);
    for (const row of rows) {
      const titleKey = songMatchKey(row.recording_name ?? "");
      if (!titleKey) continue;
      const track = unmatched.find((candidate) => songMatchKey(candidate.title) === titleKey);
      if (!track) continue;
      track.musicbrainz_recording_id ??= row.recording_mbid;
      track.global_listens = Math.max(0, Math.trunc(row.total_listen_count ?? 0));
      track.global_listeners = Math.max(0, Math.trunc(row.total_user_count ?? 0));
      if (track.global_listens > 0 || track.global_listeners > 0) matches += 1;
    }
  } catch (error) {
    console.warn("listenbrainz_artist_top_unavailable", error);
  }
  return matches;
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
  let matches = 0;
  for (const [index, song] of (payload.data ?? []).entries()) {
    if (!song.id || !song.attributes?.name) continue;
    const titleKey = songMatchKey(song.attributes.name);
    const possible = candidates.filter((candidate) => songMatchKey(candidate.track.title) === titleKey);
    if (possible.length === 0) continue;
    const albumTitleKey = albumKey(song.attributes.albumName ?? "");
    const selected = possible.find((candidate) => albumKey(candidate.album.title) === albumTitleKey) ?? possible[0];
    if (selected.track.apple_music_rank != null && selected.track.apple_music_rank <= index + 1) continue;
    selected.track.apple_music_id = song.id;
    selected.track.apple_music_url = song.attributes.url;
    selected.track.apple_music_rank = index + 1;
    matches += 1;
  }
  return matches;
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

    const spotifyClientID = Deno.env.get("SPOTIFY_CLIENT_ID")?.trim();
    const spotifyClientSecret = Deno.env.get("SPOTIFY_CLIENT_SECRET")?.trim();
    if (!spotifyClientID || !spotifyClientSecret) {
      return jsonResponse({
        success: false,
        error: "Configure SPOTIFY_CLIENT_ID e SPOTIFY_CLIENT_SECRET nos secrets do Supabase.",
      }, 503);
    }
    const spotifyToken = await fetchSpotifyAccessToken(spotifyClientID, spotifyClientSecret);

    const discoveredByID = new Map<string, SpotifyAlbumSummary>();
    for (const spotifyArtistID of artist.spotifyIDs) {
      const discovered = await fetchSpotifyArtistAlbums(spotifyArtistID, spotifyToken);
      for (const album of discovered) if (album.id) discoveredByID.set(album.id, album);
    }
    const dynamicAlbums = chooseDiscoveredAlbums([...discoveredByID.values()], artist);
    const candidates: Array<{ id: string; known?: KnownAlbum }> = [
      ...artist.albums.map((known) => ({ id: known.spotifyAlbumID, known })),
      ...dynamicAlbums.map((album) => ({ id: album.id! })),
    ];

    const albums: ImportedAlbum[] = [];
    let musicBrainzMatches = 0;
    for (const candidate of candidates) {
      const spotifyAlbum = await fetchSpotifyAlbum(candidate.id, spotifyToken);
      const imported = importedSpotifyAlbum(spotifyAlbum, candidate.known);
      if (candidate.known?.releaseGroupMBID) {
        try {
          const reference = await fetchMusicBrainzReference(candidate.known);
          musicBrainzMatches += attachMusicBrainzReferences(imported, reference);
        } catch (error) {
          console.warn(`musicbrainz_reference_unavailable:${imported.title}`, error);
        }
        await sleep(1_100);
      }
      albums.push(imported);
    }

    let listenBrainzAvailable = true;
    let listenBrainzMatches = 0;
    try {
      listenBrainzMatches = await attachListenBrainzPopularity(artist, albums);
    } catch (error) {
      listenBrainzAvailable = false;
      console.warn("listenbrainz_enrichment_unavailable", error);
    }

    const appleMusicToken = Deno.env.get("APPLE_MUSIC_DEVELOPER_TOKEN")?.trim();
    const appleMusicStorefront = normalize(Deno.env.get("APPLE_MUSIC_STOREFRONT") ?? "us");
    let appleMusicAvailable = Boolean(appleMusicToken);
    let appleMusicMatches = 0;
    if (appleMusicToken) {
      try {
        appleMusicMatches = await attachAppleMusicRanking(artist, albums, appleMusicToken, appleMusicStorefront);
      } catch (error) {
        appleMusicAvailable = false;
        console.warn("apple_music_enrichment_unavailable", error);
      }
    }

    let artistArtwork = "";
    try {
      artistArtwork = await fetchSpotifyProfileArtwork(artist.primarySpotifyID);
    } catch (error) {
      console.warn("spotify_artist_artwork_unavailable", error);
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseURL || !anonKey) throw new Error("missing_supabase_environment");
    const supabase = createClient(supabaseURL, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const payload = {
      artist: {
        name: artist.displayName,
        spotify_id: artist.primarySpotifyID,
        spotify_ids: artist.spotifyIDs,
        musicbrainz_id: artist.musicBrainzID,
        artwork_url: artistArtwork,
      },
      albums,
      generated_at: new Date().toISOString(),
      metadata_source: "spotify",
      popularity_sources: [
        ...(listenBrainzAvailable ? ["listenbrainz"] : []),
        ...(appleMusicAvailable ? ["apple_music"] : []),
        "yeply",
      ],
    };
    const { data, error } = await supabase.rpc("import_spotify_card_catalog", { p_payload: payload });
    if (error) throw new Error(`database_import_failed:${error.message}`);

    const result = data && typeof data === "object" ? data as Record<string, unknown> : {};
    const baseMessage = typeof result.message === "string" ? result.message : "Catálogo sincronizado.";
    return jsonResponse({
      ...result,
      success: true,
      spotify_profiles: artist.spotifyIDs.length,
      spotify_discovered_albums: dynamicAlbums.length,
      musicbrainz_matches: musicBrainzMatches,
      listenbrainz_available: listenBrainzAvailable,
      listenbrainz_matches: listenBrainzMatches,
      apple_music_enabled: appleMusicAvailable,
      apple_music_matches: appleMusicMatches,
      message: `${baseMessage} Raridades recalculadas dentro da discografia do artista.`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "unknown_error";
    console.error(message);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
