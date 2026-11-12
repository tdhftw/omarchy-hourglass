import QtQuick
import qs.Commons
import "Model.js" as Model

// The glass in whichever style is chosen: "matrix" (HourglassMatrix.qml),
// "turned" (HourglassTurned.qml) or "square" (HourglassSquare.qml). Used both
// as the 12px bar icon and as the large glass in the panel; each style draws a
// simplified form when small.
// `remaining` is the share of the sand still in the top bulb, 1 down to 0.
Item {
  id: root

  property string style: Model.DEFAULT_STYLE
  property real size: 16
  property real remaining: 0
  // False until the glass is first flipped. The hourglasses read an unflipped
  // glass as all sand below; the square reads it as empty.
  property bool started: true
  property color color: "white"
  property color accent: color
  // Draws the falling sand while the glass runs.
  property bool pouring: false
  // 0..1 through one fall of the grains; loops while pouring in a large glass.
  property real phase: 0

  readonly property string resolvedStyle: Model.style(style)
  readonly property bool animating: pouring && visible && size >= Model.BIG_SIZE && !Style.reduceMotion

  width: glass.item ? glass.item.width : 0
  height: glass.item ? glass.item.height : size
  implicitWidth: width
  implicitHeight: height

  // Constant motion, so linear by design.
  NumberAnimation on phase {
    from: 0
    to: 1
    duration: 900
    loops: Animation.Infinite
    running: root.animating
  }

  Loader {
    id: glass
    sourceComponent: root.resolvedStyle === "turned" ? turned
      : (root.resolvedStyle === "square" ? square : matrix)
  }

  Component {
    id: turned
    HourglassTurned {
      size: root.size
      remaining: root.remaining
      color: root.color
      pouring: root.pouring
      phase: root.phase
    }
  }

  Component {
    id: matrix
    HourglassMatrix {
      size: root.size
      remaining: root.remaining
      color: root.color
      accent: root.accent
      pouring: root.pouring
      phase: root.phase
    }
  }

  Component {
    id: square
    HourglassSquare {
      size: root.size
      filled: root.started ? 1 - root.remaining : 0
      color: root.color
      accent: root.accent
      pouring: root.pouring
      phase: root.phase
    }
  }
}
