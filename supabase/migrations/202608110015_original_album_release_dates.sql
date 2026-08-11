begin;

-- Spotify sometimes reports the date of a later digital re-upload. Preserve the
-- original project chronology for the curated Kanye West catalogue.
update public.collectible_albums
set release_date = case spotify_album_id
  when '3ff2p3LnR6V7m6BinwhNaQ' then date '2004-02-10'
  when '4GRDFQ9HRoO0by8H0r2a3I' then date '2005-08-30'
  when '6V0srAdQfEIarFvIxAYilH' then date '2007-09-11'
  when '3WFTGIO6E3Xh4paEOBY9OU' then date '2008-11-24'
  when '20r762YmB5HeofjMCiPMLv' then date '2010-11-22'
  when '4P63UgNDUcF11MnWzyvVrh' then date '2011-08-08'
  when '0A3g19AGFd9Qe3rAIkP8e0' then date '2012-09-14'
  when '7D2NdGvBHIavgLhmcwhluK' then date '2013-06-18'
  when '7gsWAHLeT0w7es6FofOXk1' then date '2016-02-14'
  when '2Ek1q2haOnxVqhvVKqMvJe' then date '2018-06-01'
  when '1oK1GzEMNDjCt7EYYpomwc' then date '2018-06-08'
  when '0FgZKfoU2Br5sHOfvZKTI9' then date '2019-10-25'
  when '5CnpZV3q5BcESefcB3WJmz' then date '2021-08-29'
  when '0k7oanYS9dXYWLXaFOYxJ8' then date '2022-02-23'
  when '0k7ALIqqds5oGFtpMsaHLK' then date '2024-02-10'
  when '5RV2TNyjylqWJNxQyHBTeJ' then date '2024-08-03'
  when '3hwveWhYFxGDLy6K6xlwFh' then date '2026-06-19'
  else release_date
end,
updated_at = now()
where spotify_album_id in (
  '3ff2p3LnR6V7m6BinwhNaQ', '4GRDFQ9HRoO0by8H0r2a3I',
  '6V0srAdQfEIarFvIxAYilH', '3WFTGIO6E3Xh4paEOBY9OU',
  '20r762YmB5HeofjMCiPMLv', '4P63UgNDUcF11MnWzyvVrh',
  '0A3g19AGFd9Qe3rAIkP8e0', '7D2NdGvBHIavgLhmcwhluK',
  '7gsWAHLeT0w7es6FofOXk1', '2Ek1q2haOnxVqhvVKqMvJe',
  '1oK1GzEMNDjCt7EYYpomwc', '0FgZKfoU2Br5sHOfvZKTI9',
  '5CnpZV3q5BcESefcB3WJmz', '0k7oanYS9dXYWLXaFOYxJ8',
  '0k7ALIqqds5oGFtpMsaHLK', '5RV2TNyjylqWJNxQyHBTeJ',
  '3hwveWhYFxGDLy6K6xlwFh'
);

commit;
