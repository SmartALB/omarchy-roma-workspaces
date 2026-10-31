.pragma library

function flag(value, fallback) {
  if (typeof value === "string") {
    var text = value.trim().toLowerCase()
    if (text === "true" || text === "1" || text === "yes" || text === "on") return true
    if (text === "false" || text === "0" || text === "no" || text === "off" || text === "") return false
    return fallback === true
  }
  return value === true
}

function boundedInteger(value, fallback, low, high) {
  var parsed = Number(value)
  if (!isFinite(parsed)) return fallback
  return Math.max(low, Math.min(high, Math.round(parsed)))
}

function roman(value) {
  if (!isFinite(value) || value < 1) return String(value)

  var amounts = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
  var symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
  var left = Math.round(value)
  var out = ""

  for (var i = 0; i < amounts.length; i++) {
    while (left >= amounts[i]) {
      out += symbols[i]
      left -= amounts[i]
    }
  }
  return out
}

// Omarchy gives every monitor this many workspaces. Hyprland numbers them in
// one sequence, so monitor 0 owns 1-10, monitor 1 owns 11-20, and so on.
function slotsPerMonitor() {
  return 10
}

function blockOf(id, slots) {
  return Math.floor((Number(id) - 1) / (slots || slotsPerMonitor()))
}

function slotOf(id, slots) {
  slots = slots || slotsPerMonitor()
  return (Number(id) - 1) % slots + 1
}

// The state file is one monitor per line: block, connector, identity.
// A monitor that is unplugged keeps its block but has an empty connector,
// and the bar only needs the monitors that are plugged in now.
function parseMonitorBlocks(text) {
  var blocks = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i] === "") continue
    var fields = lines[i].split("\t")
    if (fields.length < 2 || fields[1] === "") continue
    var block = parseInt(fields[0], 10)
    if (isFinite(block)) blocks[fields[1]] = block
  }
  return blocks
}

// The file is the authority, because the workspace a monitor is showing may
// be a guest from another block. Until the file has been read, the workspace
// it is showing is treated as one of its own.
function monitorBlock(blocks, monitorName, activeId, slots) {
  slots = slots || slotsPerMonitor()
  if (blocks && monitorName && blocks[monitorName] !== undefined && blocks[monitorName] !== null) {
    var assigned = Number(blocks[monitorName])
    if (isFinite(assigned)) return assigned
  }
  var active = Number(activeId)
  if (isFinite(active) && active > 0) return blockOf(active, slots)
  return 0
}

// The ids to draw for one monitor: its own slots, from I upward, then any
// workspace that is only visiting because its monitor is unplugged.
function listedWorkspaces(spec) {
  var slots = spec.slots || slotsPerMonitor()
  var count = boundedInteger(spec.workspaceCount, 5, 1, spec.maxCount || slots)
  var own = Math.min(count, slots)
  var block = Number(spec.block)
  if (!isFinite(block) || block < 0) block = 0

  var base = block * slots
  var ids = []
  var i
  for (i = 1; i <= own; i++) ids.push(base + i)

  var guests = []
  var workspaces = spec.workspaces || []
  if (spec.reveal) {
    for (i = 0; i < workspaces.length; i++) {
      var id = Math.round(Number(workspaces[i].id))
      if (!isFinite(id) || id <= 0) continue
      if (blockOf(id, slots) === block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (workspaces[i].monitorName && spec.monitorName && workspaces[i].monitorName === spec.monitorName) {
        if (guests.indexOf(id) === -1) guests.push(id)
      }
    }
  }

  ids.sort(function(left, right) { return left - right })
  guests.sort(function(left, right) { return left - right })

  var entries = []
  for (i = 0; i < ids.length; i++) entries.push({ id: ids[i], slot: slotOf(ids[i], slots), guest: false })
  for (i = 0; i < guests.length; i++) entries.push({ id: guests[i], slot: slotOf(guests[i], slots), guest: true })
  return entries
}

// A slot of this monitor's own block is focused by slot, on that monitor, so
// a click cannot pull another screen's workspace across. A visitor has no
// slot here, and is focused by its real id.
function focusExpression(id, block, monitorName, slots) {
  slots = slots || slotsPerMonitor()
  id = Math.round(Number(id))
  var name = String(monitorName || "")
  if (name && blockOf(id, slots) === Number(block)) {
    return "o.workspaces.focus(" + slotOf(id, slots) + ", \"" + name.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\")"
  }
  return "hl.dsp.focus({ workspace = \"" + id + "\" })"
}
