# Home Assistant App: RomM

## About

RomM is a self-hosted ROM manager and player with library scanning, metadata,
 artwork downloads, browser-based play support, and a responsive web UI.

This Home Assistant app packages upstream RomM for Home Assistant and stores
all persistent RomM data under `/share/romm` by default.

## Requirements

1. Install and start the Home Assistant `MariaDB` app first.
2. Make sure your ROM library is available under the Home Assistant `/share`
   directory, or adjust `storage_path` to another writable location inside
   `/share`.

The RomM app consumes the Home Assistant `mysql` service and creates its own
database automatically on first boot.

## Installation

1. Add this repository to Home Assistant.
2. Install the `RomM` app.
3. Review the options and start the app.
4. Open the web UI on port `8080` using the **OPEN WEB UI** button.
5. Complete the RomM first-run setup inside the RomM interface.

## Options

### `storage_path`

Base path for RomM data. The app creates these directories under the chosen
path:

- `library`
- `assets`
- `resources`
- `config`

Default: `/share/romm`

### `database_name`

MariaDB database name RomM should use. The database is created automatically if
it does not already exist.

Default: `romm`

### `log_level`

RomM runtime log level.

Default: `INFO`

### `kiosk_mode`

Starts RomM in read-only kiosk mode.

Default: `false`

### `enable_rescan_on_filesystem_change`

Starts RomM's filesystem watcher so library changes trigger rescan behavior.

Default: `false`

### `enable_scheduled_rescan`

Enables scheduled rescans using the cron expression below.

Default: `false`

### `scheduled_rescan_cron`

Cron expression for scheduled library rescans.

Default: `0 3 * * *`

### `disable_emulator_js`

Disables EmulatorJS browser play support.

Default: `false`

### `disable_ruffle_rs`

Disables Ruffle-based Flash playback.

Default: `false`

### Metadata provider secrets

These optional settings are passed through to RomM when present:

- `igdb_client_id`
- `igdb_client_secret`
- `screenscraper_user`
- `screenscraper_password`
- `retroachievements_api_key`
- `steamgriddb_api_key`
- `mobygames_api_key`

## Data Layout

RomM uses the configured `storage_path` as `ROMM_BASE_PATH`. That means:

- ROMs should live under `${storage_path}/library`
- Uploaded saves and states live under `${storage_path}/assets`
- Downloaded artwork and metadata resources live under `${storage_path}/resources`
- RomM `config.yml` lives at `${storage_path}/config/config.yml`

## Notes

- This app uses a direct `webui` on port `8080`; it does not yet use Home
  Assistant ingress.
- The app relies on Home Assistant's `mysql` service rather than bundling its
  own database.
