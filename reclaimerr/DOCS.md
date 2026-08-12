# Home Assistant App: Reclaimerr

## About

Reclaimerr scans Plex, Jellyfin, and Emby libraries for items that match your
reclaim rules. It tracks protections, requests, approvals, and history, and
can route an approved operation through a media server, Radarr, or Sonarr.
Automatic deletion is deliberately opt-in.

This is an unofficial Home Assistant package of Reclaimerr 0.3.5. It is not
sponsored, endorsed, or supported by the upstream project. Packaging issues
belong in this repository; application behavior, integrations, and feature
requests belong in [upstream support](https://github.com/jessielw/Reclaimerr).

## Install and first run

1. Add `https://github.com/rigerc/ha-apps-next` under **Settings → Apps → App
   Store → Repositories**.
2. Install **Reclaimerr** and review the app options before starting it.
3. Confirm that host port `8000` is available, or choose another host-side
   port in the app's **Network** settings. The container port remains `8000`.
4. Start the app and select **Open Web UI**.
5. Complete the Reclaimerr first-run setup. Create or confirm the initial admin
   account, then connect at least one media server.
6. If more than one media server is configured, choose exactly one as the main
   server. Add Radarr or Sonarr only when you want their service-specific
   routing.
7. Run an initial media sync and review candidates, rules, schedules, and
   move/delete behavior before enabling automation.

The first start can take longer while the SQLite schema and generated secrets
are initialized. A missing external integration should not prevent the web
interface from starting.

### Transient admin password recovery

If you need to create the first admin password or reset the first admin
account, set the optional `admin_password` app option and restart Reclaimerr.
Sign in, then clear `admin_password` and restart again. Treat this as a
one-time recovery value: the option is stored in Home Assistant's app
configuration while present, and should not remain set.

## Networking

### Direct LAN access

The app exposes a direct HTTP Web UI on container port `8000`. The default
setup is intended for a trusted local network. Use the **Open Web UI** button,
or browse to `http://<home-assistant-host>:8000` when the host port has not
been changed. Do not expose this HTTP endpoint directly to the public
internet. `cookie_secure` should remain `false` for direct HTTP access.

If you change the host-side port in Home Assistant, use the new port in your
browser and in any reverse-proxy configuration. The internal app port and
watchdog URL remain `8000`.

### HTTPS reverse proxy

Reclaimerr does not terminate TLS. Put a reverse proxy in front of the direct
host port and forward WebSocket and normal HTTP traffic to it. For example,
for `https://reclaimerr.example.com` with a proxy at `192.168.1.20`, use:

```yaml
timezone: Europe/Amsterdam
cors_origins: https://reclaimerr.example.com
proxy_trusted_hosts: 192.168.1.20
cookie_secure: true
```

The proxy must preserve the original `Host`, `X-Forwarded-Proto`, and client
connection behavior. `proxy_trusted_hosts` must name the proxy address (or a
narrow CIDR), not arbitrary clients; do not use `*`, `0.0.0.0/0`, or `::/0`.
Set `cors_origins` to the exact browser-visible HTTPS origin(s), separated by
commas when needed. Do not include a path, query, or fragment.

Configure Reclaimerr's **Application URL** in its General Settings when an
integration needs an absolute public callback or link. OIDC and media-service
callbacks must use the same public HTTPS origin and be forwarded by the proxy.

### Why ingress is not enabled

This package intentionally uses direct Web UI access rather than Home
Assistant ingress. The current upstream frontend and API use root-relative
asset and API paths, auth cookies, and callbacks, and the upstream response
policy includes `X-Frame-Options: DENY`. Home Assistant's dynamic ingress
prefix would therefore make routes and framing unreliable without an
upstream-compatible base-path change. Use the direct port or an HTTPS reverse
proxy instead.

## Options

Options are translated to the supported Reclaimerr environment variables by
the app wrapper. Values are validated before startup.

| Option | Default | Purpose |
| --- | --- | --- |
| `timezone` | `UTC` | Installed IANA timezone used by scheduled tasks. |
| `log_level` | `INFO` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, or `CRITICAL`. |
| `log_retention_days` | `30` | Number of days of rotated logs to retain; minimum `1`. |
| `command_workers` | `2` | Durable command executors, from `1` to `8`; leave at `2` unless needed. |
| `cors_origins` | `http://homeassistant.local:8000` | Comma-separated exact CORS origins. Use the public HTTPS origin behind a proxy. |
| `proxy_trusted_hosts` | `127.0.0.1,::1` | Explicit proxy IPs or CIDRs allowed to supply forwarded headers. |
| `cookie_secure` | `false` | Mark auth cookies Secure; set `true` only when the browser uses HTTPS. |
| `admin_password` | unset | Temporary first-admin creation/reset value; clear it after login. |

The wrapper fixes the service bind address to `0.0.0.0`, the internal port to
`8000`, and the persistent data paths under `/data/reclaimerr`. JWT and field
encryption secrets are generated by Reclaimerr and are not exposed as app
options.

## Persistent data and permissions

The complete persistent state is below `/data/reclaimerr`:

- `database/reclaimerr.db` — SQLite users, settings, media metadata, rules,
  candidates, history, and scheduled jobs.
- `secrets.env` — generated JWT and encryption secrets. Keep it private and
  restore it with the database.
- `logs/` — rotated application logs and audit information.
- `static/avatars/` — uploaded user avatars and other generated static state.

The app maps Home Assistant's `/media` and `/share` trees read-write. Configure
Reclaimerr path mappings to the paths as they appear inside the app. No Home
Assistant API, Supervisor API, host networking, or privileged access is
required.

The service runs as root inside its protected container because Home Assistant
media trees can contain files owned by different numeric users and groups; a
fixed unprivileged UID cannot reliably perform configured moves and deletions.
The custom AppArmor profile permits only `dac_override` for that filesystem
case, limits writes to `/data/reclaimerr`, `/media`, `/share`, and runtime
temporary paths, and does not grant privileged mode or host-level
administration. Keep protected mode enabled.

### Destructive operations — read before enabling

Reclaimerr can move or delete real media files. A rule or scheduled task can
make that operation automatic after its review period. Before enabling it:

- take a tested backup of the media library and the Reclaimerr app data;
- verify `/media` and `/share` path mappings and any move destination
  carefully;
- begin with automatic deletion disabled and run manual reviews;
- confirm protections, pending requests, and fallback deletion settings;
- test with disposable fixture media first.

Moving or deleting media is an application action, not an app upgrade action.
This package cannot recover files removed from `/media` or `/share`; keep
independent library backups and do not grant a broader mount than required.

## External services

Reclaimerr can connect to Plex, Jellyfin, Emby, Radarr, Sonarr, and optional
notification or metadata services. The web UI and local database remain
available when an external service is temporarily offline. Tasks that require
the unavailable service will wait, skip, or report an error until it returns.

An existing service can be disabled or deleted while unreachable. Enabling a
service or saving a new enabled configuration still requires a successful
connection test. The active main media server must be changed first before it
can be disabled or deleted.

## Backup, restore, and rollback

Use a Home Assistant cold backup before upgrades and before enabling destructive
automation. Stop the app before making a manual copy so the SQLite database and
`secrets.env` are consistent. Back up the entire app data volume, not only the
database:

1. Stop Reclaimerr.
2. Create a Home Assistant backup that includes this app and separately back up
   the `/media` and `/share` libraries used by path mappings (including any move
   destinations).
3. For a manual copy, preserve all of `/data/reclaimerr`, including
   `secrets.env`, and retain file ownership and permissions.
4. Restore the app data and the matching media backup while Reclaimerr is
   stopped, then start it and verify users, settings, rules, schedules, and
   `/api/info/version`.

The database and generated secrets must come from the same backup. Restoring a
database without its matching `secrets.env` can make encrypted values and
sessions unreadable. Test restores on a disposable instance when possible.

The app version `0.3.5-1` means upstream Reclaimerr `0.3.5` plus wrapper
revision `1`. A wrapper-only revision increments the suffix; an upstream
release starts a new base version. Always read both upstream and package
release notes, back up first, and allow migrations to finish before using the
UI. Do not roll back across a database migration by swapping images. Restore
the matching pre-upgrade cold backup instead.

## Troubleshooting

- **Web UI does not open:** check the app log for migration errors, confirm the
  host-side port is free, and verify that the app is listening on internal
  port `8000`.
- **Login does not persist behind a proxy:** use the exact HTTPS origin in the
  browser, set `cookie_secure: true`, and list only the proxy address in
  `proxy_trusted_hosts`.
- **CORS or redirects fail:** set `cors_origins` to the exact public origin and
  configure Reclaimerr's Application URL; do not use a path-based ingress URL.
- **Scheduled tasks do not run:** confirm one reachable main media server is
  selected, the task is enabled, and the task history does not show a pending
  protection or service error.
- **Files are missing from candidates or moves fail:** check that the media
  server paths match `/media` or `/share` and that the app has read-write
  access to the exact mapped directories.
- **A configured service is offline:** disable it temporarily or inspect the
  task history; reconnect and run the relevant sync after it returns.
- **Password recovery remains active:** clear `admin_password` in the app
  options and restart immediately after signing in.

## Support and license

For app metadata, image, wrapper, AppArmor, or Home Assistant lifecycle issues,
open an issue in this repository. For Reclaimerr application bugs, integrations,
and behavior, use the [upstream issue tracker](https://github.com/jessielw/Reclaimerr/issues)
and identify the packaged version (`0.3.5-1`).

Reclaimerr is distributed under the GNU General Public License, version 3.
The exact upstream license text is included in [LICENSE.md](LICENSE.md).
This package applies a published source patch that corrects the upstream
`/api/info/version` response; the patch is retained under `patches/` and the
container image is therefore clearly identified as Home Assistant packaging.
The corresponding upstream source is tag `0.3.5`, commit
`a1d24a4fa6534aae70009b431f5328b022eef6f1`. The packaging patch was added on
2026-08-11 and the complete wrapper source is distributed in this repository.
