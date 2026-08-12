---
id: TASK-2
title: Add Reclaimerr Home Assistant app
status: In Progress
assignee:
  - '@bond'
created_date: '2026-08-11 16:18'
updated_date: '2026-08-11 17:03'
labels: []
dependencies: []
references:
  - 'https://github.com/jessielw/Reclaimerr'
  - docs/context/Reclaimerr
documentation:
  - docs/context/developers.home-assistant/docs/apps
modified_files:
  - README.md
  - .github/workflows/publish-reclaimerr.yaml
  - reclaimerr/config.yaml
  - reclaimerr/Dockerfile
  - reclaimerr/run.sh
  - reclaimerr/apparmor.txt
  - reclaimerr/README.md
  - reclaimerr/DOCS.md
  - reclaimerr/CHANGELOG.md
  - reclaimerr/LICENSE.md
  - reclaimerr/icon.png
  - reclaimerr/logo.png
  - reclaimerr/translations/en.yaml
  - reclaimerr/patches/0001-fix-version-endpoint.patch
  - reclaimerr/tests/options-default.json
  - reclaimerr/tests/options-full.json
  - reclaimerr/tests/smoke.sh
  - reclaimerr/tests/local-apparmor.sh
priority: high
type: feature
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Package the current stable Reclaimerr release as an unofficial Home Assistant App. Extend the digest-pinned upstream multi-architecture image with a small Home Assistant runtime wrapper, persistent local state, direct Web UI access, constrained media access, documentation, smoke tests, and signed GHCR publishing. The research snapshot is cloned at docs/context/Reclaimerr from upstream commit 0b0ca4f; the initial wrapper targets upstream 0.3.5.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Reclaimerr app installs and starts on Home Assistant amd64 and aarch64 using a digest-pinned upstream 0.3.5 image and a repository-owned 0.3.5-1 multi-architecture image.
- [x] #2 Fresh start, first-run setup, health monitoring, clean shutdown, restart, cold backup, restore, and upgrade preserve the SQLite database, generated encryption/session secrets, settings, users, and scheduled jobs.
- [ ] #3 Only required Home Assistant access is granted: direct port 8000, read-write media mapping, protected mode, and a custom enforced AppArmor profile; no host networking, Supervisor APIs, privileged mode, or share mapping is used.
- [x] #4 Home Assistant options are validated and safely mapped to supported Reclaimerr environment variables, transient admin-password reset is documented, and secrets or full option payloads never appear in logs.
- [x] #5 Automated tests cover option rejection, watchdog health/version, persistence, signal handling, unavailable external services, media path mapping, and safe fixture-based move and deletion behavior.
- [x] #6 README, DOCS, changelog, translation, icon/logo, GPLv3 attribution, backup/rollback guidance, destructive-operation warnings, direct-LAN and reverse-proxy guidance, and unofficial-package support boundaries are present.
- [ ] #7 CI validates metadata and scripts, runs the amd64 smoke and enforced-AppArmor suites, builds native amd64 and aarch64 images, and publishes a signed generic GHCR manifest whose tag and labels match config.yaml.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Baseline and pinning: target Reclaimerr 0.3.5, pin ghcr.io/jessielw/reclaimerr by OCI index digest, record upstream source/tag/version locations and GPLv3 obligations, and use wrapper version 0.3.5-1.
2. Scaffold reclaimerr/: add config.yaml, digest-pinned Dockerfile, run.sh, custom apparmor.txt, README.md, DOCS.md, CHANGELOG.md, LICENSE.md, translations/en.yaml, upstream-derived icon/logo, and test fixtures. Configure amd64/aarch64, stage experimental, init false, startup application, cold backup, port/webui/watchdog on 8000, and repository image ghcr.io/rigerc/ha-addon-reclaimerr.
3. Runtime wrapper: read and type-check /data/options.json; set fixed DATA_DIR=/data/reclaimerr, STATIC_DIR and AVATARS_DIR beneath it, FRONTEND_DIST=/app/frontend/dist, API_HOST=0.0.0.0, API_PORT=8000, and preserve the upstream single Granian worker. Initialize ownership, prefer dropping to a fixed unprivileged runtime through the upstream entrypoint, and verify mounted-media permissions before accepting any root-runtime exception.
4. Options and secrets: initially expose timezone, log_level, log_retention_days, command_workers, cors_origins, proxy_trusted_hosts, cookie_secure, and optional transient admin_password. Reject wildcard proxy trust and malformed origins; never expose JWT_SECRET or ENCRYPTION_KEY, allowing Reclaimerr to generate and persist them. Defer forward-auth and task-isolation tuning.
5. Storage and access: persist all Reclaimerr state and generated secrets below /data/reclaimerr; map only Home Assistant media read-write for path mappings, direct cleanup, and moves; omit share, Home Assistant/Supervisor APIs, host networking, and privileged access. Build an AppArmor profile limited to packaged runtime files, outbound networking, required process/signal operations, /data/reclaimerr, and /media.
6. UI and networking: ship direct Open Web UI access on port 8000 and document trusted-LAN HTTP plus explicit HTTPS reverse-proxy settings. Do not enable ingress because the current frontend, static assets, auth cookies, and callbacks use root-relative paths and X-Frame-Options DENY; track ingress/base-path support as a separate upstream-compatible follow-up.
7. Verification: add shell/static metadata checks plus Docker smoke tests for fresh setup, health/version, persistence, generated-secret stability, clean TERM, invalid options, unavailable integrations, changed host port, and safe media move/delete fixtures. Parse and enforce the AppArmor profile, then test install, backup/restore, upgrade, path mappings, and Open Web UI in the HA devcontainer or a real supervised system.
8. Publishing and release: add publish-reclaimerr.yaml following the current Endurain matrix: validate, amd64 smoke, native amd64/aarch64 builds, generic signed multi-arch manifest, and strict version/tag/label consistency. Keep stage experimental until both architectures and real Home Assistant lifecycle checks pass.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implementation started with three Luna agents assigned to non-overlapping runtime, security/CI/testing, and documentation/assets workstreams. Main agent retains integration and final verification.

Integrated all three Luna workstreams and resolved cross-review findings. The wrapper preserves the upstream entrypoint while deferring TZ to avoid AppArmor-blocked /etc writes; JSON options use the pinned Python runtime, avoiding a mutable apt/jq layer. Root runtime is an explicit, documented exception for mixed-owner Home Assistant media trees and is constrained by protected mode plus an AppArmor profile granting only dac_override and scoped writes. CI pins the metadata helper commit and explicitly enables Cosign for native images and the generic manifest.

Local verification passed: ShellCheck and bash -n; YAML/JSON parsing; git diff --check; Docker build --check and amd64 build; image label/base-digest inspection; full smoke covering fresh setup, watchdog health/version, direct host port, safe media move/delete fixtures, cold backup/restore, restart, unavailable Radarr, invalid options, secret redaction, clean TERM, transient admin bootstrap, and a digest-pinned Reclaimerr 0.3.4 to packaged 0.3.5 migration preserving users, general settings, schedules, database integrity, and generated secrets. AppArmor preprocessing passed in Ubuntu 24.04. GPL license hash, asset dimensions, docs links, and clean upstream clone were verified.

Release gates still requiring external evidence: this host cannot execute native aarch64 containers and its kernel has AppArmor disabled, so AC1/AC3/AC7 remain unchecked until GitHub Actions completes native amd64/aarch64 signed publication plus enforced-AppArmor smoke, followed by a Home Assistant supervised install/Open Web UI/backup-restore check. Task intentionally remains In Progress; no commit, push, or publish was performed.
<!-- SECTION:NOTES:END -->
