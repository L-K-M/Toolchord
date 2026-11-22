// html.js — HTML entity escape/unescape for Toolchord.
// Exposes global function: preview(input, options, api)
//
// api.id: "html.escape" | "html.unescape"
// api.limits: { maxInputBytes, maxOutputBytes, maxNestingDepth, outputLimitMessage, nestingLimitMessage }
// api.cancelled(): boolean
// options: (none used)
// input: string | null (null = no input)

function preview(input, options, api) {
  if (api.id === "html.escape") return escapeHTML(input, options, api);
  if (api.id === "html.unescape") return unescapeHTML(input, options, api);
  return { error: "unsupported", message: "Unknown api.id: " + api.id };
}

// ─── HTML4 Entity Table (252 entities + apos) ──────────────────────────────

var HTMLENTITIES = {
  "Aacute": 0x00C1, "aacute": 0x00E1, "Acirc": 0x00C2, "acirc": 0x00E2,
  "acute": 0x00B4, "AElig": 0x00C6, "aelig": 0x00E6, "Agrave": 0x00C0,
  "agrave": 0x00E0, "alefsym": 0x2135, "Alpha": 0x0391, "alpha": 0x03B1,
  "amp": 0x0026, "and": 0x2227, "ang": 0x2220, "apos": 0x0027,
  "Aring": 0x00C5, "aring": 0x00E5, "asymp": 0x2248, "Atilde": 0x00C3,
  "atilde": 0x00E3, "Auml": 0x00C4, "auml": 0x00E4, "bdquo": 0x201E,
  "Beta": 0x0392, "beta": 0x03B2, "brvbar": 0x00A6, "bull": 0x2022,
  "cap": 0x2229, "Ccedil": 0x00C7, "ccedil": 0x00E7, "cedil": 0x00B8,
  "cent": 0x00A2, "Chi": 0x03A7, "chi": 0x03C7, "circ": 0x02C6,
  "clubs": 0x2663, "cong": 0x2245, "copy": 0x00A9, "crarr": 0x21B5,
  "cup": 0x222A, "curren": 0x00A4, "Dagger": 0x2021, "dagger": 0x2020,
  "dArr": 0x21D3, "darr": 0x2193, "deg": 0x00B0, "Delta": 0x0394,
  "delta": 0x03B4, "diams": 0x2666, "divide": 0x00F7, "Eacute": 0x00C9,
  "eacute": 0x00E9, "Ecirc": 0x00CA, "ecirc": 0x00EA, "Egrave": 0x00C8,
  "egrave": 0x00E8, "empty": 0x2205, "emsp": 0x2003, "ensp": 0x2002,
  "Epsilon": 0x0395, "epsilon": 0x03B5, "equiv": 0x2261, "Eta": 0x0397,
  "eta": 0x03B7, "ETH": 0x00D0, "eth": 0x00F0, "Euml": 0x00CB,
  "euml": 0x00EB, "euro": 0x20AC, "exist": 0x2203, "fnof": 0x0192,
  "forall": 0x2200, "frac12": 0x00BD, "frac14": 0x00BC, "frac34": 0x00BE,
  "frasl": 0x2044, "Gamma": 0x0393, "gamma": 0x03B3, "ge": 0x2265,
  "gt": 0x003E, "hArr": 0x21D4, "harr": 0x2194, "hearts": 0x2665,
  "hellip": 0x2026, "Iacute": 0x00CD, "iacute": 0x00ED, "Icirc": 0x00CE,
  "icirc": 0x00EE, "iexcl": 0x00A1, "Igrave": 0x00CC, "igrave": 0x00EC,
  "image": 0x2111, "infin": 0x221E, "int": 0x222B, "Iota": 0x0399,
  "iota": 0x03B9, "iquest": 0x00BF, "isin": 0x2208, "Iuml": 0x00CF,
  "iuml": 0x00EF, "Kappa": 0x039A, "kappa": 0x03BA, "Lambda": 0x039B,
  "lambda": 0x03BB, "lang": 0x2329, "laquo": 0x00AB, "lArr": 0x21D0,
  "larr": 0x2190, "lceil": 0x2308, "ldquo": 0x201C, "le": 0x2264,
  "lfloor": 0x230A, "lowast": 0x2217, "loz": 0x25CA, "lrm": 0x200E,
  "lsaquo": 0x2039, "lsquo": 0x2018, "lt": 0x003C, "macr": 0x00AF,
  "mdash": 0x2014, "micro": 0x00B5, "middot": 0x00B7, "minus": 0x2212,
  "Mu": 0x039C, "mu": 0x03BC, "nabla": 0x2207, "nbsp": 0x00A0,
  "ndash": 0x2013, "ne": 0x2260, "ni": 0x220B, "not": 0x00AC,
  "notin": 0x2209, "nsub": 0x2284, "Ntilde": 0x00D1, "ntilde": 0x00F1,
  "Nu": 0x039D, "nu": 0x03BD, "Oacute": 0x00D3, "oacute": 0x00F3,
  "Ocirc": 0x00D4, "ocirc": 0x00F4, "OElig": 0x0152, "oelig": 0x0153,
  "Ograve": 0x00D2, "ograve": 0x00F2, "oline": 0x203E, "Omega": 0x03A9,
  "omega": 0x03C9, "Omicron": 0x039F, "omicron": 0x03BF, "oplus": 0x2295,
  "or": 0x2228, "ordf": 0x00AA, "ordm": 0x00BA, "Oslash": 0x00D8,
  "oslash": 0x00F8, "Otilde": 0x00D5, "otilde": 0x00F5, "otimes": 0x2297,
  "Ouml": 0x00D6, "ouml": 0x00F6, "para": 0x00B6, "part": 0x2202,
  "permil": 0x2030, "perp": 0x22A5, "Phi": 0x03A6, "phi": 0x03C6,
  "Pi": 0x03A0, "pi": 0x03C0, "piv": 0x03D6, "plusmn": 0x00B1,
  "pound": 0x00A3, "Prime": 0x2033, "prime": 0x2032, "prod": 0x220F,
  "prop": 0x221D, "Psi": 0x03A8, "psi": 0x03C8, "quot": 0x0022,
  "radic": 0x221A, "rang": 0x232A, "raquo": 0x00BB, "rArr": 0x21D2,
  "rarr": 0x2192, "rceil": 0x2309, "rdquo": 0x201D, "real": 0x211C,
  "reg": 0x00AE, "rfloor": 0x230B, "Rho": 0x03A1, "rho": 0x03C1,
  "rlm": 0x200F, "rsaquo": 0x203A, "rsquo": 0x2019, "sbquo": 0x201A,
  "Scaron": 0x0160, "scaron": 0x0161, "sdot": 0x22C5, "sect": 0x00A7,
  "shy": 0x00AD, "Sigma": 0x03A3, "sigma": 0x03C3, "sigmaf": 0x03C2,
  "sim": 0x223C, "spades": 0x2660, "sub": 0x2282, "sube": 0x2286,
  "sum": 0x2211, "sup": 0x2283, "sup1": 0x00B9, "sup2": 0x00B2,
  "sup3": 0x00B3, "supe": 0x2287, "szlig": 0x00DF, "Tau": 0x03A4,
  "tau": 0x03C4, "there4": 0x2234, "Theta": 0x0398, "theta": 0x03B8,
  "thetasym": 0x03D1, "thinsp": 0x2009, "THORN": 0x00DE, "thorn": 0x00FE,
  "tilde": 0x02DC, "times": 0x00D7, "trade": 0x2122, "Uacute": 0x00DA,
  "uacute": 0x00FA, "uArr": 0x21D1, "uarr": 0x2191, "Ucirc": 0x00DB,
  "ucirc": 0x00FB, "Ugrave": 0x00D9, "ugrave": 0x00F9, "uml": 0x00A8,
  "upsih": 0x03D2, "Upsilon": 0x03A5, "upsilon": 0x03C5, "Uuml": 0x00DC,
  "uuml": 0x00FC, "weierp": 0x2118, "Xi": 0x039E, "xi": 0x03BE,
  "Yacute": 0x00DD, "yacute": 0x00FD, "yen": 0x00A5, "Yuml": 0x0178,
  "yuml": 0x00FF, "Zeta": 0x0396, "zeta": 0x03B6, "zwj": 0x200D,
  "zwnj": 0x200C
};

// ─── Helpers ────────────────────────────────────────────────────────────────

// Convert a code point to a JavaScript string (handles surrogate pairs).
function codePointToString(cp) {
  if (cp <= 0xFFFF) {
    return String.fromCharCode(cp);
  }
  cp -= 0x10000;
  return String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
}

// Get Unicode scalar values from a string as an array of code points.
function unicodeScalars(str) {
  var result = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length) {
      var lo = str.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        result.push(((c - 0xD800) << 10) + (lo - 0xDC00) + 0x10000);
        i++;
        continue;
      }
    }
    result.push(c);
  }
  return result;
}

// ─── Escape ─────────────────────────────────────────────────────────────────

function escapeHTML(input, options, api) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Paste text to escape." };
  }

  var scalars = unicodeScalars(input);
  var parts = [];
  var outputByteCount = 0;
  var maxBytes = api.limits.maxOutputBytes;

  for (var i = 0; i < scalars.length; i++) {
    if (i % 4096 === 0 && api.cancelled()) return { error: "cancelled", message: "" };

    var entity;
    var cp = scalars[i];
    if (cp === 0x26) entity = "&amp;";
    else if (cp === 0x3C) entity = "&lt;";
    else if (cp === 0x3E) entity = "&gt;";
    else if (cp === 0x22) entity = "&quot;";
    else if (cp === 0x27) entity = "&#39;";
    else entity = null;

    if (entity) {
      outputByteCount += entity.length;
      if (outputByteCount > maxBytes) {
        return { error: "tooLarge", message: api.limits.outputLimitMessage };
      }
      parts.push(entity);
    } else {
      // Count UTF-8 bytes for the character
      if (cp < 0x80) outputByteCount += 1;
      else if (cp < 0x800) outputByteCount += 2;
      else if (cp < 0x10000) outputByteCount += 3;
      else outputByteCount += 4;

      if (outputByteCount > maxBytes) {
        return { error: "tooLarge", message: api.limits.outputLimitMessage };
      }
      parts.push(codePointToString(cp));
    }
  }

  return {
    primaryText: parts.join(""),
    status: "Escaped"
  };
}

// ─── Unescape ───────────────────────────────────────────────────────────────

var MAX_REFERENCE_LENGTH = 32;

function unescapeHTML(input, options, api) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Paste text to unescape." };
  }

  var scalars = unicodeScalars(input);
  var result = [];
  var invalidRefs = [];
  var unknownNames = [];
  var unknownSeen = new Set();
  var index = 0;

  while (index < scalars.length) {
    if (index % 4096 === 0 && api.cancelled()) return { error: "cancelled", message: "" };

    var scalar = scalars[index];
    if (scalar !== 0x26) { // Not '&'
      result.push(scalar);
      index++;
      continue;
    }

    // Try numeric reference first
    var numeric = numericReference(scalars, index);
    if (numeric) {
      if (numeric.scalar !== null) {
        result.push(numeric.scalar);
      } else {
        result.push(0xFFFD);
        invalidRefs.push(numeric.spelling);
      }
      index = numeric.end;
    } else {
      // Try named reference
      var named = namedReference(scalars, index);
      if (named) {
        var codePoint = HTMLENTITIES[named.name];
        if (Object.prototype.hasOwnProperty.call(HTMLENTITIES, named.name)) {
          result.push(codePoint);
        } else {
          // Unknown entity — leave unchanged
          for (var k = index; k < named.end; k++) {
            result.push(scalars[k]);
          }
          if (!unknownSeen.has(named.name)) {
            unknownSeen.add(named.name);
            unknownNames.push(named.name);
          }
        }
        index = named.end;
      } else {
        result.push(scalar);
        index++;
      }
    }
  }

  // Build warnings
  var warnings = [];
  var invalidLimit = Math.min(invalidRefs.length, 5);
  for (var wi = 0; wi < invalidLimit; wi++) {
    warnings.push('Replaced invalid character reference \u201C' + invalidRefs[wi] + '\u201D with U+FFFD.');
  }
  if (invalidRefs.length > 5) {
    warnings.push("\u2026and " + (invalidRefs.length - 5) + " more invalid character references.");
  }
  var unknownLimit = Math.min(unknownNames.length, 5);
  for (var wj = 0; wj < unknownLimit; wj++) {
    warnings.push('Unknown entity \u201C&' + unknownNames[wj] + ';\u201D was left unchanged.');
  }
  if (unknownNames.length > 5) {
    warnings.push("\u2026and " + (unknownNames.length - 5) + " more unknown entities.");
  }

  var output = "";
  for (var ri = 0; ri < result.length; ri++) {
    output += codePointToString(result[ri]);
  }

  return {
    primaryText: output,
    status: "Unescaped",
    warnings: warnings
  };
}

// Parse &#123; or &#x1F600; starting at start.
// Returns { scalar: number|null, end: number, spelling: string } or null.
function numericReference(scalars, start) {
  var index = start + 1;
  if (index >= scalars.length || scalars[index] !== 0x23) return null; // '#'
  index++;
  var radix = 10;
  if (index < scalars.length && (scalars[index] === 0x78 || scalars[index] === 0x58)) { // 'x' or 'X'
    radix = 16;
    index++;
  }
  var digitsStart = index;
  var value = 0;
  while (index < scalars.length && (index - digitsStart) < MAX_REFERENCE_LENGTH) {
    var digit = digitValue(scalars[index], radix);
    if (digit === null) break;
    // Saturate above the Unicode range
    if (value <= 0x10FFFF) {
      value = value * radix + digit;
    }
    index++;
  }
  if (index <= digitsStart) return null; // No digits
  if (index >= scalars.length || scalars[index] !== 0x3B) return null; // ';'
  var end = index + 1;

  // Build spelling string
  var spelling = "";
  for (var si = start; si < end; si++) {
    spelling += codePointToString(scalars[si]);
  }

  var isValid = value !== 0 && value < 0xD800 || (value > 0xDFFF && value <= 0x10FFFF);
  var scalar = isValid ? value : null;
  return { scalar: scalar, end: end, spelling: spelling };
}

// Parse &name; starting at start.
// Returns { name: string, end: number } or null.
function namedReference(scalars, start) {
  var index = start + 1;
  var nameStart = index;
  while (index < scalars.length && (index - nameStart) < MAX_REFERENCE_LENGTH) {
    var s = scalars[index];
    if (s > 0x7F) break; // Not ASCII
    // Check if alphabetic or digit
    if ((s >= 0x41 && s <= 0x5A) || (s >= 0x61 && s <= 0x7A) || (s >= 0x30 && s <= 0x39)) {
      index++;
    } else {
      break;
    }
  }
  if (index <= nameStart) return null; // No name chars
  if (index >= scalars.length || scalars[index] !== 0x3B) return null; // ';'
  var end = index + 1;
  var name = "";
  for (var ni = nameStart; ni < index; ni++) {
    name += String.fromCharCode(scalars[ni]);
  }
  return { name: name, end: end };
}

function digitValue(scalar, radix) {
  if (scalar >= 0x30 && scalar <= 0x39) return scalar - 0x30; // '0'-'9'
  if (radix === 16) {
    if (scalar >= 0x61 && scalar <= 0x66) return scalar - 0x61 + 10; // 'a'-'f'
    if (scalar >= 0x41 && scalar <= 0x46) return scalar - 0x41 + 10; // 'A'-'F'
  }
  return null;
}
