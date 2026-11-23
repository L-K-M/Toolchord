/* @toolchord
{
  "apiVersion": 1,
  "id": "markdown.plaintext",
  "title": "Convert Markdown to Plain Text",
  "summary": "Remove Markdown syntax, keep the text",
  "options": [
    {"id": "links", "label": "Show link URLs", "defaultValue": "false"}
  ],
  "palette": {
    "group": "markdown", "groupTitle": "Markdown",
    "aliases": ["markdown to text", "markdown to plain text", "strip markdown",
                "remove markdown", "md to text", "plain text"],
    "glyph": "M↓", "copyNoun": "text",
    "suggestions": [{"when": ["markdown"], "score": 80}]
  }
}
*/
function preview(input, options, api) {
    return convertMarkup(input, options, api, "markdown.plaintext");
}

// @shared json.format/utf8
// JavaScriptCore does not provide the browser's TextEncoder/TextDecoder APIs.
const utf8 = {
    size(text) {
        let count = 0;
        for (const scalar of text) {
            const n = scalar.codePointAt(0);
            count += n < 128 ? 1 : n < 2048 ? 2 : n < 65536 ? 3 : 4;
        }
        return count;
    },
    encode(text) {
        const out = [];
        for (const scalar of text) {
            const n = scalar.codePointAt(0);
            if (n < 128) out.push(n);
            else if (n < 2048) out.push(192 | n >> 6, 128 | n & 63);
            else if (n < 65536) out.push(224 | n >> 12, 128 | n >> 6 & 63, 128 | n & 63);
            else out.push(240 | n >> 18, 128 | n >> 12 & 63, 128 | n >> 6 & 63, 128 | n & 63);
        }
        return out;
    },
    decode(bytes) {
        const chunks = [], units = [];
        for (let i = 0; i < bytes.length;) {
            const lead = bytes[i++];
            let n = lead, tail = 0, minimum = 0;
            if (lead >= 128) {
                if (lead >= 194 && lead <= 223) { n = lead & 31; tail = 1; minimum = 128; }
                else if (lead >= 224 && lead <= 239) { n = lead & 15; tail = 2; minimum = 2048; }
                else if (lead >= 240 && lead <= 244) { n = lead & 7; tail = 3; minimum = 65536; }
                else return null;
                for (let k = 0; k < tail; k++) {
                    if (i === bytes.length || (bytes[i] & 192) !== 128) return null;
                    n = n * 64 + (bytes[i++] & 63);
                }
                if (n < minimum || n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff)) return null;
            }
            if (n <= 65535) units.push(n);
            else { n -= 65536; units.push(0xd800 + (n >> 10), 0xdc00 + (n & 1023)); }
            if (units.length >= 4096) { chunks.push(String.fromCharCode(...units)); units.length = 0; }
        }
        return chunks.join('') + String.fromCharCode(...units);
    },
    location(text, offset) {
        let line = 1, column = 1;
        for (let i = 0; i < offset;) {
            const n = text.codePointAt(i);
            i += n > 65535 ? 2 : 1;
            if (n === 13) { if (text[i] === '\n' && i < offset) i++; line++; column = 1; }
            else if (n === 10) { line++; column = 1; }
            else column++;
        }
        return {line,column};
    },
    trimBounds(text) {
        const space = /[\p{White_Space}\u200b]/u;
        let first = 0, end = text.length;
        while (first < end && space.test(text[first])) first++;
        while (end > first && space.test(text[end-1])) end--;
        return [first,end];
    }
};
// @endshared

// @shared html.escape/html
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
// @endshared

// @shared html.plaintext/markup-html
function htmlToText(input, showLinks, api) {

    var raw = {"script":1,"style":1,"title":1,"iframe":1,"noscript":1,"noembed":1,"noframes":1};
    var hidden = {"template":1,"object":1,"svg":1,"math":1,"canvas":1,"audio":1,"video":1,"datalist":1};
    var paragraphs = {"p":1,"h1":1,"h2":1,"h3":1,"h4":1,"h5":1,"h6":1,"pre":1,"listing":1,"blockquote":1,
        "ul":1,"ol":1,"menu":1,"dl":1,"table":1,"hr":1,"figure":1,"address":1,"fieldset":1,"details":1};
    var lines = {"article":1,"aside":1,"body":1,"caption":1,"center":1,"dd":1,"dialog":1,"div":1,"dt":1,
        "figcaption":1,"footer":1,"form":1,"header":1,"hgroup":1,"html":1,"legend":1,"li":1,"main":1,
        "nav":1,"option":1,"search":1,"section":1,"summary":1,"tbody":1,"textarea":1,"tfoot":1,"thead":1,"tr":1};
    var lists = {"ul":1,"ol":1,"menu":1,"dl":1};
    var enclosingEnds = {};
    var _k;
    for (_k in paragraphs) enclosingEnds[_k] = 1;
    for (_k in lines) enclosingEnds[_k] = 1;
    enclosingEnds["td"] = 1;
    enclosingEnds["th"] = 1;
    var closesParagraph = {"address":1,"article":1,"aside":1,"blockquote":1,"center":1,"details":1,"dialog":1,
        "div":1,"dl":1,"fieldset":1,"figcaption":1,"figure":1,"footer":1,"form":1,"h1":1,"h2":1,"h3":1,
        "h4":1,"h5":1,"h6":1,"header":1,"hgroup":1,"hr":1,"listing":1,"main":1,"menu":1,"nav":1,"ol":1,
        "p":1,"pre":1,"search":1,"section":1,"summary":1,"table":1,"ul":1};
    var voidEls = {"area":1,"base":1,"br":1,"col":1,"embed":1,"hr":1,"img":1,"input":1,"link":1,"meta":1,"source":1,"track":1,"wbr":1};
    var foreignRoots = {"svg":1,"math":1};
    var maxHiddenInner = 256;

    function has(obj, key) { return Object.hasOwn(obj, key); }

    function arrContains(arr, val) { return arr.indexOf(val) >= 0; }

    function startTagEnds(h, start, inner) {
        switch (h) {
            case "p":
                if (!has(closesParagraph, start)) return false;
                for (var i = 0; i < inner.length; i++) {
                    if (inner[i] === "button" || inner[i] === "table" || inner[i] === "td" ||
                        inner[i] === "th" || inner[i] === "caption" || inner[i] === "template" ||
                        inner[i] === "object") return false;
                }
                return true;
            case "li": return start === "li" && !arrContains(inner, "ul") && !arrContains(inner, "ol") && !arrContains(inner, "menu") && !arrContains(inner, "dl");
            case "dt":
            case "dd":
                return (start === "dt" || start === "dd") && !arrContains(inner, "dl");
            case "option": return start === "option" || start === "optgroup";
            case "tr": return start === "tr" && !arrContains(inner, "table");
            case "td":
            case "th":
                return (start === "td" || start === "th" || start === "tr") && !arrContains(inner, "table");
            default: return false;
        }
    }

    function isHiddenByAttribute(tag) {
        if (tag.attributes["hidden"] !== undefined) return true;
        var style = tag.attributes["style"];
        if (!style) return false;
        var display;
        var decls = style.split(";");
        for (var d = 0; d < decls.length; d++) {
            var decl = decls[d];
            var colonIdx = decl.indexOf(":");
            if (colonIdx < 0) continue;
            var prop = decl.substring(0, colonIdx).trim().toLowerCase();
            if (prop !== "display") continue;
            var val = decl.substring(colonIdx + 1).trim().toLowerCase();
            if (val.length > 10 && val.substring(val.length - 10) === "!important") {
                val = val.substring(0, val.length - 10).trim();
            }
            display = val;
        }
        return display === "none";
    }

    function opensHiddenContent(tag) {
        if (tag.end) return false;
        if (has(raw, tag.name) || (tag.name === "textarea" && isHiddenByAttribute(tag))) return true;
        if (has(voidEls, tag.name)) return false;
        if (tag.selfClosing && has(foreignRoots, tag.name)) return false;
        return has(hidden, tag.name) || isHiddenByAttribute(tag);
    }

    // HTML list markers in the original tools accept signed 64-bit integers.
    // Bound the source before constructing a BigInt, including leading zeros.
    function ordinal(text, fallback) {
        if (text === undefined || !/^[+-]?\d+$/.test(text)) return fallback;
        const digits = text.replace(/^[+-]?0*/, '') || '0';
        if (digits.length > 19) return fallback;
        const n = BigInt((text[0] === '-' ? '-' : '') + digits);
        return n >= -9223372036854775808n && n <= 9223372036854775807n ? n : fallback;
    }

    function markupLinkSuffix(text, url) {
        var trimmed = text.trim();
        if (!url || url.charAt(0) === "#" || url.toLowerCase().indexOf("javascript:") === 0) return "";
        var short = url;
        var lowerUrl = url.toLowerCase();
        if (lowerUrl.indexOf("mailto:") === 0) short = url.substring(7);
        else if (lowerUrl.indexOf("http://") === 0) short = url.substring(7);
        else if (lowerUrl.indexOf("https://") === 0) short = url.substring(8);
        return (trimmed === url || trimmed === short) ? "" : " (" + url + ")";
    }

    function PlainTextWriter() {
        this.bytes = [];
        this.prefixes = [];
        this.emittedPrefixes = 0;
        this.pendingBoundary = 0;
        this.pendingEndings = [];
        this.preserveLeadingBreaks = false;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        this.lineVerbatim = false;
        this.trailingBreaks = 0;
        this.ticks = 0;
        this.meaningfulEnd = 0;
        this.lastContentVerbatim = false;
        this.boundaryPrefixFloor = Infinity;
    }

    PlainTextWriter.prototype.check = function () {
        this.ticks++;
        if (this.ticks % 2048 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
        if (this.bytes.length > api.limits.maxOutputBytes) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
    };

    PlainTextWriter.prototype.append = function (text) {
        var encoded = utf8.encode(text);
        if (encoded.length > api.limits.maxOutputBytes - this.bytes.length)
            throw { error: "tooLarge", message: api.limits.outputLimitMessage };
        for (const byte of encoded) this.bytes.push(byte);
        this.check();
    };

    PlainTextWriter.prototype.trimLine = function () {
        if (!this.lineVerbatim) {
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) {
                this.bytes.pop();
            }
        }
        if (this.bytes.length < this.meaningfulEnd) this.meaningfulEnd = this.bytes.length;
    };

    PlainTextWriter.prototype.boundary = function (count) {
        this.pendingSpace = false;
        if (!this.lineContent && this.trailingBreaks === 0 && this.pendingEndings.length === 0 && this.bytes.length > 0) return;
        if (count > this.pendingBoundary) this.pendingBoundary = count;
        if (this.prefixes.length < this.boundaryPrefixFloor) this.boundaryPrefixFloor = this.prefixes.length;
    };

    PlainTextWriter.prototype.newline = function (blank, ending, prefixLimit) {
        if (blank === undefined) blank = false;
        if (ending === undefined) ending = "\n";
        if (prefixLimit === undefined) prefixLimit = Infinity;
        this.trimLine();
        if (blank) {
            var lim = prefixLimit < this.prefixes.length ? prefixLimit : this.prefixes.length;
            for (var i = 0; i < lim; i++) {
                if (this.prefixes[i].quote) this.append(this.prefixes[i].text);
            }
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) this.bytes.pop();
        }
        this.append(ending);
        this.trailingBreaks++;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        this.lineVerbatim = false;
        this.emittedPrefixes = 0;
    };

    PlainTextWriter.prototype.prepare = function (flushMarkerGap) {
        if (flushMarkerGap === undefined) flushMarkerGap = true;
        var needed = this.pendingBoundary > this.trailingBreaks + this.pendingEndings.length
            ? this.pendingBoundary : this.trailingBreaks + this.pendingEndings.length;
        if (needed > 0) {
            if (this.bytes.length > 0 || this.preserveLeadingBreaks) {
                while (this.trailingBreaks + this.pendingEndings.length < needed) {
                    this.pendingEndings.push("\n");
                }
                var floor = this.boundaryPrefixFloor < this.prefixes.length ? this.boundaryPrefixFloor : this.prefixes.length;
                for (var i = 0; i < this.pendingEndings.length; i++) {
                    this.newline(this.trailingBreaks > 0, this.pendingEndings[i], floor);
                }
            }
            this.pendingBoundary = 0;
            this.pendingEndings = [];
            this.preserveLeadingBreaks = false;
            this.boundaryPrefixFloor = Infinity;
        }
        if (this.markerGap && flushMarkerGap) {
            this.append(" ");
            this.markerGap = false;
        }
        while (this.emittedPrefixes < this.prefixes.length) {
            this.append(this.prefixes[this.emittedPrefixes].text);
            this.emittedPrefixes++;
        }
    };

    PlainTextWriter.prototype.pushQuote = function () {
        this.prefixes.push({ text: "> ", quote: true, item: false });
    };

    PlainTextWriter.prototype.pushIndent = function (width) {
        var s = "";
        for (var i = 0; i < width; i++) s += " ";
        this.prefixes.push({ text: s, quote: false, item: false });
    };

    PlainTextWriter.prototype.popPrefix = function () {
        if (this.prefixes.length > 0) {
            var last = this.prefixes.pop();
            if (last.item) this.lineContent = true;
        }
        if (this.emittedPrefixes > this.prefixes.length) this.emittedPrefixes = this.prefixes.length;
    };

    PlainTextWriter.prototype.beginItem = function (marker) {
        this.prepare();
        if (this.pendingSpace && this.lineContent) this.append(" ");
        this.pendingSpace = false;
        // marker without trailing space
        this.append(marker.substring(0, marker.length - 1));
        this.markerGap = true;
        var pad = "";
        for (var i = 0; i < marker.length; i++) pad += " ";
        this.prefixes.push({ text: pad, quote: false, item: true });
        this.emittedPrefixes = this.prefixes.length;
        this.trailingBreaks = 0;
        this.meaningfulEnd = this.bytes.length;
        this.lastContentVerbatim = false;
    };

    PlainTextWriter.prototype.deferBreak = function (ending, verbatim) {
        if (verbatim === undefined) verbatim = false;
        while (this.trailingBreaks + this.pendingEndings.length < this.pendingBoundary) {
            this.pendingEndings.push("\n");
        }
        this.pendingEndings.push(ending);
        this.pendingBoundary = 0;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        if (verbatim) this.preserveLeadingBreaks = true;
        this.check();
    };

    PlainTextWriter.prototype.hardBreak = function () {
        this.deferBreak("\n");
    };

    PlainTextWriter.prototype.write = function (text, verbatim, collapse) {
        if (verbatim === undefined) verbatim = false;
        if (collapse === undefined) collapse = true;
        var previousCR = false;
        for (var i = 0; i < text.length; i++) {
            var cp = text.charCodeAt(i);
            // Handle surrogate pairs
            if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
                var lo = text.charCodeAt(i + 1);
                if (lo >= 0xDC00 && lo <= 0xDFFF) {
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    i++;
                }
            }
            this.check();
            if (verbatim) {
                if (cp === 0x0A && previousCR) {
                    this.pendingEndings[this.pendingEndings.length - 1] = "\r\n";
                    previousCR = false;
                    continue;
                }
                if (cp === 0x0D || cp === 0x0A) {
                    this.lineVerbatim = true;
                    this.deferBreak(cp === 0x0D ? "\r" : "\n", true);
                    previousCR = cp === 0x0D;
                    continue;
                }
                previousCR = false;
                this.prepare();
                this.lineVerbatim = true;
                var ch = cp === 0x00A0 ? " " : String.fromCodePoint(cp);
                this.append(ch);
                this.lineContent = true;
                this.trailingBreaks = 0;
                this.meaningfulEnd = this.bytes.length;
                this.lastContentVerbatim = true;
            } else if (collapse && (cp === 0x20 || cp === 0x09 || cp === 0x0D || cp === 0x0A || cp === 0x0C)) {
                if (this.lineContent) this.pendingSpace = true;
            } else {
                this.prepare();
                if (this.pendingSpace && this.lineContent) this.append(" ");
                this.pendingSpace = false;
                var ch2 = cp === 0x00A0 ? " " : String.fromCodePoint(cp);
                this.append(ch2);
                this.lineContent = true;
                this.trailingBreaks = 0;
                this.meaningfulEnd = this.bytes.length;
                this.lastContentVerbatim = false;
            }
        }
    };

    PlainTextWriter.prototype.row = function (cells) {
        this.prepare();
        for (var i = 0; i < cells.length; i++) {
            if (i > 0) this.append("\t");
            this.append(cells[i]);
        }
        this.lineContent = true;
        this.trailingBreaks = 0;
        this.meaningfulEnd = this.bytes.length;
        this.lastContentVerbatim = false;
    };

    PlainTextWriter.prototype.finish = function () {
        if (this.meaningfulEnd < this.bytes.length) {
            this.bytes = this.bytes.slice(0, this.meaningfulEnd);
        }
        if (!this.lastContentVerbatim) {
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) this.bytes.pop();
        }
        while (this.bytes.length > 0 && (this.bytes[this.bytes.length - 1] === 10 || this.bytes[this.bytes.length - 1] === 13)) {
            this.bytes.pop();
        }
        return utf8.decode(this.bytes);
    };

    function decodeEntities(text) {
        return text.replace(/&(?:#([0-9]{1,32})|#[xX]([0-9a-fA-F]{1,32})|([a-zA-Z0-9]{1,32}));/g,
            (raw, decimal, hex, name) => {
                if (name) return Object.hasOwn(HTMLENTITIES, name) ? String.fromCodePoint(HTMLENTITIES[name]) : raw;
                const point = parseInt(decimal || hex, decimal ? 10 : 16);
                return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff)
                    ? String.fromCodePoint(point) : '\uFFFD';
            });
    }

    function isSpace(b) { return b === 32 || b === 9 || b === 10 || b === 13 || b === 12; }
    function isLetter(b) { return (b >= 65 && b <= 90) || (b >= 97 && b <= 122); }
    function toLower(b) { return (b >= 65 && b <= 90) ? b + 32 : b; }

    function parseTag(bytes, start) {
        var i = start + 1;
        var end = false;
        if (i < bytes.length && bytes[i] === 47) { end = true; i++; }
        if (i >= bytes.length || !isLetter(bytes[i])) return null;
        var nameStart = i;
        while (i < bytes.length && (isLetter(bytes[i]) || (bytes[i] >= 48 && bytes[i] <= 57) || bytes[i] === 45 || bytes[i] === 58 || bytes[i] === 46)) i++;
        var nameBytes = [];
        for (var j = nameStart; j < i; j++) nameBytes.push(toLower(bytes[j]));
        var name = utf8.decode(nameBytes);
        var attrs = Object.create(null);
        var selfClosing = false;
        while (i < bytes.length) {
            if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
            while (i < bytes.length && isSpace(bytes[i])) i++;
            if (i >= bytes.length) return null;
            if (bytes[i] === 62) return { tag: { name: name, end: end, attributes: attrs, selfClosing: selfClosing }, next: i + 1 };
            if (bytes[i] === 47) { selfClosing = true; i++; continue; }
            selfClosing = false;
            var a = i;
            while (i < bytes.length && !isSpace(bytes[i]) && bytes[i] !== 61 && bytes[i] !== 62 && bytes[i] !== 47) i++;
            if (a === i) { i++; continue; }
            var keyBytes = [];
            for (var k = a; k < i; k++) keyBytes.push(toLower(bytes[k]));
            var key = utf8.decode(keyBytes);
            while (i < bytes.length && isSpace(bytes[i])) i++;
            var value = "";
            if (i < bytes.length && bytes[i] === 61) {
                i++;
                while (i < bytes.length && isSpace(bytes[i])) i++;
                if (i < bytes.length && (bytes[i] === 34 || bytes[i] === 39)) {
                    var quote = bytes[i]; i++;
                    var va = i;
                    while (i < bytes.length && bytes[i] !== quote) {
                        if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
                        i++;
                    }
                    if (i >= bytes.length) return null;
                    var valBytes = [];
                    for (var v = va; v < i; v++) valBytes.push(bytes[v]);
                    value = utf8.decode(valBytes);
                    i++;
                } else {
                    var va2 = i;
                    while (i < bytes.length && !isSpace(bytes[i]) && bytes[i] !== 62) i++;
                    var valBytes2 = [];
                    for (var v2 = va2; v2 < i; v2++) valBytes2.push(bytes[v2]);
                    value = utf8.decode(valBytes2);
                }
            }
            if (!Object.hasOwn(attrs, key)) {
                attrs[key] = decodeEntities(value);
            }
        }
        return null;
    }

    var b = utf8.encode(input);
    var frames = [];
    var depth = 0;
    var hiddenName = null;
    var hiddenInner = [];
    var rawName = null;
    var hiddenOverflow = false;
    var hiddenSameDepth = 0;
    var hiddenByAttribute = false;
    var rawKeepsText = false;
    var preDepth = 0;
    var dropFirstBreak = false;
    var anchor = null; // { url, text }
    var cell = null; // PlainTextWriter or null
    var cells = [];
    var rowOpen = false;
    var tableDepth = 0;
    var rowBytes = 0;
    var work = 0;

    var writer = new PlainTextWriter();

    function current() { return cell !== null ? cell : writer; }

    function textOut(s, verbatim) {
        if (verbatim === undefined) verbatim = false;
        if (anchor !== null) anchor.text += s;
        if (cell !== null) {
            cell.write(s, verbatim);
        } else {
            writer.write(s, verbatim);
        }
    }

    function boundary(n) {
        if (cell !== null) {
            cell.pendingSpace = cell.lineContent;
        } else {
            writer.boundary(n);
        }
    }

    function endCell() {
        if (cell !== null) {
            var text = cell.finish().trim();
            rowBytes += utf8.size(text) + (cells.length === 0 ? 0 : 1);
            if (rowBytes > api.limits.maxOutputBytes - writer.bytes.length)
                throw { error: "tooLarge", message: api.limits.outputLimitMessage };
            cells.push(text);
            cell = null;
        }
    }

    function endRow() {
        endCell();
        if (rowOpen || cells.length > 0) {
            writer.boundary(1);
            writer.row(cells);
            writer.boundary(1);
        }
        cells = [];
        rowOpen = false;
        rowBytes = 0;
    }

    function close(name) {
        var index = -1;
        for (var i = frames.length - 1; i >= 0; i--) {
            if (frames[i].name === name) { index = i; break; }
        }
        if (index < 0) return;
        for (var j = frames.length - 1; j >= index; j--) {
            var frame = frames[j];
            if (frame.prefix) current().popPrefix();
            if (frame.name === "blockquote" || has(lists, frame.name) || frame.name === "dd") depth--;
        }
        frames.length = index;
    }

    function open(name, prefix, next) {
        if (next === undefined) next = 1;
        if (name === "blockquote" || has(lists, name) || name === "dd") {
            depth++;
            if (depth > api.limits.maxNestingDepth)
                throw { error: "tooLarge", message: api.limits.nestingLimitMessage };
        }
        frames.push({ name: name, prefix: prefix, next: next });
    }

    var i = 0;
    while (i < b.length) {
        work++;
        if (work % 2048 === 1 && api.cancelled())
            throw { error: "cancelled", message: "Evaluation was cancelled." };

        // Raw text mode
        if (rawName !== null) {
            var target = utf8.encode("</" + rawName);
            var rawStart = i;
            var found = false;
            while (i < b.length) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                if (b[i] === 60 && i + target.length < b.length) {
                    var matches = true;
                    for (var tj = 0; tj < target.length; tj++) {
                        if (toLower(b[i + tj]) !== target[tj]) { matches = false; break; }
                    }
                    if (matches && (isSpace(b[i + target.length]) || b[i + target.length] === 47 || b[i + target.length] === 62)) {
                        found = true;
                        break;
                    }
                }
                i++;
            }
            rawName = null;
            if (rawKeepsText) {
                rawKeepsText = false;
                var s = decodeEntities(utf8.decode(b.slice(rawStart, i)));
                // Drop first break after opening tag
                if (s.length >= 2 && s.charCodeAt(0) === 0x0D && s.charCodeAt(1) === 0x0A) s = s.substring(2);
                else if (s.length > 0 && (s.charCodeAt(0) === 0x0A || s.charCodeAt(0) === 0x0D)) s = s.substring(1);
                textOut(s, true);
            }
            if (!found) break;
        }

        // Text node
        if (b[i] !== 60) {
            var start = i;
            while (i < b.length && b[i] !== 60) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                i++;
            }
            if (hiddenName === null) {
                var s2 = decodeEntities(utf8.decode(b.slice(start, i)));
                if (dropFirstBreak) {
                    if (s2.length >= 2 && s2.charCodeAt(0) === 0x0D && s2.charCodeAt(1) === 0x0A) s2 = s2.substring(2);
                    else if (s2.length > 0 && (s2.charCodeAt(0) === 0x0A || s2.charCodeAt(0) === 0x0D)) s2 = s2.substring(1);
                    dropFirstBreak = false;
                }
                textOut(s2, preDepth > 0);
            }
            continue;
        }

        dropFirstBreak = false;

        // Comments, CDATA, processing instructions, DOCTYPE
        if (i + 1 < b.length && (b[i + 1] === 33 || b[i + 1] === 63)) {
            var comment = (i + 3 < b.length && b[i + 1] === 33 && b[i + 2] === 45 && b[i + 3] === 45);
            var cdata = false;
            if (i + 8 < b.length) {
                var cdataTarget = [60, 33, 91, 67, 68, 65, 84, 65, 91];
                cdata = true;
                for (var ci = 0; ci < 9; ci++) {
                    if (b[i + ci] !== cdataTarget[ci]) { cdata = false; break; }
                }
            }
            i += comment ? 4 : (cdata ? 9 : 2);
            while (i < b.length) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                if (comment && i + 2 < b.length && b[i] === 45 && b[i + 1] === 45 && b[i + 2] === 62) { i += 3; break; }
                if (cdata && i + 2 < b.length && b[i] === 93 && b[i + 1] === 93 && b[i + 2] === 62) { i += 3; break; }
                if (!comment && !cdata && b[i] === 62) { i += 1; break; }
                i++;
            }
            continue;
        }

        // Check valid tag start
        var validStart = false;
        if (i + 1 < b.length) {
            if (isLetter(b[i + 1])) validStart = true;
            else if (b[i + 1] === 47 && i + 2 < b.length && isLetter(b[i + 2])) validStart = true;
        }
        if (!validStart) {
            if (hiddenName === null) textOut("<", preDepth > 0);
            i++;
            continue;
        }

        var result = parseTag(b, i);
        if (!result) break;
        var t = result.tag;
        i = result.next;

        // Inside hidden element
        if (hiddenName !== null) {
            var impliedEnds = hiddenByAttribute && !hiddenOverflow && !arrContains(hiddenInner, "template") && !arrContains(hiddenInner, "svg") && !arrContains(hiddenInner, "math");
            if (t.end) {
                if (!hiddenOverflow) {
                    var openIdx = hiddenInner.lastIndexOf(t.name);
                    if (openIdx >= 0) {
                        // Decrement hiddenSameDepth for matching elements
                        for (var si = openIdx; si < hiddenInner.length; si++) {
                            if (hiddenInner[si] === hiddenName) hiddenSameDepth--;
                        }
                        hiddenInner = hiddenInner.slice(0, openIdx);
                        continue;
                    }
                }
                if (t.name === hiddenName) {
                    if (hiddenSameDepth > 0) {
                        hiddenSameDepth--;
                    } else {
                        hiddenName = null;
                        hiddenInner = [];
                        hiddenOverflow = false;
                    }
                    continue;
                }
                if (impliedEnds && has(enclosingEnds, t.name)) {
                    // Fall through: enclosing end closes hidden
                } else {
                    continue;
                }
            } else if (!(impliedEnds && startTagEnds(hiddenName, t.name, hiddenInner))) {
                if (has(raw, t.name) || t.name === "textarea") { rawName = t.name; rawKeepsText = false; }
                var inForeignContent = has(foreignRoots, hiddenName);
                if (!inForeignContent) {
                    for (var fi = 0; fi < hiddenInner.length; fi++) {
                        if (has(foreignRoots, hiddenInner[fi])) { inForeignContent = true; break; }
                    }
                }
                var selfClosingForeign = t.selfClosing && (inForeignContent || has(foreignRoots, t.name));
                if (!selfClosingForeign && !has(voidEls, t.name)) {
                    if (t.name === hiddenName) hiddenSameDepth++;
                    if (hiddenInner.length < maxHiddenInner) hiddenInner.push(t.name);
                    else hiddenOverflow = true;
                }
                continue;
            }
            hiddenName = null;
            hiddenInner = [];
            hiddenOverflow = false;
            hiddenSameDepth = 0;
        }

        // Raw text elements
        if (!t.end && has(raw, t.name)) { rawName = t.name; continue; }
        if (!t.end && t.name === "textarea" && isHiddenByAttribute(t)) { rawName = t.name; rawKeepsText = false; continue; }
        if (!t.end && (has(hidden, t.name) || isHiddenByAttribute(t))) {
            if (opensHiddenContent(t)) {
                hiddenName = t.name;
                hiddenInner = [];
                hiddenOverflow = false;
                hiddenSameDepth = 0;
                hiddenByAttribute = !has(hidden, t.name);
            }
            continue;
        }

        // Process visible tags
        var nestedList = has(lists, t.name) && (function () {
            for (var ni = 0; ni < frames.length; ni++) {
                if (frames[ni].name === "li" || frames[ni].name === "dd" || frames[ni].name === "dt") return true;
            }
            return false;
        })();
        var amount = has(paragraphs, t.name) ? (nestedList ? 1 : 2) : (has(lines, t.name) ? 1 : 0);

        if (t.end) {
            switch (t.name) {
                case "a":
                    if (anchor !== null && showLinks) textOut(markupLinkSuffix(anchor.text, anchor.url));
                    anchor = null;
                    break;
                case "pre":
                case "listing":
                    if (preDepth > 0) preDepth--;
                    break;
                case "td":
                case "th":
                case "tr":
                    if (tableDepth > 1) {
                        boundary(1);
                    } else if (t.name === "tr") {
                        endRow();
                    } else {
                        endCell();
                    }
                    break;
                case "table":
                    if (tableDepth > 1) {
                        tableDepth--;
                        boundary(1);
                    } else {
                        tableDepth = 0;
                        endRow();
                    }
                    break;
            }
            close(t.name);
            if (amount > 0) boundary(amount);
            continue;
        }

        // Start tags
        if (t.name === "li") {
            var liIdx = -1;
            var listIdx = -1;
            for (var li2 = frames.length - 1; li2 >= 0; li2--) {
                if (frames[li2].name === "li" && liIdx < 0) liIdx = li2;
                if (has(lists, frames[li2].name) && listIdx < 0) listIdx = li2;
            }
            if (liIdx >= 0 && liIdx > listIdx) close("li");
        }

        if (amount > 0) boundary(amount);

        switch (t.name) {
            case "br":
                if (cell !== null) { cell.pendingSpace = cell.lineContent; }
                else writer.hardBreak();
                break;
            case "blockquote":
                current().pushQuote();
                open(t.name, true);
                break;
            case "ul":
            case "ol":
            case "menu":
            case "dl":
                var startAttr = t.attributes["start"];
                const nextVal = ordinal(startAttr, 1n);
                open(t.name, false, nextVal);
                break;
            case "li":
                var marker = "\u2022 ";
                var olIdx = -1;
                for (var oi = frames.length - 1; oi >= 0; oi--) {
                    if (has(lists, frames[oi].name)) { olIdx = oi; break; }
                }
                if (olIdx >= 0 && frames[olIdx].name === "ol") {
                    const n = ordinal(t.attributes["value"], frames[olIdx].next);
                    marker = n + ". ";
                    frames[olIdx].next = n === 9223372036854775807n ? n : n + 1n;
                }
                current().beginItem(marker);
                open("li", true);
                break;
            case "dd":
                current().pushIndent(2);
                open("dd", true);
                break;
            case "dt":
                close("dt");
                open("dt", false);
                break;
            case "pre":
            case "listing":
                preDepth++;
                dropFirstBreak = true;
                break;
            case "textarea":
                rawName = "textarea";
                rawKeepsText = true;
                break;
            case "img":
                var alt = (t.attributes["alt"] || "").trim();
                if (alt.length > 0) textOut("[" + alt + "]");
                break;
            case "a":
                anchor = { url: t.attributes["href"] || "", text: "" };
                break;
            case "table":
                tableDepth++;
                break;
            case "tr":
                if (tableDepth > 1) { boundary(1); }
                else { endRow(); rowOpen = true; }
                break;
            case "td":
            case "th":
                if (tableDepth > 1) { boundary(1); }
                else { endCell(); cell = new PlainTextWriter(); rowOpen = true; }
                break;
        }
    }

    // End of input
    if (anchor !== null && showLinks) {
        textOut(markupLinkSuffix(anchor.text, anchor.url));
        anchor = null;
    }
    endRow();

    return writer.finish();
}
// @endshared

// @shared html.plaintext/markup
function convertMarkup(input, options, api, operation) {
  try {
    if (api.cancelled()) return {error: 'cancelled'};
    if (operation === 'html.plaintext') {
      return {primaryText: htmlToText(input, options.links === 'true', api), status: 'Plain text'};
    }
    const parsed = api.native('markdown.parse', input);
    if (parsed.error) return parsed;
    const asText = operation === 'markdown.plaintext';
    const limit = asText
      ? Math.max(api.limits.maxOutputBytes * 4, api.limits.maxInputBytes * 8)
      : api.limits.maxOutputBytes;
    const nodes = parsed.nodes;
    for (const node of nodes) node.children = node.children.map(index => nodes[index]);
    const html = renderMarkdown(nodes[0], limit, asText, api);
    return asText
      ? {primaryText: htmlToText(html, options.links === 'true', api), status: 'Plain text'}
      : {primaryText: html, status: 'Rendered HTML', syntax: 'xml'};
  } catch (error) {
    if (error.error) return error;
    throw error;
  }
}

// Nodes: { kind, children:[], runs:[], task?:bool, loose?:bool, value?:number, alignments?:[string|null] }
// Inline keys: text, link, image, emphasis, strong, strike, code, soft, hard, html,
//              linkEmphasis, linkStrong, linkStrike

function renderMarkdown(root, limit, taskMarkersAsText, api) {
  var bytes = [];
  var pendingLF = false;

  function endsInLF() { return pendingLF || (bytes.length > 0 && bytes[bytes.length - 1] === 10); }

  function flushLF() {
    if (pendingLF) {
      if (bytes.length >= limit) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
      bytes.push(10);
      pendingLF = false;
    }
  }

  function append(text) {
    if (api.cancelled()) throw { error: "cancelled", message: "" };
    if (text.length === 0) return;
    flushLF();
    var encoded = utf8.encode(text);
    var finalLF = (encoded.length > 0 && encoded[encoded.length - 1] === 10);
    var count = encoded.length - (finalLF ? 1 : 0);
    if (count > limit - bytes.length) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
    for (var i = 0; i < count; i++) {
      bytes.push(encoded[i]);
    }
    pendingLF = finalLF;
  }

  function cr() {
    if ((bytes.length > 0 || pendingLF) && !endsInLF()) {
      append("\n");
    }
  }

  function escaped(text) {
    var encoded = utf8.encode(text);
    for (var i = 0; i < encoded.length; i++) {
      if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "" };
      var b = encoded[i];
      switch (b) {
        case 38: append("&amp;"); break;
        case 60: append("&lt;"); break;
        case 62: append("&gt;"); break;
        case 34: append("&quot;"); break;
        default:
          flushLF();
          if (bytes.length >= limit) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
          bytes.push(b);
      }
    }
  }

  function inline(runs, drop) {
    var stack = [];
    var remaining = drop || 0;

    function closeElement(element) {
      append("</" + element.tag + ">");
    }

    for (var ri = 0; ri < runs.length; ri++) {
      var run = runs[ri];
      if (remaining > 0) {
        // Swift: run.text.utf8.count and dropFirst(count) on UTF-8 bytes
        var utf8Bytes = utf8.encode(run.text);
        var byteCount = Math.min(remaining, utf8Bytes.length);
        var restBytes = utf8Bytes.slice(byteCount);
        run = Object.create(run);
        run.text = utf8.decode(restBytes);
        remaining -= byteCount;
        if (run.text.length === 0) continue;
      }

      // Build wanted elements
      var wanted = [];
      if (run.strike) wanted.push({ tag: "del", url: null, inner: false });
      if (run.emphasis) wanted.push({ tag: "em", url: null, inner: false });
      if (run.strong) wanted.push({ tag: "strong", url: null, inner: false });
      if (run.link != null) wanted.push({ tag: "a", url: run.link, inner: false });
      if (run.linkStrike) wanted.push({ tag: "del", url: null, inner: true });
      if (run.linkEmphasis) wanted.push({ tag: "em", url: null, inner: true });
      if (run.linkStrong) wanted.push({ tag: "strong", url: null, inner: true });

      // Find how many stack elements to keep
      var keep = stack.length;
      for (var ki = 0; ki < stack.length; ki++) {
        var found = false;
        for (var wi = 0; wi < wanted.length; wi++) {
          if (elementsEqual(stack[ki], wanted[wi])) { found = true; break; }
        }
        if (!found) { keep = ki; break; }
      }

      // Outer formatting opens outside the link
      var hasOuterMissing = false;
      for (var wo = 0; wo < wanted.length; wo++) {
        if (wanted[wo].tag !== "a" && !wanted[wo].inner) {
          var inStack = false;
          for (var sk = 0; sk < keep; sk++) {
            if (elementsEqual(stack[sk], wanted[wo])) { inStack = true; break; }
          }
          if (!inStack) { hasOuterMissing = true; break; }
        }
      }
      if (hasOuterMissing) {
        for (var li = 0; li < keep; li++) {
          if (stack[li].tag === "a") { keep = li; break; }
        }
      }

      // Close elements from keep onwards (reversed)
      for (var ci = stack.length - 1; ci >= keep; ci--) {
        closeElement(stack[ci]);
      }
      stack.length = keep;

      // Open wanted elements not already in stack
      for (var wo2 = 0; wo2 < wanted.length; wo2++) {
        var e = wanted[wo2];
        var inStack2 = false;
        for (var sk2 = 0; sk2 < stack.length; sk2++) {
          if (elementsEqual(stack[sk2], e)) { inStack2 = true; break; }
        }
        if (!inStack2) {
          if (e.url !== null && e.url !== undefined) {
            append("<a href=\"");
            escaped(e.url);
            append("\">");
          } else {
            append("<" + e.tag + ">");
          }
          stack.push(e);
        }
      }

      // Render the run content
      if (run.image != null) {
        append("<img src=\"");
        escaped(run.image);
        append("\" alt=\"");
        var altText = run.text;
        if (altText.length === 1 && altText.codePointAt(0) === 0xFFFC) altText = "";
        escaped(altText);
        append("\" />");
      } else if (run.soft) {
        append("\n");
      } else if (run.hard) {
        append("<br />\n");
      } else if (run.html) {
        append(run.text);
      } else if (run.code) {
        append("<code>");
        escaped(run.text);
        append("</code>");
      } else {
        escaped(run.text);
      }
    }

    // Close remaining stack elements (reversed)
    for (var ri2 = stack.length - 1; ri2 >= 0; ri2--) {
      closeElement(stack[ri2]);
    }
  }

  function checkbox(item) {
    if (taskMarkersAsText) return null;
    if (item.task === null || item.task === undefined) return null;
    return item.task;
  }

  function openNode(node, tight, taskDrop) {
    var kind = node.kind;

    if (kind === "root" || kind === "cell" || kind === "row" || kind === "headerRow") {
      // No open tag
    } else if (kind === "paragraph") {
      if (!tight) { cr(); append("<p>"); }
      inline(node.runs, taskDrop);
      if (!tight) { append("</p>\n"); }
    } else if (kind === "header") {
      cr();
      append("<h" + node.value + ">");
      inline(node.runs, 0);
      append("</h" + node.value + ">\n");
    } else if (kind === "quote") {
      cr(); append("<blockquote>\n");
    } else if (kind === "orderedList") {
      var start = 1;
      if (node.children.length > 0) {
        var firstChild = node.children[0];
        if (firstChild.kind === "item") start = firstChild.value;
      }
      cr();
      if (start !== 1) {
        append("<ol start=\"" + start + "\">\n");
      } else {
        append("<ol>\n");
      }
    } else if (kind === "unorderedList") {
      cr(); append("<ul>\n");
    } else if (kind === "item") {
      cr(); append("<li>");
      var checked = checkbox(node);
      if (checked !== null) {
        if (checked) {
          append("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
        } else {
          append("<input type=\"checkbox\" disabled=\"\" /> ");
        }
      }
    } else if (kind === "code") {
      cr(); append("<pre><code");
      // Extract first word of language hint
      var lang = node.value;
      if (lang) {
        var parts = lang.split(/\s+/);
        var hint = parts[0];
        if (hint.length > 0) {
          append(" class=\"language-");
          escaped(hint);
          append("\"");
        }
      }
      append(">");
      for (var cri = 0; cri < node.runs.length; cri++) {
        escaped(node.runs[cri].text);
      }
      append("</code></pre>\n");
    } else if (kind === "thematic") {
      cr(); append("<hr />\n");
    } else if (kind === "html") {
      cr();
      for (var hri = 0; hri < node.runs.length; hri++) {
        append(node.runs[hri].text);
      }
      cr();
    } else if (kind === "table") {
      cr(); append("<table>");
      var columns = node.value;
      var body = false;
      for (var tci = 0; tci < node.children.length; tci++) {
        var row = node.children[tci];
        var isHeader = (row.kind === "headerRow");
        if (isHeader) {
          cr(); append("<thead>");
        } else if (!body) {
          cr(); append("<tbody>"); cr();
          body = true;
        }
        cr(); append("<tr>");
        var cells = {};
        for (var cci = 0; cci < row.children.length; cci++) {
          var cell = row.children[cci];
          if (cell.kind === "cell") {
            cells[cell.value] = cell;
          }
        }
        for (var ci2 = 0; ci2 < columns; ci2++) {
          var tag = isHeader ? "th" : "td";
          cr();
          append("<" + tag);
          if (ci2 < node.alignments.length && node.alignments[ci2] !== null) {
            append(" align=\"" + node.alignments[ci2] + "\"");
          }
          append(">");
          if (cells[ci2] !== undefined) {
            inline(cells[ci2].runs, 0);
          }
          append("</" + tag + ">");
        }
        cr(); append("</tr>");
        if (isHeader) { cr(); append("</thead>"); }
      }
      if (body) { cr(); append("</tbody>"); cr(); }
      cr(); append("</table>"); cr();
    }
  }

  function closeNode(node) {
    var kind = node.kind;
    if (kind === "quote") { cr(); append("</blockquote>\n"); }
    else if (kind === "orderedList") { append("</ol>\n"); }
    else if (kind === "unorderedList") { append("</ul>\n"); }
    else if (kind === "item") { append("</li>\n"); }
  }

  function isContainer(node) {
    var kind = node.kind;
    return kind === "root" || kind === "quote" || kind === "orderedList" || kind === "unorderedList" || kind === "item";
  }

  var stack = [{ node: root, tight: false, nextChild: 0 }];
  while (stack.length > 0) {
    if (api.cancelled()) throw { error: "cancelled", message: "" };
    var top = stack[stack.length - 1];
    if (top.nextChild >= top.node.children.length) {
      closeNode(top.node);
      stack.pop();
      continue;
    }
    var index = top.nextChild;
    stack[stack.length - 1].nextChild += 1;
    var child = top.node.children[index];
    var tight;
    var taskDrop = 0;
    var parentKind = top.node.kind;
    if (parentKind === "orderedList" || parentKind === "unorderedList") {
      tight = !top.node.loose;
    } else if (parentKind === "item") {
      tight = top.tight;
      if (index === 0 && checkbox(top.node) !== null) {
        taskDrop = 4;
      }
    } else {
      tight = false;
    }
    openNode(child, tight, taskDrop);
    if (isContainer(child)) {
      stack.push({ node: child, tight: tight, nextChild: 0 });
    }
  }

  return utf8.decode(bytes);
}

function elementsEqual(a, b) {
  return a.tag === b.tag && a.url === b.url && a.inner === b.inner;
}
// @endshared
