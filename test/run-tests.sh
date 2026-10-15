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

  if [ "$qml_min" = "1" ] && [ "$qml_max" = "20" ] \
      && [ "$manifest_min" = "$qml_min" ] && [ "$manifest_max" = "$qml_max" ] \
      && [ "$manifest_step" = "1" ] && [ "$manifest_type" = "integer" ] \
      && "$BIN_GREP" -q '1–20' "$README"; then
    ok "QML, manifest, and README agree on integer workspaces 1 through 20"
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

printf 'Roma Workspaces — tests\n'
assert_versions_match
assert_workspace_contract
assert_input_lifecycle
assert_logic

printf '\n'
if [ "$fail_count" -eq 0 ]; then
  printf 'PASS  %d assertions\n' "$pass_count"
  exit 0
fi

printf 'FAIL  %d of %d assertions failed\n' "$fail_count" "$((pass_count + fail_count))"
exit 1
