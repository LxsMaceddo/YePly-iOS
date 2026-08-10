# sync-card-catalog

Synchronizes Kanye West's current album catalogue from both official Spotify profiles,
adds verified collaborative releases, maps known recordings to MusicBrainz, enriches
rarity with ListenBrainz, Apple Music (optional), and YePly playback, then imports the
snapshot through an admin-only RPC.

Deploy after applying migrations through `202608100012_spotify_card_catalog.sql`:

```bash
supabase functions deploy sync-card-catalog
```

Supabase supplies `SUPABASE_URL` and `SUPABASE_ANON_KEY`; the function forwards the
signed-in admin JWT to the security-definer import RPC. Never add a Supabase service-role
key to the app or function secrets.

Spotify catalogue access is required. Create a Spotify developer app, then store its
client credentials only in Supabase Edge Function secrets:

```bash
supabase secrets set SPOTIFY_CLIENT_ID="YOUR_SPOTIFY_CLIENT_ID"
supabase secrets set SPOTIFY_CLIENT_SECRET="YOUR_SPOTIFY_CLIENT_SECRET"
```

Apple Music is optional. To add the artist's official `top-songs` popularity order,
store a developer token only in Supabase Edge Function secrets:

```bash
supabase secrets set APPLE_MUSIC_DEVELOPER_TOKEN="YOUR_SIGNED_TOKEN"
supabase secrets set APPLE_MUSIC_STOREFRONT="br"
```

Spotify removed its public track/album popularity fields from Development Mode in 2026.
YePly therefore never fabricates a Spotify popularity score: Spotify provides catalogue
metadata, while rarity comes from artist-relative ListenBrainz, Apple Music, and YePly
signals. Tracks with no real signal always remain Common.

Never add Spotify credentials, the `.p8` private key, or an Apple developer token to the
iOS project. The Spotify client secret must stay in Supabase Edge Function secrets.
