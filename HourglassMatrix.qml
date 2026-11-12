import QtQuick
import "Model.js" as Model

// The "dot matrix" glass: no outline, just a grid of cells. Dim cells are
// empty glass, lit cells are sand, and as many light up below as go dark
// above. While running, the neck and the falling grains take the accent.
// Below Model.BIG_SIZE it becomes a square-pixel glyph that only moves whole
// rows; drawn 12px tall that is one cell per pixel.
Item {
  id: root

  property real size: 12
  property real remaining: 0
  property color color: "white"
  property color accent: color
  property bool pouring: false
  property real phase: 0

  readonly property var layout: Model.matrixLayout(size)
  readonly property int step: Math.floor((phase % 1) * 2)
  readonly property var states: Model.matrixStates(size, remaining, pouring, step)

  width: layout.width
  height: size
  implicitWidth: width
  implicitHeight: height

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
