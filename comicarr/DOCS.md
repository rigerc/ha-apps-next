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

The default persistent paths are:

- `/data/comicarr`: database, configuration, logs, secrets, cache, and backups.
  This is included in a cold Home Assistant app backup.
- `/media/comics`: default comic library.
- `/media/manga`: default manga library.
- `/share/comicarr/downloads`: default download and direct-download path.

`/media` and `/share` are mapped read-write because Comicarr imports, moves,
renames, and tags library files. They are not part of the app's own backup;
back them up separately. Change these paths in the Home Assistant app
configuration. Every configured path must be a child of `/media` or `/share`;
other host paths are not mounted into the app.

When configuring a download client, use paths as seen inside that client's
container and configure its remote path mapping to
`/share/comicarr/downloads` when necessary.

## Configuration ownership

At each start, the app synchronizes the settings documented below into
`/data/comicarr/config.ini`. These values therefore appear read-only in the
Comicarr UI and must be changed in the Home Assistant app configuration.
Comicarr continues to own every setting that is not exposed here.

Existing `config.ini` sections, search providers, metadata keys, notifications,
and other unexposed values are preserved. Optional passwords are written only
when a non-empty value is supplied. Leave a password empty to preserve the
encrypted value already stored by Comicarr. To clear a stored credential, use
Comicarr or edit `config.ini` while the app is stopped.

Restart the app after changing Home Assistant options.

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

### Storage directories

- `comics`: organized comic library (`DESTINATION_DIR`).
- `manga`: organized manga library (`MANGA_DESTINATION_DIR`).
- `downloads`: shared SABnzbd and direct-download directory.
- `torrent_watch`: output directory for torrent watchfolder mode.

All four values must be absolute child paths below `/media` or `/share`. The
app creates missing directories at startup.

### Library and files

Configure automatic series-folder creation, imported-file renaming, the file
operation (`move`, `copy`, `hardlink`, or `softlink`), Comicarr folder/file
templates, startup backups, and backup retention. Hard links require source and
destination paths on the same filesystem.

### Scheduler

The RSS, full-search, and download-scan values are intervals in minutes. Avoid
aggressive RSS or search intervals because providers can enforce rate limits.

### Torrent downloads

Enable torrent acquisition and torrent searching separately, set a minimum
seeder count, and choose one active client:

- `watchfolder`
- `utorrent`
- `rtorrent`
- `transmission`
- `deluge`
- `qbittorrent`

The app currently provides connection fields for qBittorrent and Transmission.
The selected client and all exposed connection values are synchronized to
`config.ini`. Configure Torznab search providers in Comicarr or directly in
`config.ini`; provider rows may contain encrypted credentials and remain under
Comicarr's ownership.

For qBittorrent, enter the full Web UI URL, optional credentials, an existing
category, a download path visible to both containers, and the desired load
action. For Transmission, enter its full RPC URL, optional credentials, and a
shared download path. Container paths must match the paths exposed to the
download client; use remote path mappings where necessary.

### OPDS catalog

Enable the OPDS feed, optionally require HTTP Basic authentication, select its
endpoint, page size, and extended-metadata behavior. With the default endpoint,
the catalog is available at `http://HOST:8090/opds`. Use HTTPS when OPDS is
reachable outside a trusted network because Basic authentication does not
encrypt credentials by itself.

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
