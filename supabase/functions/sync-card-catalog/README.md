# sync-card-catalog

Synchronizes the curated official Kanye West studio-album catalog from MusicBrainz,
adds global listen/listener counts from ListenBrainz, and imports the snapshot through
the admin-only `import_external_card_catalog` RPC.

Deploy after applying migration `202608090008_external_card_catalog.sql`:

```bash
supabase functions deploy sync-card-catalog
```

No Spotify secret or Supabase service-role key is required. Supabase supplies
`SUPABASE_URL` and `SUPABASE_ANON_KEY`; the function forwards the signed-in admin JWT
to the security-definer import RPC.
