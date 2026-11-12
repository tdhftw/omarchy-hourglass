import QtQuick
import QtQuick.Shapes
import "Model.js" as Model

// The "turned" glass: curved bulbs with a real waist, slab caps and two slim
// posts with a ring. Sand dips as it drains and mounds as it lands. Below
// Model.BIG_SIZE the posts and slabs drop out and the sand sits flat.
Item {
  id: root

  property real size: 16
  property real remaining: 0
  property color color: "white"
  property bool pouring: false
  property real phase: 0

  readonly property var glass: Model.turnedGlass(size)
  readonly property var sand: Model.turnedSand(size, remaining)
  readonly property color sandColor: Qt.rgba(color.r, color.g, color.b, color.a * (glass.big ? 0.92 : 1))
  readonly property bool streaming: pouring && sand.top !== null

  // An empty bulb collapses to a point at the centre, which keeps the bar's
  // icon bounds measuring the glass alone.
  function points(list) {
    if (!list || list.length === 0) return [Qt.point(width / 2, size / 2)]
    var out = []
    for (var i = 0; i < list.length; i++) out.push(Qt.point(list[i].x, list[i].y))
    return out
  }

  width: glass.width
  height: size
  implicitWidth: width
  implicitHeight: height

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.sand.top ? root.sandColor : "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      PathPolyline { path: root.points(root.sand.top) }
    }

    ShapePath {
      fillColor: root.sand.bottom ? root.sandColor : "transparent"
      strokeColor: "transparent"
      strokeWidth: 0
      PathPolyline { path: root.points(root.sand.bottom) }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.streaming ? root.sandColor : "transparent"
      strokeWidth: Math.max(1, root.glass.sw * 0.7)
      capStyle: ShapePath.FlatCap
      startX: root.width / 2
      startY: root.sand.streamFrom
      PathLine { x: root.width / 2; y: root.sand.streamTo }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.glass.sw
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.FlatCap
      PathSvg { path: root.glass.outline }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.glass.sw
      joinStyle: ShapePath.MiterJoin
      capStyle: ShapePath.FlatCap
      PathSvg { path: root.glass.caps }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.glass.posts !== "" ? Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.5) : "transparent"
      strokeWidth: root.glass.sw
      capStyle: ShapePath.FlatCap
      PathSvg { path: root.glass.posts !== "" ? root.glass.posts : "M0,0" }
    }
  }

  Repeater {
    model: root.streaming && root.glass.big ? Model.turnedGrains(root.size, root.sand, root.phase) : []

    Rectangle {
      required property var modelData
      x: modelData.x - modelData.r
      y: modelData.y - modelData.r
      width: modelData.r * 2
      height: width
      radius: modelData.r
      color: root.sandColor
    }
  }
}
