# Home Assistant App: Endurain

Endurain is a self-hosted fitness and activity tracking service with support for
activity imports, Garmin and Strava connections, maps, statistics, goals, and
health data.

This unofficial Home Assistant package contains Endurain 0.19.0, PostgreSQL 18,
and Valkey in one app. All application and database state is kept in the app's
private data directory and included in cold backups.

The web interface is available through **Open Web UI** on host port `8081` by
default. The initial Endurain credentials are `admin` / `admin`; change the
password immediately after signing in.

This package is not sponsored or endorsed by the Endurain project. Endurain® is
a registered trademark of João Vitória Silva.
