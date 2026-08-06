# Home Assistant App: Endurain

## About

This unofficial app packages Endurain 0.19.0 with private PostgreSQL 18 and
Valkey services. It does not need another database app, Home Assistant API
access, host networking, or ingress. All mutable state is below `/data` and is
captured by a cold app backup.

Endurain is licensed under AGPL-3.0-or-later. Canonical upstream source and
support are at [Codeberg](https://codeberg.org/endurain-project/endurain).

## Install and first login

1. Install Endurain from this repository.
2. Confirm that host port `8081` is available in the **Network** section.
3. Leave the default options for direct access from a trusted local network.
4. Start the app. First initialization and database migrations can take several minutes.
5. Select **Open Web UI** and sign in with `admin` / `admin`.
6. Change the default password immediately.

The default HTTP setup is for a trusted LAN only. Do not expose it to the
internet.

## URL and TLS modes

`endurain_host` must exactly match the origin users enter in the browser,
including the scheme and non-default port. It must not contain a trailing slash,
path, query, fragment, or credentials.

### Trusted-LAN HTTP

Use an `http://` origin with:

```yaml
endurain_host: http://homeassistant.local:8081
behind_proxy: false
trusted_proxies: ""
```

The wrapper selects Endurain's development cookie behavior so login and session
refresh work over local HTTP. This mode must not be publicly exposed.

### Reverse-proxy HTTPS

Endurain does not terminate TLS. A public origin therefore requires a reverse
proxy that handles HTTPS and forwards to the configured Home Assistant host
port:

```yaml
endurain_host: https://endurain.example.com
behind_proxy: true
trusted_proxies: 192.168.1.10
```

The wrapper selects production cookie behavior. `trusted_proxies` must contain
only the exact proxy IP, a narrow CIDR, or a resolvable proxy hostname; `*` is
rejected. Strava requires a public HTTPS origin. OIDC callbacks and WebSocket
connections must also be forwarded by the proxy.

Changing the Network host port does not automatically change `endurain_host`.
Update the option to the exact new browser-visible origin.

## Options

- **`endurain_host`**: exact public origin. Default `http://homeassistant.local:8081`.
- **`timezone`**: installed IANA time zone. Default `UTC`.
- **`log_level`**: `critical`, `error`, `warning`, `info`, `debug`, or `trace`.
- **`behind_proxy`**: enable forwarded client information only for HTTPS proxy deployments.
- **`trusted_proxies`**: comma-separated explicit proxy IPs, CIDRs, or hostnames.
- **`smtp_host`**, **`smtp_port`**, **`smtp_username`**, **`smtp_password`**, **`smtp_from`**: optional password-reset email settings.
- **`smtp_secure`** and **`smtp_secure_type`**: enable SMTP encryption with `starttls` or `ssl`.
- **`allowed_redirect_schemes`**: custom mobile callback schemes such as `endurain,gadgetbridge`.
- **`ssrf_allowed_hosts`**: narrow hostname or CIDR exceptions for private OIDC discovery/JWKS endpoints.
- **`csp_additional_connect_src`**: explicit HTTP/WebSocket origins needed by a forward-auth proxy.
- **`allow_api_key_query_param`**: permit API keys in URLs. Disabled by default because URLs leak into logs and browser history. Prefer `X-API-Key`.

Normal accounts, MFA, API keys, branding, Strava, Garmin, and OIDC are configured
inside Endurain. SMTP is optional, but password-reset email is unavailable until
it is configured.

## Persistent data

The app maintains:

- `/data/endurain/data`: activity files, imports, thumbnails, media, and images.
- `/data/endurain/logs`: application logs.
- `/data/postgresql`: Endurain users, settings, activity records, and other database state.
- `/data/valkey`: rate-limit, login lockout, and temporary authentication-security state.
- `/data/secrets`: stable database, JWT, and Fernet keys generated on first start.

Generated secrets are not app options and are never printed. PostgreSQL and
Valkey listen only on container loopback and have no host ports.

## Backup, restore, and upgrades

The app uses cold backups. Home Assistant stops Endurain, requests a fast clean
PostgreSQL shutdown, and lets Valkey flush its append-only state before copying
`/data`. A complete app backup therefore contains all Endurain state and its
private services.

Create a backup before every update. Wrapper revisions use versions such as
`0.19.0-1` and `0.19.0-2`; an upstream update starts a new series such as
`0.19.1-1`. PostgreSQL remains on major version 18 for this app series. A future
major PostgreSQL change requires an explicit migration release and is never
performed automatically at startup.

Do not roll back across an Endurain database migration. Restore the matching
pre-upgrade cold backup instead.

## Integrations

- Send API keys in the `X-API-Key` header.
- Strava callbacks require the exact public HTTPS `endurain_host`.
- Garmin, reverse geocoding, release checks, SMTP, and OIDC require outbound network access.
- Private OIDC hosts may require a narrow `ssrf_allowed_hosts` entry.
- A forward-auth domain may require `csp_additional_connect_src`.

## Troubleshooting

- **App rejects HTTP options:** disable `behind_proxy` and clear `trusted_proxies`.
- **App rejects HTTPS options:** enable `behind_proxy` and set an explicit trusted proxy.
- **Login does not persist:** confirm the browser URL exactly matches `endurain_host`; production mode requires HTTPS.
- **Web UI does not start:** allow the first migration several minutes, then inspect the app log.
- **Port conflict:** change host port `8081` in the Network section and update `endurain_host`.
- **PostgreSQL major-version error:** restore a PostgreSQL 18 app backup; do not edit `PG_VERSION`.
- **Password reset unavailable:** configure all required SMTP values.

Report packaging problems at this repository. Report reproducible Endurain
application bugs to the canonical Codeberg project and identify this package as
an unofficial deployment.

## License and trademark

The exact upstream release source is
[`v0.19.0`](https://codeberg.org/endurain-project/endurain/src/tag/v0.19.0).
The wrapper source is published with the image in this repository. See
`LICENSE` for AGPL-3.0-or-later terms and attribution.

This package is not sponsored or endorsed by the Endurain project. Endurain® is
a registered trademark of João Vitória Silva.
