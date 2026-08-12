# Home Assistant App: Reclaimerr

Reclaimerr scans Plex, Jellyfin, and Emby libraries for reclaim candidates,
then protects, reviews, and routes approved media cleanup through the matching
media service, Radarr, or Sonarr.

This repository provides an **unofficial Home Assistant package** for
Reclaimerr 0.3.5. It is not sponsored, endorsed, or supported by the upstream
Reclaimerr project. The app keeps its database, generated secrets, logs, and
avatars in its private `/data/reclaimerr` directory and maps Home Assistant's
`/media` directory read-write for configured path mappings and cleanup actions.
The package also carries a small published patch for the upstream version-info
endpoint; all wrapper changes are available in this repository.

The package is based on upstream tag `0.3.5` at commit
`a1d24a4fa6534aae70009b431f5328b022eef6f1`; its OCI base image is pinned by
digest. Packaging modifications and their source are included under
`reclaimerr/`.

## Install and open

1. Add `https://github.com/rigerc/ha-apps-next` as a Home Assistant app
   repository.
2. Install **Reclaimerr** and review its options before starting it.
3. Select **Open Web UI**. The app listens on port `8000` by default.
4. Complete the first-run setup and connect at least one media server.

Automatic deletion is opt-in. Review every rule and task before allowing a
move or delete operation to run.

See [DOCS.md](DOCS.md) for installation, reverse-proxy, storage, backup,
upgrade, and troubleshooting guidance. Report packaging issues here; report
application bugs and feature requests to the [upstream Reclaimerr project](https://github.com/jessielw/Reclaimerr).

Reclaimerr is licensed under the GNU GPLv3; the exact upstream license text is
included in [LICENSE.md](LICENSE.md).
