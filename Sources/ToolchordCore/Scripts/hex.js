// hex.js — Hex encode/decode for Toolchord.
// Exposes global function: preview(input, options, api)
//
// api.id: "hex.encode" | "hex.decode"
// api.limits: { maxInputBytes, maxOutputBytes, maxNestingDepth, outputLimitMessage, nestingLimitMessage }
// api.cancelled(): boolean
// options: { separator: "none" | "space" } (for hex.encode)
// input: string | null (null = no input)

function preview(input, options, api) {
  if (api.id === "hex.encode") return hexEncode(input, options, api);
  if (api.id === "hex.decode") return hexDecode(input, options, api);
  return { error: "unsupported", message: "Unknown api.id: " + api.id };
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function utf8Bytes(str) {
  // Encode a JavaScript string to UTF-8 bytes without TextEncoder.
  // Avoid large constants in bitwise ops (JS uses 32-bit signed ints).
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    // Handle surrogate pairs
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length) {
      var lo = str.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        var cp = ((c - 0xD800) << 10) + (lo - 0xDC00) + 0x10000;
        i++;
        bytes.push(
          0xF0 | ((cp >> 18) & 0x07),
          0x80 | ((cp >> 12) & 0x3F),
          0x80 | ((cp >> 6) & 0x3F),
          0x80 | (cp & 0x3F)
        );
        continue;
      }
    }
    if (c < 0x80) {
      bytes.push(c);
    } else if (c < 0x800) {
      bytes.push(
        0xC0 | ((c >> 6) & 0x1F),
        0x80 | (c & 0x3F)
      );
    } else {
      bytes.push(
        0xE0 | ((c >> 12) & 0x0F),
        0x80 | ((c >> 6) & 0x3F),
        0x80 | (c & 0x3F)
      );
    }
  }
  return bytes;
}

function utf8Decode(bytes) {
  // Decode UTF-8 bytes to a JavaScript string. Returns null on invalid UTF-8.
  var chars = [];
  var i = 0;
  while (i < bytes.length) {
    var b = bytes[i];
    var cp;
    if (b < 0x80) {
      cp = b;
      i++;
    } else if (b < 0xC0) {
      return null; // Unexpected continuation
    } else if (b < 0xE0) {
      if (i + 1 >= bytes.length) return null;
      if ((bytes[i + 1] & 0xC0) !== 0x80) return null;
      cp = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
      i += 2;
      if (cp < 0x80) return null; // Overlong
    } else if (b < 0xF0) {
      if (i + 2 >= bytes.length) return null;
      if ((bytes[i + 1] & 0xC0) !== 0x80 || (bytes[i + 2] & 0xC0) !== 0x80) return null;
      cp = ((b & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
      i += 3;
      if (cp < 0x800) return null; // Overlong
    } else if (b < 0xF8) {
      if (i + 3 >= bytes.length) return null;
      if ((bytes[i + 1] & 0xC0) !== 0x80 || (bytes[i + 2] & 0xC0) !== 0x80 || (bytes[i + 3] & 0xC0) !== 0x80) return null;
      cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) | ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      i += 4;
      if (cp < 0x10000) return null; // Overlong
    } else {
      return null; // Invalid leading byte
    }
    // Check for surrogates and out-of-range
    if (cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) return null;
    if (cp <= 0xFFFF) {
      chars.push(String.fromCharCode(cp));
    } else {
      cp -= 0x10000;
      chars.push(String.fromCharCode(0xD800 + (cp >> 10)));
      chars.push(String.fromCharCode(0xDC00 + (cp & 0x3FF)));
    }
  }
  return chars.join("");
}

function byteCountText(count) {
  if (count === 1) return "1 byte";
  if (count < 1024) return count + " bytes";
  var units = ["KiB", "MiB", "GiB"];
  var value = count;
  var unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  var rounded = Math.round(value * 10) / 10;
  var number = rounded === Math.round(rounded) ? String(Math.round(rounded)) : rounded.toFixed(1);
  return number + " " + units[unit];
}

// Compute line/column (1-based) from a UTF-8 byte offset in the original text.
// Columns count Unicode scalars; CR, LF, CRLF each count as one line break.
function locationOfUTF8Offset(text, offset) {
  var bytes = utf8Bytes(text);
  var line = 1;
  var column = 1;
  var previousWasCR = false;
  var position = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (position >= offset) break;
    position++;
    var byte = bytes[i];
    if (byte === 0x0A) {
      if (previousWasCR) {
        previousWasCR = false;
        continue;
      }
      line++;
      column = 1;
    } else if (byte === 0x0D) {
      line++;
      column = 1;
      previousWasCR = true;
      continue;
    } else if ((byte & 0xC0) !== 0x80) {
      column++;
    }
    previousWasCR = false;
  }
  return { line: line, column: column };
}

// ─── Encode ─────────────────────────────────────────────────────────────────

function hexEncode(input, options, api) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Paste text to encode." };
  }
  if (api.cancelled()) return { error: "cancelled", message: "" };

  var spaced = options && options.separator === "space";
  var bytes = utf8Bytes(input);
  var count = bytes.length;
  var size = count * 2 + (spaced ? Math.max(0, count - 1) : 0);
  if (size > api.limits.maxOutputBytes) {
    return { error: "tooLarge", message: api.limits.outputLimitMessage };
  }

  var digits = "0123456789abcdef";
  var parts = [];
  for (var i = 0; i < count; i++) {
    if (i % 4096 === 0 && api.cancelled()) return { error: "cancelled", message: "" };
    if (spaced && i > 0) parts.push(" ");
    parts.push(digits[(bytes[i] >> 4) & 0x0F]);
    parts.push(digits[bytes[i] & 0x0F]);
  }
  var result = parts.join("");
  return {
    primaryText: result,
    status: byteCountText(count)
  };
}

// ─── Decode ─────────────────────────────────────────────────────────────────

function hexDecode(input, options, api) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Paste hex to decode." };
  }
  if (api.cancelled()) return { error: "cancelled", message: "" };

  var bytes = [];
  var high = null;
  // We need to track UTF-8 offset for error locations.
  // Walk the original input's scalars, skipping leading/trailing whitespace and 0x prefix.
  var scalars = [];
  for (var si = 0; si < input.length; si++) {
    var ch = input.charCodeAt(si);
    if (ch >= 0xD800 && ch <= 0xDBFF && si + 1 < input.length) {
      var lo = input.charCodeAt(si + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        scalars.push(ch);
        scalars.push(lo);
        si++;
        continue;
      }
    }
    scalars.push(ch);
  }

  // Find start index (skip leading whitespace)
  var start = 0;
  while (start < scalars.length && isWhitespaceScalar(scalars[start])) {
    start++;
    if (start % 4096 === 0 && api.cancelled()) return { error: "cancelled", message: "" };
  }
  // Find end index (skip trailing whitespace) — end is exclusive (one past last non-ws)
  var end = scalars.length;
  while (end > start && isWhitespaceScalar(scalars[end - 1])) {
    end--;
    if ((scalars.length - end) % 4096 === 0 && api.cancelled()) return { error: "cancelled", message: "" };
  }

  // Skip 0x/0X prefix
  if (start < end && scalars[start] === 48) {
    var next = start + 1;
    if (next < end && (scalars[next] === 120 || scalars[next] === 88)) {
      start = next + 1;
    }
  }

  // Compute UTF-8 offset for each scalar index
  var utf8Offsets = [];
  var off = 0;
  for (var k = 0; k < scalars.length; k++) {
    utf8Offsets.push(off);
    var cp = scalars[k];
    if (cp >= 0xD800 && cp <= 0xDBFF && k + 1 < scalars.length && scalars[k + 1] >= 0xDC00 && scalars[k + 1] <= 0xDFFF) {
      var codePoint = ((cp - 0xD800) << 10) + (scalars[k + 1] - 0xDC00) + 0x10000;
      if (codePoint < 0x10000) off += 3;
      else off += 4;
      k++;
    } else if (cp < 0x80) {
      off += 1;
    } else if (cp < 0x800) {
      off += 2;
    } else {
      off += 3;
    }
  }

  var nextCheck = 0;
  for (var idx = start; idx < end; idx++) {
    if (idx >= nextCheck) {
      if (api.cancelled()) return { error: "cancelled", message: "" };
      nextCheck = idx + 4096;
    }
    var n = scalars[idx];
    // Skip spaces, tabs, newlines, colons (same as Swift: 32, 9, 10, 13, 58)
    if (n === 32 || n === 9 || n === 10 || n === 13 || n === 58) continue;

    var digit;
    if (n >= 48 && n <= 57) {
      digit = n - 48;
    } else if (n >= 65 && n <= 70) {
      digit = n - 65 + 10;
    } else if (n >= 97 && n <= 102) {
      digit = n - 97 + 10;
    } else {
      // Invalid hex digit — need the character representation and location
      var chStr;
      if (n >= 0xD800 && n <= 0xDBFF && idx + 1 < scalars.length && scalars[idx + 1] >= 0xDC00 && scalars[idx + 1] <= 0xDFFF) {
        chStr = String.fromCharCode(n) + String.fromCharCode(scalars[idx + 1]);
      } else {
        chStr = String.fromCharCode(n);
      }
      var loc = locationOfUTF8Offset(input, utf8Offsets[idx]);
      return {
        error: "invalid",
        message: 'Invalid hex digit \u201C' + chStr + '\u201D.',
        location: loc
      };
    }

    if (high !== null) {
      if (bytes.length >= api.limits.maxOutputBytes) {
        return { error: "tooLarge", message: api.limits.outputLimitMessage };
      }
      bytes.push((high << 4) | digit);
      high = null;
    } else {
      high = digit;
    }
  }

  if (high !== null) {
    // Odd number of digits — location at the end of the last digit
    var loc = locationOfUTF8Offset(input, utf8Offsets[end - 1] + scalarUTF8Length(scalars[end - 1]));
    return {
      error: "invalid",
      message: "Hex text has an odd number of digits.",
      location: loc
    };
  }

  var decoded = utf8Decode(bytes);
  if (decoded === null) {
    return { error: "invalid", message: "Decoded bytes are not UTF-8 text." };
  }

  return {
    primaryText: decoded,
    status: "Decoded · " + byteCountText(bytes.length)
  };
}

function isWhitespaceScalar(code) {
  // Foundation additionally classifies U+200B as horizontal whitespace.
  return code === 0x200B || /^\p{White_Space}$/u.test(String.fromCodePoint(code));
}

function scalarUTF8Length(code) {
  if (code < 0x80) return 1;
  if (code < 0x800) return 2;
  if (code >= 0xD800 && code <= 0xDFFF) return 2; // surrogate (half of pair)
  return 3;
}
