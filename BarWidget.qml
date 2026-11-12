import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The hourglass in the bar. It owns the state: when the glass was flipped and
// how long it takes to empty both live in this widget's shell.json entry, so
// they survive a restart and every monitor's bar shows the same glass.
//
// left = panel · right = flip
BarWidget {
  id: root
  moduleName: "tdh.hourglass"

  // The icon moves in quarters; the panel shows the fine-grained glass.
  readonly property int iconChunks: 4

  property real nowMs: Date.now()
  // Values this widget has just written, which win over what comes back from
  // shell.json until the write has settled. The shell re-reads the file after
  // each save, so two quick changes (pressing t twice) would otherwise see the
  // first save's re-read land after the second change and flick back to it.
  property var pending: ({})

  readonly property int durationMinutes: Model.duration(current("durationMinutes", Model.DEFAULT_MINUTES))
  readonly property string glassStyle: Model.style(current("style", Model.DEFAULT_STYLE))
  readonly property real flippedAt: Model.flippedAt(current("flippedAt", 0))
  // The flip whose run-out has already been announced, so each flip notifies
  // once, across restarts and across the bars on several monitors.
  readonly property real notifiedFor: Model.flippedAt(current("notifiedFor", 0))
  readonly property var glass: Model.state(flippedAt, durationMinutes, nowMs)
  readonly property real iconRemaining: Model.chunked(glass.remaining, iconChunks)

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function tick() { nowMs = Date.now() }

  function current(name, fallback) {
    return name in root.pending ? root.pending[name] : setting(name, fallback)
  }

  // Applied locally first so the glass turns on the click itself; the
  // shell.json write comes back through the bar as the same value.
  function persistSettings(values) {
    var nextPending = {}
    for (var p in root.pending) nextPending[p] = root.pending[p]
    for (var v in values) nextPending[v] = values[v]
    root.pending = nextPending
    settle.restart()

    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in nextPending) entry[key] = nextPending[key]

    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function flip() {
    tick()
    persistSettings({ flippedAt: root.nowMs })
  }

  function reset() {
    persistSettings({ flippedAt: 0 })
  }

  function setDuration(minutes) {
    var next = Model.duration(minutes)
    if (next !== root.durationMinutes) persistSettings({ durationMinutes: next })
  }

  // One bar per monitor runs this widget; only the first one announces.
  function isLeader() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : []
    return !items || items.length === 0 || items[0] === root
  }

  // Runs when the alarm fires and on every tick, so a run-out missed while
  // the machine slept is still announced on wake.
  function checkRunOut(quietIfOld) {
    tick()
    if (glass.phase !== "done" || root.flippedAt === 0 || root.notifiedFor === root.flippedAt) return
    if (!isLeader()) return
    persistSettings({ notifiedFor: root.flippedAt })
    // A glass that ran out long before the shell started is old news.
    if (quietIfOld && glass.overMs > Model.STALE_RUN_OUT_MS) return
    notify()
  }

  // Critical, because Omarchy's notification daemon keeps only critical
  // notifications on screen until dismissed; it ignores a "never expire"
  // timeout. Do Not Disturb still holds it back, since that only lets
  // critical through for Omarchy's own senders.
  function notify() {
    var minutes = root.durationMinutes
    Util.execArgv([
      "omarchy-notification-send",
      "--app-name", strings.t("title"),
      "-g", "󰔟",
      "-u", "critical",
      strings.t("notify.title"),
      strings.tn("notify.body", minutes).arg(Commons.I18n.formatNumber(minutes))
    ])
  }

  function setStyle(value) {
    var next = Model.style(value)
    if (next !== root.glassStyle) persistSettings({ style: next })
  }

  function tooltip() {
    if (glass.phase === "running") {
      var left = Model.minutesLeft(glass.leftMs)
      return strings.tn("tooltip.running", left).arg(Commons.I18n.formatNumber(left))
    }
    return strings.t(glass.phase === "done" ? "tooltip.done" : "tooltip.idle")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The first check waits for the bar, which carries the shell.json write and
  // the list of sibling widgets on other monitors.
  property bool startupChecked: false
  onBarChanged: {
    injectPanel()
    if (root.bar && !root.startupChecked) {
      root.startupChecked = true
      Qt.callLater(root.checkRunOut, true)
    }
  }
  onOpenedChanged: if (opened) tick()
  onFlippedAtChanged: tick()

  // Fires the moment the sand runs out, however long the glass is set for.
  // Rebuilt whenever the flip or the duration changes.
  Timer {
    id: alarm
    interval: Math.max(50, root.glass.leftMs + 50)
    running: root.glass.phase === "running"
    repeat: false
    onTriggered: root.checkRunOut(false)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // By now every re-read of shell.json from our own writes has come back.
  Timer {
    id: settle
    interval: 1500
    onTriggered: root.pending = ({})
  }

  // Once a second while the panel is watching; otherwise only often enough
  // to move the icon a quarter at a time. Stopped while nothing is falling.
  Timer {
    interval: root.opened ? 1000 : 5000
    running: root.glass.phase === "running" || (root.opened && root.glass.phase === "done")
    repeat: true
    onTriggered: root.checkRunOut(false)
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltip()
    // Run out reads as the bar's active colour until the glass is flipped
    // or reset; a glass that was never flipped stays quiet.
    active: root.glass.phase === "done"
    dimmed: root.glass.phase === "idle"
    iconComponent: Component {
      Item {
        // Drawn at the bar's icon size so the bar never rescales it, which
        // keeps the dot-matrix glyph on whole pixels.
        Hourglass {
          anchors.centerIn: parent
          style: root.glassStyle
          size: Style.bar.iconSize
          remaining: root.iconRemaining
          started: root.glass.phase !== "idle"
          color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) root.flip()
    }
  }
}
