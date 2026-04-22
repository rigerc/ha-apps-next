# Home Assistant App: RomM

RomM is a self-hosted ROM manager and player packaged for Home Assistant.

This app wraps upstream `rommapp/romm:v2.3.1`, discovers the Home Assistant
`mysql` service automatically, persists data under `/share/romm`, and exposes
the RomM web interface on port `8080`.
