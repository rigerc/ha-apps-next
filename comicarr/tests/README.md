# Comicarr app tests

Build and run the Docker smoke suite:

```bash
docker build \
  --build-arg BUILD_ARCH=amd64 \
  --build-arg BUILD_VERSION=0.31.0-1 \
  --tag local/ha-addon-comicarr:0.31.0-1 \
  comicarr
comicarr/tests/smoke.sh local/ha-addon-comicarr:0.31.0-1
```

The suite checks startup and health, seeded Home Assistant storage paths,
persistent state across a restart, clean shutdown, and invalid option rejection.
