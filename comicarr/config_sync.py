#!/usr/bin/env python3
"""Synchronize Home Assistant options into Comicarr's config.ini."""

from __future__ import annotations

import configparser
import json
import os
import posixpath
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

OPTIONS_FILE = Path("/data/options.json")
DATA_DIR = Path("/data/comicarr")
CONFIG_FILE = DATA_DIR / "config.ini"
BACKUP_DIR = DATA_DIR / "backups"

DEFAULTS: dict[str, Any] = {
    "directories": {
        "comics": "/media/comics",
        "manga": "/media/manga",
        "downloads": "/share/comicarr/downloads",
        "torrent_watch": "/share/comicarr/watch",
    },
    "library": {
        "create_folders": True,
        "rename_files": False,
        "file_operation": "move",
        "folder_format": "$Series ($Year)",
        "file_format": "$Series $Annual $Issue ($Year)",
        "backup_on_start": False,
        "backup_retention": 4,
    },
    "scheduler": {
        "rss_interval": 20,
        "search_interval": 1440,
        "download_scan_interval": 5,
    },
    "torrents": {
        "enabled": False,
        "search_enabled": False,
        "minimum_seeders": 0,
        "client": "watchfolder",
    },
    "qbittorrent": {
        "label": "comicarr",
        "download_path": "/share/comicarr/downloads",
        "load_action": "default",
    },
    "transmission": {
        "download_path": "/share/comicarr/downloads",
    },
    "opds": {
        "enabled": False,
        "authentication": False,
        "endpoint": "opds",
        "page_size": 30,
        "extended_metadata": False,
    },
}

TORRENT_CLIENTS = {
    "watchfolder": 0,
    "utorrent": 1,
    "rtorrent": 2,
    "transmission": 3,
    "deluge": 4,
    "qbittorrent": 5,
}


def fail(message: str) -> None:
    raise ValueError(message)


def read_options() -> dict[str, Any]:
    with OPTIONS_FILE.open(encoding="utf-8") as options_file:
        options = json.load(options_file)
    if not isinstance(options, dict):
        fail("Home Assistant options must be an object")
    return options


def group(options: dict[str, Any], name: str) -> dict[str, Any]:
    value = options.get(name, {})
    if not isinstance(value, dict):
        fail(f"{name} must be an object")
    return value


def value(
    options: dict[str, Any], group_name: str, key: str, expected_type: type
) -> Any:
    values = group(options, group_name)
    result = values.get(key, DEFAULTS[group_name][key])
    if type(result) is not expected_type:
        fail(f"{group_name}.{key} must be a {expected_type.__name__}")
    return result


def optional_string(options: dict[str, Any], group_name: str, key: str) -> str | None:
    values = group(options, group_name)
    if key not in values or values[key] == "":
        return None
    result = values[key]
    if type(result) is not str:
        fail(f"{group_name}.{key} must be a string")
    if len(result) > 512 or any(character in result for character in "\r\n\0"):
        fail(f"{group_name}.{key} contains an invalid value")
    return result


def managed_path(options: dict[str, Any], key: str) -> str:
    raw_path = value(options, "directories", key, str)
    return validate_managed_path(raw_path, f"directories.{key}")


def validate_managed_path(raw_path: str, label: str) -> str:
    if not raw_path.startswith("/") or any(character in raw_path for character in "\r\n\0"):
        fail(f"{label} must be an absolute path")
    normalized = posixpath.normpath(raw_path)
    if any(part == ".." for part in raw_path.split("/")):
        fail(f"{label} must not contain parent traversal")
    if not any(normalized.startswith(f"{root}/") for root in ("/media", "/share")):
        fail(f"{label} must be below /media or /share")
    return normalized


def bounded_integer(
    options: dict[str, Any], group_name: str, key: str, minimum: int, maximum: int
) -> int:
    result = value(options, group_name, key, int)
    if not minimum <= result <= maximum:
        fail(f"{group_name}.{key} must be between {minimum} and {maximum}")
    return result


def bounded_string(
    options: dict[str, Any], group_name: str, key: str, maximum: int = 200
) -> str:
    result = value(options, group_name, key, str)
    if not result or len(result) > maximum or any(character in result for character in "\r\n\0"):
        fail(f"{group_name}.{key} contains an invalid value")
    return result


def boolean_text(value_: bool) -> str:
    return "True" if value_ else "False"


def set_value(parser: configparser.ConfigParser, section: str, key: str, value_: Any) -> None:
    if not parser.has_section(section):
        parser.add_section(section)
    parser.set(section, key, str(value_))


def build_updates(options: dict[str, Any]) -> tuple[list[tuple[str, str, str]], list[str]]:
    paths = {
        key: managed_path(options, key)
        for key in ("comics", "manga", "downloads", "torrent_watch")
    }
    torrent_client = value(options, "torrents", "client", str)
    if torrent_client not in TORRENT_CLIENTS:
        fail("torrents.client is not supported")
    file_operation = value(options, "library", "file_operation", str)
    if file_operation not in {"move", "copy", "hardlink", "softlink"}:
        fail("library.file_operation is not supported")
    load_action = value(options, "qbittorrent", "load_action", str)
    if load_action not in {"default", "force_start", "paused"}:
        fail("qbittorrent.load_action is not supported")

    updates = [
        ("General", "config_version", "18"),
        ("General", "minimal_ini", "False"),
        ("General", "launch_browser", "False"),
        ("General", "destination_dir", paths["comics"]),
        ("General", "manga_destination_dir", paths["manga"]),
        ("General", "backup_location", str(BACKUP_DIR)),
        ("General", "create_folders", boolean_text(value(options, "library", "create_folders", bool))),
        ("General", "rename_files", boolean_text(value(options, "library", "rename_files", bool))),
        ("General", "folder_format", bounded_string(options, "library", "folder_format")),
        ("General", "file_format", bounded_string(options, "library", "file_format")),
        ("General", "backup_on_start", boolean_text(value(options, "library", "backup_on_start", bool))),
        ("General", "backup_retention", str(bounded_integer(options, "library", "backup_retention", 1, 50))),
        ("Interface", "http_host", "0.0.0.0"),
        ("Interface", "http_port", "8090"),
        ("PostProcess", "file_opts", file_operation),
        ("Scheduler", "rss_checkinterval", str(bounded_integer(options, "scheduler", "rss_interval", 10, 10080))),
        ("Scheduler", "search_interval", str(bounded_integer(options, "scheduler", "search_interval", 10, 10080))),
        ("Scheduler", "download_scan_interval", str(bounded_integer(options, "scheduler", "download_scan_interval", 1, 1440))),
        ("Client", "torrent_downloader", str(TORRENT_CLIENTS[torrent_client])),
        ("Torrents", "enable_torrents", boolean_text(value(options, "torrents", "enabled", bool))),
        ("Torrents", "enable_torrent_search", boolean_text(value(options, "torrents", "search_enabled", bool))),
        ("Torrents", "minseeds", str(bounded_integer(options, "torrents", "minimum_seeders", 0, 100000))),
        ("Watchdir", "torrent_local", boolean_text(torrent_client == "watchfolder")),
        ("Watchdir", "local_watchdir", paths["torrent_watch"]),
        ("SABnzbd", "sab_directory", paths["downloads"]),
        ("DDL", "ddl_location", paths["downloads"]),
        ("qBittorrent", "qbittorrent_label", bounded_string(options, "qbittorrent", "label", 100)),
        ("qBittorrent", "qbittorrent_folder", managed_client_path(options, "qbittorrent", "download_path")),
        ("qBittorrent", "qbittorrent_loadaction", load_action),
        ("Transmission", "transmission_directory", managed_client_path(options, "transmission", "download_path")),
        ("OPDS", "opds_enable", boolean_text(value(options, "opds", "enabled", bool))),
        ("OPDS", "opds_authentication", boolean_text(value(options, "opds", "authentication", bool))),
        ("OPDS", "opds_endpoint", validate_endpoint(options)),
        ("OPDS", "opds_pagesize", str(bounded_integer(options, "opds", "page_size", 1, 500))),
        ("OPDS", "opds_metainfo", boolean_text(value(options, "opds", "extended_metadata", bool))),
    ]

    secret_supplied = False
    optional_keys = {
        "qbittorrent": {
            "host": ("qBittorrent", "qbittorrent_host", False),
            "username": ("qBittorrent", "qbittorrent_username", False),
            "password": ("qBittorrent", "qbittorrent_password", True),
        },
        "transmission": {
            "host": ("Transmission", "transmission_host", False),
            "username": ("Transmission", "transmission_username", False),
            "password": ("Transmission", "transmission_password", True),
        },
        "opds": {
            "username": ("OPDS", "opds_username", False),
            "password": ("OPDS", "opds_password", True),
        },
    }
    for group_name, keys in optional_keys.items():
        for option_key, (section, config_key, secret) in keys.items():
            configured = optional_string(options, group_name, option_key)
            if configured is not None:
                updates.append((section, config_key, configured))
                secret_supplied = secret_supplied or secret
    if secret_supplied:
        updates.append(("General", "encrypt_passwords", "True"))

    return updates, list(paths.values())


def managed_client_path(options: dict[str, Any], group_name: str, key: str) -> str:
    raw_path = value(options, group_name, key, str)
    return validate_managed_path(raw_path, f"{group_name}.{key}")


def validate_endpoint(options: dict[str, Any]) -> str:
    endpoint = bounded_string(options, "opds", "endpoint", 64).strip("/")
    if not endpoint or any(character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for character in endpoint):
        fail("opds.endpoint may contain only letters, numbers, hyphens, and underscores")
    return endpoint


def synchronize(options: dict[str, Any]) -> None:
    updates, managed_directories = build_updates(options)
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    for directory in managed_directories:
        Path(directory).mkdir(parents=True, exist_ok=True)

    parser = configparser.ConfigParser(interpolation=None)
    if CONFIG_FILE.exists():
        with CONFIG_FILE.open(encoding="utf-8") as config_file:
            parser.read_file(config_file)
    for section, key, configured in updates:
        set_value(parser, section, key, configured)

    current_mode = 0o600
    if CONFIG_FILE.exists():
        current_mode = stat.S_IMODE(CONFIG_FILE.stat().st_mode)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".ha-config-", dir=DATA_DIR)
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, current_mode)
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            parser.write(temporary_file)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, CONFIG_FILE)
        directory_descriptor = os.open(DATA_DIR, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        temporary_path.unlink(missing_ok=True)
    print(f"[comicarr] Synchronized {len(updates)} Home Assistant settings into config.ini")


def main() -> None:
    try:
        synchronize(read_options())
    except (OSError, ValueError, json.JSONDecodeError, configparser.Error) as error:
        print(f"[comicarr] ERROR: Invalid Home Assistant configuration: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
