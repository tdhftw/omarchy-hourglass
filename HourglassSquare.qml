import QtQuick
import "Model.js" as Model

// The "square" style: not an hourglass at all, but a square of dots that
// fills up, one dot at a time, as the time runs. Dim dots are time still to
// come; lit dots are time gone. While running, the next dot blinks in the
// accent. Below Model.BIG_SIZE it is a 4 by 4 grid of square pixels.
Item {
  id: root

  property real size: 12
  // Share of the time gone, 0..1.
  property real filled: 0
  property color color: "white"
  property color accent: color
  property bool pouring: false
  property real phase: 0

  readonly property var layout: Model.squareLayout(size)
  readonly property int step: Math.floor((phase % 1) * 2)
  readonly property var states: Model.squareStates(size, filled, pouring, step)

  width: layout.width
  height: layout.height
  implicitWidth: width
  implicitHeight: height

  // Holds the icon's bounds to the full frame, so the bar draws the grid at
  // its own size rather than stretching the 11px block to 12.
  Rectangle {
    anchors.fill: parent
    visible: !root.layout.big
    color: "transparent"
  }

  Repeater {
    model: root.layout.cells

    Rectangle {
      required property var modelData
      required property int index
      readonly property int cellState: root.states[index] || 0

      x: modelData.x
      y: modelData.y
      width: modelData.w
      height: modelData.h
      radius: modelData.radius
      antialiasing: modelData.radius > 0
      color: cellState === 2 ? root.accent : root.color
      opacity: cellState === 0 ? root.layout.dim : 1
    }
  }
}
