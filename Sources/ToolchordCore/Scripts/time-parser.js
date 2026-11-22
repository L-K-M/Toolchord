// Millisecond range: 0001-01-01T00:00:00.000Z … 9999-12-31T23:59:59.999Z
var MIN_MS = -62135596800000;
var MAX_MS = 253402300799999;
var RANGE_MSG = "Out of range. Toolchord supports dates from year 0001 to 9999.";
var MS_HINT = " If this is a millisecond timestamp, set Unit to Milliseconds.";

// ─── Helpers ──────────────────────────────────────────────────────────────────

function isDigit(b) {
  return b >= 48 && b <= 57;
}

function isLeap(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function monthDays(month, year) {
  if (month === 2) return isLeap(year) ? 29 : 28;
  if (month === 4 || month === 6 || month === 9 || month === 11) return 30;
  return 31;
}

// March-based Gregorian era algorithm; epoch = 1970-01-01 = day 0
function daysFromCivil(year, month, day) {
  var y = year - (month <= 2 ? 1 : 0);
  var era = Math.floor(y / 400);
  var yoe = y - era * 400;
  var doy = Math.floor((153 * (month + (month > 2 ? -3 : 9)) + 2) / 5) + day - 1;
  var doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

// ─── Text location (line/column from UTF-8 byte offset) ──────────────────────
// Columns count Unicode scalars; CR, LF, CRLF each count as one line break.

function textLocation(utf8Bytes, offset) {
  var line = 1;
  var column = 1;
  var prevCR = false;
  var pos = 0;
  for (var i = 0; i < utf8Bytes.length; i++) {
    if (pos >= offset) break;
    pos++;
    var b = utf8Bytes[i];
    if (b === 0x0A) {
      if (prevCR) { prevCR = false; continue; }
      line++;
      column = 1;
    } else if (b === 0x0D) {
      line++;
      column = 1;
      prevCR = true;
      continue;
    } else if ((b & 0xC0) !== 0x80) {
      column++;
    }
    prevCR = false;
  }
  return { line: line, column: column };
}

function trimInput(text, api) {
  var original = utf8.encode(text);
  var first = null;
  var end = 0;
  var offset = 0;
  var scalarCount = 0;
  for (var si = 0; si < text.length; si++) {
    if (scalarCount % 4096 === 0 && api.cancelled()) return { error: "cancelled" };
    var cp = text.codePointAt(si);
    var charLen;
    if (cp < 0x80) charLen = 1;
    else if (cp < 0x800) charLen = 2;
    else if (cp < 0x10000) charLen = 3;
    else charLen = 4;
    if (!/[\p{White_Space}\u200b]/u.test(String.fromCodePoint(cp))) {
      if (first === null) first = offset;
      end = offset + charLen;
    }
    offset += charLen;
    scalarCount++;
    // Advance si for surrogate pairs
    if (cp >= 0x10000) si++;
  }
  if (api.cancelled()) return { error: "cancelled" };
  var start = first !== null ? first : offset;
  var bytes;
  if (start >= offset) {
    bytes = [];
  } else {
    bytes = original.slice(start, end);
  }
  return { original: original, start: start, bytes: bytes };
}

// ─── Error helpers ────────────────────────────────────────────────────────────

function makeInvalid(message, original, start, offset) {
  var loc = textLocation(original, start + offset);
  return { error: "invalid", message: message, location: loc };
}

// Keep at most 19 significant digits. A valid Int64 outside the calendar
// range has a different diagnostic from a malformed or missing seed.
function parseSeed(text, api) {
    const missing = {error:"needsInput", message:"Select Show Current Time again to capture the time."};
    if (!text || text === "-") return missing;
    const negative = text[0] === "-";
    let digits = "";
    for (let i = negative ? 1 : 0; i < text.length; i++) {
        if ((i & 4095) === 0 && api.cancelled()) return {error:"cancelled"};
        const c = text[i];
        if (c < "0" || c > "9") return missing;
        if (c !== "0" || digits.length) digits += c;
        if (digits.length > 19) return missing;
    }
    const max = negative ? "9223372036854775808" : "9223372036854775807";
    if (digits.length === 19 && digits > max) return missing;
    const ms = Number(digits) * (negative ? -1 : 1);
    return ms < MIN_MS || ms > MAX_MS ? {error:"invalid", message:RANGE_MSG} : ms;
}

// ─── Unix timestamp parser ───────────────────────────────────────────────────

function parseUnix(text, unit, api) {
  var trimmed = trimInput(text, api);
  if (trimmed.error) return trimmed;
  var original = trimmed.original;
  var start = trimmed.start;
  var bytes = trimmed.bytes;

  var malformed = "Enter a Unix time such as 1700000000.";
  if (bytes.length === 0) {
    return makeInvalid(malformed, original, start, 0);
  }

  var negative = bytes[0] === 45;
  var index = negative ? 1 : 0;
  var digitStart = index;
  var whole = 0;
  var overflow = false;

  while (index < bytes.length && isDigit(bytes[index])) {
    if (index % 4096 === 0 && api.cancelled()) return { error: "cancelled" };
    var digit = bytes[index] - 48;
    // JS Number loses precision above MAX_SAFE_INTEGER (16 digits).
    // Mark overflow once we exceed it so we can still report range errors.
    if (whole > (Number.MAX_SAFE_INTEGER - digit) / 10) {
      overflow = true;
    }
    if (!overflow) {
      whole = whole * 10 + digit;
    }
    index++;
  }

  if (index <= digitStart) {
    return makeInvalid(malformed, original, start, index);
  }

  var dot = index;
  var fraction = 0;
  var fractionCount = 0;

  if (index < bytes.length && bytes[index] === 46) {
    index++;
    while (index < bytes.length && isDigit(bytes[index])) {
      if (index % 4096 === 0 && api.cancelled()) return { error: "cancelled" };
      if (fractionCount < 3) {
        fraction = fraction * 10 + (bytes[index] - 48);
      }
      fractionCount++;
      index++;
    }
    if (fractionCount === 0) {
      return makeInvalid(malformed, original, start, index);
    }
  }

  if (index < bytes.length) {
    return makeInvalid(malformed, original, start, index);
  }

  // Milliseconds must be whole number
  if (unit === "ms" && fractionCount > 0) {
    return makeInvalid("Milliseconds must be a whole number.", original, start, dot);
  }

  // Seconds: up to 3 decimal places
  if (unit !== "ms" && fractionCount > 3) {
    return makeInvalid("Unix seconds support up to millisecond precision (three decimal places).", original, start, dot + 1);
  }

  // Normalize fraction to milliseconds
  if (fractionCount === 1) fraction *= 100;
  if (fractionCount === 2) fraction *= 10;

  var isMs = unit === "ms";
  var scale = isMs ? 1 : 1000;

  // Compute scaled magnitude with overflow tracking
  var scaled;
  var scaleOverflow = false;
  if (!overflow) {
    scaled = whole * scale;
    if (scaled / scale !== whole) scaleOverflow = true;
  }

  var magnitude;
  var fractionOverflow = false;
  if (!overflow && !scaleOverflow) {
    magnitude = scaled + (isMs ? 0 : fraction);
    if (magnitude < 0) fractionOverflow = true;
  }

  if (!overflow && !scaleOverflow && !fractionOverflow) {
    var value = negative ? -magnitude : magnitude;
    if (value >= MIN_MS && value <= MAX_MS) {
      return { milliseconds: value, unit: isMs ? "ms" : "s" };
    }
  }

  // Out of range — check auto fallback
  var message = RANGE_MSG;
  if (!isMs && fractionCount === 0 && !overflow) {
    var absWhole = negative ? -whole : whole;
    if (absWhole >= MIN_MS && absWhole <= MAX_MS) {
      if (unit === "auto") {
        return { milliseconds: negative ? -whole : whole, unit: "ms" };
      }
      message += MS_HINT;
    }
  }

  return makeInvalid(message, original, start, 0);
}

// ─── RFC 3339 parser ─────────────────────────────────────────────────────────

function parseRFC3339(text, api) {
  var trimmed = trimInput(text, api);
  if (trimmed.error) return trimmed;
  var original = trimmed.original;
  var start = trimmed.start;
  var bytes = trimmed.bytes;

  var generic = "Use an RFC 3339 date such as 2024-01-01T12:00:00Z.";

  function number(offset, count) {
    if (offset + count > bytes.length) {
      throw makeInvalid(generic, original, start, Math.min(offset, bytes.length));
    }
    var value = 0;
    for (var i = offset; i < offset + count; i++) {
      if (!isDigit(bytes[i])) {
        throw makeInvalid(generic, original, start, i);
      }
      value = value * 10 + (bytes[i] - 48);
    }
    return value;
  }

  function expect(byte, offset) {
    if (offset >= bytes.length || bytes[offset] !== byte) {
      throw makeInvalid(generic, original, start, Math.min(offset, bytes.length));
    }
  }

  // Parse year (4 digits)
  var year;
  try { year = number(0, 4); } catch (e) { return e; }
  try { expect(45, 4); } catch (e) { return e; } // '-'
  var month;
  try { month = number(5, 2); } catch (e) { return e; }
  try { expect(45, 7); } catch (e) { return e; } // '-'
  var day;
  try { day = number(8, 2); } catch (e) { return e; }

  if (year < 1) {
    return makeInvalid("Year must be between 0001 and 9999.", original, start, 0);
  }
  if (month < 1 || month > 12) {
    return makeInvalid("Month must be between 01 and 12.", original, start, 5);
  }

  var maxDay = monthDays(month, year);
  if (day < 1 || day > maxDay) {
    var monthNames = ["January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"];
    return makeInvalid(monthNames[month - 1] + " " + year + " has " + maxDay + " days.", original, start, 8);
  }

  // Date-only is incomplete
  if (bytes.length === 10) {
    return makeInvalid("Add a time and offset, for example \u201C2024-01-01T00:00:00Z\u201D.", original, start, 10);
  }

  // Separator: T, t, or space
  if (bytes[10] !== 84 && bytes[10] !== 116 && bytes[10] !== 32) {
    return makeInvalid(generic, original, start, 10);
  }

  var hour;
  try { hour = number(11, 2); } catch (e) { return e; }
  try { expect(58, 13); } catch (e) { return e; } // ':'
  var minute;
  try { minute = number(14, 2); } catch (e) { return e; }
  try { expect(58, 16); } catch (e) { return e; } // ':'
  var second;
  try { second = number(17, 2); } catch (e) { return e; }

  if (hour >= 24) {
    return makeInvalid("Hour must be between 00 and 23.", original, start, 11);
  }
  if (minute >= 60) {
    return makeInvalid("Minute must be between 00 and 59.", original, start, 14);
  }
  if (second === 60) {
    return makeInvalid("Leap seconds (:60) aren\u2019t supported.", original, start, 17);
  }
  if (second >= 60) {
    return makeInvalid("Second must be between 00 and 59.", original, start, 17);
  }

  // Fractional seconds
  var idx = 19;
  var fraction = 0;
  if (idx < bytes.length && bytes[idx] === 46) {
    idx++;
    var fracStart = idx;
    while (idx < bytes.length && isDigit(bytes[idx])) {
      if (idx % 4096 === 0 && api.cancelled()) return { error: "cancelled" };
      if (idx - fracStart < 3) {
        fraction = fraction * 10 + (bytes[idx] - 48);
      } else if (bytes[idx] !== 48) {
        return makeInvalid("Toolchord supports millisecond precision (three fraction digits).", original, start, idx);
      }
      idx++;
    }
    var count = idx - fracStart;
    if (count === 0) {
      return makeInvalid(generic, original, start, idx);
    }
    if (count === 1) fraction *= 100;
    if (count === 2) fraction *= 10;
  }

  // Time zone offset required
  if (idx >= bytes.length) {
    return makeInvalid("Add a time zone offset such as \u201CZ\u201D or \u201C+01:00\u201D. Toolchord doesn\u2019t guess the time zone.", original, start, idx);
  }

  var tzOffset = 0;
  if (bytes[idx] === 90 || bytes[idx] === 122) {
    // Z or z
    idx++;
  } else if (bytes[idx] === 43 || bytes[idx] === 45) {
    var neg = bytes[idx] === 45;
    var oh;
    try { oh = number(idx + 1, 2); } catch (e) { return e; }
    try { expect(58, idx + 3); } catch (e) { return e; }
    var om;
    try { om = number(idx + 4, 2); } catch (e) { return e; }
    if (oh >= 24) {
      return makeInvalid("Offset hour must be between 00 and 23.", original, start, idx + 1);
    }
    if (om >= 60) {
      return makeInvalid("Offset minute must be between 00 and 59.", original, start, idx + 4);
    }
    tzOffset = (oh * 3600 + om * 60) * (neg ? -1 : 1);
    idx += 6;
  } else {
    return makeInvalid(generic, original, start, idx);
  }

  if (idx < bytes.length) {
    return makeInvalid(generic, original, start, idx);
  }

  // Compute milliseconds
  var seconds = daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second - tzOffset;
  var milliseconds = seconds * 1000 + fraction;

  if (milliseconds < MIN_MS || milliseconds > MAX_MS) {
    return makeInvalid(RANGE_MSG, original, start, 0);
  }

  return milliseconds;
}

// ─── Public API ───────────────────────────────────────────────────────────────

function parseClockInput(kind, text, unit, api) {
  // Default api
  if (!api) api = {};
  if (!api.cancelled) api.cancelled = function () { return false; };

  if (kind === "seed") {
    return parseSeed(text, api);
  }

  if (text === null || text === undefined) {
    if (kind === "unix") {
      return { error: "needsInput", message: "Enter a Unix time such as 1700000000." };
    }
    return { error: "needsInput", message: "Use an RFC 3339 date such as 2024-01-01T12:00:00Z." };
  }

  if (kind === "unix") {
    var u = unit || "auto";
    return parseUnix(text, u, api);
  }

  if (kind === "rfc3339") {
    return parseRFC3339(text, api);
  }

  return { error: "invalid", message: "Unknown kind: " + kind };
}
