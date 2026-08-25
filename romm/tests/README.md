# RomM app tests

Build and run the Docker smoke and database-upgrade suite:

```bash
docker build \
  --build-arg BUILD_ARCH=amd64 \
  --build-arg BUILD_VERSION=5.1.0-1 \
  --tag local/ha-addon-romm:5.1.0-1 \
  romm
romm/tests/smoke.sh local/ha-addon-romm:5.1.0-1
```

The suite starts MariaDB 11.4 with binary logging, publishes its connection
through a minimal Supervisor-compatible service endpoint, and checks fresh
startup, the web and heartbeat endpoints, option mapping, secret handling,
Valkey and file persistence, clean shutdown, and direct host-port access.

It also starts the published `5.0.0-5` Home Assistant app, seeds three ROMs,
then upgrades the same database and storage with the candidate image. The test
verifies Alembic revision `0103`, preserved data, generated facet rows, virtual
collection rows, and the four trigger-maintained update paths.

On an AppArmor-capable Linux host, run the same suite under enforcement:

```bash
sudo romm/tests/local-apparmor.sh local/ha-addon-romm:5.1.0-1
```
