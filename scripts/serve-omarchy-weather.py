#!/usr/bin/env python3
"""Start or reuse the loopback-only server used by the Omarchy launcher."""

from __future__ import annotations

import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOST = "127.0.0.1"
DEFAULT_PORT = 47653  # Keep the origin stable so browser storage and the service worker persist.
EXPECTED_PAGE_MARKER = b"<title>Omarchy Weather</title>"


def app_is_served(url: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=0.7) as response:
            return response.status == 200 and EXPECTED_PAGE_MARKER in response.read(32768)
    except (OSError, urllib.error.URLError, TimeoutError):
        return False


def runtime_directory() -> Path:
    configured = os.environ.get("XDG_RUNTIME_DIR")
    if configured:
        path = Path(configured)
    else:
        path = Path(tempfile.gettempdir()) / f"omarchy-weather-{os.getuid()}"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: serve-omarchy-weather.py APP_DIRECTORY", file=sys.stderr)
        return 2

    try:
        port = int(os.environ.get("OMARCHY_WEATHER_PORT", str(DEFAULT_PORT)))
    except ValueError:
        print("OMARCHY_WEATHER_PORT must be an integer from 1 to 65535.", file=sys.stderr)
        return 2
    if not 1 <= port <= 65535:
        print("OMARCHY_WEATHER_PORT must be an integer from 1 to 65535.", file=sys.stderr)
        return 2
    url = f"http://{HOST}:{port}/"

    app_directory = Path(sys.argv[1]).expanduser().resolve()
    if not (app_directory / "index.html").is_file():
        print(f"Omarchy Weather files were not found in {app_directory}.", file=sys.stderr)
        return 1

    if app_is_served(url):
        print(url)
        return 0

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind((HOST, port))
        except OSError:
            if app_is_served(url):
                print(url)
                return 0
            print(
                f"Port {port} is already in use. Choose another with OMARCHY_WEATHER_PORT.",
                file=sys.stderr,
            )
            return 1

    command = [
        sys.executable,
        "-m",
        "http.server",
        str(port),
        "--bind",
        HOST,
        "--directory",
        str(app_directory),
    ]
    try:
        server = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        print(f"Could not start the local weather app server: {error}", file=sys.stderr)
        return 1

    pid_file = runtime_directory() / "omarchy-weather-server.pid"
    pid_file.write_text(f"{server.pid} {port}\n", encoding="utf-8")

    for _ in range(40):
        if app_is_served(url):
            print(url)
            return 0
        if server.poll() is not None:
            break
        time.sleep(0.1)

    if server.poll() is None:
        server.terminate()
        try:
            server.wait(timeout=1)
        except subprocess.TimeoutExpired:
            server.kill()
    try:
        pid_file.unlink()
    except FileNotFoundError:
        pass
    print("The local weather app server did not become ready.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
