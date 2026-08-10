# sync-card-catalog

Synchronizes the curated official Kanye West studio-album catalog from MusicBrainz,
adds global listen/listener counts from ListenBrainz, and imports the snapshot through
the admin-only `import_external_card_catalog` RPC.

Deploy after applying migrations `202608090008_external_card_catalog.sql` and
`202608090009_apple_music_admin_packs.sql`:

```bash
supabase functions deploy sync-card-catalog
```

No Spotify secret or Supabase service-role key is required. Supabase supplies
`SUPABASE_URL` and `SUPABASE_ANON_KEY`; the function forwards the signed-in admin JWT
to the security-definer import RPC.

Apple Music is optional. To add the artist's official `top-songs` popularity order,
store a developer token only in Supabase Edge Function secrets:

```bash
supabase secrets set APPLE_MUSIC_DEVELOPER_TOKEN="YOUR_SIGNED_TOKEN"
supabase secrets set APPLE_MUSIC_STOREFRONT="br"
```

Never add the `.p8` private key or developer token to the iOS project. Without these
secrets the function keeps working with MusicBrainz and ListenBrainz.
