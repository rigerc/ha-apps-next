---
id: TASK-3
title: Add Comicarr Home Assistant app
status: Done
assignee:
  - '@codex'
created_date: '2026-08-13 15:28'
updated_date: '2026-08-13 15:54'
labels: []
dependencies: []
references:
  - 'https://github.com/frankieramirez/comicarr'
modified_files:
  - docs/context/comicarr
  - comicarr
  - .github/workflows/publish-comicarr.yaml
  - README.md
type: feature
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Vendor the upstream Comicarr project under docs/context and add a self-contained Home Assistant App package that runs Comicarr with persistent data and documented configuration.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The upstream Comicarr repository is copied into docs/context/comicarr with provenance retained
- [x] #2 A comicarr app folder contains valid Home Assistant metadata, container build files, startup logic, and least-privilege runtime configuration
- [x] #3 Comicarr configuration and generated data survive app restarts through /data
- [x] #4 README, DOCS, CHANGELOG, translations, branding assets, and license attribution are included
- [x] #5 Automated smoke checks pass and the container build is validated when local tooling supports it
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Copy the tagged Comicarr v0.31.0 source snapshot into docs/context/comicarr and record its origin/commit.
2. Add a comicarr Home Assistant App based on the pinned upstream multi-architecture image, with a validating startup wrapper, persistent /data state, explicit /media and /share mappings, web UI metadata, and AppArmor.
3. Add store/docs assets, repository-level discovery text, and license attribution.
4. Add static and container smoke tests covering defaults, invalid options, startup/health, persistence, and clean shutdown.
5. Run format/schema/static checks, Docker build, and smoke tests; then finalize TASK-3 with evidence.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Vendored Comicarr v0.31.0 at commit 743b610bf118ae59aac38db000de51c2b0f022c5 into docs/context/comicarr with its git origin and clean worktree intact. Added the HA App package, docs/assets, AppArmor policy, tests, and release workflow. Docker build succeeded. Initial smoke testing exposed Comicarr 0.31.0's broken minimal-INI bootstrap; changed the seeded configuration to full serialization while retaining HA paths, after which startup, health, persistence, restart, shutdown, and invalid-option checks passed.

Final validation: shellcheck and bash syntax checks passed; YAML and JSON parsed; git diff whitespace check passed; AppArmor policy preprocessed with apparmor_parser in Ubuntu 24.04; local amd64 image built from the pinned upstream multi-arch digest; smoke suite verified the React UI, health API, HA storage paths, SQLite/config creation, full options, clean shutdown, /data persistence after restart, and invalid-option rejection.

HA runtime follow-up: startup failed at run.sh:93 because the custom AppArmor profile allowed install and Python but omitted the resolved /usr/bin/mkdir executable. Added the narrow rix rule and a CI assertion for that exact runtime dependency. Verified command resolution in the packaged image, shell/static checks, and AppArmor preprocessing.

Because PR #2 merged and published 0.31.0-1 before the AppArmor correction, bumped the repaired Home Assistant app release to 0.31.0-2 so Supervisor detects and installs the fixed image.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Copied the clean Comicarr v0.31.0 source repository into docs/context and added a documented, branded, AppArmor-confined Home Assistant App with persistent /data state, /media and /share access, a pinned multi-architecture base image, and a signed GHCR publishing workflow. Verified with static format/config checks, AppArmor preprocessing, a successful Docker build, and repeated end-to-end smoke tests covering UI/health, restart persistence, clean shutdown, and invalid configuration.

Follow-up fix: permit /usr/bin/mkdir under AppArmor so Home Assistant can create the persistent Comicarr directories during startup.
<!-- SECTION:FINAL_SUMMARY:END -->
