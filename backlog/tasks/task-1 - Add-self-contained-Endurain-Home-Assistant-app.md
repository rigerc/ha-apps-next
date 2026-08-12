---
id: TASK-1
title: Add self-contained Endurain Home Assistant app
status: In Progress
assignee:
  - '@bond'
created_date: '2026-08-06 16:17'
updated_date: '2026-08-07 04:27'
labels: []
dependencies: []
references:
  - docs/plans/endurain-home-assistant-app.md
priority: high
type: feature
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the approved design in docs/plans/endurain-home-assistant-app.md: package Endurain v0.19.0 with embedded PostgreSQL 18 and Valkey, persistent /data state, least-privilege runtime, documentation, smoke tests, and signed multi-architecture publishing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Endurain app metadata, image, runtime supervisor, embedded PostgreSQL 18, and Valkey are implemented for amd64 and aarch64
- [x] #2 Options are validated and safely mapped to Endurain without logging secrets
- [x] #3 Persistent state, clean shutdown, restart, and child-failure behavior are covered by automated smoke tests
- [x] #4 AppArmor, translations, documentation, licensing attribution, artwork, and root repository documentation are present
- [ ] #5 CI validates and smoke-tests the app and publishes signed multi-architecture images on master
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add Endurain app metadata, a digest-pinned Dockerfile, Valkey config, and a PID 1 Bash wrapper that validates options, generates persistent secrets, initializes PostgreSQL 18, starts all services as unprivileged users, and coordinates readiness/failure/shutdown.
2. Maintain the option fixtures and Docker smoke suite covering fresh boot, persistence, validation failures, child failure, secret safety, and clean termination.
3. Add AppArmor, translations, user/store documentation, AGPL attribution, trademark notices, and correctly sized upstream artwork.
4. Keep the Endurain CI/publish workflow and repository metadata aligned with the chosen release process.
5. Add a confinement-aware local test driver that requires an AppArmor-enabled Docker host, loads an isolated copy of the shipped profile, applies it to every smoke-test container, confirms enforcement, reports kernel denials, and cleans up safely.
6. Fix the confined runtime paths discovered by the new process, including the resolved PostgreSQL 18 executables, and release the correction as 0.19.0-3.
7. Run static checks, ordinary Docker smoke tests, AppArmor profile parsing, and the confinement-aware suite on a capable host; record any residual real-device or multi-architecture gates.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented the Endurain app scaffold, digest-pinned image, PostgreSQL 18/Valkey PID 1 runtime, strict option mapping, generated secrets, cold-shutdown behavior, AppArmor, documentation, artwork, fixtures, smoke tests, and multi-architecture publish workflow. Local amd64 image build and complete Docker smoke suite pass. A local arm64 build reached the foreign-architecture RUN step but could not execute because this Docker host has no arm64 binfmt/QEMU; the GitHub builder matrix covers native aarch64 validation. Independent subagent review was attempted, but all three reviewer children stalled without producing transcripts and the workflow timed out.

Validation evidence: `bash -n` and `shellcheck` pass for both scripts; both JSON fixtures parse with jq; YAML files parse with yq; the amd64 Docker image builds with labels `amd64 0.19.0-1`; `endurain/tests/smoke.sh ha-addon-endurain:test` passes fresh initialization, PostgreSQL/Valkey readiness, persistent restart, full options, rejection cases, all three child failures, clean stop, and secret-log scanning. Artwork is exactly 128x128 and 250x100. `shazam_verify --preCommit` is blocked only by 11 pre-existing missing-import/type diagnostics in ignored `docs/context/Yamtrack`, unrelated to this app. Home Assistant/AppArmor runtime, native aarch64, and publish/sign checks remain for CI or supervised-device verification.

Pushed implementation commit af70142 to origin/master. CI and native aarch64 publication remain pending.

Home Assistant startup follow-up: diagnosed `install: can't create directory /run/endurain: Permission denied` as an AppArmor path-rule gap. The profile allowed descendants (`/run/endurain/**`, `/run/postgresql/**`, `/run/secrets/**`) but not creation of the runtime directories themselves. Added exact directory rules, bumped the app release and Docker label default to 0.19.0-2, and documented the fix. Validation: AppArmor profile parses successfully with Ubuntu 24.04 `apparmor_parser`; config YAML, version/changelog consistency, ShellCheck, Bash syntax, JSON fixtures, and `git diff --check` pass.

AppArmor validation follow-up for 0.19.0-3: added `endurain/tests/local-apparmor.sh`, which refuses AppArmor-disabled Docker hosts, builds the current image, loads an isolated enforced copy of the shipped profile, applies it to every full-smoke container, verifies `/proc/1/attr/current`, reports kernel audits, rejects unexpected denials, and cleans up the profile/data/containers. Extended `smoke.sh` with profile injection, enforced-profile verification, deterministic wrapper readiness, and actionable child-failure diagnostics. Fixed Alpine PostgreSQL executable rules for resolved `/usr/libexec/postgresql18/*` paths, disabled Python bytecode writes, and allowed only explicit read-only capability probes. Release metadata is 0.19.0-3. Objective evidence: local amd64 build and ordinary full smoke pass; GitHub Actions run 31147068213 passed static validation, native amd64/aarch64 builds, and the complete enforced AppArmor suite in 2m3s. The temporary workflow test job was removed afterward, retaining the requested smoke-test-free publish workflow.

Published the 0.19.0-3 correction directly to master at 87cd13c. Master workflow run 31147351290 passed validation, amd64 and aarch64 builds, and multi-architecture manifest publication. Verified `ghcr.io/rigerc/ha-addon-endurain:0.19.0-3` resolves to linux/amd64 and linux/arm64 manifests (index digest `sha256:daf0fcbbbc08699809e5ea122bc949ddf41247dafbcc7ea342d4414da9a4ad30`). The broader task remains In Progress because real Home Assistant device confirmation and the deliberately removed permanent CI smoke job are not represented by completed acceptance criteria.
<!-- SECTION:NOTES:END -->
