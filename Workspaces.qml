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
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
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

  // Workspace id -> how many windows it holds. Read straight off the live
  // models so opening or closing a window updates every bar.
  readonly property var windowCounts: {
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
    return Logic.windowCounts(workspaceRecords, topRecords)
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
      if (switched || windowsChanged || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        Hyprland.refreshToplevels()
      }
    }
  }

  Component.onCompleted: {
    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
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
        readonly property bool occupied: Logic.hasWindow(root.windowCounts, modelData)
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

        // The button's own label cannot be made bold. This one is measured
        // bold so the slot is wide enough either way, and the weight follows
        // `shown`. Centering matches WidgetButton: the line box keeps room
        // for descenders, so the figure height is what gets centered.
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          anchors.verticalCenterOffset: root.vertical ? 0
            : (boldMetrics.descent - boldMetrics.ascent + boldMetrics.tightBoundingRect("0").height) / 2
          text: parent.text
          color: parent.active && parent.useActiveColor ? parent.activeColor : parent.foreground
          font.family: parent.fontFamily
          font.pixelSize: parent.fontSize
          font.bold: parent.occupied
          renderType: Text.NativeRendering
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        FontMetrics {
          id: boldMetrics
          font.family: parent.fontFamily
          font.pixelSize: parent.fontSize
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
