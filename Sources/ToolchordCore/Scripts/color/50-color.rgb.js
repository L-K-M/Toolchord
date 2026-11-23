/* @toolchord
{
  "apiVersion": 1,
  "id": "color.rgb",
  "title": "Convert Color to RGB",
  "summary": "rgb() notation for any CSS color",
  "palette": {
    "group": "color", "groupTitle": "Color",
    "aliases": ["to rgb", "hex to rgb", "hsl to rgb", "rgb color"],
    "symbol": "paintpalette", "copyNoun": "RGB color",
    "suggestions": [
      {"when": ["hexColor"], "score": 95},
      {"when": ["color"], "score": 85}
    ]
  }
}
*/
function preview(input, options, api) {
    return convertColor(input, options, api, "rgb");
}

// @shared color.hex/color
function convertColor(input, options, api, format) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Enter a hex, rgb(), or hsl() color, such as #ff8800." };
  }
  if (api.cancelled()) return { error: "cancelled", message: "" };

  var trimmed = input.replace(/^[\p{White_Space}\u200B]+|[\p{White_Space}\u200B]+$/gu, "");
  if (trimmed.length === 0) {
    return { error: "invalid", message: "Enter a hex, rgb(), or hsl() color, such as #ff8800." };
  }

  var color = parseColor(trimmed);
  if (color === null) {
    if (trimmed.charAt(0) === "#") {
      return { error: "invalid", message: '"' + trimmed + '" isn\'t a valid hex color.' };
    }
    return { error: "invalid", message: "Enter a hex, rgb(), or hsl() color, such as #ff8800." };
  }

  var hex = formatHex(color.r, color.g, color.b, color.a);
  var rgb = formatRgb(color.r, color.g, color.b, color.a);
  var hsl = formatHsl(color.r, color.g, color.b, color.a);
  var swatch = {
    red: color.r,
    green: color.g,
    blue: color.b,
    alpha: color.a
  };
  var fields = [
    { id: "hex", label: "Hex", value: hex },
    { id: "rgb", label: "RGB", value: rgb },
    { id: "hsl", label: "HSL", value: hsl }
  ];

  const primaryText = {hex, rgb, hsl}[format];

  return {
    primaryText: primaryText,
    status: "sRGB",
    fields: fields,
    swatch: swatch
  };
}

// ─── Color Parsing ──────────────────────────────────────────────────────────

function parseColor(text) {
  if (text.charAt(0) === "#") {
    return parseHex(text);
  }
  return parseFunctional(text);
}

function parseHex(text) {
  var body = text.substring(1); // remove '#'
  var upper = body.toUpperCase();

  // Validate hex digits
  for (var i = 0; i < upper.length; i++) {
    var c = upper.charCodeAt(i);
    if (!((c >= 48 && c <= 57) || (c >= 65 && c <= 70))) {
      return null;
    }
  }

  var len = upper.length;
  if (len !== 3 && len !== 4 && len !== 6 && len !== 8) return null;

  function hexDigitValue(c) {
    if (c >= 48 && c <= 57) return c - 48;
    if (c >= 65 && c <= 70) return c - 55;
    return null;
  }

  function hexByte(s) {
    if (s.length !== 2) return null;
    var h = hexDigitValue(s.charCodeAt(0));
    var l = hexDigitValue(s.charCodeAt(1));
    if (h === null || l === null) return null;
    return ((h << 4) | l) / 255.0;
  }

  function hexSingle(s) {
    var doubled = s + s;
    return hexByte(doubled);
  }

  if (len === 3) {
    var r = hexSingle(upper.charAt(0));
    var g = hexSingle(upper.charAt(1));
    var b = hexSingle(upper.charAt(2));
    if (r === null || g === null || b === null) return null;
    return { r: r, g: g, b: b, a: 1.0 };
  } else if (len === 4) {
    var r4 = hexSingle(upper.charAt(0));
    var g4 = hexSingle(upper.charAt(1));
    var b4 = hexSingle(upper.charAt(2));
    var a4 = hexSingle(upper.charAt(3));
    if (r4 === null || g4 === null || b4 === null || a4 === null) return null;
    return { r: r4, g: g4, b: b4, a: a4 };
  } else if (len === 6) {
    var r6 = hexByte(upper.substring(0, 2));
    var g6 = hexByte(upper.substring(2, 4));
    var b6 = hexByte(upper.substring(4, 6));
    if (r6 === null || g6 === null || b6 === null) return null;
    return { r: r6, g: g6, b: b6, a: 1.0 };
  } else {
    // len === 8
    var r8 = hexByte(upper.substring(0, 2));
    var g8 = hexByte(upper.substring(2, 4));
    var b8 = hexByte(upper.substring(4, 6));
    var a8 = hexByte(upper.substring(6, 8));
    if (r8 === null || g8 === null || b8 === null || a8 === null) return null;
    return { r: r8, g: g8, b: b8, a: a8 };
  }
}

function parseFunctional(text) {
  // Must end with ')'
  if (text.charAt(text.length - 1) !== ")") return null;

  var openIdx = text.indexOf("(");
  if (openIdx < 0) return null;

  var closeIdx = text.length - 1;
  if (openIdx >= closeIdx) return null;

  var name = text.substring(0, openIdx).toLowerCase();
  var body = text.substring(openIdx + 1, closeIdx);

  // No nested parens
  if (body.indexOf("(") >= 0 || body.indexOf(")") >= 0) return null;

  if (name === "rgb" || name === "rgba") {
    return parseRgbBody(body);
  } else if (name === "hsl" || name === "hsla") {
    return parseHslBody(body);
  }
  return null;
}

function parseRgbBody(body) {
  var split = splitChannelsAndAlpha(body);
  if (split === null) return null;

  var channels = split.channels;
  var alpha = split.alpha;

  var r = parseRgbChannel(channels[0]);
  var g = parseRgbChannel(channels[1]);
  var b = parseRgbChannel(channels[2]);
  if (r === null || g === null || b === null) return null;

  // Clamp to 0-255, then convert to 0-1
  r = Math.max(0, Math.min(255, r)) / 255.0;
  g = Math.max(0, Math.min(255, g)) / 255.0;
  b = Math.max(0, Math.min(255, b)) / 255.0;
  var a = alpha !== null ? Math.max(0, Math.min(1, alpha)) : 1.0;

  return { r: r, g: g, b: b, a: a };
}

function parseHslBody(body) {
  var split = splitChannelsAndAlpha(body);
  if (split === null) return null;

  var channels = split.channels;
  var alpha = split.alpha;

  var h = parseHue(channels[0]);
  var s = parsePercent(channels[1]);
  var l = parsePercent(channels[2]);
  if (h === null || s === null || l === null) return null;

  // Normalize hue to 0-360
  var hue = ((h % 360) + 360) % 360;
  var sat = Math.max(0, Math.min(100, s));
  var lit = Math.max(0, Math.min(100, l));

  var rgb = hslToRgb(hue, sat, lit);
  var a = alpha !== null ? Math.max(0, Math.min(1, alpha)) : 1.0;

  return { r: rgb[0], g: rgb[1], b: rgb[2], a: a };
}

function splitChannelsAndAlpha(body) {
  if (body.indexOf(",") >= 0) {
    // Comma syntax: no slash allowed
    if (body.indexOf("/") >= 0) return null;

    var parts = body.split(",").map(function (p) {
      return trimColorWhitespace(p);
    });

    if (parts.length !== 3 && parts.length !== 4) return null;

    // Each part must be non-empty and contain no spaces
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].length === 0 || parts[i].indexOf(" ") >= 0) return null;
    }

    if (parts.length === 4) {
      var alpha = parseAlphaValue(parts[3]);
      if (alpha === null) return null;
      return { channels: [parts[0], parts[1], parts[2]], alpha: alpha };
    }
    return { channels: parts, alpha: null };
  }

  // Space syntax: optional / alpha
  var slashParts = body.split("/").map(function (p) {
    return trimColorWhitespace(p);
  });

  if (slashParts.length > 2) return null;

  // Split channels by spaces
  var channels = slashParts[0].split(/\s+/).filter(function (s) {
    return s.length > 0;
  });

  if (channels.length !== 3) return null;

  if (slashParts.length === 2) {
    // Alpha part must not contain spaces
    if (slashParts[1].indexOf(" ") >= 0) return null;
    var alpha = parseAlphaValue(slashParts[1]);
    if (alpha === null) return null;
    return { channels: channels, alpha: alpha };
  }

  return { channels: channels, alpha: null };
}

function parseRgbChannel(text) {
  var trimmed = trimColorWhitespace(text);
  if (trimmed.charAt(trimmed.length - 1) === "%") {
    var numPart = trimmed.substring(0, trimmed.length - 1);
    var val = strictDouble(numPart);
    if (val === null) return null;
    return (val / 100.0) * 255.0;
  }
  return strictDouble(trimmed);
}

function parseHue(text) {
  var trimmed = trimColorWhitespace(text);
  var lower = trimmed.toLowerCase();
  if (lower.length >= 3 && lower.substring(lower.length - 3) === "deg") {
    var numPart = trimColorWhitespace(lower.substring(0, lower.length - 3));
    return strictDouble(numPart);
  }
  return strictDouble(trimmed);
}

function parsePercent(text) {
  var trimmed = trimColorWhitespace(text);
  if (trimmed.charAt(trimmed.length - 1) !== "%") return null;
  var numPart = trimmed.substring(0, trimmed.length - 1);
  return strictDouble(numPart);
}

function parseAlphaValue(text) {
  var trimmed = trimColorWhitespace(text);
  if (trimmed.charAt(trimmed.length - 1) === "%") {
    var numPart = trimmed.substring(0, trimmed.length - 1);
    var val = strictDouble(numPart);
    if (val === null) return null;
    return val / 100.0;
  }
  return strictDouble(trimmed);
}

// ─── Color Space Conversion ─────────────────────────────────────────────────

function hslToRgb(h, s, l) {
  var sNorm = s / 100.0;
  var lNorm = l / 100.0;

  var c = (1.0 - Math.abs(2.0 * lNorm - 1.0)) * sNorm;
  var x = c * (1.0 - Math.abs(((h / 60.0) % 2) - 1.0));
  var m = lNorm - c / 2.0;

  var r, g, b;

  if (h < 60) {
    r = c; g = x; b = 0;
  } else if (h < 120) {
    r = x; g = c; b = 0;
  } else if (h < 180) {
    r = 0; g = c; b = x;
  } else if (h < 240) {
    r = 0; g = x; b = c;
  } else if (h < 300) {
    r = x; g = 0; b = c;
  } else {
    r = c; g = 0; b = x;
  }

  return [r + m, g + m, b + m];
}

function rgbToHsl(r, g, b) {
  var maxC = Math.max(r, g, b);
  var minC = Math.min(r, g, b);
  var l = (maxC + minC) / 2.0;

  if (maxC === minC) {
    return [0, 0, l * 100.0];
  }

  var diff = maxC - minC;
  var s;
  if (l > 0.5) {
    s = diff / (2.0 - maxC - minC);
  } else {
    s = diff / (maxC + minC);
  }

  var h;
  if (maxC === r) {
    h = ((g - b) / diff) % 6;
  } else if (maxC === g) {
    h = (b - r) / diff + 2;
  } else {
    h = (r - g) / diff + 4;
  }
  h *= 60;
  if (h < 0) h += 360;

  return [h, s * 100.0, l * 100.0];
}

// ─── Formatting ─────────────────────────────────────────────────────────────

function formatHex(r, g, b, a) {
  var ri = Math.round(r * 255);
  var gi = Math.round(g * 255);
  var bi = Math.round(b * 255);

  if (a < 1.0) {
    var ai = Math.round(a * 255);
    return "#" + padHex(ri) + padHex(gi) + padHex(bi) + padHex(ai);
  }
  return "#" + padHex(ri) + padHex(gi) + padHex(bi);
}

function padHex(n) {
  var s = n.toString(16);
  if (s.length === 1) return "0" + s;
  return s;
}

function formatRgb(r, g, b, a) {
  var ri = Math.round(r * 255);
  var gi = Math.round(g * 255);
  var bi = Math.round(b * 255);

  if (a < 1.0) {
    var alphaStr = formatAlpha(a);
    return "rgba(" + ri + ", " + gi + ", " + bi + ", " + alphaStr + ")";
  }
  return "rgb(" + ri + ", " + gi + ", " + bi + ")";
}

function formatHsl(r, g, b, a) {
  // Convert from unquantized channels
  var hsl = rgbToHsl(r, g, b);
  var hStr = formatOneDecimal(hsl[0]);
  var sStr = formatOneDecimal(hsl[1]);
  var lStr = formatOneDecimal(hsl[2]);

  if (a < 1.0) {
    var alphaStr = formatAlpha(a);
    return "hsla(" + hStr + ", " + sStr + "%, " + lStr + "%, " + alphaStr + ")";
  }
  return "hsl(" + hStr + ", " + sStr + "%, " + lStr + "%)";
}

function formatOneDecimal(value) {
  var rounded = Math.round(value * 10) / 10.0;
  if (rounded === Math.round(rounded)) {
    return String(Math.round(rounded));
  }
  return rounded.toFixed(1);
}

function formatAlpha(a) {
  var rounded = Math.round(a * 1000) / 1000.0;
  var formatted = rounded.toFixed(3);
  // Remove trailing zeros after decimal point
  while (formatted.charAt(formatted.length - 1) === "0") {
    formatted = formatted.substring(0, formatted.length - 1);
  }
  if (formatted.charAt(formatted.length - 1) === ".") {
    formatted = formatted.substring(0, formatted.length - 1);
  }
  return formatted;
}

// ─── Strict Number Parsing ──────────────────────────────────────────────────

function strictDouble(text) {
  if (text.length === 0) return null;

  var i = 0;
  if (text.charCodeAt(i) === 43 || text.charCodeAt(i) === 45) { // '+' or '-'
    i++;
  }

  var digits = 0;
  while (i < text.length) {
    var c = text.charCodeAt(i);
    if (c >= 48 && c <= 57) {
      i++;
      digits++;
    } else {
      break;
    }
  }

  if (i < text.length && text.charCodeAt(i) === 46) { // '.'
    i++;
    while (i < text.length) {
      var c2 = text.charCodeAt(i);
      if (c2 >= 48 && c2 <= 57) {
        i++;
        digits++;
      } else {
        break;
      }
    }
  }

  if (digits === 0) return null;

  if (i < text.length && (text.charCodeAt(i) === 101 || text.charCodeAt(i) === 69)) { // 'e' or 'E'
    i++;
    if (i < text.length && (text.charCodeAt(i) === 43 || text.charCodeAt(i) === 45)) {
      i++;
    }
    var expStart = i;
    while (i < text.length) {
      var c3 = text.charCodeAt(i);
      if (c3 >= 48 && c3 <= 57) {
        i++;
      } else {
        break;
      }
    }
    if (i <= expStart) return null;
  }

  if (i !== text.length) return null;

  var value = Number(text);
  if (!isFinite(value)) return null;
  return value;
}

// Foundation .whitespaces contains horizontal Unicode spaces and tab.
function trimColorWhitespace(text) {
  return text.replace(/^[\p{Zs}\t\u200B]+|[\p{Zs}\t\u200B]+$/gu, "");
}
// @endshared
