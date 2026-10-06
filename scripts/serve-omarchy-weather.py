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
PORT = 47653  # Keep the origin stable so browser storage and the service worker persist.
URL = f"http://{HOST}:{PORT}/"
EXPECTED_PAGE_MARKER = b"<title>Omarchy Weather</title>"


def app_is_served() -> bool:
    try:
        with urllib.request.urlopen(URL, timeout=0.7) as response:
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

    app_directory = Path(sys.argv[1]).expanduser().resolve()
    if not (app_directory / "index.html").is_file():
        print(f"Omarchy Weather files were not found in {app_directory}.", file=sys.stderr)
        return 1

    if app_is_served():
        print(URL)
        return 0

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        try:
            probe.bind((HOST, PORT))
        except OSError:
            if app_is_served():
                print(URL)
                return 0
            print(
                f"Port {PORT} is already in use. Close the conflicting service or change PORT in scripts/serve-omarchy-weather.py and reinstall.",
                file=sys.stderr,
            )
            return 1

    command = [
        sys.executable,
        "-m",
        "http.server",
        str(PORT),
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
    pid_file.write_text(f"{server.pid} {PORT}\n", encoding="utf-8")

    for _ in range(40):
        if app_is_served():
            print(URL)
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
