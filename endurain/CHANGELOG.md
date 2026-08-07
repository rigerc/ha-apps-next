# Changelog

## 0.19.0-3

- Allow AppArmor to execute Alpine's resolved PostgreSQL 18 programs below
  `/usr/libexec`, restoring database initialization and management.
- Add a confinement-aware local test process that loads the shipped AppArmor
  profile, runs the complete smoke suite under enforcement, and reports kernel
  denials.
- No configuration or data migration is required for this update.

## 0.19.0-2

- Allow AppArmor to create the Endurain, PostgreSQL, and secrets runtime
  directories below `/run`, restoring startup on Home Assistant.
- No configuration or data migration is required for this update.

## 0.19.0-1

- Package stable Endurain 0.19.0 from its digest-pinned upstream image.
- Embed PostgreSQL 18 and persistent Valkey storage in the app container.
- Persist Endurain data, logs, database files, and generated secrets below `/data`.
- Add LAN HTTP and reverse-proxy HTTPS configuration with strict validation.
- Add coordinated service supervision, cold-backup shutdown, watchdog, AppArmor, smoke tests, and signed `amd64`/`aarch64` publishing.
