# Reclaimerr local runtime testing

The ordinary Docker smoke suite verifies startup, persistence, option
validation, media path handling, cold backups, upgrades, and secret handling.
It does not reproduce Home Assistant's AppArmor confinement unless a profile is
attached explicitly.

Run the complete confinement-aware process on a Linux host where both the
kernel and Docker have AppArmor enabled:

```shell
sudo apt-get install apparmor-utils docker.io
reclaimerr/tests/local-apparmor.sh
```

The driver:

1. refuses to run when AppArmor is disabled, preventing an unconfined false
   positive;
2. builds the current Reclaimerr image and release metadata;
3. loads an isolated, enforced copy of `reclaimerr/apparmor.txt`;
4. attaches that profile to every application container in the full smoke
   suite and verifies the profile reported by the container;
5. reports matching kernel denials and fails on any unexpected denial; and
6. removes its containers, temporary data, and AppArmor profile on exit.

The audit filter recognizes exact non-blocking probes: Bash and `run.sh`
opening `/dev/tty` without a TTY, granian probing its executable directory, the
`/proc` root, and the cgroup CPU cap, and Python removing unused `urllib3`
source modules during startup compaction. Those deletion and discovery paths
intentionally remain denied because the application keeps running correctly
without them. Any other denial fails the process and is printed with its
operation and path.

For a quick functional check without Home Assistant confinement, build an image
and call the smoke suite directly:

```shell
docker build \
  --build-arg BUILD_ARCH=amd64 \
  --build-arg BUILD_VERSION=0.3.5-1 \
  --tag local/ha-addon-reclaimerr:test \
  reclaimerr
reclaimerr/tests/smoke.sh local/ha-addon-reclaimerr:test
```

An unconfined smoke pass is not sufficient release evidence for changes to
`apparmor.txt`, runtime executable paths, or directories below `/run`.