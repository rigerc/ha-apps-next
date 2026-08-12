# Home Assistant Apps

This repository contains Home Assistant apps distributed as signed,
multi-architecture container images.

## Included apps

### RomM

RomM is a self-hosted ROM manager and player. The app packages stable RomM
5.0.0 with:

- Browser-based EmulatorJS and Ruffle playback.
- Automatic Home Assistant MariaDB service discovery.
- Persistent library and application data below `/share/romm`.
- Signed `amd64` and `aarch64` images published to GHCR.

Install and start the official Home Assistant MariaDB app before starting
RomM.

### Endurain

Endurain is a self-hosted fitness and activity tracker. The app packages stable
Endurain 0.19.0 with:

- Activity imports, maps, statistics, goals, Garmin, and Strava support.
- Private embedded PostgreSQL 18 and Valkey services.
- All application and database state in one cold-backed-up app data directory.
- Signed `amd64` and `aarch64` images published to GHCR.

No separate database app is required. This is an unofficial package and is not
sponsored or endorsed by the Endurain project.

### Reclaimerr

Reclaimerr is a media-library reclaim and cleanup service. The app packages
stable Reclaimerr 0.3.5 with:

- Plex, Jellyfin, and Emby scanning with Radarr and Sonarr routing.
- Candidate protection, approval, history, and scheduled task workflows.
- Persistent SQLite state and generated secrets under `/data/reclaimerr`.
- Read-write `/media` access for configured path mappings and cleanup actions.
- Signed `amd64` and `aarch64` images published to GHCR.

Automatic deletion is opt-in. This is an unofficial package and is not
sponsored or endorsed by the Reclaimerr project.

## Installation

1. In Home Assistant, open **Settings** > **Apps** > **App Store**.
2. Open the repository menu and add:
   `https://github.com/rigerc/ha-apps-next`
3. Select the app to install.
4. For RomM only, install and start the official MariaDB app first.
5. For Reclaimerr, review `/media` path mappings and external-service options
   before starting it.
6. Start the selected app and choose **Open Web UI**.

See each app's documentation for storage, configuration, networking, backup,
and upgrade details.
