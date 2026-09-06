import QtQuick
import qs.Commons
import "PaletteData.js" as PaletteData

// A row of palette circles that morphs into one continuous capsule.
//
// morph 0 -> discrete circles separated by `gap`
// morph 1 -> each cell spans a full pitch, so neighbours abut and the inner
//            corners have flattened out: the row reads as a single stripe of
//            the palette. Cells animate with a per-index delay, so the merge
//            travels along the row instead of snapping.
//
// The row's footprint never changes (both states measure count * pitch), so a
// morph inside the bar cannot reflow the widgets next to it.
Item {
  id: root

  property var colors: []
  // Surface the row is painted on. Set it and every swatch is checked against
  // it, so a palette that matches its own background stays visible.
  property color surface: "transparent"
  readonly property bool surfaceKnown: surface.a > 0.35
  readonly property var paintColors: surfaceKnown
    ? PaletteData.visibleList(colors, PaletteData.toHex([surface.r, surface.g, surface.b]))
    : (colors ? colors : [])
  property real dotSize: 7
  property real gap: Math.max(1, Math.round(dotSize * 0.45))
  property bool morphed: false
  // Extra thickness at full morph, as a ratio of dotSize.
  property real bulge: 0.5
  property int stagger: 26
  property int duration: 240
  property bool interactive: false
  property int hoveredIndex: -1

  signal dotActivated(int index, string color)

  readonly property int count: paintColors.length
  readonly property real pitch: dotSize + gap

  implicitWidth: count > 0 ? count * pitch : 0
  implicitHeight: Math.round(dotSize * (1 + bulge))

  onInteractiveChanged: if (!interactive) hoveredIndex = -1

  Repeater {
    model: root.count

    Rectangle {
      id: cell

      readonly property bool isFirst: index === 0
      readonly property bool isLast: index === root.count - 1
      readonly property bool hovered: root.interactive && root.hoveredIndex === index

      // Animated 0..1+ morph. `merge` is clamped for geometry that has to line
      // up exactly; the raw value keeps its overshoot for the thickness pop.
      property real morph: root.morphed || hovered ? 1 : 0
      readonly property real merge: Math.max(0, Math.min(1, morph))
      readonly property real thickness: root.dotSize * (1 + root.bulge * Math.max(0, morph))
      readonly property real endRadius: thickness / 2
      readonly property real innerRadius: endRadius * (1 - merge)

      x: index * root.pitch + (root.gap / 2) * (1 - merge)
      y: (root.height - thickness) / 2
      width: root.dotSize + (root.pitch - root.dotSize) * merge
      height: thickness
      antialiasing: true
      color: root.paintColors[index] !== undefined ? root.paintColors[index] : Color.muted

      topLeftRadius: isFirst ? endRadius : innerRadius
      bottomLeftRadius: isFirst ? endRadius : innerRadius
      topRightRadius: isLast ? endRadius : innerRadius
      bottomRightRadius: isLast ? endRadius : innerRadius

      Behavior on morph {
        SequentialAnimation {
          PauseAnimation { duration: index * root.stagger }
          NumberAnimation {
            duration: root.duration
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
          }
        }
      }

      // Theme switches replace the whole palette; crossfade on the same curve
      // the bar uses for its own colour transitions.
      Behavior on color {
        ColorAnimation { duration: 420; easing.type: Easing.InOutCubic }
      }

      Loader {
        active: root.interactive
        anchors.fill: parent
        anchors.margins: -root.gap / 2

        sourceComponent: MouseArea {
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.hoveredIndex = index
          onExited: if (root.hoveredIndex === index) root.hoveredIndex = -1
          onClicked: root.dotActivated(index, String(root.colors[index]))
        }
      }
    }
  }
}
