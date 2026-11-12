import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The popout: a large glass with the time since the flip beneath it, and a
// settings view behind the cog for how long the glass takes to empty. All
// state lives on the bar widget; this only draws it and asks for changes.
//
// Keys: Enter/Space/f = flip · x = reset · t = next style · s = settings
// In settings: Left/Right = one minute · Up/Down = five · t = style · Enter/Esc = back
Panel {
  id: root
  moduleName: "tdh.hourglass"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool settingsOpen: false

  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  // Painted on the popup surface, so it takes the popup's own text colour
  // rather than the bar's wallpaper-adapted one.
  readonly property color foreground: Commons.Color.popups.text
  readonly property color dim: Qt.darker(root.foreground, 1.4)
  // Rest colour for buttons that select. Button fades its fill between
  // states; from the faint selected tint to an opaque background that fade
  // passes through a bright grey, which flashed on every style or preset
  // change. Fully transparent foreground leaves only the alpha to fade.
  readonly property color chipBackground: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0)

  readonly property var glass: root.hostWidget ? root.hostWidget.glass : Model.state(0, Model.DEFAULT_MINUTES, 0)
  readonly property int durationMinutes: root.hostWidget ? root.hostWidget.durationMinutes : Model.DEFAULT_MINUTES
  readonly property real flippedAt: root.hostWidget ? root.hostWidget.flippedAt : 0
  readonly property string glassStyle: root.hostWidget ? root.hostWidget.glassStyle : Model.DEFAULT_STYLE

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function flip() { if (root.hostWidget) root.hostWidget.flip() }
  function reset() { if (root.hostWidget) root.hostWidget.reset() }
  function setDuration(minutes) { if (root.hostWidget) root.hostWidget.setDuration(minutes) }
  function nudgeDuration(delta) { root.setDuration(root.durationMinutes + delta) }
  function setStyle(value) { if (root.hostWidget) root.hostWidget.setStyle(value) }
  function cycleStyle() { root.setStyle(Model.nextStyle(root.glassStyle)) }

  function minutesText(key, minutes) {
    return strings.tn(key, minutes).arg(Commons.I18n.formatNumber(minutes))
  }

  readonly property string caption: {
    if (glass.phase === "running")
      return strings.tn("caption.running", durationMinutes)
        .arg(Model.clock(glass.leftMs)).arg(Commons.I18n.formatNumber(durationMinutes))
    if (glass.phase === "done") return strings.t("caption.done").arg(Model.clock(glass.overMs))
    return minutesText("caption.idle", durationMinutes)
  }

  // Every panel open starts on the glass, not wherever it was left.
  onOpenedChanged: if (!opened) settingsOpen = false

  // A flip turns the glass over: it starts upside down, which is how the old
  // glass looked, and comes round to upright.
  onFlippedAtChanged: {
    if (root.opened && root.flippedAt > 0) turn.restart()
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(264))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.settingsOpen) root.settingsOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: {
        if (root.settingsOpen) root.settingsOpen = false
        else root.flip()
      }
      onDeleteRequested: if (!root.settingsOpen) root.reset()
      onMoveRequested: function(dx, dy) {
        if (!root.settingsOpen) return
        if (dx !== 0) root.nudgeDuration(dx)
        else if (dy !== 0) root.nudgeDuration(-dy * 5)
      }
      onTextKey: function(key) {
        if (key === "s") root.settingsOpen = !root.settingsOpen
        else if (key === "f" && !root.settingsOpen) root.flip()
        else if (key === "t") root.cycleStyle()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, cog.height)

          Label {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("title")
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          PanelActionButton {
            id: cog
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.settingsOpen ? "󰁍" : "󰒓"
            tooltipText: strings.t(root.settingsOpen ? "settings.back" : "settings.open")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            bordered: true
            onClicked: root.settingsOpen = !root.settingsOpen
          }
        }

        // The glass.
        Column {
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.spacing.panelGap

          Item {
            width: parent.width
            height: bigGlass.height + Style.space(8)

            Hourglass {
              id: bigGlass
              anchors.centerIn: parent
              style: root.glassStyle
              size: Style.space(148)
              remaining: root.glass.remaining
              started: root.glass.phase !== "idle"
              pouring: root.opened && root.glass.phase === "running"
              color: root.foreground
              accent: Commons.Color.accent
              opacity: root.glass.phase === "idle" ? 0.5 : 1

              NumberAnimation {
                id: turn
                target: bigGlass
                property: "rotation"
                from: 180
                to: 0
                duration: Style.duration(280)
                easing.type: Easing.Bezier
                easing.bezierCurve: Style.easeOut
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            Label {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Model.clock(root.glass.elapsedMs)
              color: root.glass.phase === "done" && root.bar ? root.bar.urgent : root.foreground
              opacity: root.glass.phase === "idle" ? 0.5 : 1
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              font.features: { "tnum": 1 }
            }

            Label {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.caption
              color: root.dim
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }

          Row {
            id: actions
            width: parent.width
            spacing: Style.spacing.controlGap
            readonly property bool canReset: root.glass.phase !== "idle"

            Button {
              id: flipButton
              width: actions.canReset ? Math.round((actions.width - actions.spacing) * 0.64) : actions.width
              text: strings.t("action.flip")
              iconText: "󰑐"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.flip()
            }

            Button {
              visible: actions.canReset
              width: actions.width - actions.spacing - Math.round((actions.width - actions.spacing) * 0.64)
              // Flip carries an icon, which makes it taller; match it.
              height: flipButton.height
              text: strings.t("action.reset")
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.reset()
            }
          }
        }

        // Settings: how long the glass takes to empty.
        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.spacing.panelGap

          PanelSectionHeader {
            text: strings.t("settings.style")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          ButtonGroup {
            id: styleGroup
            width: parent.width
            focusable: false
            value: root.glassStyle
            foreground: root.foreground
            background: root.chipBackground
            fontFamily: root.fontFamily
            options: [
              { value: "matrix", label: strings.t("style.matrix") },
              { value: "turned", label: strings.t("style.turned") },
              { value: "square", label: strings.t("style.square") }
            ]
            onChanged: function(value) { root.setStyle(value) }
          }

          PanelSectionHeader {
            text: strings.t("settings.heading")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: stepper
            width: parent.width
            spacing: Style.spacing.controlGap
            readonly property real stepWidth: Style.space(40)

            Button {
              width: stepper.stepWidth
              text: "−"
              bordered: true
              enabled: root.durationMinutes > Model.MIN_MINUTES
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.nudgeDuration(-1)
            }

            Label {
              width: stepper.width - (stepper.stepWidth + stepper.spacing) * 2
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: root.minutesText("settings.minutes", root.durationMinutes)
              font.pixelSize: Style.font.heading
              font.bold: true
            }

            Button {
              width: stepper.stepWidth
              text: "+"
              bordered: true
              enabled: root.durationMinutes < Model.MAX_MINUTES
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.nudgeDuration(1)
            }
          }

          Row {
            id: presets
            width: parent.width
            spacing: Style.spacing.md

            Repeater {
              model: Model.PRESETS

              Button {
                required property int modelData
                width: (presets.width - presets.spacing * (Model.PRESETS.length - 1)) / Model.PRESETS.length
                text: Commons.I18n.formatNumber(modelData)
                tooltipText: strings.t("settings.presetMinutes").arg(Commons.I18n.formatNumber(modelData))
                selected: root.durationMinutes === modelData
                bordered: true
                background: root.chipBackground
                horizontalPadding: Style.spacing.sm
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.setDuration(modelData)
              }
            }
          }

          Label {
            width: parent.width
            text: strings.t("settings.hint")
            color: root.dim
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Button {
            width: parent.width
            text: strings.t("action.done")
            iconText: "󰄬"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.settingsOpen = false
          }
        }
      }
    }
  }
}
