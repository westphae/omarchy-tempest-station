// Pure parsing for the Tempest bar widget. The network fetch lives in
// fetch.py so the access token never has to be assembled in QML.
//
// WeatherFlow's condition icon is a name, not a glyph. Only names in
// ICON_GLYPHS become a character the bar font can draw. Anything else falls
// back to the cloudy glyph, so a response cannot put markup or an unexpected
// character into the icon.

var ICON_GLYPHS = {
  "clear-day": "\ue30d",
  "clear-night": "\ue32b",
  "cloudy": "\ue33d",
  "foggy": "\ue313",
  "partly-cloudy-day": "\ue302",
  "partly-cloudy-night": "\ue32e",
  "possibly-rainy-day": "\ue308",
  "possibly-rainy-night": "\ue333",
  "possibly-sleet-day": "\ue3ad",
  "possibly-sleet-night": "\ue3ad",
  "possibly-snow-day": "\ue30a",
  "possibly-snow-night": "\ue327",
  "possibly-thunderstorm-day": "\ue31d",
  "possibly-thunderstorm-night": "\ue31d",
  "rainy": "\ue318",
  "sleet": "\ue3ad",
  "snow": "\ue31a",
  "thunderstorm": "\ue31d",
  "windy": "\ue31e"
}

var CLOUDY = "\ue33d"

var CONDITION_KEYS = {
  "Clear": "cond.clear",
  "Rain Likely": "cond.rainLikely",
  "Rain Possible": "cond.rainPossible",
  "Snow": "cond.snow",
  "Snow Possible": "cond.snowPossible",
  "Wintry Mix Likely": "cond.wintryMixLikely",
  "Wintry Mix Possible": "cond.wintryMixPossible",
  "Thunderstorms Likely": "cond.thunderstormsLikely",
  "Thunderstorms Possible": "cond.thunderstormsPossible",
  "Windy": "cond.windy",
  "Foggy": "cond.foggy",
  "Cloudy": "cond.cloudy",
  "Partly Cloudy": "cond.partlyCloudy",
  "Very Light Rain": "cond.veryLightRain"
}

var CARDINALS = {
  N: 1, NNE: 1, NE: 1, ENE: 1, E: 1, ESE: 1, SE: 1, SSE: 1,
  S: 1, SSW: 1, SW: 1, WSW: 1, W: 1, WNW: 1, NW: 1, NNW: 1
}

var FETCH_ERRORS = { network: 1, token: 1, config: 1, size: 1 }

function sanitizeStationId(value) {
  if (typeof value === "number" && isFinite(value)) value = String(Math.round(value))
  var id = String(value == null ? "" : value).replace(/^\s+|\s+$/g, "")
  return /^[0-9]{1,12}$/.test(id) ? id : ""
}

function sanitizeToken(value) {
  var token = String(value == null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (token.length < 8 || token.length > 128) return ""
  return /^[A-Za-z0-9_-]+$/.test(token) ? token : ""
}

function normalizeUnits(value) {
  var mode = String(value == null ? "" : value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (mode === "imperial" || mode === "metric" || mode === "auto") return mode
  return "auto"
}

function useImperial(units, localeName) {
  var mode = normalizeUnits(units)
  if (mode === "imperial") return true
  if (mode === "metric") return false
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/i.test(name) || /^en[_-]LR($|[_.-])/i.test(name)
}

function refreshSeconds(value) {
  var n = Number(value)
  if (!isFinite(n)) return 60
  n = Math.round(n)
  if (n < 30) return 30
  if (n > 1800) return 1800
  return n
}

function iconGlyph(icon) {
  return ICON_GLYPHS[String(icon || "")] || CLOUDY
}

function clipText(value, max) {
  var text = String(value == null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, "").replace(/^\s+|\s+$/g, "")
  if (text.length > max) text = text.slice(0, max)
  return text
}

function finiteIn(value, min, max) {
  if (typeof value !== "number" || !isFinite(value)) return null
  if (value < min || value > max) return null
  return value
}

function firstNumber(obj, keys, min, max) {
  if (!obj) return null
  for (var i = 0; i < keys.length; i++) {
    var value = finiteIn(obj[keys[i]], min, max)
    if (value !== null) return value
  }
  return null
}

function conditionOf(value) {
  var text = clipText(value, 48)
  var key = CONDITION_KEYS[text] || ""
  return { key: key, text: key ? "" : text }
}

function cardinal(value) {
  var text = String(value == null ? "" : value).replace(/^\s+|\s+$/g, "").toUpperCase()
  return CARDINALS[text] ? text : ""
}

function age(epochSeconds, nowMs) {
  if (typeof epochSeconds !== "number" || !isFinite(epochSeconds)) return { unit: "unknown", count: 0 }
  var delta = Math.round(nowMs / 1000 - epochSeconds)
  if (delta < 0) delta = 0
  if (delta < 45) return { unit: "now", count: 0 }
  if (delta < 3600) return { unit: "minute", count: Math.max(1, Math.round(delta / 60)) }
  if (delta < 172800) return { unit: "hour", count: Math.max(1, Math.round(delta / 3600)) }
  return { unit: "unknown", count: 0 }
}

function bounds(imperial) {
  if (imperial) {
    return { temp: [-80, 140], wind: [0, 200], pressure: [20, 35], rain: [0, 30] }
  }
  return { temp: [-60, 60], wind: [0, 320], pressure: [700, 1100], rain: [0, 500] }
}

function parseDays(forecast, limit, imperial) {
  var daily = forecast && forecast.daily
  if (!daily || !daily.length) return []
  var range = bounds(imperial)
  var out = []
  var count = Math.min(daily.length, 8)
  for (var i = 0; i < count && out.length < limit; i++) {
    var day = daily[i]
    if (!day || typeof day !== "object") continue
    var high = finiteIn(day.air_temp_high, range.temp[0], range.temp[1])
    var low = finiteIn(day.air_temp_low, range.temp[0], range.temp[1])
    if (high === null && low === null) continue
    var month = finiteIn(day.month_num, 1, 12)
    var dayNum = finiteIn(day.day_num, 1, 31)
    var cond = conditionOf(day.conditions)
    out.push({
      month: month === null ? 0 : month,
      day: dayNum === null ? 0 : dayNum,
      high: high,
      low: low,
      icon: iconGlyph(day.icon),
      conditionKey: cond.key,
      conditionText: cond.text,
      precip: finiteIn(day.precip_probability, 0, 100)
    })
  }
  return out
}

// raw is the fetch.py stdout: either the WeatherFlow JSON, or a small
// {"ok":false,"error":"..."} when the request itself failed.
function parseForecast(raw, nowMs, imperial) {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 524288)
    return { ok: false, error: "size" }
  var data
  try {
    data = JSON.parse(raw)
  } catch (e) {
    return { ok: false, error: "unavailable" }
  }
  if (!data || typeof data !== "object" || Array.isArray(data))
    return { ok: false, error: "unavailable" }
  if (data.ok === false) {
    var code = FETCH_ERRORS[data.error] ? data.error : "unavailable"
    return { ok: false, error: code }
  }
  var status = data.status
  if (status && typeof status === "object") {
    var statusCode = Number(status.status_code)
    if (statusCode === 401 || statusCode === 403) return { ok: false, error: "unauthorized" }
    if (statusCode === 404) return { ok: false, error: "notFound" }
    if (isFinite(statusCode) && statusCode > 0) return { ok: false, error: "unavailable" }
  }

  var current = data.current_conditions
  if (!current || typeof current !== "object") return { ok: false, error: "unavailable" }
  var range = bounds(!!imperial)
  var temperature = finiteIn(current.air_temperature, range.temp[0], range.temp[1])
  if (temperature === null) return { ok: false, error: "unavailable" }
  var cond = conditionOf(current.conditions)
  var time = finiteIn(current.time, 1000000000, 4000000000)
  if (time !== null && typeof nowMs === "number" && time > nowMs / 1000 + 3600) time = null

  return {
    ok: true,
    units: imperial ? "imperial" : "metric",
    location: clipText(data.location_name, 48),
    time: time,
    temperature: temperature,
    feelsLike: finiteIn(current.feels_like, range.temp[0], range.temp[1]),
    humidity: finiteIn(current.relative_humidity, 0, 100),
    windAvg: finiteIn(current.wind_avg, range.wind[0], range.wind[1]),
    windGust: finiteIn(current.wind_gust, range.wind[0], range.wind[1]),
    windCardinal: cardinal(current.wind_direction_cardinal),
    pressure: firstNumber(current, ["sea_level_pressure", "barometric_pressure", "station_pressure"], range.pressure[0], range.pressure[1]),
    rainToday: firstNumber(current, ["precip_accum_local_day", "precip_accum_local_day_final"], range.rain[0], range.rain[1]),
    uv: finiteIn(current.uv, 0, 25),
    lightning: firstNumber(current, ["lightning_strike_count_last_3hr", "lightning_strike_count_last_1hr", "lightning_strike_count"], 0, 100000),
    icon: iconGlyph(current.icon),
    conditionKey: cond.key,
    conditionText: cond.text,
    days: parseDays(data.forecast, 3, !!imperial)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    sanitizeStationId: sanitizeStationId,
    sanitizeToken: sanitizeToken,
    normalizeUnits: normalizeUnits,
    useImperial: useImperial,
    refreshSeconds: refreshSeconds,
    iconGlyph: iconGlyph,
    clipText: clipText,
    age: age,
    parseForecast: parseForecast,
    CLOUDY: CLOUDY
  }
}
