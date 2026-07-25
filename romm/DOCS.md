# Home Assistant App: RomM

## About

RomM is a self-hosted ROM manager and player with library scanning, metadata
downloads, artwork management, browser-based play, and a responsive web UI.

This app runs the full RomM 5.0.0 image. It discovers the Home Assistant
MariaDB service automatically and keeps RomM files under `/share/romm` by
default.

## Before installation

Install, configure, and start the official Home Assistant **MariaDB** app.
RomM requires the `mysql` service it provides. The RomM app creates its own
database with the service credentials; no database password needs to be copied
into the RomM configuration.

## Installation

1. Install and start the Home Assistant MariaDB app.
2. Install RomM from this repository.
3. Review the RomM app configuration and start the app.
4. Select **Open Web UI**.
5. Complete RomM's setup wizard and scan the library.

The initial start can take longer while RomM creates its database and runs
migrations.

## Storage layout

The default `storage_path` is `/share/romm`. The app creates:

- `/share/romm/library` for ROMs and firmware.
- `/share/romm/assets` for saves, states, screenshots, and uploaded files.
- `/share/romm/resources` for downloaded artwork and metadata.
- `/share/romm/config/config.yml` for advanced RomM configuration.
- `/share/romm/sync` for RomM synchronization data.

The authentication secret and embedded Valkey data are stored privately under
`/data`. Valkey uses append-only persistence so sessions and queued work survive
ordinary app restarts.

See RomM's folder-structure documentation before populating `library`.

## Configuration

### `storage_path`

Writable directory below `/share` used as `ROMM_BASE_PATH`.

Default: `/share/romm`

### `database_name`

MariaDB database created and used by RomM. The name may contain letters,
numbers, and underscores.

Default: `romm`

### `base_url`

Optional public URL used by RomM when generating invite links, QR codes, OIDC
redirects, and other absolute links. Set it to the URL users actually use,
including HTTPS and a non-default port when applicable.

Example: `https://romm.example.com`

### `log_level`

RomM runtime log level: `DEBUG`, `INFO`, `WARNING`, `ERROR`, or `CRITICAL`.

Default: `INFO`

### Scan options

- `enable_rescan_on_filesystem_change` watches the library for changes.
- `enable_scheduled_rescan` enables cron-based rescans.
- `scheduled_rescan_cron` sets the rescan schedule.

The default schedule is `0 3 * * *`.

### Playback and display options

- `kiosk_mode` enables RomM's read-only kiosk mode.
- `disable_emulator_js` disables EmulatorJS browser playback.
- `disable_ruffle_rs` disables Ruffle browser playback.

### Metadata providers

`hasheous_api_enabled` is enabled by default. These optional credentials can
enable additional metadata providers:

- `igdb_client_id`
- `igdb_client_secret`
- `screenscraper_user`
- `screenscraper_password`
- `retroachievements_api_key`
- `steamgriddb_api_key`
- `mobygames_api_key`

Secrets are passed to RomM without being written to its logs.

## Networking

RomM listens on container port `8080`. Change the host-side port from the
Home Assistant app's Network section if `8080` is already occupied.

This app uses a direct web UI rather than Home Assistant ingress. RomM relies
on root-relative API and WebSocket routes and does not document deployment
under the dynamic URL prefix used by ingress.

## Backup and restore

Back up all three parts of the installation:

1. The RomM app data, which contains the authentication secret and Valkey data.
2. The `/share/romm` directory.
3. The MariaDB app data containing the RomM database.

The app uses cold backups so RomM is stopped while its private data is copied.
For a consistent full restore, keep the RomM app data, `/share/romm`, and the
MariaDB backup from the same Home Assistant backup.

Before upgrading RomM, create a full Home Assistant backup and review the
upstream RomM release notes.

## Troubleshooting

- **MariaDB service unavailable:** confirm the official MariaDB app is running
  and has completed startup.
- **Invalid storage path:** `storage_path` must be below `/share`.
- **Web UI does not open:** inspect the app log for migration errors, then check
  that the configured host port is available.
- **Generated links use the wrong address:** set `base_url` to the public URL.
