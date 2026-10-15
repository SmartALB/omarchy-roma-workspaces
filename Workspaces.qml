import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Logic.js" as Logic

// Workspace indicators in Roman numerals, and the menu that decides how many
// of them there are. Grown from a clone of omarchy.workspaces, so the parts
// that are not about numerals -- the grid that turns vertical with the bar,
// the focus dispatch, the button styling -- behave exactly like the built-in
// widget they came from.
//
// Left click focuses a workspace, because that is what a click on a
// workspace means. The menu is on right click; it cannot have the left one.
Panel {
  id: root
  moduleName: "smartalb.roma-workspaces"
  ipcTarget: "smartalb.roma-workspaces"
  manageIpc: true

  // Second copy of what manifest.json says: QML cannot read the manifest,
  // because Omarchy's PluginRegistry is an instance rather than a singleton.
  readonly property string pluginVersion: "1.1.1"

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
  readonly property int maxCount: 20

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

  // ---- Which workspaces to draw.
  //
  // The configured count is a floor, not a ceiling: a workspace past it stays
  // visible while it exists, so the one you are actually on is never missing
  // from the bar. Switching that off makes the count literal.
  function workspaceIds() {
    var ids = []
    for (var n = 1; n <= root.workspaceCount; n++) ids.push(n)

    if (root.revealOccupied) {
      var values = Hyprland.workspaces.values
      for (var i = 0; i < values.length; i++) {
        var id = values[i].id
        if (id > root.workspaceCount && id <= root.maxCount && ids.indexOf(id) === -1) ids.push(id)
      }
      ids.sort(function(left, right) { return left - right })
    }

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
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
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
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(0.75)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        // No colour or font is set here on purpose. The built-in workspaces
        // widget sets none either, so both follow whatever theme is active
        // rather than one particular author's.
        bar: root.bar
        text: Logic.roman(modelData)
        tooltipText: root.workspaceTooltip(workspace)
        active: focused
        opacity: (occupied || focused || !root.dimEmpty) ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : -1
        fixedHeight: root.barSize
        onPressed: function(b) {
          if (b === Qt.RightButton) root.toggle()
          else root.focusWorkspace(modelData)
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
