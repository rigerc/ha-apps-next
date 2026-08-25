# Changelog

## 5.1.0-1

- Update the packaged upstream release to RomM 5.1.0.
- Add scheduled orphaned-resource cleanup and secure-session-cookie options.
- Support upstream's nginx-to-Gunicorn TCP transport and archive handling.
- Add automated fresh-install, persistence, and 5.0.0 database-upgrade tests.
- The first start performs one-time database backfills and trigger migrations
  and can take longer for large libraries. Create a full Home Assistant backup
  before upgrading and do not interrupt the migration.
- Emulator streaming remains unsupported because it requires separate broker
  and emulator containers.

## 5.0.0-5

- Allow libmagic to read its compiled MIME database under AppArmor so RomM
  migrations can import the filesystem handlers.
- Disable Gunicorn's unused control socket so it does not attempt to create
  runtime files below `/root`.
- Link the upstream filesystem watcher path to the configured library
  directory so filesystem-change rescans work with `/share` storage.
- No configuration or data migration is required for this update.

## 5.0.0-4

- Allow Python to inspect the RomM backend directory under AppArmor so
  Alembic can import the application configuration during database migrations.
- No configuration or data migration is required for this update.

## 5.0.0-3

- Allow the embedded Valkey service to read its packaged configuration under
  the app's AppArmor profile.
- Ensure the persistent Valkey data directory is owned by the RomM user.
- No configuration or data migration is required for this update.

## 5.0.0-2

- Allow the upstream Nginx entrypoint hooks to execute under the app's
  AppArmor profile, restoring access to the RomM web interface.
- No configuration or data migration is required for this update.

## 5.0.0-1

- Rebuild the Home Assistant app around stable RomM 5.0.0.
- Correct Home Assistant MariaDB service-response handling.
- Persist the embedded Valkey store in the app data directory.
- Preserve RomM libraries and assets below `/share/romm`.
- Add an optional public base URL and Hasheous configuration.
- Add a health watchdog, cold backups, and a tightened AppArmor profile.
- Publish signed `amd64` and `aarch64` images with the current Home Assistant
  builder actions.
