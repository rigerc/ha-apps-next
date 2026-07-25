# Home Assistant App: RomM

RomM is a self-hosted ROM manager and player for organizing, enriching,
browsing, and playing a game collection.

This app packages the full RomM 5.0.0 image for Home Assistant, including
browser-based EmulatorJS and Ruffle playback. It uses the Home Assistant
MariaDB service, stores user-managed data below `/share/romm`, and persists its
internal Valkey data in the app's private data directory.

The web interface is available through the **Open Web UI** button on port
`8080`.
