# Changelog

## 0.19.0-1

- Package stable Endurain 0.19.0 from its digest-pinned upstream image.
- Embed PostgreSQL 18 and persistent Valkey storage in the app container.
- Persist Endurain data, logs, database files, and generated secrets below `/data`.
- Add LAN HTTP and reverse-proxy HTTPS configuration with strict validation.
- Add coordinated service supervision, cold-backup shutdown, watchdog, AppArmor, smoke tests, and signed `amd64`/`aarch64` publishing.
