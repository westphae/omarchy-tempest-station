import importlib.util
import os
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import fetch

spec = importlib.util.spec_from_file_location("save_token", ROOT / "save-token.py")
save_token = importlib.util.module_from_spec(spec)
spec.loader.exec_module(save_token)


def test_station_and_token_alphabets():
    assert fetch.sanitize_station("12345") == "12345"
    assert fetch.sanitize_station("12345&units_temp=c") == ""
    assert fetch.sanitize_station("123\n45") == ""
    assert fetch.sanitize_token("abcd-ef_12") == "abcd-ef_12"
    assert fetch.sanitize_token("abcd efgh") == ""
    assert fetch.sanitize_token("short") == ""
    assert save_token.sanitize_token("abcd\"efghij") == ""


def test_url_stays_on_weatherflow():
    url = fetch.forecast_url("42", "abcd-ef_12", "imperial")
    assert url.startswith("https://swd.weatherflow.com/swd/rest/better_forecast?")
    assert "station_id=42" in url
    assert "units_temp=f" in url
    assert "token=abcd-ef_12" in url
    assert fetch.forecast_url("42&x=1", "abcd-ef_12", "imperial") == ""
    assert fetch.forecast_url("42", "abcd-ef_12", "furlongs") == ""


def test_redirects_are_not_followed():
    handler = fetch._NoRedirect()
    assert handler.redirect_request(None, None, 302, "Found", {}, "https://example.invalid/") is None


def test_save_writes_mode_600(tmp_path):
    path = tmp_path / "tempest-token"
    env = os.environ.copy()
    env["TEMPEST_TOKEN"] = "abcd-ef_12"
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parents[1] / "save-token.py"), str(path)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert result.stdout == "ok"
    assert path.read_text(encoding="utf-8") == "abcd-ef_12\n"
    assert stat.S_IMODE(path.stat().st_mode) == 0o600


def test_save_rejects_markup_token(tmp_path):
    path = tmp_path / "tempest-token"
    env = os.environ.copy()
    env["TEMPEST_TOKEN"] = "<img src=x>"
    result = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parents[1] / "save-token.py"), str(path)],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert result.stdout == "invalid"
    assert not path.exists()


if __name__ == "__main__":
    test_station_and_token_alphabets()
    test_url_stays_on_weatherflow()
    test_redirects_are_not_followed()
    with tempfile.TemporaryDirectory() as directory:
        test_save_writes_mode_600(Path(directory))
    with tempfile.TemporaryDirectory() as directory:
        test_save_rejects_markup_token(Path(directory))
    print("ok")
