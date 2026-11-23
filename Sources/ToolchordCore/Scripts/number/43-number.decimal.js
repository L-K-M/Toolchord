/* @toolchord
{
  "apiVersion": 1,
  "id": "number.decimal",
  "title": "Convert to Decimal",
  "summary": "Base 10 from hex, binary, or octal",
  "options": [
    {"id": "from", "label": "Read as", "defaultValue": "auto",
     "choices": [
       {"id": "auto", "label": "Auto"},
       {"id": "10", "label": "Decimal"},
       {"id": "16", "label": "Hex"},
       {"id": "2", "label": "Binary"},
       {"id": "8", "label": "Octal"}
     ]},
    {"id": "prefix", "label": "Add prefix", "defaultValue": "false"}
  ],
  "palette": {
    "group": "number", "groupTitle": "Number",
    "aliases": ["to decimal", "hex to decimal", "binary to decimal",
                "octal to decimal", "base 10"],
    "symbol": "number", "copyNoun": "decimal",
    "suggestions": [{"when": ["hex"], "score": 70}]
  }
}
*/
function preview(input, options, api) {
    return convertNumber(input, options, api, 10);
}

// @shared number.decimal/number
function convertNumber(input, options, api, targetBase) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Enter a number." };
  }

  if (api.cancelled()) return {error: "cancelled", message: ""};

  var fromChoice = (options && options.from) || "auto";
  var addPrefix = (options && options.prefix) === "true";

  var explicitBase = null;
  switch (fromChoice) {
    case "10": explicitBase = 10; break;
    case "16": explicitBase = 16; break;
    case "2":  explicitBase = 2;  break;
    case "8":  explicitBase = 8;  break;
    default:   explicitBase = null; break;
  }

  var parsed = parseNumber(input, explicitBase);

  if (parsed.type === "empty") {
    return { error: "invalid", message: "Enter a number." };
  }

  if (parsed.type === "prefixNoDigits") {
    return {
      error: "invalid",
      message: "Expected digits after \u201C" + parsed.prefixStr + "\u201D.",
      location: parsed.location
    };
  }

  if (parsed.type === "badDigit") {
    var msg;
    switch (parsed.base) {
      case 16: msg = "\u201C" + parsed.ch + "\u201D isn\u2019t a hex digit."; break;
      case 2:  msg = "\u201C" + parsed.ch + "\u201D isn\u2019t a binary digit."; break;
      case 8:  msg = "\u201C" + parsed.ch + "\u201D isn\u2019t an octal digit."; break;
      default: msg = "\u201C" + parsed.ch + "\u201D isn\u2019t a decimal digit."; break;
    }
    return {
      error: "invalid",
      message: msg,
      location: parsed.location
    };
  }

  if (parsed.type === "wrongPrefix") {
    return {
      error: "invalid",
      message: "\u201C" + parsed.prefixStr + "\u201D doesn\u2019t match Read as " + parsed.baseName + "."
    };
  }

  if (parsed.type === "tooManyDigits") {
    return { error: "tooLarge", message: "Numbers can have at most 4,096 digits." };
  }

  // Success path
  var sign = parsed.sign;
  var digits = parsed.digits; // array of Int digits, most significant first
  var detectedBase = parsed.detectedBase;

  var bigNum = bigIntFromDigits(digits, detectedBase);

  // Never output -0
  var isZero = bigIntIsZero(bigNum);
  var effectiveSign = sign && !isZero;

  var effectivePrefix = addPrefix && targetBase !== 10;
  var primary = formatNumber(bigNum, targetBase, effectiveSign, effectivePrefix);

  var fields = [
    {
      id: "decimal",
      label: "Decimal",
      value: formatNumber(bigNum, 10, effectiveSign, false)
    },
    {
      id: "hex",
      label: "Hex",
      value: formatNumber(bigNum, 16, effectiveSign, effectivePrefix)
    },
    {
      id: "binary",
      label: "Binary",
      value: formatNumber(bigNum, 2, effectiveSign, effectivePrefix)
    },
    {
      id: "octal",
      label: "Octal",
      value: formatNumber(bigNum, 8, effectiveSign, effectivePrefix)
    }
  ];

  var status = "Read as " + baseName(detectedBase);

  return {
    primaryText: primary,
    status: status,
    fields: fields
  };
}

// ─── Helpers ────────────────────────────────────────────────────────────────

function baseName(base) {
  switch (base) {
    case 16: return "hex";
    case 2:  return "binary";
    case 8:  return "octal";
    default: return "decimal";
  }
}

function isWhitespaceScalar(code) {
  // Foundation additionally classifies U+200B as horizontal whitespace.
  return code === 0x200B || /^\p{White_Space}$/u.test(String.fromCodePoint(code));
}

// Extract Unicode scalars from a JS string as an array of code points.
// JS strings use UTF-16, so we need to handle surrogate pairs.
function extractScalars(str) {
  var scalars = [];
  for (var i = 0; i < str.length; i++) {
    var ch = str.charCodeAt(i);
    if (ch >= 0xD800 && ch <= 0xDBFF && i + 1 < str.length) {
      var lo = str.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        var cp = ((ch - 0xD800) << 10) + (lo - 0xDC00) + 0x10000;
        scalars.push(cp);
        i++;
        continue;
      }
    }
    scalars.push(ch);
  }
  return scalars;
}

// Compute the UTF-8 byte length of a single scalar value.
function scalarUTF8Length(code) {
  if (code < 0x80) return 1;
  if (code < 0x800) return 2;
  if (code < 0x10000) return 3;
  return 4;
}

// Compute line/column (1-based) from a scalar offset in the original text.
// Columns count Unicode scalars; CR, LF, CRLF each count as one line break.
function locationOfScalarOffset(text, scalarOffset) {
  var scalars = extractScalars(text);
  var line = 1;
  var column = 1;
  var previousWasCR = false;
  for (var i = 0; i < scalars.length; i++) {
    if (i >= scalarOffset) break;
    var cp = scalars[i];
    if (cp === 0x0A) {
      if (previousWasCR) {
        previousWasCR = false;
        continue;
      }
      line++;
      column = 1;
    } else if (cp === 0x0D) {
      line++;
      column = 1;
      previousWasCR = true;
      continue;
    } else {
      column++;
    }
    previousWasCR = false;
  }
  return { line: line, column: column };
}

// Convert a scalar code point to a JS string character.
function scalarToString(cp) {
  if (cp <= 0xFFFF) {
    return String.fromCharCode(cp);
  }
  cp -= 0x10000;
  return String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
}

// ─── Parsing ────────────────────────────────────────────────────────────────

function parseNumber(text, explicitBase) {
  // Trim leading/trailing whitespace (matching Swift's CharacterSet.whitespacesAndNewlines)
  var scalars = extractScalars(text);

  var start = 0;
  while (start < scalars.length && isWhitespaceScalar(scalars[start])) {
    start++;
  }
  var end = scalars.length;
  while (end > start && isWhitespaceScalar(scalars[end - 1])) {
    end--;
  }

  if (start >= end) {
    return { type: "empty" };
  }

  // Diagnostics point into the original input, past any leading whitespace.
  // `leading` is the number of scalars before the trimmed content.
  var leading = start;

  var i = 0; // index into scalars, starting from `start`

  var negative = false;
  if (i < scalars.length && scalars[start + i] === 45) { // '-'
    negative = true;
    i++;
  }
  if (start + i >= end) {
    return { type: "empty" };
  }

  var detectedPrefix = null;
  var prefixBase = null;
  var absIdx = start + i;
  if (absIdx + 1 < end && scalars[absIdx] === 48) { // '0'
    var second = scalars[absIdx + 1];
    if (second === 120 || second === 88) { // 'x' or 'X'
      detectedPrefix = "0x";
      prefixBase = 16;
      i += 2;
    } else if ((second === 98 || second === 66) && explicitBase !== 16) { // 'b' or 'B'
      detectedPrefix = "0b";
      prefixBase = 2;
      i += 2;
    } else if (second === 111 || second === 79) { // 'o' or 'O'
      detectedPrefix = "0o";
      prefixBase = 8;
      i += 2;
    }
  }

  var readBase;
  if (explicitBase !== null) {
    if (prefixBase !== null && prefixBase !== explicitBase) {
      var baseNameStr;
      switch (explicitBase) {
        case 16: baseNameStr = "Hex"; break;
        case 2:  baseNameStr = "Binary"; break;
        case 8:  baseNameStr = "Octal"; break;
        default: baseNameStr = "Decimal"; break;
      }
      return { type: "wrongPrefix", prefixStr: detectedPrefix, baseName: baseNameStr };
    }
    readBase = explicitBase;
  } else if (prefixBase !== null) {
    readBase = prefixBase;
  } else {
    // Auto-detect: scan remaining scalars for hex digits (a-f, A-F)
    var hasHexDigit = false;
    for (var j = start + i; j < end; j++) {
      var v = scalars[j];
      if ((v >= 97 && v <= 102) || (v >= 65 && v <= 70)) {
        hasHexDigit = true;
        break;
      }
    }
    readBase = hasHexDigit ? 16 : 10;
  }

  var digits = [];
  var lastWasDigit = false;
  var scalarIdx = start + i; // tracks the scalar index in the original array

  while (start + i < end) {
    var s = scalars[start + i];
    var v = s;

    // Underscore handling
    if (v === 95) { // '_'
      if (!lastWasDigit) {
        var loc = locationOfScalarOffset(text, scalarIdx);
        return { type: "badDigit", ch: scalarToString(s), base: readBase, location: loc };
      }
      lastWasDigit = false;
      i++;
      scalarIdx++;
      continue;
    }

    var digitValue;
    if (v >= 48 && v <= 57) {
      digitValue = v - 48;
    } else if (v >= 97 && v <= 102) {
      digitValue = v - 97 + 10;
    } else if (v >= 65 && v <= 70) {
      digitValue = v - 65 + 10;
    } else {
      var loc2 = locationOfScalarOffset(text, scalarIdx);
      return { type: "badDigit", ch: scalarToString(s), base: readBase, location: loc2 };
    }

    if (digitValue >= readBase) {
      var loc3 = locationOfScalarOffset(text, scalarIdx);
      return { type: "badDigit", ch: scalarToString(s), base: readBase, location: loc3 };
    }

    digits.push(digitValue);
    lastWasDigit = true;
    i++;
    scalarIdx++;
  }

  if (digits.length === 0) {
    if (detectedPrefix !== null) {
      var loc4 = locationOfScalarOffset(text, leading + i);
      return { type: "prefixNoDigits", prefixStr: detectedPrefix, location: loc4 };
    }
    return { type: "empty" };
  }

  if (!lastWasDigit) {
    var loc5 = locationOfScalarOffset(text, scalarIdx - 1);
    return { type: "badDigit", ch: "_", base: readBase, location: loc5 };
  }

  if (digits.length > 4096) {
    return { type: "tooManyDigits" };
  }

  // Strip leading zeros
  var sIdx = 0;
  while (sIdx < digits.length - 1 && digits[sIdx] === 0) {
    sIdx++;
  }
  var significant = digits.slice(sIdx);

  return { type: "success", sign: negative, digits: significant, detectedBase: readBase };
}

// ─── BigInt (pure JS, using native BigInt for arithmetic) ───────────────────

// We use JS BigInt for the actual arithmetic, but implement the conversion
// logic ourselves to match the Swift behavior exactly.

// Build a BigInt from digits in the given base (most significant first).
function bigIntFromDigits(digits, base) {
  if (digits.length === 0 || (digits.length === 1 && digits[0] === 0)) {
    return BigInt(0);
  }
  var result = BigInt(0);
  var b = BigInt(base);
  for (var i = 0; i < digits.length; i++) {
    result = result * b + BigInt(digits[i]);
  }
  return result;
}

function bigIntIsZero(n) {
  return n === BigInt(0);
}

// Convert a BigInt to digits in the given base (most significant first).
function bigIntToDigits(n, base) {
  if (n === BigInt(0)) return [0];

  var b = BigInt(base);
  var digits = [];
  var remaining = n;
  while (remaining > BigInt(0)) {
    var divmod = bigIntDivMod(remaining, b);
    remaining = divmod[0];
    digits.push(Number(divmod[1]));
  }
  // digits are least significant first, reverse them
  digits.reverse();
  return digits;
}

// Division with modulus for BigInt.
function bigIntDivMod(n, d) {
  return [n / d, n % d];
}

// ─── Formatting ─────────────────────────────────────────────────────────────

function formatNumber(num, base, sign, prefix) {
  var digits = bigIntToDigits(num, base);
  var hexChars = "0123456789abcdef";

  var parts = [];
  if (sign) {
    parts.push("-");
  }
  if (prefix) {
    switch (base) {
      case 16: parts.push("0x"); break;
      case 2:  parts.push("0b"); break;
      case 8:  parts.push("0o"); break;
    }
  }
  for (var i = 0; i < digits.length; i++) {
    parts.push(hexChars[digits[i]]);
  }
  return parts.join("");
}
// @endshared
