import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "PaletteData.js" as PaletteData

// Bar widget: the active theme's palette as small circles that morph into one
// capsule, plus a popup that switches themes by colour. Every theme card shows
// the wallpaper that switching will pull in — chosen by matching the wallpaper
// library's aether palettes against the theme palette in OKLab (bin/palette).
Panel {
  id: root

  moduleName: "amh.palette"
  ipcTarget: "amh.palette"
  // This file owns the single IpcHandler the target allows, so it can expose
  // theme/wallpaper actions next to the inherited open/close/toggle.
  manageIpc: false

  // --- inline shell.json settings -----------------------------------------
  readonly property int dotSize: Math.max(4, Math.round(Style.spaceReal(Number(setting("dotSize", 7)))))
  readonly property int dotCount: Math.max(2, Math.min(8, Number(setting("dots", 6))))
  readonly property int columns: Math.max(2, Number(setting("columns", 3)))
  readonly property bool autoIndex: setting("autoIndex", true) !== false

  readonly property string script: Qt.resolvedUrl("bin/palette").toString().replace(/^file:\/\//, "")

  // --- live state ----------------------------------------------------------
  property var themeColors: ({})
  property string themeName: ""
  property var themeList: []
  property var wallpaperMap: ({})
  property string wallpaperLabel: ""
  property string pending: ""
  property bool indexing: false
  property int cursor: -1

  readonly property var swatches: PaletteData.swatches(themeColors, dotCount)
  readonly property bool busy: pending !== "" || indexing

  // A theme is free to ship a popup surface its own text does not survive on
  // (shell.toml overrides, generated themes); check before painting.
  readonly property string popupSurface: PaletteData.toHex([
    Color.popups.background.r, Color.popups.background.g, Color.popups.background.b])
  readonly property string popupText: PaletteData.legible(
    PaletteData.toHex([Color.popups.text.r, Color.popups.text.g, Color.popups.text.b]), popupSurface, 4.5)
  readonly property string popupMuted: PaletteData.legible(
    PaletteData.toHex([Color.muted.r, Color.muted.g, Color.muted.b]), popupSurface, 3.0)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // --- actions -------------------------------------------------------------
  function matchesFor(slug) {
    var hits = wallpaperMap ? wallpaperMap[slug] : undefined
    return hits ? hits : []
  }

  function start(process, args) {
    if (process.running)
      return false
    process.command = [root.script].concat(args)
    process.running = true
    return true
  }

  function applyTheme(slug) {
    if (!slug || root.pending !== "")
      return
    root.pending = slug
    if (!start(applyProcess, ["apply", slug]))
      root.pending = ""
  }

  function applyCursor() {
    if (cursor >= 0 && cursor < themeList.length)
      applyTheme(themeList[cursor].name)
  }

  function cycleWallpaper(pick) {
    start(wallpaperProcess, ["wallpaper", "--pick", pick])
  }

  // Turn one swatch into a whole new theme: pick the wallpaper that carries
  // this colour most convincingly, then let aether generate + apply from it.
  function generateFrom(color) {
    if (!color || root.pending !== "")
      return
    root.pending = color
    if (!start(generateProcess, ["from-color", color]))
      root.pending = ""
  }

  function refreshIndex() {
    if (indexing)
      return
    indexing = true
    if (!start(indexProcess, ["index", "--rebuild"]))
      indexing = false
  }

  function refreshBackground() {
    if (!currentBackgroundProcess.running)
      currentBackgroundProcess.running = true
  }

  function reloadTheme() {
    nameFile.reload()
    colorsFile.reload()
    start(themesProcess, ["themes"])
    refreshBackground()
  }

  function moveCursor(dx, dy) {
    if (!themeList.length)
      return
    var next = cursor < 0 ? 0 : cursor + dx + dy * root.columns
    cursor = Math.max(0, Math.min(themeList.length - 1, next))
    revealCursor()
  }

  // Keyboard navigation has to drag the grid along with it.
  function revealCursor() {
    if (cursor < 0 || !cards.height)
      return
    var row = Math.floor(cursor / root.columns)
    var top = row * (root.cardHeight + root.cardGap)
    var bottom = top + root.cardHeight
    if (top < cards.contentY)
      cards.contentY = top
    else if (bottom > cards.contentY + cards.height)
      cards.contentY = Math.min(bottom - cards.height, Math.max(0, cards.contentHeight - cards.height))
  }

  function cursorOfCurrent() {
    for (var i = 0; i < themeList.length; i++)
      if (themeList[i].name === root.themeName)
        return i
    return -1
  }

  onOpenedChanged: {
    if (opened) {
      reloadTheme()
      cursor = cursorOfCurrent()
    } else {
      cursor = -1
    }
  }

  Component.onCompleted: {
    start(themesProcess, ["themes"])
    start(mapProcess, ["map"])
    refreshBackground()
  }

  // --- theme state ---------------------------------------------------------

  // `Color.currentThemePath` is ~/.local/state/omarchy/current/theme, so the
  // sibling theme.name file is the same path with the extension appended.
  FileView {
    id: nameFile
    path: Color.currentThemePath + ".name"
    printErrors: false
    onLoaded: root.themeName = text().trim()
  }

  FileView {
    id: colorsFile
    path: Color.currentThemePath + "/colors.toml"
    printErrors: false
    onLoaded: root.themeColors = PaletteData.parseColors(text())
  }

  // Theme switches arrive as a shell IPC payload (omarchy-theme-set), not as a
  // file event on the swapped-out theme dir, so re-read once the singleton has
  // taken the new palette.
  Connections {
    target: Color
    function onBackgroundChanged() { reloadTimer.restart() }
    function onAccentChanged() { reloadTimer.restart() }
  }

  Timer {
    id: reloadTimer
    interval: 150
    onTriggered: root.reloadTheme()
  }

  // Keep the wallpaper palette cache warm without competing with login.
  Timer {
    interval: 8000
    running: root.autoIndex
    onTriggered: root.start(indexProcess, ["index"])
  }

  Process {
    id: themesProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.themeList = JSON.parse(text)
        } catch (error) {
          root.themeList = []
        }
      }
    }
  }

  Process {
    id: mapProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.wallpaperMap = JSON.parse(text).themes || ({})
        } catch (error) {
          root.wallpaperMap = ({})
        }
      }
    }
  }

  Process {
    id: indexProcess
    onExited: {
      root.indexing = false
      root.start(mapProcess, ["map"])
    }
  }

  Process {
    id: applyProcess
    onExited: {
      root.pending = ""
      root.reloadTheme()
    }
  }

  Process {
    id: generateProcess
    onExited: {
      root.pending = ""
      root.reloadTheme()
    }
  }

  Process {
    id: wallpaperProcess
    stdout: StdioCollector {
      onStreamFinished: {
        var path = text.trim()
        if (path)
          root.wallpaperLabel = PaletteData.basename(path)
      }
    }
  }

  // Prints the current background as a display name, not a path.
  Process {
    id: currentBackgroundProcess
    command: ["omarchy-theme-bg-current"]
    stdout: StdioCollector {
      onStreamFinished: root.wallpaperLabel = text.trim()
    }
  }

  IpcHandler {
    target: "amh.palette"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function apply(theme: string): void { root.applyTheme(theme) }
    function wallpaper(pick: string): void { root.cycleWallpaper(pick || "next") }
    function generate(color: string): void { root.generateFrom(color) }
    function reindex(): void { root.refreshIndex() }
    function morph(): void { previewMorph.restart() }
  }

  // --- bar surface ---------------------------------------------------------
  // Lets `omarchy-shell amh.palette morph` play the morph without a pointer.
  Timer {
    id: previewMorph
    interval: 1400
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    active: root.opened
    fixedWidth: barDots.implicitWidth + Style.spaceReal(9)
    tooltipText: {
      var name = root.themeName ? PaletteData.displayName(root.themeName) : "Palette"
      if (root.pending !== "")
        return name + " — applying…"
      return root.wallpaperLabel ? name + " — " + root.wallpaperLabel : name
    }

    onPressed: function (mouseButton) {
      if (mouseButton === Qt.RightButton)
        root.cycleWallpaper("next")
      else if (mouseButton === Qt.MiddleButton)
        root.cycleWallpaper("random")
      else
        root.toggle()
    }

    onWheelMoved: function (delta) {
      root.cycleWallpaper(delta > 0 ? "next" : "prev")
    }

    PaletteDots {
      id: barDots
      anchors.centerIn: parent
      colors: root.swatches
      // The bar island paints this behind the row; a monochrome or light theme
      // would otherwise render swatches that match it exactly.
      surface: root.bar ? root.bar.background : Color.bar.background
      dotSize: root.dotSize
      morphed: button.tooltipHovered || root.opened || previewMorph.running
      opacity: root.busy ? 0.55 : 1

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }

  // --- popup ---------------------------------------------------------------
  readonly property int cardWidth: Style.space(154)
  readonly property int cardHeight: Style.space(94)
  readonly property int cardGap: Style.spacing.lg
  readonly property int visibleRows: Math.max(2, Number(setting("rows", 4)))

  KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(root.columns * root.cardWidth + (root.columns - 1) * root.cardGap + panel.padding * 2)
    contentHeight: panel.fittedContentHeight(layout.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent

      onCloseRequested: root.close()
      onMoveRequested: function (dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.applyCursor()
      onTextKey: function (character) {
        if (character === "w")
          root.cycleWallpaper("next")
        else if (character === "b")
          root.cycleWallpaper("prev")
        else if (character === "g")
          root.generateFrom(root.themeColors.accent)
        else if (character === "r")
          root.refreshIndex()
      }

      Column {
        id: layout
        width: parent.width
        spacing: Style.spacing.xl

        // Header: the live palette, clickable colour by colour.
        Row {
          width: parent.width
          spacing: Style.spacing.xl

          Column {
            width: parent.width - liveDots.width - parent.spacing
            spacing: Style.spacing.xxs

            Text {
              text: root.themeName ? PaletteData.displayName(root.themeName) : "Palette"
              color: root.popupText
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.pending !== "" ? "applying " + PaletteData.displayName(root.pending) + "…"
                : root.indexing ? "indexing wallpapers…"
                : root.wallpaperLabel ? root.wallpaperLabel
                : "no wallpaper"
              color: root.popupMuted
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          PaletteDots {
            id: liveDots
            anchors.verticalCenter: parent.verticalCenter
            colors: root.swatches
            surface: Color.popups.background
            dotSize: Style.space(14)
            interactive: true
            morphed: liveDots.hoveredIndex >= 0
            onDotActivated: function (index, color) { root.generateFrom(color) }
          }
        }

        Text {
          width: parent.width
          text: "click a colour → new theme · enter applies · w/b wallpaper · r reindex"
          color: root.popupMuted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Flickable {
          id: cards
          width: parent.width
          // Clamp to whole rows so the grid never shows a sliced card.
          height: Math.min(grid.implicitHeight, root.visibleRows * (root.cardHeight + root.cardGap) - root.cardGap)
          contentWidth: width
          contentHeight: grid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Grid {
            id: grid
            columns: root.columns
            spacing: root.cardGap

            Repeater {
              model: root.themeList

              Rectangle {
                id: card

                required property var modelData
                required property int index

                readonly property bool isCurrent: modelData.name === root.themeName
                readonly property bool isCursor: root.cursor === index
                readonly property bool hovered: cardMouse.containsMouse
                readonly property string preview: PaletteData.firstPath(root.matchesFor(modelData.name))
                // Text and swatches sit on a solid slab of the theme's own
                // background, never on the wallpaper: that is the only way the
                // theme's authored foreground/background pairing is what the
                // eye actually gets. Light theme + bright wallpaper used to
                // render the label at 1.0:1.
                readonly property string band: String(modelData.background)
                readonly property string label: PaletteData.legible(modelData.foreground, band, 4.5)
                readonly property string outline: PaletteData.legible(modelData.accent, band, 2.2)

                width: root.cardWidth
                height: root.cardHeight
                radius: Style.space(10)
                color: modelData.background
                border.width: isCurrent || isCursor || hovered ? Math.max(1, Style.space(2)) : Style.spacing.hairline
                border.color: isCurrent || isCursor ? card.outline : (hovered ? Style.hoverBorderColor : Style.normalBorderColor)
                clip: true
                scale: hovered && root.pending === "" ? 1.02 : 1
                opacity: root.pending === "" || root.pending === modelData.name ? 1 : 0.45

                Behavior on scale {
                  NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                  NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
                Behavior on border.color {
                  ColorAnimation { duration: 160 }
                }

                // The wallpaper this theme will actually pull in.
                Image {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: Math.round(card.height - bandRow.height)
                  source: card.preview ? Util.fileUrl(card.preview) : ""
                  visible: status === Image.Ready
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: true
                  sourceSize.width: Math.round(root.cardWidth * 2)
                  opacity: card.hovered || card.isCursor ? 1 : 0.78

                  Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                  }

                  // Soft hand-off into the slab instead of a hard cut.
                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Style.space(18)
                    gradient: Gradient {
                      GradientStop { position: 0.0; color: Util.alpha(card.modelData.background, 0.0) }
                      GradientStop { position: 1.0; color: card.modelData.background }
                    }
                  }
                }

                Rectangle {
                  id: bandRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Style.space(46)
                  color: card.modelData.background

                  Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.spacing.xxl
                    spacing: Style.spacing.md

                    PaletteDots {
                      colors: card.modelData.swatches
                      surface: card.modelData.background
                      dotSize: Style.space(11)
                      morphed: card.hovered || card.isCursor
                    }

                    Row {
                      width: parent.width
                      spacing: Style.spacing.md

                      Text {
                        width: parent.width - marker.width - parent.spacing
                        text: PaletteData.displayName(card.modelData.name)
                        color: card.label
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        font.bold: card.isCurrent
                        elide: Text.ElideRight
                      }

                      Rectangle {
                        id: marker
                        anchors.verticalCenter: parent.verticalCenter
                        visible: card.isCurrent
                        width: card.isCurrent ? Style.space(7) : 0
                        height: Style.space(7)
                        radius: width / 2
                        color: card.outline
                      }
                    }
                  }
                }

                MouseArea {
                  id: cardMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onEntered: root.cursor = card.index
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton && card.isCurrent)
                      root.cycleWallpaper("next")
                    else
                      root.applyTheme(card.modelData.name)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
