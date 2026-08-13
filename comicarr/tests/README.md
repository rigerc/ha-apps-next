# Comicarr app tests

Build and run the Docker smoke suite:

```bash
docker build \
  --build-arg BUILD_ARCH=amd64 \
  --build-arg BUILD_VERSION=0.31.0-3 \
  --tag local/ha-addon-comicarr:0.31.0-3 \
  comicarr
comicarr/tests/smoke.sh local/ha-addon-comicarr:0.31.0-3
```

The suite checks legacy-option upgrades, startup and health, HA-managed
`config.ini` values, custom directories, preservation of unowned settings and
encrypted secrets, persistent state across restarts, clean shutdown, and
invalid option rejection.
