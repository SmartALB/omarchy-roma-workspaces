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
