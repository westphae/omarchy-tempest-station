"use strict"

const assert = require("assert")
const Model = require("../Model.js")

function test(name, fn) {
  try {
    fn()
    console.log("ok " + name)
  } catch (error) {
    console.error("fail " + name)
    console.error(error.stack || error)
    process.exitCode = 1
  }
}

const now = 1672431870000

const sample = JSON.stringify({
  location_name: "Backyard",
  current_conditions: {
    time: 1672431810,
    conditions: "Partly Cloudy",
    icon: "partly-cloudy-night",
    air_temperature: 15.2,
    feels_like: 14,
    sea_level_pressure: 1025.8,
    relative_humidity: 92,
    wind_avg: 5,
    wind_gust: 8,
    wind_direction_cardinal: "W",
    uv: 0,
    precip_accum_local_day: 1.5,
    lightning_strike_count_last_3hr: 2
  },
  forecast: {
    daily: [
      { month_num: 12, day_num: 30, air_temp_high: 20, air_temp_low: 12, icon: "cloudy", conditions: "Cloudy", precip_probability: 10 },
      { month_num: 12, day_num: 31, air_temp_high: 18, air_temp_low: 11, icon: "rainy", conditions: "Rain Likely", precip_probability: 70 },
      { month_num: 1, day_num: 1, air_temp_high: 17, air_temp_low: 9, icon: "clear-day", conditions: "Clear", precip_probability: 0 },
      { month_num: 1, day_num: 2, air_temp_high: 16, air_temp_low: 8, icon: "clear-day", conditions: "Clear", precip_probability: 0 }
    ]
  }
})

test("parses a station reading and keeps three days", () => {
  const report = Model.parseForecast(sample, now, false)
  assert.strictEqual(report.ok, true)
  assert.strictEqual(report.units, "metric")
  assert.strictEqual(report.location, "Backyard")
  assert.strictEqual(report.temperature, 15.2)
  assert.strictEqual(report.feelsLike, 14)
  assert.strictEqual(report.humidity, 92)
  assert.strictEqual(report.windAvg, 5)
  assert.strictEqual(report.windGust, 8)
  assert.strictEqual(report.windCardinal, "W")
  assert.strictEqual(report.pressure, 1025.8)
  assert.strictEqual(report.rainToday, 1.5)
  assert.strictEqual(report.uv, 0)
  assert.strictEqual(report.lightning, 2)
  assert.strictEqual(report.conditionKey, "cond.partlyCloudy")
  assert.strictEqual(report.conditionText, "")
  assert.strictEqual(report.icon, "\ue32e")
  assert.strictEqual(report.days.length, 3)
  assert.strictEqual(report.days[1].conditionKey, "cond.rainLikely")
  assert.strictEqual(report.days[1].icon, "\ue318")
})

test("keeps markup as text and will not use it as an icon", () => {
  const markup = '<img src="https://example.invalid/tracker">'
  const report = Model.parseForecast(JSON.stringify({
    location_name: markup,
    current_conditions: {
      time: 1672431810,
      conditions: markup,
      icon: markup,
      air_temperature: 20
    }
  }), now, false)
  assert.strictEqual(report.ok, true)
  assert.ok(report.location.indexOf("<img") === 0)
  assert.strictEqual(report.conditionKey, "")
  assert.ok(report.conditionText.indexOf("<img") === 0)
  assert.strictEqual(report.icon, Model.CLOUDY)
  assert.ok(report.icon.indexOf("<") === -1)
})

test("drops out-of-range numbers and unknown compass points", () => {
  const report = Model.parseForecast(JSON.stringify({
    location_name: "Yard",
    current_conditions: {
      time: 1672431810,
      conditions: "Clear",
      icon: "clear-day",
      air_temperature: 21,
      relative_humidity: 140,
      wind_avg: 3,
      wind_direction_cardinal: "<script>",
      sea_level_pressure: 10,
      uv: 80
    }
  }), now, false)
  assert.strictEqual(report.ok, true)
  assert.strictEqual(report.humidity, null)
  assert.strictEqual(report.windCardinal, "")
  assert.strictEqual(report.pressure, null)
  assert.strictEqual(report.uv, null)
})

test("rejects a reading with no temperature", () => {
  const report = Model.parseForecast(JSON.stringify({
    current_conditions: { time: 1672431810, conditions: "Clear", icon: "clear-day" }
  }), now, false)
  assert.strictEqual(report.ok, false)
  assert.strictEqual(report.error, "unavailable")
})

test("maps WeatherFlow status codes without keeping the message", () => {
  const denied = Model.parseForecast(JSON.stringify({
    status: { status_code: 401, status_message: "UNAUTHORIZED token=secret" }
  }), now, false)
  assert.strictEqual(denied.error, "unauthorized")
  assert.strictEqual(JSON.stringify(denied).indexOf("secret"), -1)
  const missing = Model.parseForecast(JSON.stringify({
    status: { status_code: 404, status_message: "not found" }
  }), now, false)
  assert.strictEqual(missing.error, "notFound")
})

test("passes through fetch failures and rejects a huge body", () => {
  assert.strictEqual(Model.parseForecast('{"ok":false,"error":"network"}', now, false).error, "network")
  assert.strictEqual(Model.parseForecast('{"ok":false,"error":"token"}', now, true).error, "token")
  assert.strictEqual(Model.parseForecast("{" + "a".repeat(600000), now, false).error, "size")
})

test("station id and token stay in a safe alphabet", () => {
  assert.strictEqual(Model.sanitizeStationId(" 12345 "), "12345")
  assert.strictEqual(Model.sanitizeStationId(12345), "12345")
  assert.strictEqual(Model.sanitizeStationId("12345;rm"), "")
  assert.strictEqual(Model.sanitizeStationId("123\n45"), "")
  assert.strictEqual(Model.sanitizeStationId(""), "")
  assert.strictEqual(Model.sanitizeToken("abcd-ef_12"), "abcd-ef_12")
  assert.strictEqual(Model.sanitizeToken("short"), "")
  assert.strictEqual(Model.sanitizeToken("abcd efgh"), "")
  assert.strictEqual(Model.sanitizeToken("abcd\"efgh"), "")
  assert.strictEqual(Model.sanitizeToken("abcd\nefgh"), "")
})

test("units follow the setting, then the locale", () => {
  assert.strictEqual(Model.useImperial("imperial", "da"), true)
  assert.strictEqual(Model.useImperial("metric", "en-US"), false)
  assert.strictEqual(Model.useImperial("auto", "en-US"), true)
  assert.strictEqual(Model.useImperial("auto", "en_US.UTF-8"), true)
  assert.strictEqual(Model.useImperial("auto", "da"), false)
  assert.strictEqual(Model.normalizeUnits("nope"), "auto")
  assert.strictEqual(Model.refreshSeconds("15"), 30)
  assert.strictEqual(Model.refreshSeconds("90"), 90)
  assert.strictEqual(Model.refreshSeconds("99999"), 1800)
})

test("age buckets", () => {
  assert.strictEqual(Model.age(now / 1000 - 20, now).unit, "now")
  assert.strictEqual(Model.age(now / 1000 - 120, now).unit, "minute")
  assert.strictEqual(Model.age(now / 1000 - 120, now).count, 2)
  assert.strictEqual(Model.age(now / 1000 - 7200, now).unit, "hour")
  assert.strictEqual(Model.age(now / 1000 - 7200, now).count, 2)
})

test("imperial bounds drop a metric pressure", () => {
  const report = Model.parseForecast(sample, now, true)
  assert.strictEqual(report.units, "imperial")
  assert.strictEqual(report.pressure, null)
  assert.strictEqual(report.temperature, 15.2)
})
