# Endurain local runtime testing

The ordinary Docker smoke suite verifies startup, persistence, option
validation, supervision, shutdown, and secret handling. It does not reproduce
Home Assistant's AppArmor confinement unless a profile is attached explicitly.

Run the complete confinement-aware process on a Linux host where both the
kernel and Docker have AppArmor enabled:

```shell
sudo apt-get install apparmor-utils docker.io
endurain/tests/local-apparmor.sh
```

The driver:

1. refuses to run when AppArmor is disabled, preventing an unconfined false
   positive;
2. builds the current Endurain image and release metadata;
3. loads an isolated, enforced copy of `endurain/apparmor.txt`;
4. attaches that profile to every application container in the full smoke
   suite and verifies the profile reported by the container;
5. reports matching kernel denials and fails on any denial; and
6. removes its containers, temporary data, and AppArmor profile on exit.

For a quick functional check without Home Assistant confinement, build an image
and call the smoke suite directly:

```shell
docker build \
  --build-arg BUILD_ARCH=amd64 \
  --tag local/ha-addon-endurain:test \
  endurain
endurain/tests/smoke.sh local/ha-addon-endurain:test
```

An unconfined smoke pass is not sufficient release evidence for changes to
`apparmor.txt`, runtime executable paths, or directories below `/run`.
