#!/usr/bin/env python3
"""Fetch WeatherFlow's better forecast for one Tempest station.

The token is read from a mode-600 file. It is never taken from argv, and
failures are reported as a short JSON code so a urllib error (which quotes
the request URL) cannot reach the bar.
"""

import json
import os
import sys
import urllib.error
import urllib.request

MAX_BYTES = 524288
API = "https://swd.weatherflow.com/swd/rest/better_forecast"
TOKEN_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def sanitize_station(value):
    text = str(value or "").strip()
    if text.isdigit() and 1 <= len(text) <= 12:
        return text
    return ""


def sanitize_token(value):
    text = str(value or "").strip()
    if len(text) < 8 or len(text) > 128:
        return ""
    if any(ch not in TOKEN_CHARS for ch in text):
        return ""
    return text


def units_query(units):
    if units == "imperial":
        return "units_temp=f&units_wind=mph&units_pressure=inhg&units_precip=in&units_distance=mi"
    if units == "metric":
        return "units_temp=c&units_wind=kph&units_pressure=hpa&units_precip=mm&units_distance=km"
    return ""


def forecast_url(station, token, units):
    station = sanitize_station(station)
    token = sanitize_token(token)
    query = units_query(units)
    if not station or not token or not query:
        return ""
    return API + "?station_id=" + station + "&" + query + "&token=" + token


def token_path(home):
    return os.path.join(home, ".config", "omarchy", "tempest-token")


def read_token(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return sanitize_token(handle.read())
    except OSError:
        return ""


def emit_error(code):
    sys.stdout.write(json.dumps({"ok": False, "error": code}))


def read_response(url):
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "eric.tempest"},
    )
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(request, timeout=12) as response:
            return response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        return error.read(MAX_BYTES + 1)
    except Exception:
        return None


def main(argv):
    station = sanitize_station(argv[1] if len(argv) > 1 else "")
    units = argv[2] if len(argv) > 2 else ""
    if units not in ("imperial", "metric"):
        units = ""
    if not station or not units:
        emit_error("config")
        return 0
    path = token_path(os.environ.get("HOME", ""))
    token = read_token(path)
    if not token:
        emit_error("token")
        return 0
    body = read_response(forecast_url(station, token, units))
    if body is None:
        emit_error("network")
        return 0
    if len(body) > MAX_BYTES:
        emit_error("size")
        return 0
    sys.stdout.buffer.write(body)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
