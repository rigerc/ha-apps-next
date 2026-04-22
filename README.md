# Home Assistant Apps

This repository contains Home Assistant apps packaged for local install or
distribution through a custom app repository.

## Included Apps

- `RomM`: A Home Assistant-packaged wrapper around upstream RomM with
  persistent storage under `/share/romm`, direct web access on port `8080`,
  and MariaDB service discovery through Home Assistant.

## Install

1. In Home Assistant, go to **Settings** -> **Apps** -> **App Store**.
2. Open the repository menu and add this Git repository URL.
3. Install the `RomM` app from the repository.
4. Install and start the Home Assistant `MariaDB` app before starting `RomM`.

## Notes

- The `RomM` app is currently exposed through its own `webui` rather than
  Home Assistant ingress.
- Image publishing is configured for `ghcr.io/rigerc/ha-addon-romm`.
