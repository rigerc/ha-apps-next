# Comicarr Home Assistant App

## About

Comicarr manages comic and manga libraries in the style of Sonarr and Radarr.
It supports ComicVine and Metron metadata, NZB and torrent clients, direct
downloads, post-processing, story arcs, weekly pull lists, and an OPDS feed.

## Installation and first start

1. Install and start the Comicarr app.
2. Open the app log and copy the one-time setup token printed after
   `[SETUP] Setup token:`.
3. Choose **Open Web UI**, then create the first administrator with that token.
4. Configure a ComicVine API key, search providers, and at least one download
   client in Comicarr's Settings page.

The setup token is generated again on each start until an administrator has
been created. Do not share app logs while the token is active.

## Storage paths

The app creates these persistent paths:

- `/data/comicarr`: database, configuration, logs, secrets, cache, and backups.
  This is included in a cold Home Assistant app backup.
- `/media/comics`: default comic library.
- `/media/manga`: default manga library.
- `/share/comicarr/downloads`: default download and direct-download path.

`/media` and `/share` are mapped read-write because Comicarr imports, moves,
renames, and tags library files. They are not part of the app's own backup;
back them up separately. The initial configuration uses the paths above. You
can change them in Comicarr, but only locations below `/media` and `/share` are
available from the app.

When configuring a download client, use paths as seen inside that client's
container and configure its remote path mapping to
`/share/comicarr/downloads` when necessary.

## App options

### `timezone`

An IANA time zone such as `Etc/UTC`, `Europe/Amsterdam`, or
`America/New_York`. It controls Comicarr schedules and timestamps.

### `log_level`

- `warning`: warnings and errors only.
- `normal`: normal operational logging.
- `debug`: verbose diagnostics; use temporarily because it can produce large
  logs.

Comicarr Settings can also store a logging level, but the Home Assistant app
option takes precedence at each start.

## Networking

Comicarr listens on TCP port 8090. Change the host-side port in the app's
Network settings if 8090 is already in use. No Home Assistant or Supervisor
API access, host networking, hardware access, or elevated Supervisor role is
requested.

## Backups and upgrades

Stop the app or create a cold app backup before upgrading. Home Assistant backs
up `/data/comicarr`, including the SQLite database and encrypted credentials.
Back up `/media` and `/share` separately. The container image is replaceable;
all durable application state remains under `/data`.

## Support

- App packaging: <https://github.com/rigerc/ha-apps-next/issues>
- Comicarr documentation: <https://comicarr.com/docs>
- Upstream issues: <https://github.com/frankieramirez/comicarr/issues>

This app is an unofficial package. Reproduce packaging issues with the
upstream container before reporting them to Comicarr.
