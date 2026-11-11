#!/usr/bin/bash

set -uo pipefail

readonly BIN_GREP=/usr/bin/grep
readonly BIN_JQ=/usr/bin/jq
readonly BIN_NODE=/usr/bin/node
readonly BIN_SED=/usr/bin/sed

self="${BASH_SOURCE[0]}"
[[ "$self" == */* ]] || self="./$self"
readonly REPO="$(cd -- "${self%/*}/.." && pwd)"
readonly LOGIC="$REPO/Logic.js"
readonly QML="$REPO/Workspaces.qml"
readonly MANIFEST="$REPO/manifest.json"
readonly README="$REPO/README.md"

pass_count=0
fail_count=0

ok()  { printf '  ok    %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad() { printf '  FAIL  %s\n       %s\n' "$1" "$2"; fail_count=$((fail_count + 1)); }

assert_versions_match() {
  local manifest_version qml_version
  manifest_version="$("$BIN_JQ" -r '.version // empty' "$MANIFEST")"
  qml_version="$("$BIN_SED" -n 's/^ *readonly property string pluginVersion: "\([^"]*\)".*/\1/p' "$QML")"

  if [ -n "$manifest_version" ] && [ "$manifest_version" = "$qml_version" ]; then
    ok "manifest and QML report version $manifest_version"
  else
    bad "manifest and QML versions match" "manifest=$manifest_version qml=$qml_version"
  fi
}

assert_workspace_contract() {
  local qml_min qml_max manifest_min manifest_max manifest_step manifest_type
  qml_min="$("$BIN_SED" -n 's/^ *readonly property int minCount: \([0-9]\+\).*/\1/p' "$QML")"
  qml_max="$("$BIN_SED" -n 's/^ *readonly property int maxCount: \([0-9]\+\).*/\1/p' "$QML")"
  manifest_min="$("$BIN_JQ" -r '.barWidget.schema[] | select(.key == "workspaceCount") | .min' "$MANIFEST")"
  manifest_max="$("$BIN_JQ" -r '.barWidget.schema[] | select(.key == "workspaceCount") | .max' "$MANIFEST")"
  manifest_step="$("$BIN_JQ" -r '.barWidget.schema[] | select(.key == "workspaceCount") | .step' "$MANIFEST")"
  manifest_type="$("$BIN_JQ" -r '.barWidget.schema[] | select(.key == "workspaceCount") | .type' "$MANIFEST")"

  if [ "$qml_min" = "1" ] && [ "$qml_max" = "10" ] \
      && [ "$manifest_min" = "$qml_min" ] && [ "$manifest_max" = "$qml_max" ] \
      && [ "$manifest_step" = "1" ] && [ "$manifest_type" = "integer" ] \
      && "$BIN_GREP" -q '1–10' "$README"; then
    ok "QML, manifest, and README agree on integer workspaces 1 through 10 per monitor"
  else
    bad "workspace range contract" \
      "qml=$qml_min..$qml_max manifest=$manifest_min..$manifest_max/$manifest_step type=$manifest_type"
  fi
}

assert_input_lifecycle() {
  local loader_block
  loader_block="$($BIN_SED -n '/id: panelContent/,/sourceComponent: Component {/p' "$QML")"

  if [ "$($BIN_GREP -c 'NumberField {' "$QML")" = "1" ] \
      && printf '%s\n' "$loader_block" | "$BIN_GREP" -q 'active: root.opened' \
      && "$BIN_SED" -n '/sourceComponent: Component {/,/^      }/p' "$QML" \
        | "$BIN_GREP" -q 'NumberField {' \
      && "$BIN_GREP" -q 'field.editable: false' "$QML" \
      && "$BIN_GREP" -q 'panelContent.item ? panelContent.item.implicitHeight : 0' "$QML"; then
    ok "NumberField is non-editable and exists only while the settings panel is open"
  else
    bad "settings input lifecycle" \
      "NumberField must be non-editable and live in a Loader active only while root.opened"
  fi
}

assert_logic() {
  if "$BIN_NODE" - "$LOGIC" <<'NODE'
const fs = require("fs")
const vm = require("vm")

const file = process.argv[2]
const source = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
const logic = {}
vm.createContext(logic)
vm.runInContext(source, logic, { filename: file })

const numerals = new Map([
  [1, "I"], [4, "IV"], [9, "IX"], [10, "X"], [11, "XI"],
  [14, "XIV"], [19, "XIX"], [20, "XX"], [49, "XLIX"]
])
for (const [input, expected] of numerals) {
  if (logic.roman(input) !== expected)
    throw new Error(`roman(${input}) = ${logic.roman(input)}, expected ${expected}`)
}

const integers = [
  ["7", 5, 1, 20, 7], [3.6, 5, 1, 20, 4], [0, 5, 1, 20, 1],
  [21, 5, 1, 20, 20], ["not-a-number", 5, 1, 20, 5]
]
for (const [input, fallback, low, high, expected] of integers) {
  const actual = logic.boundedInteger(input, fallback, low, high)
  if (actual !== expected)
    throw new Error(`boundedInteger(${JSON.stringify(input)}) = ${actual}, expected ${expected}`)
}

const flags = [
  ["true", false, true], ["false", true, false], ["ON", false, true],
  ["0", true, false], [true, false, true], [false, true, false], ["unknown", true, true]
]
for (const [input, fallback, expected] of flags) {
  const actual = logic.flag(input, fallback)
  if (actual !== expected)
    throw new Error(`flag(${JSON.stringify(input)}) = ${actual}, expected ${expected}`)
}
NODE
  then
    ok "Roman numerals and setting coercion behave correctly"
  else
    bad "shared JavaScript logic" "one or more behavioral cases failed"
  fi
}

assert_per_monitor() {
  if "$BIN_GREP" -q 'monitor.activeWorkspace' "$QML" \
      && "$BIN_GREP" -q 'monitor-workspaces' "$QML" \
      && "$BIN_GREP" -q 'focusExpression' "$QML" \
      && "$BIN_GREP" -q 'font.bold: parent.occupied' "$QML" \
      && "$BIN_GREP" -q 'id: occupancyMark' "$QML" \
      && "$BIN_GREP" -q 'holdsWindow' "$QML" \
      && ! "$BIN_GREP" -q 'focusedWorkspace' "$QML" \
      && "$BIN_GREP" -q 'o.workspaces.focus' "$LOGIC"; then
    ok "each bar bolds workspaces that hold a window"
  else
    bad "per-monitor workspace marking" \
      "mark monitor.activeWorkspace in bold, and do not follow the global focused workspace"
  fi

  if "$BIN_NODE" - "$LOGIC" <<'NODE'
const fs = require("fs")
const vm = require("vm")

const file = process.argv[2]
const source = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
const logic = {}
vm.createContext(logic)
vm.runInContext(source, logic, { filename: file })

function ids(entries) { return entries.map((entry) => entry.id).join(",") }
function fail(message) { throw new Error(message) }

const laptop = "eDP-2"
const external = "HDMI-A-1"
const blocks = logic.parseMonitorBlocks(`0\t${laptop}\tPanel\n1\t${external}\tExternal\n`)
if (blocks[laptop] !== 0 || blocks[external] !== 1) fail(`blocks ${JSON.stringify(blocks)}`)

const unplugged = logic.parseMonitorBlocks(`0\t${laptop}\tPanel\n1\t\tExternal\n`)
if (unplugged[external] !== undefined || unplugged[laptop] !== 0) fail("empty connector should be ignored")

if (logic.monitorBlock(blocks, laptop, 1, 10) !== 0) fail("laptop block")
if (logic.monitorBlock(blocks, external, 11, 10) !== 1) fail("external block")
if (logic.monitorBlock({}, external, 11, 10) !== 1) fail("fallback uses the workspace the monitor is showing")
if (logic.monitorBlock({}, laptop, 1, 10) !== 0) fail("single monitor fallback")
if (logic.monitorBlock({}, "", -1, 10) !== 0) fail("unknown monitor starts at the first block")

const screens = [
  { name: "eDP-2", x: 0, y: 150 },
  { name: "HDMI-A-1", x: 1922, y: 0 }
]
if (logic.matchMonitor(screens, "HDMI-A-1", 1922, 0) !== "HDMI-A-1") fail("external screen matches its connector")
if (logic.matchMonitor(screens, "eDP-2", 0, 150) !== "eDP-2") fail("laptop screen matches its connector")
if (logic.matchMonitor(screens, "", 1922, 0) !== "HDMI-A-1") fail("position matches the external monitor")
if (logic.matchMonitor(screens, "unknown", 0, 150) !== "eDP-2") fail("position matches the laptop when the name does not")
if (logic.matchMonitor(screens, "unknown", 9, 9) !== "") fail("an unmatched screen must not take the first monitor")
if (logic.matchMonitor([], "eDP-2", 0, 0) !== "") fail("no monitors means no match")

const single = logic.listedWorkspaces({
  workspaceCount: 10, maxCount: 10, slots: 10,
  block: logic.monitorBlock({ [laptop]: 0 }, laptop, 4, 10),
  reveal: true, monitorName: laptop,
  workspaces: [{ id: 1, monitorName: laptop }, { id: 11, monitorName: external }]
})
if (ids(single) !== "1,2,3,4,5,6,7,8,9,10") fail(`one monitor listed ${ids(single)}`)
if (single.some((entry) => entry.id === 11)) fail("one monitor must not list the other monitor's block")
if (logic.roman(single[3].slot) !== "IV") fail("the active slot on one monitor is still IV")

const externalEntries = logic.listedWorkspaces({
  workspaceCount: 10, maxCount: 10, slots: 10, block: 1,
  reveal: true, monitorName: external,
  workspaces: [
    { id: 1, monitorName: laptop },
    { id: 11, monitorName: external },
    { id: 12, monitorName: external },
    { id: 13, monitorName: external },
    { id: -98, monitorName: external }
  ]
})
if (ids(externalEntries) !== "11,12,13,14,15,16,17,18,19,20") fail(`external listed ${ids(externalEntries)}`)
if (logic.roman(externalEntries[0].slot) !== "I" || logic.roman(externalEntries[2].slot) !== "III")
  fail("external slots are numbered from I, not from XI")

const revealed = logic.listedWorkspaces({
  workspaceCount: 5, maxCount: 10, slots: 10, block: 1,
  reveal: true, monitorName: external,
  workspaces: [
    { id: 11, monitorName: external },
    { id: 17, monitorName: external },
    { id: 3, monitorName: laptop }
  ]
})
if (ids(revealed) !== "11,12,13,14,15,17") fail(`reveal listed ${ids(revealed)}`)

const literal = logic.listedWorkspaces({
  workspaceCount: 5, maxCount: 10, slots: 10, block: 1,
  reveal: false, monitorName: external,
  workspaces: [{ id: 17, monitorName: external }]
})
if (ids(literal) !== "11,12,13,14,15") fail(`literal count listed ${ids(literal)}`)

const visiting = logic.listedWorkspaces({
  workspaceCount: 10, maxCount: 10, slots: 10, block: 0,
  reveal: true, monitorName: laptop,
  workspaces: [{ id: 1, monitorName: laptop }, { id: 12, monitorName: laptop }]
})
if (visiting.length !== 11 || !visiting[10].guest || visiting[10].id !== 12 || visiting[0].guest)
  fail(`guest listing ${JSON.stringify(visiting[visiting.length - 1])}`)

if (logic.focusExpression(11, 1, external, 10) !== 'o.workspaces.focus(1, "HDMI-A-1")')
  fail(`own focus ${logic.focusExpression(11, 1, external, 10)}`)
if (logic.focusExpression(4, 0, laptop, 10) !== 'o.workspaces.focus(4, "eDP-2")')
  fail(`single focus ${logic.focusExpression(4, 0, laptop, 10)}`)
if (logic.focusExpression(12, 0, laptop, 10) !== 'hl.dsp.focus({ workspace = "12" })')
  fail(`guest focus ${logic.focusExpression(12, 0, laptop, 10)}`)

const counts = logic.windowCounts(
  [
    { id: 1, toplevelCount: 0, reportedWindows: 1 },
    { id: 11, toplevelCount: 2, reportedWindows: 0 },
    { id: 15, toplevelCount: 0, reportedWindows: 1 },
    { id: -98, toplevelCount: 1, reportedWindows: 1 }
  ],
  [{ workspaceId: 12 }, { workspaceId: 13 }, { workspaceId: 13 }, { workspaceId: -98 }]
)
if (!logic.hasWindow(counts, 1) || !logic.hasWindow(counts, 11) || !logic.hasWindow(counts, 12)
    || !logic.hasWindow(counts, 13) || !logic.hasWindow(counts, 15))
  fail(`occupied set ${JSON.stringify(counts)}`)
if (logic.hasWindow(counts, 2) || logic.hasWindow(counts, 14) || logic.hasWindow(counts, -98))
  fail(`empty workspace looked occupied ${JSON.stringify(counts)}`)
if (counts["13"] !== 2) fail(`duplicate windows collapsed ${JSON.stringify(counts)}`)
const marked = "1,11,13,15"
if (!logic.holdsWindow(marked, 1) || !logic.holdsWindow(marked, 11) || !logic.holdsWindow(marked, 13)
    || !logic.holdsWindow(marked, 15))
  fail("marked ids were not occupied")
if (logic.holdsWindow(marked, 2) || logic.holdsWindow(marked, 12) || logic.holdsWindow("1", 11)
    || logic.holdsWindow("", 1) || logic.holdsWindow(marked, -98))
  fail("empty id looked occupied")
NODE
  then
    ok "one monitor and several monitors list and focus their own workspaces"
  else
    bad "per-monitor listing" "one or more monitor cases failed"
  fi
}

printf 'Roma Workspaces — tests\n'
assert_versions_match
assert_workspace_contract
assert_input_lifecycle
assert_logic
assert_per_monitor

printf '\n'
if [ "$fail_count" -eq 0 ]; then
  printf 'PASS  %d assertions\n' "$pass_count"
  exit 0
fi

printf 'FAIL  %d of %d assertions failed\n' "$fail_count" "$((pass_count + fail_count))"
exit 1
