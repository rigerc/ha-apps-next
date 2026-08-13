# Comicarr

Comicarr is an automated comic book and manga manager with a modern web UI.
It monitors series, searches configured indexers, hands releases to download
clients, imports completed downloads, and manages metadata.

This Home Assistant App packages Comicarr 0.31.0 for `amd64` and `aarch64`.
Application state is stored in the app backup, while comic libraries and
downloads use user-configurable paths below Home Assistant's `/media` and
`/share` mounts. The app configuration also exposes selected `config.ini`-only
library, scheduler, torrent-client, and OPDS settings.

This is an unofficial package and is not sponsored or endorsed by the
Comicarr project.

See [DOCS.md](DOCS.md) for installation, storage paths, first-run setup, and
upgrade guidance.
