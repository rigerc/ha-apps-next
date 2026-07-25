# Changelog

## 5.0.0-2

- Allow the upstream Nginx entrypoint hooks to execute under the app's
  AppArmor profile, restoring access to the RomM web interface.

## 5.0.0-1

- Rebuild the Home Assistant app around stable RomM 5.0.0.
- Correct Home Assistant MariaDB service-response handling.
- Persist the embedded Valkey store in the app data directory.
- Preserve RomM libraries and assets below `/share/romm`.
- Add an optional public base URL and Hasheous configuration.
- Add a health watchdog, cold backups, and a tightened AppArmor profile.
- Publish signed `amd64` and `aarch64` images with the current Home Assistant
  builder actions.
