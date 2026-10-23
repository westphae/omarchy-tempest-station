import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar pill and popup for one WeatherFlow Tempest. The station ID lives in
// this widget's shell.json entry. The personal access token does not: it is
// written to ~/.config/omarchy/tempest-token mode 600, and fetch.py reads
// that file itself so the token is never placed on a command line.
Panel {
  id: root
  moduleName: "eric.tempest"
  ipcTarget: "eric.tempest"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string stationId: Model.sanitizeStationId(setting("stationId", ""))
  readonly property int refreshEvery: Model.refreshSeconds(setting("refreshSeconds", 60))
  readonly property bool imperial: Model.useImperial(setting("units", "auto"), Commons.I18n.formatLocale)
  readonly property string unitsName: imperial ? "imperial" : "metric"
  readonly property string unitLetter: imperial ? "F" : "C"

  property string token: ""
  property bool editing: false
  property string formError: ""
  property string errorCode: ""
  property var report: null
  property double nowMs: Date.now()
  property string pendingStation: ""
  property string fetchStation: ""
  property bool fetchImperial: false
  property bool fetchQueued: false

  readonly property bool ready: stationId !== "" && token !== ""
  readonly property bool showForm: !ready || editing
  readonly property var shown: report && report.ok === true && report.units === unitsName ? report : null
  readonly property string iconGlyph: shown ? shown.icon : Model.CLOUDY
  readonly property string tempText: shown ? Commons.I18n.formatNumber(Math.round(shown.temperature)) + "\u00b0" : ""
  readonly property string tempWithUnit: tempText === "" ? "" : tempText + unitLetter
  readonly property string conditionLabel: {
    var language = strings.language
    if (!shown) return ""
    if (shown.conditionKey) return strings.t(shown.conditionKey)
    return shown.conditionText || ""
  }
  readonly property string tooltipLabel: {
    var language = strings.language
    if (!ready) return strings.t("tooltip.setup")
    if (!shown) return strings.t("tooltip.loading")
    var parts = []
    if (tempWithUnit !== "") parts.push(tempWithUnit)
    if (conditionLabel !== "") parts.push(conditionLabel)
    if (shown.location) parts.push(shown.location)
    return parts.join(" \u00b7 ")
  }
  readonly property var stats: buildStats()
  readonly property string ageLabel: buildAgeLabel()
  readonly property string errorLabel: buildErrorLabel()

  function fileUrl(url) {
    var text = String(url || "")
    if (text.indexOf("file://") !== 0) return text
    return decodeURIComponent(text.slice(7))
  }

  readonly property string fetchScript: fileUrl(Qt.resolvedUrl("fetch.py"))
  readonly property string saveScript: fileUrl(Qt.resolvedUrl("save-token.py"))

  function open() {
    editing = false
    formError = ""
    root.controller.show()
    refresh()
  }

  function refresh() { refreshDebounce.restart() }

  function fetchNow() {
    if (!ready) {
      if (!shown) errorCode = stationId === "" ? "config" : "token"
      return
    }
    if (fetchProc.running) {
      fetchQueued = true
      return
    }
    fetchStation = stationId
    fetchImperial = imperial
    fetchProc.command = ["/usr/bin/python3", fetchScript, stationId, unitsName]
    fetchProc.running = true
  }

  function ingest(raw) {
    if (fetchStation !== stationId || fetchImperial !== imperial) return
    var parsed = Model.parseForecast(String(raw || ""), Date.now(), fetchImperial)
    if (!parsed || parsed.ok !== true) {
      errorCode = parsed && parsed.error ? parsed.error : "unavailable"
      return
    }
    report = parsed
    errorCode = ""
    nowMs = Date.now()
  }

  function persist(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id" && existing !== "token") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    delete entry.token
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveForm() {
    var content = panel.loadedContent
    if (!content || saveProc.running) return
    var station = Model.sanitizeStationId(content.stationField.text)
    if (!station) {
      formError = strings.t("form.stationInvalid")
      return
    }
    var typed = String(content.tokenField.text || "").replace(/^\s+|\s+$/g, "")
    if (typed === "" && token !== "") {
      formError = ""
      content.tokenField.text = ""
      persist({ stationId: station })
      editing = false
      refresh()
      return
    }
    if (!Model.sanitizeToken(typed)) {
      formError = strings.t("form.tokenInvalid")
      return
    }
    formError = ""
    pendingStation = station
    content.tokenField.text = ""
    saveProc.environment = ({ TEMPEST_TOKEN: typed, HOME: Quickshell.env("HOME") })
    saveProc.command = ["/usr/bin/python3", saveScript]
    saveProc.running = true
  }

  function fillForm() {
    var content = panel.loadedContent
    if (!content || !content.stationField) return
    content.stationField.text = stationId
  }

  function notify() {
    if (!shown) return
    var body = tempWithUnit
    if (conditionLabel !== "") body = body === "" ? conditionLabel : body + " \u00b7 " + conditionLabel
    if (shown.location) body = body === "" ? shown.location : body + " \u00b7 " + shown.location
    if (body.length > 180) body = body.slice(0, 180)
    Util.execArgv(["omarchy-notification-send", "Tempest", body])
  }

  function cycleUnits() {
    persist({ units: imperial ? "metric" : "imperial" })
  }

  function numberText(value, decimals) {
    if (value === null || value === undefined) return ""
    if (decimals === undefined) return Commons.I18n.formatNumber(Math.round(value))
    return Commons.I18n.formatNumber(value, decimals)
  }

  function buildStats() {
    var language = strings.language
    if (!shown) return []
    var out = []
    function add(label, value) { if (value !== "") out.push({ label: label, value: value }) }
    if (shown.feelsLike !== null) add(strings.t("stat.feels"), numberText(shown.feelsLike) + "\u00b0" + unitLetter)
    if (shown.windAvg !== null) {
      var wind = numberText(shown.windAvg)
      if (shown.windGust !== null && shown.windGust > shown.windAvg) wind += "\u2013" + numberText(shown.windGust)
      wind += imperial ? " mph" : " km/h"
      if (shown.windCardinal) wind += " " + shown.windCardinal
      add(strings.t("stat.wind"), wind)
    }
    if (shown.humidity !== null) add(strings.t("stat.humidity"), numberText(shown.humidity) + "%")
    if (shown.pressure !== null) add(strings.t("stat.pressure"), numberText(shown.pressure, imperial ? 2 : 0) + (imperial ? " inHg" : " hPa"))
    if (shown.rainToday !== null) add(strings.t("stat.rain"), numberText(shown.rainToday, imperial ? 2 : 1) + (imperial ? " in" : " mm"))
    if (shown.uv !== null) add(strings.t("stat.uv"), numberText(shown.uv))
    if (shown.lightning !== null && shown.lightning > 0) add(strings.t("stat.lightning"), numberText(shown.lightning))
    return out
  }

  function buildAgeLabel() {
    var language = strings.language
    if (!shown || shown.time === null) return ""
    var age = Model.age(shown.time, nowMs)
    if (age.unit === "now") return strings.t("updated.justNow")
    if (age.unit === "minute") return strings.tn("updated.minutes", age.count).arg(Commons.I18n.formatNumber(age.count))
    if (age.unit === "hour") return strings.tn("updated.hours", age.count).arg(Commons.I18n.formatNumber(age.count))
    return ""
  }

  function buildErrorLabel() {
    var language = strings.language
    if (!errorCode || errorCode === "config") return ""
    if (errorCode === "network") return strings.t(shown ? "error.stale" : "error.network")
    if (errorCode === "unauthorized") return strings.t("error.unauthorized")
    if (errorCode === "notFound") return strings.t("error.notFound")
    if (errorCode === "token") return strings.t("error.token")
    return strings.t("error.unavailable")
  }

  function dayLabel(day, index) {
    var language = strings.language
    var localeName = Commons.I18n.formatLocale
    if (!day) return ""
    if (index === 0) return strings.t("day.today")
    if (!day.month || !day.day) return ""
    var year = new Date(nowMs).getFullYear()
    var date = new Date(year, day.month - 1, day.day)
    if (date.getTime() < nowMs - 200 * 86400000) date = new Date(year + 1, day.month - 1, day.day)
    return Qt.locale(localeName).standaloneDayName(date.getDay(), Locale.ShortFormat)
  }

  function dayTemp(day) {
    if (!day) return ""
    var high = day.high === null || day.high === undefined ? "" : numberText(day.high) + "\u00b0"
    var low = day.low === null || day.low === undefined ? "" : numberText(day.low) + "\u00b0"
    if (high !== "" && low !== "") return high + " / " + low
    return high || low
  }

  onStationIdChanged: refresh()
  onTokenChanged: refresh()
  onImperialChanged: {
    report = null
    refresh()
  }
  onEditingChanged: if (editing) Qt.callLater(fillForm)
  onShowFormChanged: if (showForm) Qt.callLater(fillForm)

  FileView {
    id: tokenFile
    path: Quickshell.env("HOME") + "/.config/omarchy/tempest-token"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.token = Model.sanitizeToken(text())
    onLoadFailed: root.token = ""
  }

  Timer {
    interval: 1500
    running: true
    onTriggered: tokenFile.reload()
  }

  Timer {
    id: refreshDebounce
    interval: 200
    onTriggered: root.fetchNow()
  }

  Timer {
    interval: root.refreshEvery * 1000
    running: root.ready
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    running: root.shown !== null
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(text)
    }
    onExited: {
      if (!root.fetchQueued) return
      root.fetchQueued = false
      Qt.callLater(root.fetchNow)
    }
  }

  Process {
    id: saveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = String(text || "").replace(/^\s+|\s+$/g, "")
        if (result === "ok") {
          root.formError = ""
          root.persist({ stationId: root.pendingStation })
          root.editing = false
          root.pendingStation = ""
          tokenFile.reload()
        } else if (result === "invalid") {
          root.formError = strings.t("form.tokenInvalid")
        } else if (result !== "") {
          root.formError = strings.t("form.saveFailed")
        }
      }
    }
    onExited: function(exitCode) {
      saveProc.environment = ({})
      if (exitCode !== 0 && root.formError === "") root.formError = strings.t("form.saveFailed")
    }
  }

  TextMetrics {
    id: tempMetrics
    font.family: fontFamily
    font.pixelSize: Style.bar.iconFont
    text: root.tempText === "" ? "00\u00b0" : root.tempText
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    labelText: vertical || root.tempText === "" ? "" : root.tempText
    slotSize: Style.bar.iconSlot + (vertical || root.tempText === "" ? 0 : Math.ceil(tempMetrics.advanceWidth) + Style.space(6))
    tooltipText: root.tooltipLabel
    onPressed: function(b) {
      if (b === Qt.RightButton) root.notify()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias stationField: stationField
      property alias tokenField: tokenField
      anchors.fill: parent
      implicitHeight: flick.contentHeight
      blocked: root.showForm && (stationField.activeFocus || tokenField.activeFocus)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" && !root.showForm) root.refresh() }
      Component.onCompleted: root.fillForm()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: column
          width: flick.width
          spacing: Style.space(14)

          Column {
            visible: root.showForm
            width: parent.width
            spacing: Style.space(10)

            Text {
              textFormat: Text.PlainText
              text: strings.t("setup.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: strings.t("setup.body")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: stationField
              width: parent.width
              placeholderText: strings.t("form.stationId")
              foreground: root.foreground
              font.family: root.fontFamily
              inputMethodHints: Qt.ImhDigitsOnly
              Keys.onEscapePressed: function(event) {
                if (root.ready) root.editing = false
                else root.close()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) { root.saveForm(); event.accepted = true }
            }

            TextField {
              id: tokenField
              width: parent.width
              password: true
              placeholderText: root.token !== "" ? strings.t("form.tokenSaved") : strings.t("form.token")
              foreground: root.foreground
              font.family: root.fontFamily
              Keys.onEscapePressed: function(event) {
                if (root.ready) root.editing = false
                else root.close()
                event.accepted = true
              }
              Keys.onReturnPressed: function(event) { root.saveForm(); event.accepted = true }
            }

            Text {
              visible: root.formError !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.formError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Button {
              text: strings.t("form.save")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.saveForm()
            }
          }

          Column {
            visible: !root.showForm
            width: parent.width
            spacing: Style.space(14)

            Item {
              width: parent.width
              height: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

              Text {
                id: heroIcon
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.iconGlyph
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 48
              }

              Column {
                id: heroText
                anchors.left: heroIcon.right
                anchors.leftMargin: Style.space(14)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(2)
                  LayoutMirroring.enabled: false

                  Text {
                    id: tempBig
                    textFormat: Text.PlainText
                    text: root.tempText === "" ? "\u2014" : root.tempText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 42
                    font.bold: true
                  }
                  Text {
                    visible: root.tempText !== ""
                    textFormat: Text.PlainText
                    text: root.unitLetter
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                    anchors.top: tempBig.top
                    anchors.topMargin: Style.space(8)
                  }
                }

                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.shown && root.shown.location ? root.shown.location : "Tempest"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                  font.capitalization: Font.AllUppercase
                }

                Text {
                  visible: root.conditionLabel !== ""
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: root.conditionLabel
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            Text {
              visible: root.errorLabel !== ""
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.errorLabel
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Flow {
              visible: root.stats.length > 0
              width: parent.width
              spacing: Style.space(18)

              Repeater {
                model: root.stats
                delegate: Column {
                  required property var modelData
                  spacing: Style.space(4)
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.letterSpacing: 1
                    font.capitalization: Font.AllUppercase
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.value
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                  }
                }
              }
            }

            Row {
              visible: root.shown && root.shown.days && root.shown.days.length > 0
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: root.shown ? root.shown.days : []
                delegate: Column {
                  required property var modelData
                  required property int index
                  width: Math.floor((parent.width - Style.space(16)) / 3)
                  spacing: Style.space(3)

                  Text {
                    textFormat: Text.PlainText
                    text: root.dayLabel(modelData, index)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.capitalization: Font.AllUppercase
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: modelData.icon
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: root.dayTemp(modelData)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    visible: modelData.precip !== null && modelData.precip !== undefined
                    textFormat: Text.PlainText
                    text: modelData.precip === null || modelData.precip === undefined ? "" : root.numberText(modelData.precip) + "%"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(12)

              Text {
                textFormat: Text.PlainText
                text: root.ageLabel
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: "\u00b0" + root.unitLetter
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter

                TapHandler { onTapped: root.cycleUnits() }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
              }

              Text {
                textFormat: Text.PlainText
                text: strings.t("change")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: parent.verticalCenter

                TapHandler { onTapped: root.editing = true }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
              }
            }
          }
        }
      }
    }
  }
}
