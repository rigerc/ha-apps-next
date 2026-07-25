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

## Installation

1. In Home Assistant, open **Settings** > **Apps** > **App Store**.
2. Open the repository menu and add:
   `https://github.com/rigerc/ha-apps-next`
3. Install the official MariaDB app and wait for it to start.
4. Install RomM from this repository.
5. Start RomM and select **Open Web UI**.

See the RomM app documentation for storage, configuration, networking, and
backup details.
