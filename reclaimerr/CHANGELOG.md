# Changelog

## [0.3.5-1] - 2026-08-11

### Added

- Initial unofficial Home Assistant App package for upstream Reclaimerr 0.3.5.
- Direct Web UI access on port `8000` with watchdog health monitoring.
- Persistent SQLite state, generated secrets, logs, and avatars under
  `/data/reclaimerr`.
- Validated Home Assistant options for timezone, logging, workers, CORS,
  trusted proxies, secure cookies, and transient admin-password recovery.
- Read-write `/media` mapping for configured library path mappings and cleanup.
- Read-write `/share` mapping for libraries and files stored on the share tree.
- Custom AppArmor confinement and multi-architecture packaging for `amd64` and
  `aarch64`.
- A source-visible patch correcting the upstream `/api/info/version` response.
- A confinement-aware test process that loads the shipped AppArmor profile and
  runs the full smoke suite under enforcement, matching Endurain's approach.

### Notes

- Home Assistant ingress is intentionally not enabled; use the direct port or
  an HTTPS reverse proxy as described in `DOCS.md`.
- Automatic move and delete operations remain upstream application features;
  review and back up media before enabling them.
- The AppArmor audit filter recognizes non-blocking probes: Bash/`run.sh`
  opening `/dev/tty`, granian probing the `/proc` root, its executable
  directory, and the cgroup CPU cap, and `python3` removing unused `urllib3`
  sources during startup. Those paths remain denied; the application continues
  to run correctly.
