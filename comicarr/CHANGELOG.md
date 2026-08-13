# Changelog

## 0.31.0-2

- Allow `/usr/bin/mkdir` under AppArmor so the app can create its persistent
  storage directories during Home Assistant startup.

## 0.31.0-1

- Package Comicarr 0.31.0 for Home Assistant on `amd64` and `aarch64`.
- Persist Comicarr state below `/data/comicarr`.
- Seed Home Assistant-friendly comic, manga, and download paths.
- Add app options for time zone and logging verbosity.
- Add a custom AppArmor profile and multi-architecture publishing workflow.
- Allow the startup script to create persistent storage directories under
  AppArmor enforcement.
