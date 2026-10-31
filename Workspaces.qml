import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Workspace indicators in Roman numerals, and the menu that decides how many
// of them there are. Grown from a clone of omarchy.workspaces.
//
// Every monitor has workspaces of its own. Hyprland numbers them in a block
// of ten per monitor -- 1-10, 11-20, and so on -- and each bar shows the
// block of the monitor it is drawn on, labeled from I. The accent marks the
// workspace that monitor is showing, whether or not the keyboard is there.
// One monitor and several take the same path: resolve the screen this bar is
// on, and until that screen is known follow the focused monitor, which is
// the only monitor when there is just one.
//
// Left click focuses that monitor's workspace. The menu is on right click;
// it cannot have the left one.
Panel {
  id: root
  moduleName: "smartalb.roma-workspaces"
  ipcTarget: "smartalb.roma-workspaces"
  manageIpc: true

  // Second copy of what manifest.json says: QML cannot read the manifest,
  // because Omarchy's PluginRegistry is an instance rather than a singleton.
  readonly property string pluginVersion: "1.2.0"

  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family
  readonly property color fg: barForeground

  // ---- Settings.
  //
  // `omarchy bar set <id> <key> <value>` stores the value as a STRING unless
  // --json is passed, so shell.json can legitimately hold "false" or "7" as
  // text. Handing "false" to a bool property would read it by JS truthiness,
  // and a non-empty string is true -- switching an option off would switch
  // it on. Both readers below coerce rather than trust.
  function flag(key, fallback) {
    return Logic.flag(setting(key, fallback), fallback)
  }

  function number(key, fallback, low, high) {
    return Logic.boundedInteger(setting(key, fallback), fallback, low, high)
  }

  readonly property int minCount: 1
  readonly property int maxCount: 10

  readonly property int workspaceCount: number("workspaceCount", 5, minCount, maxCount)
  readonly property bool revealOccupied: flag("revealOccupied", true)
  readonly property bool dimEmpty: flag("dimEmpty", true)

  function setValue(key, value) {
    var entry = {}
    for (var k in root.settings) entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Which monitor this bar belongs to.
  //
  // The bar runs one surface per screen. The workspace to mark is the one
  // that screen is showing. The globally focused workspace is the same on
  // every bar, so it is the wrong one as soon as a second monitor is in use.
  readonly property var monitor: {
    // monitorFor() is a function, so reading it once does not subscribe to
    // Hyprland's monitor list. A bar that asked before that list existed
    // kept a null monitor and every screen then drew the first block.
    // Touch the list and the focused monitor so this runs again when either
    // changes, then match the screen by connector name or by position.
    var monitors = Hyprland.monitors.values
    var focused = Hyprland.focusedMonitor
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    if (!screen) return focused
    var direct = Hyprland.monitorFor(screen)
    if (direct) return direct
    var records = []
    var i
    for (i = 0; i < monitors.length; i++) {
      records.push({ name: monitors[i].name, x: monitors[i].x, y: monitors[i].y })
    }
    var matched = Logic.matchMonitor(records, screen.name, screen.x, screen.y)
    for (i = 0; i < monitors.length; i++) {
      if (matched && monitors[i].name === matched) return monitors[i]
    }
    return focused
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""
  readonly property int activeWorkspaceId: {
    var workspace = root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace : null
    return workspace ? workspace.id : -1
  }

  // Connector -> block, from the file Hyprland keeps the assignment in.
  property var blocks: ({})

  function applyBlocks(text) {
    root.blocks = Logic.parseMonitorBlocks(text)
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyBlocks(text())
    onLoadFailed: root.applyBlocks("")
  }

  readonly property int block: Logic.monitorBlock(root.blocks, root.monitorName, root.activeWorkspaceId, Logic.slotsPerMonitor())

  // Comma-separated ids of workspaces that hold a window. This is assigned
  // rather than bound. A var map returned from the shared script does not
  // notify the buttons, so a workspace with a window stayed as faint as an
  // empty one. occupiedRevision is an int, which does notify.
  property string occupiedIds: ""
  property int occupiedRevision: 0

  function recount() {
    var toplevels = Hyprland.toplevels.values
    var workspaces = Hyprland.workspaces.values
    var topRecords = []
    var workspaceRecords = []
    var i
    for (i = 0; i < toplevels.length; i++) {
      var top = toplevels[i]
      topRecords.push({ workspaceId: top.workspace ? top.workspace.id : -1 })
    }
    for (i = 0; i < workspaces.length; i++) {
      var workspace = workspaces[i]
      var listed = workspace.toplevels && workspace.toplevels.values ? workspace.toplevels.values.length : 0
      var reported = workspace.lastIpcObject && workspace.lastIpcObject.windows !== undefined
        ? Number(workspace.lastIpcObject.windows) : 0
      workspaceRecords.push({ id: workspace.id, toplevelCount: listed, reportedWindows: reported })
    }
    var counts = Logic.windowCounts(workspaceRecords, topRecords)
    var ids = []
    for (var key in counts) {
      if (Number(counts[key]) > 0) ids.push(Number(key))
    }
    ids.sort(function(a, b) { return a - b })
    var parts = []
    for (i = 0; i < ids.length; i++) parts.push(String(Math.round(ids[i])))
    root.occupiedIds = parts.join(",")
    root.occupiedRevision = root.occupiedRevision + 1
  }

  function scheduleRecount() {
    root.recount()
    recountSoon.restart()
    recountLater.restart()
  }

  function workspaceRecords(values) {
    var records = []
    if (!values) return records
    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      records.push({
        id: workspace.id,
        monitorName: workspace.monitor ? String(workspace.monitor.name) : ""
      })
    }
    return records
  }

  // The configured count is a floor, not a ceiling, inside this monitor's
  // own ten: a later slot stays visible while it exists, so the one this
  // screen is on is never missing. Switching that off makes the count literal.
  readonly property var workspaceIds: {
    var values = Hyprland.workspaces.values
    var entries = Logic.listedWorkspaces({
      workspaceCount: root.workspaceCount,
      maxCount: root.maxCount,
      slots: Logic.slotsPerMonitor(),
      block: root.block,
      reveal: root.revealOccupied,
      monitorName: root.monitorName,
      workspaces: root.workspaceRecords(values)
    })
    var ids = []
    for (var i = 0; i < entries.length; i++) ids.push(entries[i].id)
    return ids
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceTooltip(workspace) {
    if (workspace === null || workspace.toplevels.values.length === 0) return "Empty"

    var seen = ({})
    var names = []
    var values = workspace.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var top = values[i]
      var name = String(top.class || top.appId || top.title || top.name || "")
      if (name === "") name = "Window"
      if (!seen[name]) {
        seen[name] = true
        names.push(name)
      }
    }

    var shown = names.slice(0, 3)
    var tooltip = shown.join("\n")
    if (names.length > 3) tooltip += "\n..."
    return tooltip
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    var expression = Logic.focusExpression(id, root.block, root.monitorName, Logic.slotsPerMonitor())
    root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // Quickshell credits every workspace switch to the focused monitor, because
  // the event does not say which one switched, and it misses the workspace a
  // monitor falls back to when its own is moved away. Ask Hyprland for the
  // truth so the accent on each bar stays on the workspace that screen shows.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      var windowsChanged = name === "openwindow" || name === "closewindow" || name === "movewindow" || name === "movewindowv2"
      var monitorsChanged = name === "focusedmon" || name === "focusedmonv2"
      if (switched || windowsChanged || monitorsChanged || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
        root.scheduleRecount()
      }
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRecount() }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.scheduleRecount() }
  }

  Timer {
    id: recountSoon
    interval: 100
    repeat: false
    onTriggered: root.recount()
  }

  Timer {
    id: recountLater
    interval: 400
    repeat: false
    onTriggered: root.recount()
  }

  // The window list arrives after the first frame. Sample until it has, then stop.
  Timer {
    interval: 250
    repeat: true
    running: true
    property int left: 10
    onTriggered: {
      root.recount()
      left -= 1
      if (left <= 0) running = false
    }
  }

  Component.onCompleted: {
    Hyprland.refreshMonitors()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.recount()
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds.length
    columnSpacing: root.vertical ? 0 : Style.space(0.75)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds

      WidgetButton {
        required property int modelData
        required property int index

        readonly property int slots: Logic.slotsPerMonitor()
        readonly property int slot: Logic.slotOf(modelData, slots)
        readonly property bool guest: Logic.blockOf(modelData, slots) !== root.block
        readonly property bool firstGuest: guest && index > 0 && Logic.blockOf(root.workspaceIds[index - 1], slots) === root.block
        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: root.occupiedRevision >= 0 && Logic.holdsWindow(root.occupiedIds, modelData)
        readonly property bool shown: root.activeWorkspaceId === modelData

        // A gap sets a visiting workspace apart from this monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        // Family, size, and colour come from the bar. A workspace that holds a
        // window is bold. The one this monitor is showing takes the button's
        // active colour, on this screen alone.
        bar: root.bar
        text: Logic.roman(slot)
        labelVisible: false
        tooltipText: root.workspaceTooltip(workspace)
        active: shown
        opacity: (occupied || shown || !root.dimEmpty) ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Math.ceil(boldMetrics.boundingRect(text).width + scaledHorizontalMargin * 2)
        fixedHeight: root.barSize
        onPressed: function(b) {
          if (b === Qt.RightButton) root.toggle()
          else root.focusWorkspace(modelData)
        }

        // The button's own label cannot be made bold, and at this size the
        // bold face is about one pixel heavier than the regular one, which
        // does not read as bold. A second copy, one pixel over, thickens the
        // figure, and the line under it marks a workspace that holds a window.
        // Centering matches WidgetButton: the line box keeps room for
        // descenders, so the figure height is what gets centered.
        readonly property real figureShift: root.vertical ? 0
          : (boldMetrics.descent - boldMetrics.ascent + boldMetrics.tightBoundingRect("0").height) / 2
        Text {
          id: figure
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: figureShift
          anchors.horizontalCenterOffset: 0
          text: parent.text
          color: parent.active && parent.useActiveColor ? parent.activeColor : parent.foreground
          font.family: parent.fontFamily
          font.pixelSize: parent.fontSize
          font.bold: parent.occupied
          font.weight: parent.occupied ? Font.Bold : Font.Normal
          renderType: Text.NativeRendering
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          visible: parent.occupied
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: figureShift
          anchors.horizontalCenterOffset: 1
          text: figure.text
          color: figure.color
          font.family: figure.font.family
          font.pixelSize: figure.font.pixelSize
          font.bold: true
          font.weight: Font.Bold
          renderType: Text.NativeRendering
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
        // At 12px the bold face does not look bold. This line is the mark.
        Rectangle {
          id: occupancyMark
          visible: parent.occupied
          color: figure.color
          radius: 1
          height: 2
          width: Math.max(6, figure.contentWidth)
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 2
        }

        FontMetrics {
          id: boldMetrics
          font.family: parent.fontFamily || Style.font.family
          font.pixelSize: parent.fontSize > 0 ? parent.fontSize : Style.font.body
          font.bold: true
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: grid
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(panelContent.item ? panelContent.item.implicitHeight : 0)

    // NumberField inherits an editable TextInput. Qt 6.12 may inspect the
    // clipboard whenever it changes, even while a merely hidden field is not
    // being used. Destroy the complete settings subtree when this panel is
    // closed instead of leaving its input controls resident in the shared
    // shell process.
    Loader {
      id: panelContent
      active: root.opened
      width: parent.width
      sourceComponent: Component {
        Column {
          id: panelColumn
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "Roma Workspaces"
            foreground: root.fg
            fontFamily: root.fontFam
          }

          NumberField {
            width: panelColumn.width
            label: "Workspaces shown"
            field.editable: false
            value: root.workspaceCount
            from: root.minCount
            to: root.maxCount
            stepSize: 1
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFam
            onModified: function(v) { root.setValue("workspaceCount", v) }
          }

          Toggle {
            width: panelColumn.width
            label: "Reveal the ones beyond"
            description: "Keep showing a workspace past that count while it exists"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFam
            checked: root.revealOccupied
            onClicked: root.setValue("revealOccupied", !root.revealOccupied)
          }

          Toggle {
            width: panelColumn.width
            label: "Dim the empty ones"
            description: "Fade workspaces holding no windows"
            foreground: root.fg
            accent: Color.accent
            fontFamily: root.fontFam
            checked: root.dimEmpty
            onClicked: root.setValue("dimEmpty", !root.dimEmpty)
          }
        }
      }
    }
  }
}
