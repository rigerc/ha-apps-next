---
id: TASK-4
title: Expose Comicarr config.ini settings in Home Assistant
status: Done
assignee:
  - '@codex'
created_date: '2026-08-13 17:42'
updated_date: '2026-08-13 17:52'
labels: []
dependencies: []
references:
  - 'https://comicarr.com/docs/configuration'
  - 'https://comicarr.com/docs/configuration/torrent-clients'
  - 'https://comicarr.com/docs/configuration/general'
modified_files:
  - .github/workflows/publish-comicarr.yaml
  - comicarr/CHANGELOG.md
  - comicarr/DOCS.md
  - comicarr/Dockerfile
  - comicarr/README.md
  - comicarr/apparmor.txt
  - comicarr/config.yaml
  - comicarr/config_sync.py
  - comicarr/run.sh
  - comicarr/tests/README.md
  - comicarr/tests/options-default.json
  - comicarr/tests/options-full.json
  - comicarr/tests/options-legacy.json
  - comicarr/tests/smoke.sh
  - comicarr/translations/en.yaml
type: feature
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Allow users to manage Comicarr library/download directories and selected advanced config.ini-only settings from the Home Assistant App configuration screen, including torrent client configuration, without overwriting unrelated Comicarr settings or stored credentials.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Home Assistant options expose validated comic, manga, and download directories restricted to writable app mounts
- [x] #2 Home Assistant options expose documented library, scheduling, torrent, qBittorrent, Transmission, and OPDS settings with translations and usage documentation
- [x] #3 Startup synchronizes only HA-managed config.ini keys on every run while preserving all unexposed settings and omitted secrets
- [x] #4 Existing installations upgrade safely and option changes persist in the generated Comicarr configuration
- [x] #5 Automated tests cover defaults, customized settings, secret preservation, invalid paths, restart persistence, and container health
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Define nested HA options from Comicarr's documented config.ini keys, keeping passwords optional and paths constrained to /media or /share.
2. Replace first-run-only path seeding with an atomic config.ini synchronizer that preserves unrelated settings and omitted secrets.
3. Expand translations and DOCS with ownership, path, torrent-client, OPDS, and override behavior.
4. Bump the app release and extend smoke/static checks for upgrades, custom options, secrets, invalid paths, and runtime health.
5. Build and run the complete smoke suite, finalize TASK-4, and prepare the focused changes for review.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented an atomic startup synchronizer instead of first-run-only seeding. HA owns only exposed keys; blank or omitted passwords preserve Comicarr-encrypted values, and other config.ini keys/sections remain untouched. Writable paths are normalized and restricted below /media or /share.

Validation: built local/ha-addon-comicarr:0.31.0-3; full Docker smoke suite passed legacy migration, defaults, all customized groups, encrypted-secret preservation, unrelated-setting preservation, restart persistence, invalid timezone/path rejection, directory creation, UI/API health, and clean shutdown. shellcheck, bash -n, Python compilation, YAML/JSON parsing, git diff --check, and AppArmor preprocessing also passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Exposed Comicarr directories plus library, scheduler, torrent, qBittorrent, Transmission, and OPDS settings in Home Assistant. Startup now atomically synchronizes the managed config.ini keys while preserving unrelated settings and omitted encrypted passwords. Verified with the full 0.31.0-3 container smoke suite and static/AppArmor checks.
<!-- SECTION:FINAL_SUMMARY:END -->
