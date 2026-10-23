# Tempest

Live weather from a WeatherFlow Tempest station, shown on the Omarchy bar.

The built-in weather widget reports a nearby city. This one reports the station in your yard: temperature on the bar, and feels-like, wind, humidity, pressure, rain, UV, and a three-day forecast in the popup.

## Install

```sh
omarchy plugin add https://github.com/westphae/omarchy-tempest-station.git --enable
```

Click the cloud on the bar. Enter the station ID from the Tempest app (station settings) and a personal access token from [tempestwx.com/settings/tokens](https://tempestwx.com/settings/tokens).

The station ID is saved with this widget's bar settings. The token is written to `~/.config/omarchy/tempest-token` with mode 600. It is not stored in `shell.json`, not passed on a command line, and not included in this repository.

## Configure

```sh
omarchy bar set eric.tempest stationId 12345
omarchy bar set eric.tempest units auto
omarchy bar set eric.tempest refreshSeconds 60
```

`units` is `auto`, `imperial`, or `metric`. `auto` uses imperial for `en_US` and `en-LR`, and metric otherwise. The refresh interval is clamped to 30–1800 seconds. Click the unit in the popup to switch between imperial and metric.

Move it like any other bar widget:

```sh
omarchy bar move eric.tempest --section right
```

## Remove

Disable it and leave the files in place:

```sh
omarchy plugin disable eric.tempest
```

Remove the plugin itself:

```sh
omarchy plugin remove eric.tempest
```

Neither command deletes `~/.config/omarchy/tempest-token`. Remove that file yourself if you want the token gone. This plugin does not change other widgets. To put the built-in forecast back:

```sh
omarchy plugin enable omarchy.weather
```

## Dependencies

- Omarchy's shell (Quickshell / Qt 6)
- Python 3 standard library (`urllib`). No third-party packages.
- WeatherFlow's `better_forecast` API at `https://swd.weatherflow.com`, polled over HTTPS. A personal access token and a station ID are required.

## License

MIT. See [LICENSE](LICENSE).
